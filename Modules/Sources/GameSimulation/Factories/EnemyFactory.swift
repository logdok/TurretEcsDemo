import AegisECS
import GameCore

/// Assembles a hostile entity from an `EnemyArchetypeConfig`.
///
/// Every component an enemy gets is decided HERE and nowhere else — so the
/// exact component set of an enemy can be read in one place instead of pieced
/// together from several systems. Same "factory as the single entity assembly
/// point" pattern as `ProjectileFactory`/`EnemyMissileFactory`.
enum EnemyFactory {
    @discardableResult
    static func spawn(context: GameContext, archetype: EnemyArchetypeConfig,
                              spawnPosition: SIMDVector3, heading: Float) -> Entity {
        let entity = context.world.createEntity()
        guard entity >= 0 else { return -1 }

        context.transforms.assign(entity, position: spawnPosition, heading: heading, scale: archetype.visualScale)
        context.velocities.assign(entity, linearVelocity: .zero)
        context.healths.assign(entity, maxHealth: archetype.maxHealth)
        context.locomotions.assign(entity,
            speed: archetype.moveSpeed,
            turn: archetype.turnRate,
            cruise: archetype.cruiseAltitude,
            strike: archetype.strikeAltitude,
            descent: archetype.descentRadius)
        context.colliders.assign(entity, sphereRadius: archetype.colliderRadius)
        context.contactPayloads.assign(entity, contactDamage: archetype.contactDamage, radius: archetype.contactTriggerRadius)
        context.hostiles.attach(entity)

        if archetype.canFireMissiles {
            // Initial cooldown is randomised so a whole batch spawned in one
            // frame does not fire a synchronised missile volley all at once.
            let initialCooldown = context.rng.randfRange(0, archetype.missileFireInterval)
            context.missileLaunchers.assign(entity, initialCooldown: initialCooldown, engageRange: archetype.missileRange,
                interval: archetype.missileFireInterval, speed: archetype.missileSpeed, damage: archetype.missileDamage,
                impactRadius: archetype.missileImpactRadius, tint: context.renderedColor(for: archetype))
        }

        if let batch = context.getRenderBatch(archetype.renderArchetypeId) {
            batch.assign(entity, instanceTint: archetype.tint)
        }
        return entity
    }
}
