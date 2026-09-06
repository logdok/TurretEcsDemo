import AegisECS
import AVFoundation
import GameAudio
import GameCore
import GameRendering
import GameSimulation
import MetalKit
import MetalRenderKit
import simd

/// One running game: the assembled world, the presentation layer that observes
/// it, and the per-frame driver that ticks both. An `MTKView`'s display-linked
/// `draw(in:)` callback is this project's frame tick.
///
/// Responsibilities, in order: assemble the game world, assemble the
/// presentation layer (renderer, turret rig, camera, audio), wire them
/// together, then tick one frame at a time. This file owns no game rule
/// itself — everything here is assembly, not logic.
///
/// This is one of exactly two types the app shell can see (the other is
/// `GameScreen`). Everything it is built from — the ECS world, the instanced
/// batches, the voice pools — is `package`-scoped and invisible outside this
/// package, which is what keeps the shell a shell.
public final class GameSession: NSObject, MTKViewDelegate {
    package static let maxSimulationStep: Float = 0.1

    /// Where both audio buses start. Half rather than full because the arena
    /// gets loud fast: at a few hundred enemies the turret fires dozens of
    /// times a second and explosions overlap, and full volume out of the box
    /// is startling rather than impressive. The player can still take it to
    /// 100% from the settings panel.
    package static let defaultVolumePercent: Float = 50

    package let metalContext: MetalContext
    package let context: GameContext
    package let registry = RenderBatchRegistry()
    package let turretPresenter = TurretPresenter()
    package let cameraRig = OrbitCameraRig()
    package let audioEngine = AVAudioEngine()
    package let turretFireAudio = TurretFireAudio()
    package let enemyDeathAudio = EnemyDeathAudio()
    package let inspector: Inspector

    /// Captured once, right after the context is assembled, so the
    /// per-archetype "enabled" toggle in the settings panel has an original
    /// weight to restore — writing some flat default back on re-enable would
    /// lose each archetype's authored relative frequency (e.g. Drone 3.0 vs.
    /// Tank 1.0).
    package let enemyDefaultSpawnWeights: [Float]

    private let groundMesh: GreyboxMesh
    private let groundBuffer: MTLBuffer
    private let uniformsBuffer: MTLBuffer

    private var lastFrameTime: CFTimeInterval = CACurrentMediaTime()
    private var aspectRatio: Float = 1
    package private(set) var lastDrawCallCount = 0
    package private(set) var lastPrimitiveCount = 0

