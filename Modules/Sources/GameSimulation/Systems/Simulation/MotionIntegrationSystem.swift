import AegisECS
import GameCore

/// The single writer of `TransformComponentStore.position`.
///
/// Steering and aiming systems express intent only through velocity — they
/// never write position directly. Integrating velocity into position
/// (`position += velocity * delta`) happens HERE, once, for every moving
/// entity regardless of its kind. Same single-writer principle as health
/// (`DamageResolutionSystem`) and destruction (`World.flushDestroyQueue`):
/// the fewer places write the same field, the easier it is to guarantee the
/// pipeline order produces a predictable result.
final class MotionIntegrationSystem: System {
    private var context: GameContext!

    override init() {
        super.init()
        systemName = "MotionIntegration"
        requiresTime = true
    }

    override func setup(world: World, context: Any?) {
        self.context = context as? GameContext
    }

    override func execute(delta: Float) {
        let context = context!
        let velocities = context.velocities!
        let transforms = context.transforms!

        let identifiers = velocities.denseEntities
        let transformSparse = transforms.sparseIndex
        let linear = velocities.linear
        let positions = transforms.position

        for dense in 0..<Int(velocities.count) {
            let slot = transformSparse[Int(identifiers[dense])]
            if slot < 0 { continue }
            positions[Int(slot)] = positions[Int(slot)] + linear[dense] * delta
        }
    }
}
