import AegisECS
import GameCore

/// Picks and holds a target for the turret.
///
/// Re-picking is deliberately rate-limited via `TurretConfig.retargetInterval`
/// so a wide `engagementRange` does not mean a broadphase query every single
/// frame — the current target is only dropped early (not waiting for the
/// timer) if it died or moved out of range.
///
/// Periodic reassessment is "sticky": an already-held valid target is kept
/// unless the freshest nearest candidate is NOTICEABLY closer (see
/// `retargetSwitchMarginSq`), rather than merely winning a "who's closer"
/// contest among near-equidistant enemies. This costs nothing beyond the
/// query already being made once per `retargetInterval`, and avoids
/// needless target flapping.
///
/// **Historical note** — an important
/// diagnosis lesson: a headless load test at a high, symmetrically-converging
/// population once showed a clear drop in turret fire rate despite an
/// abundance of targets. The first hypothesis ("target identity flapping",
/// i.e. switching too often) was WRONG — a voluntary-switch counter confirmed
/// almost none happened. Profiling pointed at the real cause: the servo turn
/// rates were too slow to catch up after a FORCED switch (the old target died
/// or reached `CoreBreachSystem`'s trigger). With population spread evenly
/// around all 360° of the core, the new nearest target can be ~180° away from
/// the barrel's current heading — and at the earlier 7 rad/s, that one turn
/// alone ate most of the firing window. Fixed by raising the servo speed; this
/// stickiness stayed as a cheap, still-correct addition, not a replacement for
/// the fix. LESSON: an intuitively plausible bug hypothesis can be wrong —
/// verify with a counter or profiler, not by eye.
final class TurretTargetingSystem: System {
    static let retargetSwitchMargin: Float = 0.5
    static let retargetSwitchMarginSq: Float = retargetSwitchMargin * retargetSwitchMargin

    private var context: GameContext!

    override init() {
        super.init()
        systemName = "TurretTargeting"
    }

    override func setup(world: World, context: Any?) {
        self.context = context as? GameContext
    }

