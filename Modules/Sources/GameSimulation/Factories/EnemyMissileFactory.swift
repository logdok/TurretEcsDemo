import AegisECS
import Foundation
import GameCore

/// Assembles an enemy missile: a one-hit, non-homing enemy shot that flies
/// straight at the core and can be shot down in flight.
///
/// Composition deliberately MIRRORS `ProjectileFactory` — a missile is,
/// fundamentally, the enemy's version of a turret shot — but additionally
/// carries a `ContactPayloadComponentStore`, so an uncaught missile damages
/// the core exactly like a kamikaze hostile's melee contact (see
/// `CoreBreachSystem`), and exactly one hit point, so any turret projectile
/// that connects destroys it outright.
enum EnemyMissileFactory {
    static let visualScale: Float = 1.6
    static let lifetimeMargin: Float = 1.0

    @discardableResult
    static func spawn(context: GameContext, origin: SIMDVector3, targetPosition: SIMDVector3,
                              speed: Float, damage: Float, impactRadius: Float, tint: RGBA) -> Entity {
        let entity = context.world.createEntity()
        guard entity >= 0 else { return -1 }

        let offset = targetPosition - origin
        let distance = offset.length
        let direction = distance > 0.001 ? offset / distance : SIMDVector3(0, 0, 1)
        let linearVelocity = direction * speed
        // Zero yaw points along +Z — the same convention TurretFiringSystem uses.
        let heading = atan2(direction.x, direction.z)

        context.transforms.assign(entity, position: origin, heading: heading, scale: visualScale)
        context.velocities.assign(entity, linearVelocity: linearVelocity)
        context.healths.assign(entity, maxHealth: 1.0)
        context.colliders.assign(entity, sphereRadius: impactRadius)
        context.contactPayloads.assign(entity, contactDamage: damage, radius: impactRadius)
        context.lifetimes.assign(entity, seconds: distance / max(speed, 0.001) + lifetimeMargin)
        context.interceptables.attach(entity)

        // Tinted to match the launching archetype's own rendered color (see
        // GameContext.renderedColor(for:)) rather than a fixed color, so a
        // missile reads as "whose" it is at a glance.
        if let batch = context.getRenderBatch(RenderArchetypeId.missile) {
            batch.assign(entity, instanceTint: tint)
        }
        return entity
    }
}
