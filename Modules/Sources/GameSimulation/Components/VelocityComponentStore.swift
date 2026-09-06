import AegisECS
import GameCore

/// Linear velocity in world units per second. Read not just by movement but
/// by the renderer too — `InstancedRenderSystem` uses it to orient
/// PROJECTILE/MISSILE entities along their flight direction.
package final class VelocityComponentStore: PackedStore {
    private enum Column: Int32 { case linear }

    init() { super.init(schema: [.vec3]) }

    package var linear: UnsafeMutablePointer<SIMDVector3> {
        columnData(Column.linear.rawValue)!.assumingMemoryBound(to: SIMDVector3.self)
    }

    @discardableResult
    func assign(_ entity: Entity, linearVelocity: SIMDVector3) -> Int32 {
        let slot = attach(entity)
        guard slot >= 0 else { return slot }
        linear[Int(slot)] = linearVelocity
        return slot
    }
}
