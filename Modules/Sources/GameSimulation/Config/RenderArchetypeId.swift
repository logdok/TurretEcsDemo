import Foundation

/// One identifier per instanced batch. One batch equals one draw
/// call, so the list is deliberately short — adding an entry costs one draw
/// call every single frame.
package enum RenderArchetypeId {
    package static let tank: Int32 = 0
    package static let drone: Int32 = 1
    package static let projectile: Int32 = 2
    /// Enemy missiles: split out of `projectile` so a player can tell an
    /// incoming missile from a turret shot at a glance, not just by tint.
    package static let missile: Int32 = 3

    package static let count: Int32 = 4
}
