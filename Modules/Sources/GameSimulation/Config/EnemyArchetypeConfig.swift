import Foundation
import GameCore

/// Blueprint for a hostile unit. Adding a new enemy type means
/// creating one of these and appending it to
/// `SimulationConfig.enemyArchetypes` — no other code changes.
package final class EnemyArchetypeConfig {
    package var displayName: String = "Hostile"
    package var renderArchetypeId: Int32 = RenderArchetypeId.tank

    /// Relative probability of being picked by the spawner.
    package var spawnWeight: Float = 1.0

    // MARK: Durability
    package var maxHealth: Float = 60.0
    package var colliderRadius: Float = 0.6

    // MARK: Movement
    package var moveSpeed: Float = 6.0
    package var turnRate: Float = 8.0
    package var cruiseAltitude: Float = 0.8
    package var strikeAltitude: Float = 0.8
    package var descentRadius: Float = 0.0

    // MARK: Payload
    package var contactDamage: Float = 25.0
    package var contactTriggerRadius: Float = 3.2

    // MARK: Missile Attack
    /// Whether this archetype also fires missiles at the core in addition to
    /// its melee/contact payload. A purely melee type is just this flag off.
    package var canFireMissiles: Bool = true
    package var missileRange: Float = 65.0
    /// Deliberately LONG relative to how long one enemy takes to cross the
    /// arena: at thousands of enemies alive at once, even a modest per-enemy
    /// fire rate sums into a barrage no single-barrel turret could ever fully
    /// intercept. See `TurretInterceptTargetingSystem`.
    package var missileFireInterval: Float = 20.0
    package var missileSpeed: Float = 24.0
    package var missileDamage: Float = 18.0
    package var missileImpactRadius: Float = 0.6

    // MARK: Presentation
    package var visualScale: Float = 1.0
    package var tint: RGBA = RGBA(1.0, 1.0, 1.0)

    package init() {}

    /// Default two-archetype roster, used when
    /// `SimulationConfig.enemyArchetypes` is left empty.
    package static func createDefaultRoster() -> [EnemyArchetypeConfig] {
        let tank = EnemyArchetypeConfig()
        tank.displayName = "Tank"
        tank.renderArchetypeId = RenderArchetypeId.tank
        tank.spawnWeight = 1.0
        tank.maxHealth = 320.0
        tank.colliderRadius = 1.2
        tank.moveSpeed = 3.4
        tank.turnRate = 4.0
        tank.cruiseAltitude = 1.2
        tank.strikeAltitude = 1.2
        tank.contactDamage = 140.0
        tank.contactTriggerRadius = 4.0
        tank.missileRange = 70.0
        tank.missileFireInterval = 28.0
        tank.missileSpeed = 18.0
        tank.missileDamage = 34.0
        tank.missileImpactRadius = 0.9
        tank.visualScale = 1.0
        tank.tint = RGBA(0.95, 0.85, 0.85)

        let drone = EnemyArchetypeConfig()
        drone.displayName = "Drone"
        drone.renderArchetypeId = RenderArchetypeId.drone
        drone.spawnWeight = 3.0
        drone.maxHealth = 40.0
        drone.colliderRadius = 0.55
        drone.moveSpeed = 9.5
        drone.turnRate = 9.0
        // Deliberately above the turret's own pivot, which sits at
        // `TurretConfig.muzzleHeight` (18.2). Any cruise altitude below that
        // leaves the turret only ever pitching DOWN at the drone — visually
        // monotonous, and it never shows off the barrel's upward range. 30
        // sits well clear of the pivot, so tracking a cruising drone
        // genuinely elevates the barrel and sends shots arcing up over the
        // turret's own housing; the dive
        // onto `strikeAltitude` near the core is unchanged.
        drone.cruiseAltitude = 30.0
        drone.strikeAltitude = 2.0
        drone.descentRadius = 26.0
        drone.contactDamage = 30.0
        drone.missileRange = 80.0
        drone.missileFireInterval = 16.0
        drone.missileSpeed = 34.0
        drone.missileDamage = 14.0
        drone.missileImpactRadius = 0.5
        drone.visualScale = 1.0
        drone.tint = RGBA(0.85, 0.97, 1.0)

        return [tank, drone]
    }
}
