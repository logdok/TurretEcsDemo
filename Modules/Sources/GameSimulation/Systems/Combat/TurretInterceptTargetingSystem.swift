import AegisECS
import GameCore

/// Second targeting pass: prioritises an incoming missile over the turret's
/// ordinary target.
///
/// Runs RIGHT AFTER `TurretTargetingSystem` and, once a missile enters
/// `TurretConfig.interceptRange`, OVERWRITES `TurretComponentStore.targetEntity`
/// with it for this frame — so the already-existing `TurretFiringSystem`
/// starts shooting at it, with no second barrel or projectile type (see the
/// general explanation of this trick on `TurretComponentStore`).
///
/// **The override is self-healing:** next frame, `TurretTargetingSystem` will
/// find the held target no longer belongs to `GameContext.hostiles` (a
/// missile was never in it — see `MissileSpatialIndexSystem`) and reacquire a
/// proper target among ordinary enemies on its own, even before this system
/// runs again and, if the missile is still alive and in range, re-imposes the
/// intercept. No explicit "restore the main target" logic is needed.
final class TurretInterceptTargetingSystem: System {
    /// A candidate must be closer than this fraction (linear, not squared,
    /// distance) of the distance to the already-held target to be worth
    /// dropping a still-valid current target for.
    static let retargetSwitchMargin: Float = 0.5
    static let retargetSwitchMarginSq: Float = retargetSwitchMargin * retargetSwitchMargin

    private var context: GameContext!

    override init() {
        super.init()
        systemName = "TurretInterceptTargeting"
    }

    override func setup(world: World, context: Any?) {
        self.context = context as? GameContext
    }

    override func execute(delta: Float) {
        let context = context!
        let turrets = context.turrets!
        if turrets.count == 0 { return }

        let config = context.turretConfig!
        let transforms = context.transforms!
        let interceptables = context.interceptables!
        let transformSparse = transforms.sparseIndex
        let positions = transforms.position
        let rangeSquared = config.interceptRange * config.interceptRange

        // A missile descending toward the core also drops below the barrel's
        // depression limit. Capturing it after that is pointless — the same
        // decision TurretTargetingSystem makes for ordinary targets.
        let muzzleLift = SIMDVector3(0, config.muzzleHeight, 0)
        let minPitchTan = config.minPitchTangent()

        for dense in 0..<Int(turrets.count) {
            let entity = turrets.denseEntities[dense]
            // A wreck (see GameContext.isTurretAlive) cannot intercept
            // anything — it stays on the field, inert.
            if !context.isTurretAlive(entity) { continue }
            var origin = context.corePosition
            let ownSlot = transformSparse[Int(entity)]
            if ownSlot >= 0 { origin = positions[Int(ownSlot)] }
            let pivot = origin + muzzleLift

            turrets.interceptRetargetTimer[dense] -= delta
            let timerDue = turrets.interceptRetargetTimer[dense] <= 0
            var target = turrets.interceptTargetEntity[dense]
            var targetDistanceSq: Float = -1

            if target >= 0 {
                let targetSlot = transformSparse[Int(target)]
                if targetSlot < 0 || !interceptables.has(target) {
                    target = -1
                } else {
                    targetDistanceSq = positions[Int(targetSlot)].distanceSquared(to: origin)
                    if targetDistanceSq > rangeSquared {
                        target = -1
                    } else if !TurretConfig.isReachable(pivot: pivot, point: positions[Int(targetSlot)], minPitchTan: minPitchTan) {
                        target = -1
                    }
                }
            }

            if target < 0 {
                target = acquireReachableMissile(context: context, origin: origin, pivot: pivot, config: config, minPitchTan: minPitchTan)
                turrets.interceptRetargetTimer[dense] = config.interceptRetargetInterval
            } else if timerDue {
                turrets.interceptRetargetTimer[dense] = config.interceptRetargetInterval
                let candidate = acquireReachableMissile(context: context, origin: origin, pivot: pivot, config: config, minPitchTan: minPitchTan)
                if candidate >= 0 && candidate != target {
                    let candidateSlot = transformSparse[Int(candidate)]
                    if candidateSlot >= 0 {
                        let candidateDistanceSq = positions[Int(candidateSlot)].distanceSquared(to: origin)
                        if candidateDistanceSq < targetDistanceSq * Self.retargetSwitchMarginSq {
                            target = candidate
                        }
                    }
                }
            }

            turrets.interceptTargetEntity[dense] = target
            if target >= 0 {
                turrets.targetEntity[dense] = target
                // Shares TurretTargetingSystem's claim round: a missile one
                // turret is already intercepting should not also get
                // assigned to another turret's ordinary or intercept search.
                context.claimTarget(target)
            }
        }
    }

    /// Nearest missile the barrel can reach by elevation angle. Full analogue
    /// of `TurretTargetingSystem.scanReachable`, but over the missile grid,
    /// where candidates are guaranteed few (never more than
    /// `SimulationConfig.maxMissileCapacity`), so a plain scan here is cheap.
    ///
    /// Tries to avoid a missile another turret already claimed this frame
    /// first, then falls back to any reachable missile at all — with more
    /// turrets than incoming missiles, doubling up on one beats leaving a
    /// turret idle while it could be shooting.
    private func acquireReachableMissile(context: GameContext, origin: SIMDVector3, pivot: SIMDVector3,
                                          config: TurretConfig, minPitchTan: Float) -> Entity {
        let claimAware = scanReachableMissile(context: context, origin: origin, pivot: pivot,
                                               config: config, minPitchTan: minPitchTan, avoidClaimed: true)
        if claimAware >= 0 { return claimAware }
        return scanReachableMissile(context: context, origin: origin, pivot: pivot,
                                     config: config, minPitchTan: minPitchTan, avoidClaimed: false)
    }

    private func scanReachableMissile(context: GameContext, origin: SIMDVector3, pivot: SIMDVector3,
                                       config: TurretConfig, minPitchTan: Float, avoidClaimed: Bool) -> Entity {
        let grid = context.missileSpatialGrid!
        let found = grid.querySphere(center: origin, radius: config.interceptRange, resultLimit: GameContext.queryResultLimit)
        if found == 0 { return -1 }

        let candidates = grid.queryBuffer
        let slots = context.transforms.sparseIndex
        let positions = context.transforms.position

        var best: Entity = -1
        var bestDistanceSq = Float.infinity
        for i in 0..<found {
            let entity = candidates[i]
            let slot = slots[Int(entity)]
            if slot < 0 { continue }
            if avoidClaimed && context.isTargetClaimed(entity) { continue }
            let point = positions[Int(slot)]
            if !TurretConfig.isReachable(pivot: pivot, point: point, minPitchTan: minPitchTan) { continue }
            let distanceSq = point.distanceSquared(to: origin)
            if distanceSq < bestDistanceSq {
                bestDistanceSq = distanceSq
                best = entity
            }
        }
        return best
    }
}
