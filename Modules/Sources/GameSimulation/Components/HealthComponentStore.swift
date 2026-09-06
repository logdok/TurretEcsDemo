import AegisECS

/// Hit points: `current` and `maximum` (kept separate so a health fraction can
/// be computed, e.g. to darken a wounded creature's tint in
/// `InstancedRenderSystem`).
///
/// **Only `DamageResolutionSystem` may write `current`.** Every other system
/// that detects damage queues it via `GameContext.queueDamage` instead of
/// subtracting directly — the same single-writer discipline used for entity
/// destruction, and for the same reason: several projectiles can hit the same
/// target in one frame, and a single application point avoids double-counting.
package final class HealthComponentStore: PackedStore {
    private enum Column: Int32 { case current, maximum }

    init() { super.init(schema: [.float32, .float32]) }

    package var current: UnsafeMutablePointer<Float> { columnF32(Column.current.rawValue)! }
    package var maximum: UnsafeMutablePointer<Float> { columnF32(Column.maximum.rawValue)! }

    @discardableResult
    func assign(_ entity: Entity, maxHealth: Float) -> Int32 {
        let slot = attach(entity)
        guard slot >= 0 else { return slot }
        current[Int(slot)] = maxHealth
        maximum[Int(slot)] = maxHealth
        return slot
    }
}
