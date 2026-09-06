import AegisECS

/// Bounding-sphere radius, used both by the broadphase (as a neighbour-search
/// radius) and by hit resolution (as a point-collision radius).
///
/// The MVP checks a projectile's impact as a point query against this radius
/// rather than a sweep — see `ProjectileImpactSystem`.
/// `GameContext.maxColliderRadius` caches the largest value across archetypes
/// so a broadphase search margin never misses an unusually large collider.
package final class ColliderComponentStore: PackedStore {
    private enum Column: Int32 { case radius }

    init() { super.init(schema: [.float32]) }

    var radius: UnsafeMutablePointer<Float> { columnF32(Column.radius.rawValue)! }

    @discardableResult
    func assign(_ entity: Entity, sphereRadius: Float) -> Int32 {
        let slot = attach(entity)
        guard slot >= 0 else { return slot }
        radius[Int(slot)] = sphereRadius
        return slot
    }
}
