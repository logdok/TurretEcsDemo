import AegisECS
import GameCore

/// Assembles a fired turret projectile from `TurretConfig`.
///
/// A projectile carries no collider of its own: hit resolution checks the
/// projectile's OWN impact radius against the TARGET's collider (see
/// `ProjectileImpactSystem`), not an intersection of two colliders — that
/// halves the stores the hot hit-testing loop needs to touch.
enum ProjectileFactory {
    @discardableResult
    static func spawn(context: GameContext, origin: SIMDVector3, linearVelocity: SIMDVector3) -> Entity {
        let entity = context.world.createEntity()
        guard entity >= 0 else { return -1 }

        let config = context.turretConfig!
        context.transforms.assign(entity, position: origin, heading: 0, scale: config.projectileVisualScale)
        context.velocities.assign(entity, linearVelocity: linearVelocity)
        context.projectiles.assign(entity, hitDamage: config.projectileDamage, hitRadius: config.projectileImpactRadius)
        context.lifetimes.assign(entity, seconds: config.projectileLifetime)

        if let batch = context.getRenderBatch(RenderArchetypeId.projectile) {
            batch.assign(entity, instanceTint: .white)
        }
        return entity
    }
}
