import AegisECS
import GameCore

/// Rebuilds the hostile broadphase exactly once per frame.
///
/// Turret targeting, projectile hit resolution and core-breach detection all
/// read the SAME index (`GameContext.spatialGrid`). Letting each of them
/// build its own was ruled out from the start: three rebuilds a frame
/// instead of one is tripled cost for zero
/// benefit, since entity positions do not change between these systems within
/// one frame (motion integration already ran earlier in the pipeline).
///
/// `GameContext.scratchEntityIDs`/`scratchPoints` are mutated directly
/// through the class-held array property. That is a plain in-place mutation
/// in Swift as long as nothing else holds a reference to the same buffer at
/// the same time — true here, since the context owns them outright and hands
/// them to nobody.
final class SpatialIndexSystem: System {
    private var context: GameContext!

    override init() {
        super.init()
        systemName = "SpatialIndex"
    }

    override func setup(world: World, context: Any?) {
        self.context = context as? GameContext
    }

    override func execute(delta: Float) {
        let context = context!
        let hostiles = context.hostiles!
        let transforms = context.transforms!

        let hostileIDs = hostiles.denseEntities
        let transformSparse = transforms.sparseIndex
        let positions = transforms.position

        var written = 0
        for dense in 0..<Int(hostiles.count) {
            let entity = hostileIDs[dense]
            let slot = transformSparse[Int(entity)]
            if slot < 0 { continue }
            context.scratchEntityIDs[written] = entity
            context.scratchPoints[written] = positions[Int(slot)]
            written += 1
        }

        context.spatialGrid.rebuild(entityIDs: context.scratchEntityIDs, points: context.scratchPoints, entryCount: written)
    }
}