    override func execute(delta: Float) {
        let context = context!
        let turrets = context.turrets!
        if turrets.count == 0 { return }

        // Once per frame, before any turret picks a target: see
        // `GameContext.beginTargetClaimRound` for why this is a counter bump
        // rather than clearing an array. `TurretInterceptTargetingSystem`
        // shares this same round instead of starting its own.
        context.beginTargetClaimRound()

        let config = context.turretConfig!
        let transforms = context.transforms!
        let hostiles = context.hostiles!
        let transformSparse = transforms.sparseIndex
        let positions = transforms.position
        let rangeSquared = config.engagementRange * config.engagementRange

        // The barrel's pivot and the tangent of the depression limit are
        // computed once: candidates the barrel could never physically reach
        // are rejected against them.
        let muzzleLift = SIMDVector3(0, config.muzzleHeight, 0)
        let minPitchTan = config.minPitchTangent()

        for dense in 0..<Int(turrets.count) {
            let entity = turrets.denseEntities[dense]
            // A wreck (see GameContext.isTurretAlive) neither searches for
            // nor holds a target — it stays on the field, inert.
            if !context.isTurretAlive(entity) { continue }
            var origin = context.corePosition
            let ownSlot = transformSparse[Int(entity)]
            if ownSlot >= 0 { origin = positions[Int(ownSlot)] }
            let pivot = origin + muzzleLift

            turrets.retargetTimer[dense] -= delta
            let timerDue = turrets.retargetTimer[dense] <= 0
            var target = turrets.targetEntity[dense]
            var targetDistanceSq: Float = -1

            if target >= 0 {
                let targetSlot = transformSparse[Int(target)]
                if targetSlot < 0 || !hostiles.has(target) {
                    target = -1
                } else {
                    targetDistanceSq = positions[Int(targetSlot)].distanceSquared(to: origin)
                    if targetDistanceSq > rangeSquared {
                        target = -1
                    } else if !TurretConfig.isReachable(pivot: pivot, point: positions[Int(targetSlot)], minPitchTan: minPitchTan) {
                        // The target closed to point-blank and dropped below
                        // the depression limit. It cannot be kept: the barrel
                        // would point at it but never hit — a new target must
                        // be sought immediately.
                        target = -1
                    }
                }
            }

            if target < 0 {
                // No valid target at all: acquire immediately, do not wait for the timer.
                target = acquireReachable(context: context, origin: origin, pivot: pivot, config: config, minPitchTan: minPitchTan)
                turrets.retargetTimer[dense] = config.retargetInterval
            } else if timerDue {
                turrets.retargetTimer[dense] = config.retargetInterval
                let candidate = acquireReachable(context: context, origin: origin, pivot: pivot, config: config, minPitchTan: minPitchTan)
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

            turrets.targetEntity[dense] = target
            // Claimed for the rest of THIS frame's round regardless of
            // whether it was just picked or merely kept: a sticky target that
            // goes unclaimed on the frames it isn't re-scanned would be free
            // for another turret's scan to pick up right out from under it.
            context.claimTarget(target)
        }
    }

    /// Nearest target the barrel can ACTUALLY reach by elevation angle.
    ///
    /// Replaces a direct `UniformSpatialGrid.queryNearest`: that would simply
    /// return the nearest, including enemies standing right against the base
    /// — below `TurretConfig.minPitch`, impossible to hit. This instead
    /// takes every candidate in engagement range and picks the nearest
    /// REACHABLE one.
    ///
    /// More expensive than `queryNearest`, but this runs only once per
    /// `retargetInterval` (plus immediately on losing a target), so the
    /// budget absorbs it comfortably.
    ///
    /// Returns -1 if there is no reachable target at all — normal, not an
    /// error: a turret walled in by adjacent enemies stops firing and levels
    /// out instead of burning ammunition at an unreachable target. The search
    /// is two-staged purely for cost: scanning the whole engagement range on a
    /// ten-thousand-strong population would return hundreds of extra
    /// candidates. But the nearest REACHABLE target is almost always right at
    /// the edge of the blind zone, so a narrow ring around it is queried
    /// first, and the full engagement range only if that comes up empty. This
    /// cannot pick worse: the second stage fully covers the first.
    ///
    /// Every stage first tries to avoid whatever another turret already
    /// claimed this frame (see `GameContext.claimTarget`), so several turrets
    /// spread across different enemies instead of piling onto the one
    /// nearest the core. Only if BOTH stages come up empty under that
    /// restriction does the whole search repeat ignoring claims — with more
    /// turrets than reachable enemies, doubling up on a target beats leaving
    /// a turret idle while enemies it could hit walk past.
    private func acquireReachable(context: GameContext, origin: SIMDVector3, pivot: SIMDVector3,
                                   config: TurretConfig, minPitchTan: Float) -> Entity {
        // Blind-zone radius for a ground-level target — the largest it can be.
        let blindRadius = pivot.y / max(-minPitchTan, 0.0001)
        let nearRadius = min(blindRadius * 1.6, config.engagementRange)

        for avoidClaimed in [true, false] {
            let best = scanReachable(context: context, origin: origin, pivot: pivot, radius: nearRadius,
                                      minPitchTan: minPitchTan, avoidClaimed: avoidClaimed)
            if best >= 0 { return best }
            if nearRadius < config.engagementRange {
                let full = scanReachable(context: context, origin: origin, pivot: pivot, radius: config.engagementRange,
                                          minPitchTan: minPitchTan, avoidClaimed: avoidClaimed)
                if full >= 0 { return full }
            }
        }
        return -1
    }

    private func scanReachable(context: GameContext, origin: SIMDVector3, pivot: SIMDVector3,
                                radius: Float, minPitchTan: Float, avoidClaimed: Bool) -> Entity {
        let grid = context.spatialGrid!
        let found = grid.querySphere(center: origin, radius: radius, resultLimit: GameContext.queryResultLimit)
        if found == 0 { return -1 }

        let candidates = grid.queryBuffer
        let transforms = context.transforms!
        let slots = transforms.sparseIndex
        let positions = transforms.position

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
