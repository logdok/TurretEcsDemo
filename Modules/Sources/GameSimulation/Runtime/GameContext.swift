import AegisECS
import Foundation
import GameCore

/// Shared, explicitly-passed simulation state.
///
/// This is a "god object" in the good sense: the single place every system
/// reads whatever it needs from, instead of holding private references to
/// each other. That keeps the dependency graph between systems FLAT — no
/// system knows another exists directly, they all communicate purely through
/// data here, and the only thing that determines final behaviour is the order
/// systems run in the scheduler.
///
/// The context knows nothing about render nodes: those live in the
/// presentation layer and read this object one way only — outward. No field
/// here is shaped by rendering's needs.
package final class GameContext {
    package static let queryResultLimit = 2048

    // MARK: Configuration
    package var config: SimulationConfig!
    package var turretConfig: TurretConfig!
    package var enemyArchetypes: [EnemyArchetypeConfig] = []

    // MARK: Core objects
    package var world: World!
    package var scheduler: Scheduler!
    package var rng: SeededRNG!

    // MARK: Component stores
    package var transforms: TransformComponentStore!
    package var velocities: VelocityComponentStore!
    package var healths: HealthComponentStore!
    package var locomotions: LocomotionComponentStore!
    package var colliders: ColliderComponentStore!
    package var projectiles: ProjectileComponentStore!
    package var lifetimes: LifetimeComponentStore!
    package var contactPayloads: ContactPayloadComponentStore!
    package var turrets: TurretComponentStore!
    package var hostiles: TagStore!
    package var missileLaunchers: MissileLauncherComponentStore!
    /// Marks an enemy missile in flight. Deliberately SEPARATE from
    /// `hostiles` — see `MissileSpatialIndexSystem` for why missiles must not
    /// join the index/population count that tag feeds.
    package var interceptables: TagStore!
    /// Indexed directly by `RenderArchetypeId`; entries may be nil.
    package var renderBatches: [RenderBatchComponentStore?] = []
    /// Same indexing as `renderBatches`, but the plain config data (mesh kind,
    /// albedo) rather than the live store. `RenderArchetypeConfig` is pure
    /// data with no Metal dependency, so game-layer code (`EnemyFactory`,
    /// for tinting a missile after its launcher's own rendered color) can
    /// read it without reaching into the presentation layer.
    package var renderArchetypeConfigs: [RenderArchetypeConfig?] = []

    // MARK: Broadphase
    package var spatialGrid: UniformSpatialGrid!
    package var scratchEntityIDs: [Int32] = []
    package var scratchPoints: [SIMDVector3] = []
    /// Second broadphase, built only from `interceptables`.
    package var missileSpatialGrid: UniformSpatialGrid!
    package var scratchMissileEntityIDs: [Int32] = []
    package var scratchMissilePoints: [SIMDVector3] = []

    // MARK: Damage queue
    // Preallocated, rewound by resetting the cursor; never reallocated at runtime.
    package var damageTargets: [Entity] = []
    package var damageAmounts: [Float] = []
    package var damageCount: Int = 0

    // MARK: Turret target coordination
    /// Per-entity "claimed as a target this frame" stamp, checked and set by
    /// `TurretTargetingSystem`/`TurretInterceptTargetingSystem` so several
    /// turrets spread across different targets instead of piling onto
    /// whichever one is nearest. A generation counter, not a cleared array:
    /// zeroing `targetClaimStamp` every frame would cost one write per world
    /// slot for a claim round that touches at most a handful of them — the
    /// same "rewind, don't clear" trick `damageCount` already uses. Sized to
    /// world capacity, so any entity id can be stamped directly with no
    /// bounds dance.
    package var targetClaimStamp: [Int64] = []
    package var targetClaimGeneration: Int64 = 0

    // MARK: Runtime state
    /// How many turret entities `TurretFactory` should maintain. A setting,
    /// like `targetPopulation` — not runtime state — so `resetRuntimeState()`
    /// leaves it alone and `SimulationBootstrap.restart` re-applies it after
    /// `World.reset()` wipes the entities themselves.
    package var turretCount: Int32 = 1
    package var corePosition: SIMDVector3 = .zero
    package var targetPopulation: Int32 = 0
    package var paused: Bool = false
    package var killCount: Int = 0
    /// Turrets destroyed by enemy contact/missile damage. Kept separate from
    /// `killCount` — see `DamageResolutionSystem` — so losing a turret is
    /// never miscounted as a kill.
    package var turretsLostCount: Int = 0
    /// Successful contact/kamikaze hits landed on a turret — see
    /// `CoreBreachSystem`. The core itself has no health of its own to
    /// breach; the essence of this simulation is turrets being worn down and
    /// destroyed, not an abstract base HP bar (see `areAllTurretsDestroyed`).
    package var breachCount: Int = 0
    package var shotsFired: Int = 0
    package var interceptCount: Int = 0
    package var maxColliderRadius: Float = 1

    private var archetypeWeights: [Float] = []
    private var archetypeWeightTotal: Float = 0

    package init() {}

    package func initialize(simulationConfig: SimulationConfig, weaponConfig: TurretConfig) {
        config = simulationConfig
        turretConfig = weaponConfig
        enemyArchetypes = simulationConfig.resolveEnemyArchetypes()

        corePosition = simulationConfig.corePosition
        targetPopulation = simulationConfig.targetPopulation

        rng = SeededRNG(seed: simulationConfig.randomSeed)

        let worldCapacity = Int(simulationConfig.computeWorldCapacity())
        scratchEntityIDs = [Int32](repeating: 0, count: worldCapacity)
        scratchPoints = [SIMDVector3](repeating: .zero, count: worldCapacity)
        damageTargets = [Entity](repeating: 0, count: worldCapacity)
        damageAmounts = [Float](repeating: 0, count: worldCapacity)
        let missileCapacity = Int(simulationConfig.maxMissileCapacity)
        scratchMissileEntityIDs = [Int32](repeating: 0, count: missileCapacity)
        scratchMissilePoints = [SIMDVector3](repeating: .zero, count: missileCapacity)
        targetClaimStamp = [Int64](repeating: 0, count: worldCapacity)

        renderBatches = [RenderBatchComponentStore?](repeating: nil, count: Int(RenderArchetypeId.count))
        renderArchetypeConfigs = [RenderArchetypeConfig?](repeating: nil, count: Int(RenderArchetypeId.count))
        rebuildArchetypeWeights()
    }

    /// Public because an archetype's "enabled" toggle in the settings panel
    /// changes `EnemyArchetypeConfig.spawnWeight` directly at runtime (see the
    /// app's handler): `pickEnemyArchetype` reads the cached tables below
    /// rather than the live field directly, so a weight change is invisible to
    /// the spawner until this is called again.
    ///
    /// **Trap:** setting `archetype.spawnWeight = 0` alone does NOT stop that
    /// archetype from spawning — this must be called again afterward. When
    /// re-enabling an archetype, restore its weight from a saved default (see
    /// `enemyDefaultSpawnWeights` in the app layer), not a flat constant —
    /// otherwise relative archetype frequencies (e.g. Drone 3.0 vs. Tank 1.0)
    /// drift.
    package func rebuildArchetypeWeights() {
        let total = enemyArchetypes.count
        archetypeWeights = [Float](repeating: 0, count: total)
        archetypeWeightTotal = 0
        maxColliderRadius = 1
        for i in 0..<total {
            let archetype = enemyArchetypes[i]
            archetypeWeightTotal += max(archetype.spawnWeight, 0)
            archetypeWeights[i] = archetypeWeightTotal
            maxColliderRadius = max(maxColliderRadius, archetype.colliderRadius)
        }
    }

    /// Weighted random archetype pick. Returns nil only when the archetype
    /// list is empty (or every weight is zero — e.g. the player disabled all
    /// of them at once).
    package func pickEnemyArchetype() -> EnemyArchetypeConfig? {
        let total = enemyArchetypes.count
        if total == 0 || archetypeWeightTotal <= 0 { return nil }
        let roll = rng.randf() * archetypeWeightTotal
        for i in 0..<total where roll <= archetypeWeights[i] {
            return enemyArchetypes[i]
        }
        return enemyArchetypes[total - 1]
    }

    package func getRenderBatch(_ archetypeId: Int32) -> RenderBatchComponentStore? {
        guard archetypeId >= 0 && Int(archetypeId) < renderBatches.count else { return nil }
        return renderBatches[Int(archetypeId)]
    }

    package func getRenderArchetypeConfig(_ archetypeId: Int32) -> RenderArchetypeConfig? {
        guard archetypeId >= 0 && Int(archetypeId) < renderArchetypeConfigs.count else { return nil }
        return renderArchetypeConfigs[Int(archetypeId)]
    }

    /// The archetype's actual on-screen color: its visual archetype's base
    /// albedo times its own tint — the same multiply
    /// `InstancedRenderSystem` performs at render time. Used to color a
    /// launched missile after whichever archetype fired it (see
    /// `EnemyFactory`) and to preview each archetype in the settings panel
    /// (see `GameViewModel.archetypePreview`).
    package func renderedColor(for archetype: EnemyArchetypeConfig) -> RGBA {
        guard let renderConfig = getRenderArchetypeConfig(archetype.renderArchetypeId) else { return archetype.tint }
        let albedo = renderConfig.albedo
        let tint = archetype.tint
        return RGBA(albedo.r * tint.r, albedo.g * tint.g, albedo.b * tint.b, albedo.a * tint.a)
    }

    /// Queues damage. Real application is deferred to `DamageResolutionSystem`
    /// — this function does not touch health itself.
    package func queueDamage(_ entity: Entity, amount: Float) {
        guard damageCount < damageTargets.count else { return }
        damageTargets[damageCount] = entity
        damageAmounts[damageCount] = amount
        damageCount += 1
    }

    package func resetDamageQueue() { damageCount = 0 }

    /// The real defeat condition: every turret worn down to a wreck (see
    /// `isTurretAlive`). `false` before the very first turret has even
    /// spawned — that is a startup instant, not a loss.
    package func areAllTurretsDestroyed() -> Bool {
        let turrets = turrets!
        guard turrets.count > 0 else { return false }
        for dense in 0..<Int(turrets.count) {
            if isTurretAlive(turrets.denseEntities[dense]) { return false }
        }
        return true
    }

    /// A turret with zero (or less) health is a WRECK, not a removed entity:
    /// its death leaves it standing on the battlefield, visually marked (see
    /// `TurretPresenter`), rather than going through `World.queueDestroy` the
    /// way a hostile's death does (see `DamageResolutionSystem`'s turret
    /// branch). Every system that acts on turrets — targeting, firing,
    /// intercept, `nearestTurretPosition`, `CoreBreachSystem` — checks this
    /// before treating one as active; nothing here removes a wreck from
    /// `context.turrets`, so it keeps its dense-array slot forever.
    package func isTurretAlive(_ entity: Entity) -> Bool {
        let slot = healths.sparseIndex[Int(entity)]
        return slot >= 0 && healths.current[Int(slot)] > 0
    }

    /// The nearest LIVE turret's position — what a hostile actually walks
    /// toward and what an enemy missile actually launches at, now that
    /// either can sit away from the exact core (see `TurretFactory`'s ring
    /// layout). A wreck is never a candidate: hostiles retarget to whichever
    /// turret is still standing the instant one falls, exactly like a target
    /// that died normally. Falls back to `corePosition` once every turret is
    /// gone (wrecked or otherwise) — the exposed-core end game; see
    /// `CoreBreachSystem`.
    ///
    /// A plain linear scan, not a spatial query: `TurretFactory.maxCount` (8)
    /// keeps this at worst a few dozen distance checks per hostile per frame
    /// — nothing next to the broadphase rebuild that already dominates frame
    /// cost (see `SpatialIndexSystem`).
    package func nearestTurretPosition(to point: SIMDVector3) -> SIMDVector3 {
        let turrets = turrets!
        guard turrets.count > 0 else { return corePosition }
        let transformSparse = transforms.sparseIndex
        let positions = transforms.position

        var best = corePosition
        var bestDistanceSq = Float.infinity
        for dense in 0..<Int(turrets.count) {
            let entity = turrets.denseEntities[dense]
            guard isTurretAlive(entity) else { continue }
            let slot = transformSparse[Int(entity)]
            guard slot >= 0 else { continue }
            let candidate = positions[Int(slot)]
            let distanceSq = candidate.distanceSquared(to: point)
            if distanceSq < bestDistanceSq {
                bestDistanceSq = distanceSq
                best = candidate
            }
        }
        return best
    }

    /// Starts a fresh target-claim round. Call exactly once per frame, before
    /// the first targeting pass runs — `TurretTargetingSystem` does this; the
    /// intercept pass right after it shares the same round rather than
    /// starting its own, so a turret's ordinary target and another turret's
    /// intercepted missile can never collide within one frame either.
    package func beginTargetClaimRound() {
        targetClaimGeneration += 1
    }

    package func isTargetClaimed(_ entity: Entity) -> Bool {
        entity >= 0 && targetClaimStamp[Int(entity)] == targetClaimGeneration
    }

    package func claimTarget(_ entity: Entity) {
        guard entity >= 0 else { return }
        targetClaimStamp[Int(entity)] = targetClaimGeneration
    }

    /// Restores runtime state without touching configuration or reallocating
    /// memory. Used on restart, layered on top of `World.reset()`.
    package func resetRuntimeState() {
        killCount = 0
        turretsLostCount = 0
        breachCount = 0
        shotsFired = 0
        interceptCount = 0
        damageCount = 0
    }
}