    /// Metal is guaranteed present on every iOS 17 device and simulator this
    /// app targets, so setup failures here (`fatalError`) mean a genuinely
    /// broken environment, not a recoverable runtime condition — there is no
    /// meaningful fallback UI for "no GPU".
    public override init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device.")
        }
        guard let metalContext = MetalContext(device: device, colorPixelFormat: .bgra8Unorm, depthPixelFormat: .depth32Float) else {
            fatalError("Failed to build the Metal render pipeline.")
        }
        guard let uniformsBuffer = device.makeBuffer(length: MemoryLayout<FrameUniforms>.stride, options: .storageModeShared) else {
            fatalError("Failed to allocate the uniforms buffer.")
        }
        self.metalContext = metalContext
        self.uniformsBuffer = uniformsBuffer

        let simulationConfig = SimulationConfig.createDefault()
        let turretConfig = TurretConfig()
        let context = SimulationBootstrap.build(simulationConfig: simulationConfig, weaponConfig: turretConfig)
        self.context = context
        enemyDefaultSpawnWeights = context.enemyArchetypes.map { $0.spawnWeight }

        registry.build(device: device, simulationConfig: simulationConfig)
        // The renderer is presentation's concern, added last so it observes
        // an already fully-resolved frame — see SimulationBootstrap.
        context.scheduler.addSystem(InstancedRenderSystem(registry: registry))
        SimulationBootstrap.finalize(context)

        turretPresenter.configure(device: device, context: context)

        let groundData = GreyboxMeshLibrary.plane(size: simulationConfig.arenaRadius * 2.6)
        guard let groundMesh = GreyboxMesh(device: device, data: groundData) else {
            fatalError("Failed to build the ground mesh.")
        }
        guard let groundBuffer = device.makeBuffer(length: InstancePool.stride * MemoryLayout<Float>.stride, options: .storageModeShared) else {
            fatalError("Failed to allocate the ground instance buffer.")
        }
        self.groundMesh = groundMesh
        self.groundBuffer = groundBuffer

        cameraRig.focusPoint = context.corePosition.simd3 + SIMD3<Float>(0, 3, 0)
        cameraRig.configure(arenaRadius: simulationConfig.arenaRadius)

        var options = Inspector.Options()
        #if DEBUG
        options.mode = .dev
        #else
        options.mode = .telemetry
        #endif
        options.grids = ["enemies": context.spatialGrid, "missiles": context.missileSpatialGrid]
        inspector = Inspector.attach(scheduler: context.scheduler, world: context.world, options: options)

        super.init()

        InstanceBufferWriter.write(groundBuffer, worldMatrix: MathUtilities.translation(.zero), color: RGBA(0.15, 0.16, 0.19))
        setupAudio()
        setupInspectorCounters()
    }

    /// Note what is NOT here any more: any knowledge of where the sound files
    /// live. `GameAudio` owns its own clips and resolves them from its module
    /// bundle, so this composition root only has to say "engine, context, go".
    private func setupAudio() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        turretFireAudio.configure(engine: audioEngine, context: context)
        enemyDeathAudio.configure(engine: audioEngine, context: context)

        // Set explicitly rather than left alone: an AVAudioMixerNode starts at
        // 1.0, so "no code" silently means full volume. Both buses exist only
        // after `configure`, which is why this follows it.
        turretFireAudio.bus.outputVolume = GameSession.defaultVolumePercent / 100
        enemyDeathAudio.bus.outputVolume = GameSession.defaultVolumePercent / 100

        audioEngine.prepare()
        try? audioEngine.start()
    }

    /// The ECS library knows nothing about turrets or a core, so these game
    /// counters are declared here rather than inside the inspector.
    private func setupInspectorCounters() {
        let gameContext = context
        inspector.addCounterSection("Combat") {
            let turrets = gameContext.turrets!
            var aliveTurrets = 0
            for i in 0..<Int(turrets.count) where gameContext.isTurretAlive(turrets.denseEntities[i]) { aliveTurrets += 1 }
            return [
                ("Enemies", "\(gameContext.hostiles.count) / \(gameContext.targetPopulation)"),
                ("Projectiles", "\(gameContext.projectiles.count)"),
                ("Missiles", "\(gameContext.interceptables.count)"),
                ("Turrets", "\(aliveTurrets) / \(turrets.count)"),
            ]
        }
        inspector.addCounterSection("Totals") {
            [
                ("Killed", "\(gameContext.killCount)"),
                ("Intercepted", "\(gameContext.interceptCount)"),
                ("Breaches", "\(gameContext.breachCount)"),
                ("Turrets Lost", "\(gameContext.turretsLostCount)"),
                ("Shots", "\(gameContext.shotsFired)"),
            ]
        }
        inspector.addCounterSection("Render") { [weak self] in
            guard let self else { return [] }
            return [
                ("Draw calls", "\(self.lastDrawCallCount)"),
                ("Primitives", "\(self.lastPrimitiveCount)"),
            ]
        }
    }

    // MARK: - MTKViewDelegate
    //
    // These two are `public` only because a public type's conformance to a
    // public protocol has to be: they are not part of the shell-facing API in
    // any meaningful sense.

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        aspectRatio = size.height > 0 ? Float(size.width / size.height) : 1
    }

    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = metalContext.commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        else { return }

        let now = CACurrentMediaTime()
        let delta = Float(min(max(now - lastFrameTime, 0), 0.25))
        lastFrameTime = now

        // The simulation still ticks with a zero-length step while paused, so
        // the renderer keeps producing frames; time-dependent systems already
        // short-circuit on `delta <= 0` themselves (`System.requiresTime`).
        // Losing every turret freezes the same way — there is no separate
        // "game over" state, every system already knows how to sit still.
        let frozen = context.paused || context.areAllTurretsDestroyed()
        let step = frozen ? 0 : min(delta, GameSession.maxSimulationStep)
        context.scheduler.executeAll(delta: step)
        turretPresenter.update(context: context, device: metalContext.device)
        turretFireAudio.refresh()
        enemyDeathAudio.refresh()

        let projection = MathUtilities.perspective(fovyRadians: 62.0 * .pi / 180.0, aspect: aspectRatio,
                                                    nearZ: 0.1, farZ: cameraRig.maximumDistance * 3.0)
        let uniforms = FrameUniforms(
            viewProjection: projection * cameraRig.viewMatrix(),
            lightDirection: SIMD4<Float>(simd_normalize(SIMD3<Float>(0.45, -1.0, 0.55)), 0),
            lightColor: SIMD4<Float>(1.15, 1.15, 1.15, 0),
            ambientColor: SIMD4<Float>(0.44, 0.50, 0.60, 0.65),
            cameraPosition: SIMD4<Float>(cameraRig.eyePosition, 0))
        uniformsBuffer.contents().assumingMemoryBound(to: FrameUniforms.self).pointee = uniforms

        encoder.setRenderPipelineState(metalContext.pipelineState)
        encoder.setDepthStencilState(metalContext.depthStencilState)
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(.back)
        encoder.setVertexBuffer(uniformsBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 1)

        var drawCalls = 0
        var primitives = 0
        func drawInstances(mesh: GreyboxMesh, instanceBuffer: MTLBuffer, instanceCount: Int) {
            guard instanceCount > 0 else { return }
            encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 2)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: mesh.indexCount, indexType: .uint16,
                                           indexBuffer: mesh.indexBuffer, indexBufferOffset: 0, instanceCount: instanceCount)
            drawCalls += 1
            primitives += (mesh.indexCount / 3) * instanceCount
        }

        drawInstances(mesh: groundMesh, instanceBuffer: groundBuffer, instanceCount: 1)
        for pool in registry.pools {
            guard let pool, pool.visibleCount > 0 else { continue }
            drawInstances(mesh: pool.mesh, instanceBuffer: pool.buffer, instanceCount: pool.visibleCount)
        }
        for part in turretPresenter.allParts {
            drawInstances(mesh: part.mesh, instanceBuffer: part.buffer, instanceCount: 1)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()

        lastDrawCallCount = drawCalls
        lastPrimitiveCount = primitives

        // Last line of the frame, so the captured wall-clock time covers
        // everything the frame actually did, not just the scheduler.
        inspector.capture()
    }
}
