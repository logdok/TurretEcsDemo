import AegisECS
import Foundation
import GameCore

/// Turns "reach the nearest turret" intent into a velocity vector for each
/// hostile. Turrets are the actual frontline (`GameContext.
/// nearestTurretPosition`, recomputed per hostile per frame since which
/// turret is nearest changes as either side moves) — with more than one
/// turret standing away from the exact core (see `TurretFactory`), aiming at
/// the fixed core point would send hostiles marching through the empty
/// middle of the ring instead of at what is actually defending it.
///
/// Flying and ground enemies use the EXACT SAME movement code. The difference
/// between them lives entirely in DATA, not in branching logic: a ground unit
/// simply gives the same cruise and strike altitude and a zero descent radius
/// (see `LocomotionComponentStore`) — the vertical velocity component then
/// collapses to zero on its own, with no `if isFlying` anywhere. Same
/// "difference is configuration, not code" principle used everywhere in this
/// project for adding new enemy archetypes with no source changes.
final class EnemySteeringSystem: System {
    private var context: GameContext!

    override init() {
        super.init()
        systemName = "EnemySteering"
        requiresTime = true
    }

    override func setup(world: World, context: Any?) {
        self.context = context as? GameContext
    }

    override func execute(delta: Float) {
        let context = context!
        let hostiles = context.hostiles!
        let transforms = context.transforms!
        let velocities = context.velocities!
        let locomotions = context.locomotions!

        let identifiers = hostiles.denseEntities
        let transformSparse = transforms.sparseIndex
        let velocitySparse = velocities.sparseIndex
        let locomotionSparse = locomotions.sparseIndex

        let positions = transforms.position
        let headings = transforms.yaw
        let linear = velocities.linear

        let speeds = locomotions.moveSpeed
        let turnRates = locomotions.turnRate
        let cruise = locomotions.cruiseAltitude
        let strike = locomotions.strikeAltitude
        let descent = locomotions.descentRadius

        for dense in 0..<Int(hostiles.count) {
            let entity = identifiers[dense]
            let transformSlot = transformSparse[Int(entity)]
            if transformSlot < 0 { continue }
            let locomotionSlot = locomotionSparse[Int(entity)]
            if locomotionSlot < 0 { continue }
            let velocitySlot = velocitySparse[Int(entity)]
            if velocitySlot < 0 { continue }

            let origin = positions[Int(transformSlot)]
            let target = context.nearestTurretPosition(to: origin)
            let offsetX = target.x - origin.x
            let offsetZ = target.z - origin.z
            let planarDistance = (offsetX * offsetX + offsetZ * offsetZ).squareRoot()
            let speed = speeds[Int(locomotionSlot)]

            var velocityX: Float = 0
            var velocityZ: Float = 0
            if planarDistance > 0.001 {
                let scale = speed / planarDistance
                velocityX = offsetX * scale
                velocityZ = offsetZ * scale
                headings[Int(transformSlot)] = AngleMath.approach(
                    headings[Int(transformSlot)],
                    atan2(offsetX, offsetZ),
                    turnRates[Int(locomotionSlot)] * delta)
            }

            // Two-phase altitude profile: cruise until the enemy enters the
            // descent ring, then converge on the strike altitude (see
            // LocomotionComponentStore).
            var targetAltitude = cruise[Int(locomotionSlot)]
            if planarDistance <= descent[Int(locomotionSlot)] {
                targetAltitude = strike[Int(locomotionSlot)]
            }
            let velocityY = min(max((targetAltitude - origin.y) * 2.0, -speed), speed)

            linear[Int(velocitySlot)] = SIMDVector3(velocityX, velocityY, velocityZ)
        }
    }
}
