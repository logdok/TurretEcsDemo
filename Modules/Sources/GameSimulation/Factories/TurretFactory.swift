import AegisECS
import Foundation
import GameCore

/// Creates, destroys, and arranges the turret entities defending the core.
///
/// The only thing that ever changes at runtime is COUNT — no turret carries
/// state worth preserving over another (no per-turret upgrades, no identity
/// the player tracks), so growing or shrinking never tries to figure out
/// "which one to add or remove": it reconciles the whole ring to the new
/// count in one pass, every time.
package enum TurretFactory {
    /// Upper bound offered by the settings panel. Not an engine limit —
    /// `TurretComponentStore` is a plain packed store, it would hold hundreds
    /// without complaint — but past a handful the ring gets crowded and the
    /// extra draw calls (nine per turret, see `TurretPresenter`) start to
    /// matter on top of the thousands the enemy population already costs.
    package static let maxCount = 8

    /// Ring radius grows gently with turret count so barrels do not overlap.
    /// Even at `maxCount` this stays well inside `SimulationConfig.spawnRadius`
    /// (90 by default), so the ring never pokes out past where enemies
    /// themselves first appear.
    private static let baseRingRadius: Float = 24
    private static let ringRadiusPerTurret: Float = 6

    /// Adds or removes turret entities so exactly `desiredCount` (clamped to
    /// `1...maxCount`) exist, then spaces all of them evenly around
    /// `GameContext.corePosition`. Also updates `GameContext.turretCount`,
    /// the persisted setting `SimulationBootstrap.restart` re-applies after
    /// `World.reset()` wipes every entity.
    @discardableResult
    package static func setCount(_ context: GameContext, to desiredCount: Int) -> Int {
        let count = max(1, min(desiredCount, maxCount))
        let turrets = context.turrets!
        let current = Int(turrets.count)

        if current < count {
            for _ in current..<count {
                spawnOne(context)
            }
        } else if current > count {
            // Removed from the end: no turret's identity is more worth
            // keeping than another's, so only the resulting COUNT matters.
            // Destruction is deferred (`World.queueDestroy`), same as every
            // other entity removal in this project — the survivors get
            // repositioned below regardless of when the reaper actually
            // flushes these.
            for i in stride(from: current - 1, through: count, by: -1) {
                context.world.queueDestroy(turrets.denseEntities[i])
            }
        }

        layoutRing(context, count: count)
        context.turretCount = Int32(count)
        return count
    }

    @discardableResult
    private static func spawnOne(_ context: GameContext) -> Entity {
        let entity = context.world.createEntity()
        guard entity >= 0 else { return -1 }
        context.transforms.assign(entity, position: context.corePosition, heading: 0, scale: 1.0)
        context.turrets.assign(entity)
        context.healths.assign(entity, maxHealth: context.turretConfig.maxHealth)
        return entity
    }

    /// Places the first `count` entries of the turret store evenly around the
    /// core. A single turret is the one exception: it sits exactly at radius
    /// 0, matching the original single-turret layout rather than an
    /// arbitrary position on a "ring" of one.
    ///
    /// Only ever touches indices `0..<count`, deliberately not
    /// `turrets.count`: right after a shrink the store still holds the
    /// doomed surplus until the reaper flushes it, and those must not be
    /// repositioned into the new ring only to vanish next frame.
    private static func layoutRing(_ context: GameContext, count: Int) {
        guard count > 0 else { return }
        let turrets = context.turrets!
        let transforms = context.transforms!
        let radius: Float = count > 1 ? baseRingRadius + ringRadiusPerTurret * Float(count) : 0
        let angleStep = (2 * Float.pi) / Float(count)

        for i in 0..<count {
            let entity = turrets.denseEntities[i]
            let angle = angleStep * Float(i)
            let offset = SIMDVector3(sin(angle) * radius, 0, cos(angle) * radius)
            let position = context.corePosition + offset
            let slot = transforms.sparseIndex[Int(entity)]
            if slot >= 0 {
                transforms.position[Int(slot)] = position
            } else {
                transforms.assign(entity, position: position, heading: 0, scale: 1.0)
            }
        }
    }
}
