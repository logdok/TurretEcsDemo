import AegisECS
import Foundation
import GameCore

/// Turns the barrel toward the aim point and fires.
///
/// **The aim point is a lead solution, not the target's current position:**
/// projectile flight time is estimated, applied to the target's velocity,
/// then refined a SECOND time (the two-step iteration below). First pass:
/// compute flight time to the target's snapshot position as if it stood
/// still, giving a first-approximation lead point; second pass: recompute
/// flight time to THAT point (slightly different, since it moved) and offset
/// by the target's velocity again. Two iterations are enough for the speeds
/// in this project and cost almost nothing — this is a fast approximation,
/// not a full quadratic intercept solve.
final class TurretFiringSystem: System {
    private var context: GameContext!

    override init() {
        super.init()
        systemName = "TurretFiring"
        requiresTime = true
    }

    override func setup(world: World, context: Any?) {
        self.context = context as? GameContext
    }

    /// Unit direction for a yaw/pitch pair. Zero yaw points along +Z — the
    /// same convention `InstancedRenderSystem`'s basis uses, so the barrel
    /// direction and the visual orientation of projectiles agree.
    static func direction(yaw: Float, pitch: Float) -> SIMDVector3 {
        let pitchCosine = cos(pitch)
        return SIMDVector3(sin(yaw) * pitchCosine, sin(pitch), cos(yaw) * pitchCosine)
    }

    override func execute(delta: Float) {
        let context = context!
        let turrets = context.turrets!
        if turrets.count == 0 { return }

        let config = context.turretConfig!
        let transforms = context.transforms!
        let velocities = context.velocities!
        let transformSparse = transforms.sparseIndex
        let velocitySparse = velocities.sparseIndex
        let positions = transforms.position
        let linear = velocities.linear

        let yawStep = config.turnRateYaw * delta
        let pitchStep = config.turnRatePitch * delta
        let muzzleLift = SIMDVector3(0, config.muzzleHeight, 0)
        let projectileSpeed = max(config.projectileSpeed, 0.001)

        for dense in 0..<Int(turrets.count) {
            let entity = turrets.denseEntities[dense]
            // A wreck (see GameContext.isTurretAlive) never aims or fires
            // again — it stays on the field, inert.
            if !context.isTurretAlive(entity) { continue }

            turrets.cooldown[dense] -= delta

            var basePosition = context.corePosition
            let ownSlot = transformSparse[Int(entity)]
            if ownSlot >= 0 { basePosition = positions[Int(ownSlot)] }

            var yaw = turrets.yaw[dense]
            var pitch = turrets.pitch[dense]
            let target = turrets.targetEntity[dense]

            if target < 0 {
                // Idle: level the barrel and keep scanning.
                turrets.pitch[dense] = AngleMath.approach(pitch, 0, pitchStep)
                continue
            }

            let targetSlot = transformSparse[Int(target)]
            if targetSlot < 0 { continue }

            // Aiming is computed from the barrel's ROTATION CENTER, not its
            // tip. This is essential: the tip sits forward by
            // muzzleForwardOffset, so for a close target the "muzzle to
            // target" vector shrinks toward zero length — and its DIRECTION
            // starts jittering wildly at the smallest enemy movement. The
            // required angular rate grows as (target speed / vector length)
            // and rockets past turnRateYaw, so the barrel never caught up and
            // the turret almost stopped firing. From the pivot the vector
            // length is the honest distance to the target, and the turn rate
            // stays within the servo's real capability. The pivot also does
            // not depend on the barrel's current angle, so there is no
            // "angle -> reference point -> angle" feedback loop in aiming.
            // The projectile's LAUNCH point is still the barrel tip — the two
            // points must not be confused.
            let pivot = basePosition + muzzleLift
            let targetPosition = positions[Int(targetSlot)]
            var aimPoint = targetPosition

            if config.leadPredictionEnabled {
                let targetVelocitySlot = velocitySparse[Int(target)]
                if targetVelocitySlot >= 0 {
                    let targetVelocity = linear[Int(targetVelocitySlot)]
                    var flightTime = pivot.distance(to: targetPosition) / projectileSpeed
                    aimPoint = targetPosition + targetVelocity * flightTime
                    flightTime = pivot.distance(to: aimPoint) / projectileSpeed
                    aimPoint = targetPosition + targetVelocity * flightTime
                }
            }

            let toTarget = aimPoint - pivot
            let planar = (toTarget.x * toTarget.x + toTarget.z * toTarget.z).squareRoot()
            let desiredYaw = atan2(toTarget.x, toTarget.z)
            // Depression is limited from below so the turret does not bury
            // its barrel in its own base at point-blank range. It is the
            // DESIRED angle that gets clamped: then the arc-tolerance check
            // below still converges and the turret keeps firing — flat, over
            // a too-close target — instead of freezing on an unreachable
            // angle. Full reasoning lives on `TurretConfig.minPitch`.
            let desiredPitch = max(atan2(toTarget.y, max(planar, 0.0001)), config.minPitch)

            yaw = AngleMath.approach(yaw, desiredYaw, yawStep)
            pitch = AngleMath.approach(pitch, desiredPitch, pitchStep)
            turrets.yaw[dense] = yaw
            turrets.pitch[dense] = pitch

            if turrets.cooldown[dense] > 0 { continue }
            if AngleMath.shortestDelta(yaw, desiredYaw) > config.firingArcTolerance { continue }
            if AngleMath.shortestDelta(pitch, desiredPitch) > config.firingArcTolerance { continue }

            let bore = Self.direction(yaw: yaw, pitch: pitch)
            let launchPoint = basePosition + muzzleLift + bore * config.muzzleForwardOffset
            if ProjectileFactory.spawn(context: context, origin: launchPoint, linearVelocity: bore * config.projectileSpeed) >= 0 {
                turrets.cooldown[dense] = config.fireInterval
                context.shotsFired += 1
            }
        }
    }
}
