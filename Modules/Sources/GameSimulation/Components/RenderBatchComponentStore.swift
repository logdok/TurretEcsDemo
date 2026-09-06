import AegisECS
import GameCore

/// Membership in exactly one visual archetype, plus a per-instance tint.
///
/// Each visual archetype gets its OWN store (see `GameContext.renderBatches`,
/// indexed directly by archetype id — not a shared dictionary), rather than
/// one shared store with an "which archetype am I" field. That turns the
/// render pass into a direct walk of each batch's own dense array with no
/// filter check at all — the reason rendering scales to 10k instances in the
/// first place (see `InstancedRenderSystem`: every entity walked is an entity
/// drawn).
package final class RenderBatchComponentStore: PackedStore {
    private enum Column: Int32 { case tint }

    /// Same value for every entity in this particular store instance — one
    /// store per archetype, set once when the store is created (see
    /// `SimulationBootstrap`), not a per-entity column.
    package var archetypeId: Int32 = 0

    init() { super.init(schema: [.vec4]) }

    package var tint: UnsafeMutablePointer<RGBA> {
        columnData(0)!.assumingMemoryBound(to: RGBA.self)
    }

    @discardableResult
    func assign(_ entity: Entity, instanceTint: RGBA) -> Int32 {
        let slot = attach(entity)
        guard slot >= 0 else { return slot }
        tint[Int(slot)] = instanceTint
        return slot
    }
}
