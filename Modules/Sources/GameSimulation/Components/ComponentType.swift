import Foundation

/// Stable identifiers for every component store registered in the world.
///
/// Render batches occupy a contiguous block of ids starting at
/// `renderBatchBase`: the store for visual archetype `a` registers under
/// `renderBatchBase + a` (see `RenderArchetypeId` and
/// `GameContext.renderBatches`, an array indexed directly by archetype id
/// rather than a separate map). This lets a new visual archetype exist just by
/// growing `RenderArchetypeId.count`, with no edit to this file.
enum ComponentType {
    static let transform: Int32 = 0
    static let velocity: Int32 = 1
    static let health: Int32 = 2
    static let locomotion: Int32 = 3
    static let collider: Int32 = 4
    static let projectile: Int32 = 5
    static let lifetime: Int32 = 6
    static let contactPayload: Int32 = 7
    static let turret: Int32 = 8
    static let hostileTag: Int32 = 9
    static let missileLauncher: Int32 = 10
    static let interceptableTag: Int32 = 11
    static let renderBatchBase: Int32 = 12
}
