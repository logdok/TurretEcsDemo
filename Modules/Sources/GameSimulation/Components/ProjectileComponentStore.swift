import AegisECS

/// Payload carried by a fired turret projectile.
///
/// A projectile carries no collider of its own: hit resolution checks the
/// projectile's own `impactRadius` against the *target's* collider (see
/// `ProjectileImpactSystem`) rather than intersecting two colliders — half the
/// stores touched in the hot hit-testing loop.
package final class ProjectileComponentStore: PackedStore {
    private enum Column: Int32 { case damage, impactRadius }

    init() { super.init(schema: [.float32, .float32]) }

    var damage: UnsafeMutablePointer<Float> { columnF32(Column.damage.rawValue)! }
    var impactRadius: UnsafeMutablePointer<Float> { columnF32(Column.impactRadius.rawValue)! }

    @discardableResult
    func assign(_ entity: Entity, hitDamage: Float, hitRadius: Float) -> Int32 {
        let slot = attach(entity)
        guard slot >= 0 else { return slot }
        damage[Int(slot)] = hitDamage
        impactRadius[Int(slot)] = hitRadius
        return slot
    }
}
