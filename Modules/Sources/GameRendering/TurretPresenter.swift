import AegisECS
import GameCore
import GameSimulation
import Metal
import MetalRenderKit
import simd

/// Hand-built rig rendering every turret. The turret's fire SOUND is a
/// separate object in a separate module (`GameAudio.TurretFireAudio`) — see
/// its own comment for why.
///
/// This is the deliberate exception to instanced rendering: the barrel needs
/// an independent pitch axis the mass instance-transform format does not
/// carry. With turret count now variable (see `TurretFactory`), that means
/// one small hand-built rig PER turret rather than exactly one — still cheap
/// at the handful `TurretFactory.maxCount` allows, and still far simpler than
/// folding an articulated multi-part rig into the instanced path built for
/// single-mesh populations of thousands.
package final class TurretPresenter {
    package init() {}

    package struct Part {
        package let mesh: GreyboxMesh
        package let buffer: MTLBuffer
    }

    /// One turret's static geometry plus the layout numbers `update` needs
    /// every frame to re-pose it. Everything here is built once per turret in
    /// `makeRig` and never mutates afterward — only the instance buffers each
    /// `Part` owns change, rewritten in place every frame.
    private struct Rig {
        var pedestal: Part
        var coreColumn: Part
        var housing: Part
        var barrel: Part
        var barrelLength: Float
        var pedestalHeight: Float
        var coreColumnCenterY: Float
    }

    /// Applied to every mesh dimension below that has no counterpart in the
    /// game layer — unlike `TurretConfig.baseRadius`/`muzzleHeight`/
    /// `muzzleForwardOffset`, which are already scaled (see that file).
    package static let cosmeticScale: Float = 3.5
    /// The rig's vertical layout is expressed as FRACTIONS of
    /// `TurretConfig.muzzleHeight`, not absolute numbers. This is required:
    /// the weapon sits exactly at `muzzleHeight` (read by the game layer for
    /// the real projectile launch point), so if the pedestal/column instead
    /// used their own fixed cosmetic scale, changing the turret's height
    /// would leave the weapon floating, detached from its own base.
    package static let pedestalHeightRatio: Float = 0.538
    package static let coreColumnHeightRatio: Float = 0.577
    package static let coreColumnCenterRatio: Float = 0.731

    /// A wreck's whole palette collapses toward charred near-black —
    /// including the core column, whose green glow is what reads as "this
    /// turret is live" from a distance, so it is the one colour that MUST
    /// change for a wreck to register as dead at a glance, not just a shade
    /// darker than usual.
    private enum Tone {
        static let pedestal = RGBA(0.36, 0.39, 0.44)
        static let coreColumn = RGBA(0.35, 0.78, 0.55)
        static let housing = RGBA(0.48, 0.50, 0.56)
        static let barrel = RGBA(0.22, 0.24, 0.28)

        static let destroyedPedestal = RGBA(0.16, 0.15, 0.14)
        static let destroyedCoreColumn = RGBA(0.20, 0.19, 0.18)
        static let destroyedHousing = RGBA(0.18, 0.17, 0.16)
        static let destroyedBarrel = RGBA(0.08, 0.08, 0.08)
    }

    private var rigs: [Rig] = []

    /// Flattened across every turret, in the same order `GameSession.draw`
    /// already walks any other batch of parts — adding a second turret costs
    /// this array four more entries and four more draw calls, nothing else.
    package var allParts: [Part] {
        rigs.flatMap { [$0.pedestal, $0.coreColumn, $0.housing, $0.barrel] }
    }

    /// Builds exactly as many rigs as `context.turrets` currently holds.
    /// Safe to call again later with a different count — `update` does
    /// exactly that on its own whenever the live count no longer matches.
    package func configure(device: MTLDevice, context: GameContext) {
        let count = Int(context.turrets!.count)
        rigs = (0..<count).map { _ in makeRig(device: device, context: context) }
    }

    private func makeRig(device: MTLDevice, context: GameContext) -> Rig {
        let config = context.turretConfig!

        let pedestalHeight = config.muzzleHeight * Self.pedestalHeightRatio
        let pedestal = makePart(device: device,
            meshData: GreyboxMeshLibrary.cylinder(topRadius: config.baseRadius, bottomRadius: config.baseRadius * 1.25, height: pedestalHeight),
            color: Tone.pedestal)

        let coreColumnCenterY = config.muzzleHeight * Self.coreColumnCenterRatio
        let coreColumn = makePart(device: device,
            meshData: GreyboxMeshLibrary.cylinder(topRadius: 0.75 * Self.cosmeticScale, bottomRadius: 0.75 * Self.cosmeticScale,
                                                   height: config.muzzleHeight * Self.coreColumnHeightRatio),
            color: Tone.coreColumn)

        let housing = makePart(device: device,
            meshData: GreyboxMeshLibrary.generate(kind: .box, dimensions: SIMDVector3(1.6, 1.0, 1.8) * Self.cosmeticScale),
            color: Tone.housing)

        let barrelLength = config.muzzleForwardOffset * 1.6
        let barrel = makePart(device: device,
            meshData: GreyboxMeshLibrary.generate(kind: .box, dimensions: SIMDVector3(0.45 * Self.cosmeticScale, 0.45 * Self.cosmeticScale, barrelLength)),
            color: Tone.barrel)

        return Rig(pedestal: pedestal, coreColumn: coreColumn, housing: housing, barrel: barrel,
                   barrelLength: barrelLength, pedestalHeight: pedestalHeight, coreColumnCenterY: coreColumnCenterY)
    }

    private func makePart(device: MTLDevice, meshData: GreyboxMeshLibrary.MeshData, color: RGBA) -> Part {
        let mesh = GreyboxMesh(device: device, data: meshData)!
        let buffer = device.makeBuffer(length: InstancePool.stride * MemoryLayout<Float>.stride, options: .storageModeShared)!
        let part = Part(mesh: mesh, buffer: buffer)
        InstanceBufferWriter.write(part.buffer, worldMatrix: MathUtilities.translation(.zero), color: color)
        return part
    }

    /// Re-derives every rig's world transform from `TurretComponentStore`.
    /// Called once per frame, after the scheduler has run — so the rig never
    /// shows a pose one frame stale.
    ///
    /// `device` is only ever used if the live turret count no longer matches
    /// `rigs.count` — `TurretFactory.setCount` can change that count from
    /// outside the frame loop (a settings-panel action), and entity
    /// destruction is deferred to the next reaper flush besides, so this is
    /// where the render rig catches up rather than being told about it
    /// directly. A mismatch is rare (a settings change, not a per-frame
    /// event), so re-checking a count here every frame costs nothing worth
    /// avoiding.
    package func update(context: GameContext, device: MTLDevice) {
        let turrets = context.turrets!
        if Int(turrets.count) != rigs.count {
            configure(device: device, context: context)
        }
        guard turrets.count > 0 else { return }

        let config = context.turretConfig!
        let transforms = context.transforms!
        let transformSparse = transforms.sparseIndex
        let positions = transforms.position

        for dense in 0..<rigs.count {
            let rig = rigs[dense]
            let entity = turrets.denseEntities[dense]
            let alive = context.isTurretAlive(entity)
            var origin = context.corePosition
            let slot = transformSparse[Int(entity)]
            if slot >= 0 { origin = positions[Int(slot)] }
            let base = MathUtilities.translation(origin.simd3)

            let yaw = turrets.yaw[dense]
            // Local +Z tilts upward under a NEGATIVE rotation about X, so pitch
            // is negated here: a positive `pitch` has to raise the barrel.
            let pitch = turrets.pitch[dense]

            let yawPivot = base * MathUtilities.translation(SIMD3<Float>(0, config.muzzleHeight, 0)) * MathUtilities.rotationY(yaw)
            let pitchPivot = yawPivot * MathUtilities.rotationX(-pitch)

            InstanceBufferWriter.write(rig.pedestal.buffer, worldMatrix: base * MathUtilities.translation(SIMD3<Float>(0, rig.pedestalHeight * 0.5, 0)),
                                       color: alive ? Tone.pedestal : Tone.destroyedPedestal)
            InstanceBufferWriter.write(rig.coreColumn.buffer, worldMatrix: base * MathUtilities.translation(SIMD3<Float>(0, rig.coreColumnCenterY, 0)),
                                       color: alive ? Tone.coreColumn : Tone.destroyedCoreColumn)
            InstanceBufferWriter.write(rig.housing.buffer, worldMatrix: yawPivot, color: alive ? Tone.housing : Tone.destroyedHousing)
            // Offset along local +Z so the pivot sits at the breech, not the barrel's middle.
            InstanceBufferWriter.write(rig.barrel.buffer, worldMatrix: pitchPivot * MathUtilities.translation(SIMD3<Float>(0, 0, rig.barrelLength * 0.5)),
                                       color: alive ? Tone.barrel : Tone.destroyedBarrel)
        }
    }
}
