import AegisECS
import Foundation
import GameCore

/// Weapon configuration for the core's turret.
package final class TurretConfig {
    // MARK: Durability
    /// A turret's own health. This is the whole game's loss condition — see
    /// `GameContext.areAllTurretsDestroyed` — so it is deliberately high
    /// enough to survive sustained pressure from a handful of enemies, not so
    /// high that losing one reads as inconsequential.
    package var maxHealth: Float = 2000.0

    // MARK: Acquisition
    package var engagementRange: Float = 70.0
    /// Seconds between target reassessments. Larger values trade
    /// responsiveness for fewer broadphase queries per second.
    package var retargetInterval: Float = 0.15

    // MARK: Ballistics
    package var fireInterval: Float = 0.07
    package var projectileSpeed: Float = 115.0
    package var projectileDamage: Float = 34.0
    package var projectileLifetime: Float = 2.5
    package var projectileImpactRadius: Float = 1.0
    package var projectileVisualScale: Float = 1.0
    /// Aim where the target WILL be, not where it currently is.
    package var leadPredictionEnabled: Bool = true

    // MARK: Point Defense
    /// Radius inside which the turret prioritises shooting down an incoming
    /// missile over its current target. Deliberately SMALLER than
    /// `engagementRange`: at a wide radius a dense missile swarm could
    /// permanently steal the barrel from ground targets. A narrow radius means
    /// the turret only diverts for a truly close, unavoidable threat.
    package var interceptRange: Float = 32.0
    package var interceptRetargetInterval: Float = 0.08

    // MARK: Servo
    package var turnRateYaw: Float = 22.0
    package var turnRatePitch: Float = 11.0
    /// Maximum angular error, in radians, at which firing is still allowed.
    package var firingArcTolerance: Float = 0.12

    /// Downward pitch limit, in radians (negative).
    ///
    /// **This value depends on `muzzleHeight` and must be recomputed together
    /// with it.** The limit is not a "nice angle" but geometry: the barrel
    /// tip must not swing into the pedestal (radius `baseRadius`). The higher
    /// the pivot sits, the steeper a depression it can afford, because the
    /// barrel sweeps a wider arc past the base before it would clip it.
    ///
    /// The cost of an overly shallow (too permissive) limit is a blind zone
    /// at the base: `(muzzleHeight - target height) / tan(-minPitch)`. Targets
    /// inside it are unreachable, and targeting skips them (see `isReachable`).
    package var minPitch: Float = -1.1

    // MARK: Geometry
    /// **Warning:** `muzzleHeight` is not only cosmetic. The blind zone and
    /// the safe `minPitch` both depend on it — changing height means
    /// recomputing the pitch limit (see its own comment) and re-measuring the
    /// population the turret can hold. Both layers read these three fields:
    /// the game layer for the real muzzle world position and aiming math,
    /// `TurretPresenter` for the visual rig's pivot offsets. Scaling exactly
    /// these fields (rather than a purely visual node scale) is what
    /// guarantees shots leave from the barrel tip the player actually sees.
    package var muzzleHeight: Float = 18.2
    package var muzzleForwardOffset: Float = 8.4
    package var baseRadius: Float = 5.6

    package init() {}

    /// Tangent of the depression limit. Computed once per frame by the
    /// calling system and passed into `isReachable` — trigonometry per
    /// candidate in the target search loop would be a real cost.
    package func minPitchTangent() -> Float { tan(minPitch) }

    /// Can the barrel reach `point` if its pivot sits at `pivot`?
    /// `minPitchTan` is the result of `minPitchTangent()`.
    ///
    /// Reachability condition: the required elevation angle must not fall
    /// below the limit, i.e. `atan2(dy, planar) >= minPitch`. Since
    /// `planar > 0`, that is equivalent to `dy >= tan(minPitch) * planar` —
    /// avoiding both atan2 and a division.
    ///
    /// Without this check targeting would pick the NEAREST enemy, including
    /// one standing right against the base and physically unreachable because
    /// of `minPitch` — the turret would dutifully swing toward it and waste
    /// its clip on a miss until the target detonates on its own.
    package static func isReachable(pivot: SIMDVector3, point: SIMDVector3, minPitchTan: Float) -> Bool {
        let dx = point.x - pivot.x
        let dz = point.z - pivot.z
        let planarSq = dx * dx + dz * dz
        if planarSq <= 0.000_001 { return false }
        return (point.y - pivot.y) >= minPitchTan * planarSq.squareRoot()
    }
}
