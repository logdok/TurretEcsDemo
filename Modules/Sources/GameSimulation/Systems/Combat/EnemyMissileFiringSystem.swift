import AegisECS
import GameCore

/// Enemies carrying a `MissileLauncherComponentStore` fire a missile at
/// their nearest turret (`GameContext.nearestTurretPosition` — see
/// `EnemySteeringSystem` for why the fixed core point is no longer the
/// right aim reference now that turrets can stand away from it) as soon as
/// they are in range of it and their cooldown has expired.
///
/// Ballistics are NOT homing: a missile starts on a straight line to that
/// turret's CURRENT position at launch and never corrects course afterward —
/// exactly like the turret's own projectiles. The chance to shoot it down
/// comes not from an evasive maneuver but from `TurretInterceptTargetingSystem`
/// together with the turret's existing firing/hit pipeline
/// (`TurretFiringSystem`/`ProjectileImpactSystem`) — reused unchanged; no
/// separate interception logic is needed.
final class EnemyMissileFiringSystem: System {
    private var context: GameContext!

    override init() {
        super.init()
        systemName = "EnemyMissileFiring"
        requiresTime = true
    }

    override func setup(world: World, context: Any?) {
        self.context = context as? GameContext
    }

    override func execute(delta: Float) {
        let context = context!
        let launchers = context.missileLaunchers!
        if launchers.count == 0 { return }

        let transforms = context.transforms!
        let transformSparse = transforms.sparseIndex
        let positions = transforms.position
        let missileCap = Int(context.config.maxMissileCapacity)

        let identifiers = launchers.denseEntities
        let cooldown = launchers.cooldown
        let engagementRange = launchers.engagementRange
        let fireInterval = launchers.fireInterval
        let speed = launchers.missileSpeed
        let damage = launchers.missileDamage
        let impactRadius = launchers.missileImpactRadius
        let tint = launchers.tint

        for dense in 0..<Int(launchers.count) {
            cooldown[dense] -= delta
            if cooldown[dense] > 0 { continue }

            let entity = identifiers[dense]
            let slot = transformSparse[Int(entity)]
            if slot < 0 { continue }

            let origin = positions[Int(slot)]
            let target = context.nearestTurretPosition(to: origin)
            let rangeHere = engagementRange[dense]
            if origin.distanceSquared(to: target) > rangeHere * rangeHere { continue }

            // Respect the pool budget: MissileSpatialIndexSystem's scratch
            // buffers are sized for maxMissileCapacity and must not overflow.
            if context.interceptables.count >= missileCap { continue }

            if EnemyMissileFactory.spawn(context: context, origin: origin, targetPosition: target,
                                          speed: speed[dense], damage: damage[dense], impactRadius: impactRadius[dense],
                                          tint: tint[dense]) >= 0 {
                cooldown[dense] = fireInterval[dense]
            }
        }
    }
}
