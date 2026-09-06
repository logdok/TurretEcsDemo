import AegisECS
import GameCore

/// Missile-attack state for one enemy, copied from `EnemyArchetypeConfig` at
/// spawn time by `EnemyFactory`.
///
/// Only entities whose archetype turned this on
/// (`EnemyArchetypeConfig.canFireMissiles`) carry this component, which keeps
/// `EnemyMissileFiringSystem`'s dense array limited to actual "shooters"
/// rather than every hostile on the arena.
package final class MissileLauncherComponentStore: PackedStore {
    private enum Column: Int32 { case cooldown, engagementRange, fireInterval, missileSpeed, missileDamage, missileImpactRadius, tint }

    init() { super.init(schema: [.float32, .float32, .float32, .float32, .float32, .float32, .vec4]) }

    var cooldown: UnsafeMutablePointer<Float> { columnF32(Column.cooldown.rawValue)! }
    var engagementRange: UnsafeMutablePointer<Float> { columnF32(Column.engagementRange.rawValue)! }
    var fireInterval: UnsafeMutablePointer<Float> { columnF32(Column.fireInterval.rawValue)! }
    var missileSpeed: UnsafeMutablePointer<Float> { columnF32(Column.missileSpeed.rawValue)! }
    var missileDamage: UnsafeMutablePointer<Float> { columnF32(Column.missileDamage.rawValue)! }
    var missileImpactRadius: UnsafeMutablePointer<Float> { columnF32(Column.missileImpactRadius.rawValue)! }
    /// The launching archetype's own rendered color (see
    /// `GameContext.renderedColor(for:)`), copied at spawn time so a fired
    /// missile can be tinted to match whoever launched it.
    var tint: UnsafeMutablePointer<RGBA> { columnData(Column.tint.rawValue)!.assumingMemoryBound(to: RGBA.self) }

    @discardableResult
    func assign(_ entity: Entity, initialCooldown: Float, engageRange: Float, interval: Float,
                        speed: Float, damage: Float, impactRadius: Float, tint launcherTint: RGBA) -> Int32 {
        let slot = attach(entity)
        guard slot >= 0 else { return slot }
        cooldown[Int(slot)] = initialCooldown
        engagementRange[Int(slot)] = engageRange
        fireInterval[Int(slot)] = interval
        missileSpeed[Int(slot)] = speed
        missileDamage[Int(slot)] = damage
        missileImpactRadius[Int(slot)] = impactRadius
        tint[Int(slot)] = launcherTint
        return slot
    }
}
