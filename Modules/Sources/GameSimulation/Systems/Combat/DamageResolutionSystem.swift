import AegisECS
import GameCore

/// Drains the frame's damage queue in a single pass.
///
/// Centralising this means health has exactly one writer (the same principle
/// `MotionIntegrationSystem` applies to position) — kill counting and death
/// handling can never be double-applied or missed by some future damage
/// source. Damage sources (`ProjectileImpactSystem`, `CoreBreachSystem`
/// damaging a turret) never subtract health directly — they only ENQUEUE a
/// record via `GameContext.queueDamage`; the actual subtraction happens
/// here, centrally, for ANY entity with a health slot — hostile or turret
/// alike, this system does not care which.
final class DamageResolutionSystem: System {
    private var context: GameContext!

    override init() {
        super.init()
        systemName = "DamageResolution"
    }

    override func setup(world: World, context: Any?) {
        self.context = context as? GameContext
    }

    override func execute(delta: Float) {
        let context = context!
        let pending = context.damageCount
        if pending == 0 { return }

        let healths = context.healths!
        let healthSparse = healths.sparseIndex
        let current = healths.current
        let targets = context.damageTargets
        let amounts = context.damageAmounts
        let world = context.world!
        let hostiles = context.hostiles!
        let turrets = context.turrets!

        for index in 0..<pending {
            let entity = targets[index]
            let slot = healthSparse[Int(entity)]
            if slot < 0 { continue }
            // Already fatally wounded by an earlier record this same frame;
            // queueDestroy itself deduplicates a repeat enqueue.
            if current[Int(slot)] <= 0 { continue }
            current[Int(slot)] -= amounts[index]
            if current[Int(slot)] <= 0 {
                // A turret is the ONE kind of thing this store tracks health
                // for that must NOT be removed on death — checked explicitly
                // (not inferred from "isn't a hostile": an intercepted enemy
                // missile carries health too and is neither hostile nor
                // turret, and DOES need destroying like anything else here).
                if turrets.has(entity) {
                    // A turret's death is NOT a removal: the wreck stays on
                    // the battlefield, visually marked (`TurretPresenter`)
                    // instead of vanishing — see `GameContext.isTurretAlive`,
                    // which every turret-consuming system checks before
                    // treating this entity as active. The guard at the top of
                    // this loop already stops it from ever being damaged
                    // again, so leaving its health pinned at or below zero
                    // forever is enough; nothing more to do here.
                    context.turretsLostCount += 1
                } else {
                    world.queueDestroy(entity)
                    // Only an actual hostile counts as a kill — an
                    // intercepted missile is destroyed the same way but
                    // already has its own counter (`GameContext.
                    // interceptCount`, incremented by `ProjectileImpactSystem`
                    // the instant it lands the hit, not here).
                    if hostiles.has(entity) {
                        context.killCount += 1
                    }
                }
            }
        }

        context.resetDamageQueue()
    }
}
