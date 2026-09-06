import AegisECS

/// Seconds remaining before an entity self-destructs. Used by projectiles and
/// missiles: if a shot never hits anything it must not live forever and
/// clutter the stores/render
/// buffers. The initial value is normally computed by the spawning factory as
/// "time to reach the target, with margin" rather than a fixed constant.
package final class LifetimeComponentStore: PackedStore {
    private enum Column: Int32 { case remaining }

    init() { super.init(schema: [.float32]) }

    var remaining: UnsafeMutablePointer<Float> { columnF32(Column.remaining.rawValue)! }

    @discardableResult
    func assign(_ entity: Entity, seconds: Float) -> Int32 {
        let slot = attach(entity)
        guard slot >= 0 else { return slot }
        remaining[Int(slot)] = seconds
        return slot
    }
}
