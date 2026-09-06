import AegisECS
import GameCore

/// Resolves projectile hits against hostile entities through the shared
/// broadphase.
///
/// A shot is checked against the main enemy grid first, and the missile grid
/// only on a miss there — so the same barrel that hits ground tanks can, on
/// the very same shot, also shoot down an interceptable missile. No separate
/// intercept-hit system is needed. This mirrors the same simplification
/// described below: a shot connects with ANY suitable target within its
/// impact radius, not necessarily the specific one the turret considers its
/// "declared" target (`targetEntity`) — in practice, at any real population, a
/// shot is almost always headed at the declared target anyway, but the actual
/// hit is a geometric check, not an id match.
///
/// **Known MVP simplification:** hit checking is a POINT query at the
/// projectile's position AFTER this frame's motion integration, not a sweep
/// test against the whole segment travelled since the previous frame. A very
/// fast projectile could in principle tunnel past a small target between two
/// frames. Impact radii are chosen so this stays visually unnoticeable; a
/// sweep test is the natural next step if true accuracy is ever needed.
final class ProjectileImpactSystem: System {
    private var context: GameContext!

    override init() {
        super.init()
        systemName = "ProjectileImpact"
        requiresTime = true
    }

    override func setup(world: World, context: Any?) {
        self.context = context as? GameContext
    }

    override func execute(delta: Float) {
        let context = context!
        let projectiles = context.projectiles!
        if projectiles.count == 0 { return }

        let transforms = context.transforms!
        let colliders = context.colliders!
        let grid = context.spatialGrid!
        let missileGrid = context.missileSpatialGrid!
        let interceptables = context.interceptables!

        let identifiers = projectiles.denseEntities
        let transformSparse = transforms.sparseIndex
        let colliderSparse = colliders.sparseIndex
        let positions = transforms.position
        let radii = colliders.radius
        let damage = projectiles.damage
        let impactRadius = projectiles.impactRadius

        // The broadphase stores points, not volumes, so the search radius
        // must be widened by the largest collider in play, then narrowed back
        // with a precise per-candidate check.
        let searchMargin = context.maxColliderRadius

        for dense in 0..<Int(projectiles.count) {
            let entity = identifiers[dense]
            let slot = transformSparse[Int(entity)]
            if slot < 0 { continue }
            let muzzlePoint = positions[Int(slot)]
            var victim = grid.queryNearest(center: muzzlePoint, radius: impactRadius[dense] + searchMargin)
            if victim < 0 {
                victim = missileGrid.queryNearest(center: muzzlePoint, radius: impactRadius[dense] + searchMargin)
            }
            if victim < 0 { continue }
            let victimSlot = transformSparse[Int(victim)]
            if victimSlot < 0 { continue }

            var victimRadius: Float = 0.5
            let victimCollider = colliderSparse[Int(victim)]
            if victimCollider >= 0 { victimRadius = radii[Int(victimCollider)] }

            let contactDistance = impactRadius[dense] + victimRadius
            if muzzlePoint.distanceSquared(to: positions[Int(victimSlot)]) > contactDistance * contactDistance { continue }

            if interceptables.has(victim) {
                context.interceptCount += 1
            }
            context.queueDamage(victim, amount: damage[dense])
            context.world.queueDestroy(entity)
        }
    }
}
