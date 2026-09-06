import AegisECS
import Foundation
import GameCore
import GameSimulation

/// Uploads every batch into its instance buffer. Always the last game system
/// in the pipeline.
///
/// This is the single hottest loop in the whole project, so it is written as
/// flatly as possible: no allocations, no per-entity method calls, no matrix
/// objects, one buffer upload per archetype rather than per instance.
///
/// Because each visual archetype owns its own component store, there is no
/// filtering here at all — every entity walked is an entity drawn.
///
/// `RenderArchetypeId.projectile`/`.missile` are the exception to yaw-only:
/// turret shots and enemy missiles are non-homing (constant velocity after
/// launch — see `ProjectileFactory`/`EnemyMissileFactory`) and regularly fly
/// a true 3D diagonal, where yaw alone (rotation only about Y) cannot tilt
/// the body to match and it would visually fly sideways to its own nose.
/// Both archetypes build a full "look along the velocity vector" basis
/// instead. They do it along DIFFERENT local axes: the projectile dart
/// (a box) is built elongated along local Z, so "forward" goes into that
/// column; the missile capsule — like any capsule mesh — is always elongated
/// along local Y, so "forward" must go into the Y column instead, or the
/// capsule would point sideways to its own flight direction.
///
/// For every other archetype this is deliberately NOT done: those are the
/// ground/flying creatures, where yaw-only is correct, not merely cheaper —
/// and their population (up to 10k) is exactly why the cheap path exists at
/// all. Projectile and missile populations are capped two orders of
/// magnitude smaller, so the extra per-instance vector math here comes
/// nowhere near the hot-loop budget.
package final class InstancedRenderSystem: System {
    private var context: GameContext!
    private let registry: RenderBatchRegistry

    package init(registry: RenderBatchRegistry) {
        self.registry = registry
        super.init()
        systemName = "InstancedRender"
    }

    package override func setup(world: World, context: Any?) {
        self.context = context as? GameContext
    }

    package override func execute(delta: Float) {
        let context = context!
        let transforms = context.transforms!
        let healths = context.healths!

        let transformSparse = transforms.sparseIndex
        let positions = transforms.position
        let headings = transforms.yaw
        let scales = transforms.uniformScale

        let healthSparse = healths.sparseIndex
        let healthCurrent = healths.current
        let healthMaximum = healths.maximum

        let velocities = context.velocities!
        let velocitySparse = velocities.sparseIndex
        let velocityLinear = velocities.linear

        for archetypeId in 0..<context.renderBatches.count {
            guard let batch = context.renderBatches[archetypeId] else { continue }
            guard let pool = registry.pool(Int32(archetypeId)) else { continue }

            let identifiers = batch.denseEntities
            let tints = batch.tint
            let target = pool.bufferContents
            let limit = pool.capacity
            let stride = InstancePool.stride
            let albedo = pool.archetypeAlbedo
            var written = 0
            var cursor = 0
            let orientForwardZ = archetypeId == Int(RenderArchetypeId.projectile)
            let orientForwardY = archetypeId == Int(RenderArchetypeId.missile)

            for dense in 0..<Int(batch.count) {
                if written >= limit { break }
                let entity = identifiers[dense]
                let slot = transformSparse[Int(entity)]
                if slot < 0 { continue }

                let origin = positions[Int(slot)]
                let scaleFactor = scales[Int(slot)]

                if orientForwardZ || orientForwardY {
                    var forward = SIMDVector3(0, 0, 1)
                    let velocitySlot = velocitySparse[Int(entity)]
                    if velocitySlot >= 0 {
                        let linear = velocityLinear[Int(velocitySlot)]
                        if linear.lengthSquared > 0.0001 {
                            forward = linear.normalized()
                        }
                    }

                    let bx: SIMDVector3
                    let by: SIMDVector3
                    let bz: SIMDVector3
                    if orientForwardZ {
                        // Right-handed "look along forward" basis, forward ->
                        // local Z. Collapses exactly to the yaw-only formula
                        // below when forward.y == 0 — that is its general
                        // case, not a different convention.
                        var right = SIMDVector3.up.cross(forward)
                        right = right.lengthSquared < 0.0001 ? .right : right.normalized()
                        bx = right
                        by = forward.cross(right)
                        bz = forward
                    } else {
                        // forward -> local Y (a capsule's fixed long axis). A
                        // capsule is radially symmetric about that axis, so
                        // unlike the Z case above there is no "correct" roll
                        // to preserve — any perpendicular pair works. Same
                        // UP x forward derivation, just with forward moved to
                        // a different column; bz is built as side.cross(forward),
                        // NOT forward.cross(side), so bx x by = bz still holds
                        // — swapping which column carries "forward" without
                        // recomputing the third axis the same way would
                        // silently mirror the mesh instead of simply rotating it.
                        var side = SIMDVector3.up.cross(forward)
                        side = side.lengthSquared < 0.0001 ? .right : side.normalized()
                        bx = side
                        by = forward
                        bz = side.cross(forward)
                    }

                    target[cursor] = bx.x * scaleFactor
                    target[cursor + 1] = by.x * scaleFactor
                    target[cursor + 2] = bz.x * scaleFactor
                    target[cursor + 3] = origin.x
                    target[cursor + 4] = bx.y * scaleFactor
                    target[cursor + 5] = by.y * scaleFactor
                    target[cursor + 6] = bz.y * scaleFactor
                    target[cursor + 7] = origin.y
                    target[cursor + 8] = bx.z * scaleFactor
                    target[cursor + 9] = by.z * scaleFactor
                    target[cursor + 10] = bz.z * scaleFactor
                    target[cursor + 11] = origin.z
                } else {
                    let yaw = headings[Int(slot)]
                    let cosine = cos(yaw) * scaleFactor
                    let sine = sin(yaw) * scaleFactor

                    target[cursor] = cosine
                    target[cursor + 1] = 0
                    target[cursor + 2] = sine
                    target[cursor + 3] = origin.x
                    target[cursor + 4] = 0
                    target[cursor + 5] = scaleFactor
                    target[cursor + 6] = 0
                    target[cursor + 7] = origin.y
                    target[cursor + 8] = -sine
                    target[cursor + 9] = 0
                    target[cursor + 10] = cosine
                    target[cursor + 11] = origin.z
                }

                // Wounded instances darken toward red. Entities with no
                // health component (projectiles) keep their authored tint.
                var vitality: Float = 1.0
                let healthSlot = healthSparse[Int(entity)]
                if healthSlot >= 0 {
                    vitality = min(max(healthCurrent[Int(healthSlot)] / max(healthMaximum[Int(healthSlot)], 0.001), 0.3), 1.0)
                }

                // Instance tint multiplied by the batch's base albedo. The
                // hand-written shader does not fold the two together on the
                // GPU, so it is done here, once, at write time.
                let tint = tints[dense]
                target[cursor + 12] = albedo.r * tint.r
                target[cursor + 13] = albedo.g * tint.g * vitality
                target[cursor + 14] = albedo.b * tint.b * vitality
                target[cursor + 15] = albedo.a * tint.a

                cursor += stride
                written += 1
            }

            pool.commit(written)
        }
    }
}
