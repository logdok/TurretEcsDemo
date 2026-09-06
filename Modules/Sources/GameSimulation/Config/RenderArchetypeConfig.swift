import AegisECS
import Foundation
import GameCore

/// Greybox appearance of one instanced batch.
///
/// Everything here is procedural by design: there is not a single binary
/// asset backing geometry, so swapping in real art later only means swapping
/// what `GreyboxMeshLibrary` hands back for a given `meshKind`.
package final class RenderArchetypeConfig {
    package enum MeshKind {
        case box, capsule, sphere, cylinder, flyingWing, missile, tank
    }

    package var archetypeId: Int32
    package var displayName: String
    package var meshKind: MeshKind

    /// Bounding size in world units. Interpretation depends on `meshKind`: X
    /// and Z are diameters for round shapes, Y is always height.
    package var dimensions: SIMDVector3
    package var albedo: RGBA

    /// Instance pool capacity. Zero means "resolve from SimulationConfig".
    package var capacity: Int32
    package var castShadows: Bool

    package init(archetypeId: Int32, displayName: String, meshKind: MeshKind,
                dimensions: SIMDVector3, albedo: RGBA, capacity: Int32 = 0, castShadows: Bool = false) {
        self.archetypeId = archetypeId
        self.displayName = displayName
        self.meshKind = meshKind
        self.dimensions = dimensions
        self.albedo = albedo
        self.capacity = capacity
        self.castShadows = castShadows
    }

    /// Code-side defaults, used whenever `SimulationConfig.renderArchetypes`
    /// carries no overrides.
    package static func createDefaultSet() -> [RenderArchetypeConfig] {
        var result: [RenderArchetypeConfig] = []
        // A tracked-vehicle silhouette: boxy hull, turret cupola set back on
        // top, barrel projecting forward — see `GreyboxMeshLibrary.tank` for
        // how the three pieces are composed into one mesh. X = hull width,
        // Y = TOTAL height including the turret, Z = hull length.
        result.append(RenderArchetypeConfig(archetypeId: RenderArchetypeId.tank, displayName: "Tank", meshKind: .tank,
            dimensions: SIMDVector3(2.0, 1.6, 2.6), albedo: RGBA(0.56, 0.18, 0.16)))
        // A simplified flying-wing "jet drone" silhouette, by request: sharp
        // nose, wide swept flat body, small wingtip fins, tapered tail —
        // see `GreyboxMeshLibrary.flyingWing` for the low-poly greybox
        // approximation of the reference shape. X = wingspan, Y = body
        // thickness (flat), Z = nose-to-tail length.
        result.append(RenderArchetypeConfig(archetypeId: RenderArchetypeId.drone, displayName: "Drone", meshKind: .flyingWing,
            dimensions: SIMDVector3(1.8, 0.3, 1.9), albedo: RGBA(0.23, 0.65, 0.82)))
        // Deliberately elongated along local Z: that is the axis
        // InstancedRenderSystem writes "forward" into for this archetype's
        // look-along-velocity basis. A sphere is radially symmetric on every
        // axis, so no rotation, however correct, would ever be visible on it —
        // the projectile needs a silhouette with a "nose" for the fix to show.
        result.append(RenderArchetypeConfig(archetypeId: RenderArchetypeId.projectile, displayName: "Projectile", meshKind: .box,
            dimensions: SIMDVector3(0.3, 0.3, 1.5), albedo: RGBA(0.96, 0.90, 0.42)))
        // Split out of `projectile` so the missile reads as visually
        // distinct from a turret shot, not just a different tint — a
        // cylindrical body with a conical nose and tail fins, elongated
        // along local Y (the natural long axis for a capsule-like body) so
        // InstancedRenderSystem's existing "forward -> Y column" basis for
        // this archetype needs no changes.
        //
        // Albedo is white, not a fixed color: a missile's final color is
        // `albedo * instance tint`, and its tint is set per-instance to the
        // LAUNCHING archetype's own rendered color (see
        // `GameContext.renderedColor(for:)` / `EnemyFactory`), so a white
        // albedo lets that tint show through undiluted — a Drone's missile
        // reads as Drone-blue, a Tank's as Tank-red, and so on.
        // 1.5x the earlier greybox proportions (0.32, 1.5, 0.32) — sized up
        // for visibility, by direct request.
        result.append(RenderArchetypeConfig(archetypeId: RenderArchetypeId.missile, displayName: "Missile", meshKind: .missile,
            dimensions: SIMDVector3(0.48, 2.25, 0.48), albedo: RGBA(1.0, 1.0, 1.0)))
        return result
    }
}
