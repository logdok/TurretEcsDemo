import AegisECS
import Combine
import GameRuntime
import GameSimulation
import SwiftUI

/// Bridges `GameSession`/`GameContext` to SwiftUI. Population, pause, restart,
/// turret balance, sound and the per-archetype sections all write straight
/// into live simulation state: no setting here ever rebuilds the scene or
/// restarts anything.
///
/// This is the only place in the UI module that touches simulation state, and
/// it can only touch what `GameSimulation` marked `package` — the component
/// stores and systems behind it are unreachable from here by construction.
final class GameViewModel: ObservableObject {
    /// One turret's health, as the HUD needs it — a display DTO, not a live
    /// reference: it is rebuilt from scratch every refresh tick, never
    /// mutated in place. `id` is the turret's own ECS entity id, stable for
    /// as long as that turret is alive, which is all `ForEach` needs.
    struct TurretHealthReadout: Identifiable {
        let id: Int32
        let ratio: Double
        let text: String
    }

    let session: GameSession

    /// The real end of the game — every turret worn down to a wreck (see
    /// `GameContext.areAllTurretsDestroyed`). There is no separate core
    /// health bar behind this: turrets ARE the defense.
    @Published private(set) var isDefeated: Bool = false
    @Published private(set) var turretHealthReadouts: [TurretHealthReadout] = []

    private var refreshTimer: Timer?
    private var soundEnabled = true
    private var lastFireVolumePercent: Float
    private var lastExplosionVolumePercent: Float

