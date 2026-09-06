import AegisECS
import GameCore

/// Rebuilds the missile broadphase exactly once per frame — mirrors
/// `SpatialIndexSystem`, but over `GameContext.interceptables` rather than
/// hostiles.
///
/// **A second, separate grid is a deliberate choice:** if missiles shared
/// `hostiles` with ordinary enemies, that would
/// pull them into two systems that have no business seeing them — the
/// population count in `EnemySpawnSystem` (a missile would count as an
/// "enemy" against `targetPopulation`, skewing the slider's meaning) and the
/// turret's main targeting query (the turret would start getting distracted by
/// missiles instead of leaving that to the dedicated
/// `TurretInterceptTargetingSystem`). An in-flight missile is ordnance, not
/// population, so it gets its own tag, its own grid, and its own targeting pass.
final class MissileSpatialIndexSystem: System {
    private var context: GameContext!

    override init() {
        super.init()
        systemName = "MissileSpatialIndex"
    }

    override func setup(world: World, context: Any?) {
        self.context = context as? GameContext
    }

    override func execute(delta: Float) {
        let context = context!
        let interceptables = context.interceptables!
        let transforms = context.transforms!

        let missileIDs = interceptables.denseEntities
        let transformSparse = transforms.sparseIndex
        let positions = transforms.position
        let bufferLimit = context.scratchMissileEntityIDs.count

        var written = 0
        for dense in 0..<Int(interceptables.count) {
            if written >= bufferLimit { break }
            let entity = missileIDs[dense]
            let slot = transformSparse[Int(entity)]
            if slot < 0 { continue }
            context.scratchMissileEntityIDs[written] = entity
            context.scratchMissilePoints[written] = positions[Int(slot)]
            written += 1
        }

        context.missileSpatialGrid.rebuild(
            entityIDs: context.scratchMissileEntityIDs, points: context.scratchMissilePoints, entryCount: written)
    }
}
