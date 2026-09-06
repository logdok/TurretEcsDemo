import AegisECS
import GameCore

/// Decrements each time-limited entity's remaining lifetime and destroys any
/// that expired. Applies to projectiles
/// and missiles: a shot that hit nothing must not exist forever and clutter
/// the stores/render buffers.
final class LifetimeExpirySystem: System {
    private var context: GameContext!

    override init() {
        super.init()
        systemName = "LifetimeExpiry"
        requiresTime = true
    }

    override func setup(world: World, context: Any?) {
        self.context = context as? GameContext
    }

    override func execute(delta: Float) {
        let context = context!
        let lifetimes = context.lifetimes!
        if lifetimes.count == 0 { return }

        let world = context.world!
        let identifiers = lifetimes.denseEntities
        let remaining = lifetimes.remaining

        for dense in 0..<Int(lifetimes.count) {
            remaining[dense] -= delta
            if remaining[dense] <= 0 {
                world.queueDestroy(identifiers[dense])
            }
        }
    }
}
