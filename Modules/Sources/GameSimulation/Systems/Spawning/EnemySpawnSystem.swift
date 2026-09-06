import AegisECS
import Foundation
import GameCore

/// Maintains the live enemy population at `GameContext.targetPopulation`.
///
/// Population is a CONTINUOUS target, not a level parameter. Raising the UI
/// slider does not rebuild the scene or spawn everyone at once — it just
/// changes `targetPopulation`, and this system compares that every frame
/// against the current live count (`hostiles.count`) and either SPAWNS the
/// shortfall (capped at `maxSpawnsPerFrame` a frame, so a big slider jump
/// cannot create hundreds of entities in one frame and stall) or CULLS the
/// excess (same cap, `maxCullsPerFrame`). Lowering the slider needs no
/// rebuild either — the population just "melts" over a few frames.
final class EnemySpawnSystem: System {
    private var context: GameContext!

    override init() {
        super.init()
        systemName = "EnemySpawn"
        requiresTime = true
    }

    override func setup(world: World, context: Any?) {
        self.context = context as? GameContext
    }

    override func execute(delta: Float) {
        let context = context!
        let live = Int(context.hostiles.count)
        let target = Int(context.targetPopulation)
        if live < target {
            spawnBatch(min(target - live, Int(context.config.maxSpawnsPerFrame)))
        } else if live > target {
            cullBatch(min(live - target, Int(context.config.maxCullsPerFrame)))
        }
    }

    /// Spawns `amount` new enemies on a ring around the core at
    /// `SimulationConfig.spawnRadius` (with a small 0.92-1.08 random jitter so
    /// enemies do not line up in a perfectly even ring). Each enemy's
    /// archetype is a weighted random pick via `GameContext.pickEnemyArchetype`.
    private func spawnBatch(_ amount: Int) {
        let context = context!
        let config = context.config!
        let rng = context.rng!
        let core = context.corePosition

        for _ in 0..<amount {
            guard let archetype = context.pickEnemyArchetype() else { return }
            let angle = rng.randf() * (2 * Float.pi)
            let distance = config.spawnRadius * rng.randfRange(0.92, 1.08)
            let spawnPosition = SIMDVector3(
                core.x + sin(angle) * distance,
                archetype.cruiseAltitude,
                core.z + cos(angle) * distance)
            // Face the core immediately, so the very first frame does not show
            // a sharp on-the-spot turn.
            let heading = angle + Float.pi
            if EnemyFactory.spawn(context: context, archetype: archetype, spawnPosition: spawnPosition, heading: heading) < 0 {
                return
            }
        }
    }

    /// Culls the excess population from the TAIL of the dense array.
    /// Destruction is deferred (`World.queueDestroy`), so the dense array
    /// layout stays stable while this loop walks it — an immediate destroy
    /// would swap-remove entries mid-loop and risk skipping one or handling
    /// one twice.
    private func cullBatch(_ amount: Int) {
        let context = context!
        let hostiles = context.hostiles!
        let identifiers = hostiles.denseEntities
        var cursor = Int(hostiles.count)
        for _ in 0..<amount {
            cursor -= 1
            if cursor < 0 { return }
            context.world.queueDestroy(identifiers[cursor])
        }
    }
}
