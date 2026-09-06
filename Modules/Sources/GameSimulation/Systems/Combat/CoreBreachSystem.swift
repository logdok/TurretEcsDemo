import AegisECS
import GameCore

/// Applies "contact" payloads that reached a turret, consuming their carrier
/// and damaging that turret's own health — the melee/kamikaze side of
/// combat, the counterpart to `ProjectileImpactSystem` on the turret's own
/// firing side.
///
/// The essence of this simulation is turrets being worn down and destroyed
/// (see `GameContext.areAllTurretsDestroyed`) — there is no separate,
/// abstract "core health" a hit here drains instead; every contact payload
/// that lands damages the specific turret it reached, queued via
/// `GameContext.queueDamage` and applied centrally by
/// `DamageResolutionSystem` — same single-writer discipline as every other
/// damage source, and the same generic health/death handling that already
/// turns a turret into a wreck exactly like it would destroy a hostile.
///
/// Rather than scanning every hostile entity, one sphere query around each
/// LIVE turret returns just the handful of candidates actually close enough
/// to matter. Run TWICE per turret per frame — once against the
/// ordinary-enemy grid (melee contact/kamikaze), once against the missile
/// grid (an uncaught missile) — both sources carry the same
/// `ContactPayloadComponentStore`, so one small helper (`resolveGrid`)
/// resolves both cases identically, with no duplicated "enemy" vs. "missile"
/// logic.
///
/// **Invariant this relies on:** no candidate can ever be within
/// `widestTriggerRadius` of two turrets at once, so the same entity is never
/// double-processed (double-damaged) across two turrets' queries in the same
/// frame. `TurretFactory`'s ring spacing keeps turrets many times farther
/// apart than the widest trigger/impact radius in the roster — if that ring
/// geometry is ever tightened dramatically, this invariant is the thing to
/// re-check.
final class CoreBreachSystem: System {
    private var context: GameContext!
    private var widestTriggerRadius: Float = 1.0

    override init() {
        super.init()
        systemName = "CoreBreach"
        requiresTime = true
    }

    /// Computes the widest possible trigger radius across ALL archetypes up
    /// front, once, at startup — the upper bound for the query-sphere radius
    /// in `resolveGrid`, so no candidate with an unusually large
    /// `contactTriggerRadius`/`missileImpactRadius` is ever missed.
    override func setup(world: World, context: Any?) {
        self.context = context as? GameContext
        guard let context = self.context else { return }
        for archetype in context.enemyArchetypes {
            widestTriggerRadius = max(widestTriggerRadius, archetype.contactTriggerRadius)
            if archetype.canFireMissiles {
                widestTriggerRadius = max(widestTriggerRadius, archetype.missileImpactRadius)
            }
        }
    }

    override func execute(delta: Float) {
        let context = context!
        if context.contactPayloads.count == 0 { return }

        let turrets = context.turrets!
        let transformSparse = context.transforms!.sparseIndex
        let positions = context.transforms!.position

        for dense in 0..<Int(turrets.count) {
            let entity = turrets.denseEntities[dense]
            // A wreck (see GameContext.isTurretAlive) has no more health to
            // lose, and nothing steers toward it any more either (see
            // `GameContext.nearestTurretPosition`) — querying around it would
            // only waste a call.
            guard context.isTurretAlive(entity) else { continue }
            let slot = transformSparse[Int(entity)]
            guard slot >= 0 else { continue }
            let point = positions[Int(slot)]
            resolveGrid(context.spatialGrid, around: point, turret: entity)
            resolveGrid(context.missileSpatialGrid, around: point, turret: entity)
        }
    }

    private func resolveGrid(_ grid: UniformSpatialGrid, around point: SIMDVector3, turret: Entity) {
        let context = context!
        let candidateCount = grid.querySphere(center: point, radius: widestTriggerRadius,
                                               resultLimit: GameContext.queryResultLimit)
        if candidateCount == 0 { return }

        let candidates = grid.queryBuffer
        let payloads = context.contactPayloads!
        let transforms = context.transforms!
        let transformSparse = transforms.sparseIndex
        let payloadSparse = payloads.sparseIndex
        let positions = transforms.position
        let triggerRadius = payloads.triggerRadius
        let damage = payloads.damage

        for index in 0..<candidateCount {
            let entity = candidates[index]
            let payloadSlot = payloadSparse[Int(entity)]
            if payloadSlot < 0 { continue }
            let transformSlot = transformSparse[Int(entity)]
            if transformSlot < 0 { continue }
            let reach = triggerRadius[Int(payloadSlot)]
            if positions[Int(transformSlot)].distanceSquared(to: point) > reach * reach { continue }
            context.queueDamage(turret, amount: damage[Int(payloadSlot)])
            context.breachCount += 1
            context.world.queueDestroy(entity)
        }
    }
}
