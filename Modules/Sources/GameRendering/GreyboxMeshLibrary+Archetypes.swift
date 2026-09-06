import AegisECS
import GameCore
import GameSimulation
import MetalRenderKit

/// The archetype-aware half of what used to be one `GreyboxMeshLibrary`.
///
/// The primitives themselves are pure geometry and live in `MetalRenderKit`,
/// which knows nothing about this game. The mapping "a Drone is a flying wing
/// 1.8 units across" is game knowledge, so it lives here — in the one module
/// that is allowed to see both a `RenderArchetypeConfig` and a mesh builder.
/// Splitting it this way is what lets `MetalRenderKit` be reused by anything
/// else without dragging the enemy roster along.
///
/// It stays an extension on `GreyboxMeshLibrary` rather than a new type so
/// every existing call site reads exactly as before.
extension GreyboxMeshLibrary {
    package static func generate(kind: RenderArchetypeConfig.MeshKind, dimensions: SIMDVector3) -> MeshData {
        switch kind {
        case .box:
            return box(size: dimensions)
        case .capsule:
            let radius = max(dimensions.x * 0.5, 0.01)
            let height = max(dimensions.y, radius * 2 + 0.01)
            return capsule(radius: radius, height: height)
        case .sphere:
            return sphere(radius: max(dimensions.x * 0.5, 0.01))
        case .cylinder:
            return cylinder(topRadius: max(dimensions.x * 0.5, 0.01), bottomRadius: max(dimensions.z * 0.5, 0.01),
                             height: max(dimensions.y, 0.01))
        case .flyingWing:
            return flyingWing(wingspan: max(dimensions.x, 0.05), height: max(dimensions.y, 0.02), length: max(dimensions.z, 0.05))
        case .missile:
            return missile(bodyRadius: max(dimensions.x * 0.5, 0.01), totalLength: max(dimensions.y, 0.05))
        case .tank:
            return tank(dimensions: SIMDVector3(max(dimensions.x, 0.05), max(dimensions.y, 0.05), max(dimensions.z, 0.05)))
        }
    }
}