    init(session: GameSession) {
        self.session = session
        // Read back from the live buses rather than repeating a literal: the
        // session already set the starting volume, and a second copy of the
        // number here is a copy that can drift out of sync with the sliders.
        lastFireVolumePercent = session.turretFireAudio.bus.outputVolume * 100
        lastExplosionVolumePercent = session.enemyDeathAudio.bus.outputVolume * 100
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.refreshHealth() }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        refreshHealth()
    }

    private func refreshHealth() {
        isDefeated = session.context.areAllTurretsDestroyed()
        refreshTurretHealth()
    }

    /// Walks the live turret/health stores directly — the same "read
    /// `GameSimulation`'s `package` state straight through" approach every
    /// other readout on this view model uses, just producing an ARRAY this
    /// time instead of a single value, since the turret count itself varies.
    private func refreshTurretHealth() {
        let context = session.context
        let turrets = context.turrets!
        let healths = context.healths!
        let healthSparse = healths.sparseIndex
        let current = healths.current
        let maximum = healths.maximum

        var readouts: [TurretHealthReadout] = []
        readouts.reserveCapacity(Int(turrets.count))
        for dense in 0..<Int(turrets.count) {
            let entity = turrets.denseEntities[dense]
            let slot = healthSparse[Int(entity)]
            guard slot >= 0 else { continue }
            let hp = current[Int(slot)]
            let maxHp = maximum[Int(slot)]
            let ratio = Double(hp / max(maxHp, 1))
            readouts.append(TurretHealthReadout(id: entity, ratio: min(max(ratio, 0), 1),
                                                 text: "\(max(Int(hp), 0)) / \(Int(maxHp))"))
        }
        turretHealthReadouts = readouts
    }

    var maxEnemyCapacity: Int { Int(session.context.config.maxEnemyCapacity) }
    var initialPopulation: Int { Int(session.context.targetPopulation) }
    var initialTurretDamage: Float { session.context.turretConfig.projectileDamage }
    var initialTurretFireRate: Float { 1.0 / max(session.context.turretConfig.fireInterval, 0.001) }
    var initialTurretCount: Int { Int(session.context.turretCount) }
    var maxTurretCount: Int { TurretFactory.maxCount }
    var initialFireVolume: Float { lastFireVolumePercent }
    var initialExplosionVolume: Float { lastExplosionVolumePercent }
    var enemyArchetypes: [EnemyArchetypeConfig] { session.context.enemyArchetypes }

    /// What an archetype actually looks like in the 3D view — its mesh shape
    /// and its true rendered color (base albedo times its own tint, the same
    /// multiply `InstancedRenderSystem` performs) — so the settings panel can
    /// show a small preview next to each archetype's sliders. Without this,
    /// ground archetypes are hard to tell apart at arena scale; a fired
    /// missile is colored to match this same value (see
    /// `GameContext.renderedColor(for:)`).
    func archetypePreview(_ archetype: EnemyArchetypeConfig) -> (meshKind: RenderArchetypeConfig.MeshKind, color: Color) {
        let context = session.context
        let meshKind = context.getRenderArchetypeConfig(archetype.renderArchetypeId)?.meshKind ?? .box
        let rendered = context.renderedColor(for: archetype)
        return (meshKind, Color(red: Double(rendered.r), green: Double(rendered.g), blue: Double(rendered.b)))
    }

    func setPopulation(_ value: Int) {
        session.context.targetPopulation = Int32(value)
    }

    func setPaused(_ paused: Bool) {
        session.context.paused = paused
    }

    /// Also lifts the pause: a restart that leaves the world frozen reads as a
    /// button that did nothing, since the arena would sit empty and still.
    func restart() {
        session.inspector.recorder.clear()
        session.inspector.diagnostics.reset()
        SimulationBootstrap.restart(session.context)
        session.context.paused = false
        refreshHealth()
    }

    /// Adds or removes turret entities immediately — no restart, matching
    /// every other slider on this panel. `TurretFactory` also re-spaces every
    /// surviving turret around the core, since the ring's spacing depends on
    /// how many of them there are.
    func setTurretCount(_ count: Int) {
        TurretFactory.setCount(session.context, to: count)
    }

    func setTurretDamage(_ value: Float) {
        session.context.turretConfig.projectileDamage = value
    }

    func setTurretFireRate(_ shotsPerSecond: Float) {
        session.context.turretConfig.fireInterval = 1.0 / max(shotsPerSecond, 0.01)
    }

    func setSoundEnabled(_ enabled: Bool) {
        soundEnabled = enabled
        session.turretFireAudio.bus.outputVolume = enabled ? lastFireVolumePercent / 100.0 : 0
        session.enemyDeathAudio.bus.outputVolume = enabled ? lastExplosionVolumePercent / 100.0 : 0
    }

    func setTurretFireVolume(_ percent: Float) {
        lastFireVolumePercent = percent
        if soundEnabled { session.turretFireAudio.bus.outputVolume = percent / 100.0 }
    }

    func setEnemyExplosionVolume(_ percent: Float) {
        lastExplosionVolumePercent = percent
        if soundEnabled { session.enemyDeathAudio.bus.outputVolume = percent / 100.0 }
    }

    /// Zero fully excludes the archetype from `EnemySpawnSystem`'s weighted
    /// pick (already-alive members of that type stay dangerous as kamikazes
    /// through `ContactPayloadComponentStore` regardless — this only stops
    /// NEW spawns). Restoring uses the weight captured before the player
    /// touched anything, not a flat default, so relative spawn frequency
    /// between archetypes survives a disable/re-enable cycle.
    func setEnemyEnabled(_ index: Int, enabled: Bool) {
        guard index >= 0 && index < session.context.enemyArchetypes.count else { return }
        session.context.enemyArchetypes[index].spawnWeight = enabled ? session.enemyDefaultSpawnWeights[index] : 0
        session.context.rebuildArchetypeWeights()
    }

    func setEnemyMaxHealth(_ index: Int, value: Float) {
        guard index >= 0 && index < session.context.enemyArchetypes.count else { return }
        session.context.enemyArchetypes[index].maxHealth = value
    }

    func setEnemyMoveSpeed(_ index: Int, value: Float) {
        guard index >= 0 && index < session.context.enemyArchetypes.count else { return }
        session.context.enemyArchetypes[index].moveSpeed = value
    }

    /// Missiles per minute, not a raw interval: every other slider on this
    /// panel gets more aggressive as it moves right, and a raw interval slider
    /// would mean right = LESS frequent — backwards. Zero means "no missiles
    /// for this archetype", wired to `canFireMissiles` rather than a zero
    /// interval (which would mean firing every frame). The archetype stays a
    /// kamikaze either way.
    func setEnemyMissileRate(_ index: Int, ratePerMinute: Float) {
        guard index >= 0 && index < session.context.enemyArchetypes.count else { return }
        let archetype = session.context.enemyArchetypes[index]
        archetype.canFireMissiles = ratePerMinute > 0
        if archetype.canFireMissiles {
            archetype.missileFireInterval = 60.0 / ratePerMinute
        }
    }
}
