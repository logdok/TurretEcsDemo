import AegisECS
import GameCore

/// Spatial state of every rendered entity: world position, heading (yaw) and
/// uniform scale.
///
/// Rotation is a single angle, not a full quaternion/basis — deliberately, for
/// performance: the instanced-render buffer for yaw-only rotation with
/// uniform scale is filled with three multiplications (see
/// `InstancedRenderSystem`), where a full basis would cost noticeably more
/// trigonometry per entity per frame at a population of up to 10k. Entities
/// that truly need pitch (the turret barrel) are not rendered through this
/// component/instancing at all — they are a small hand-built node rig
/// (`TurretPresenter`).
package final class TransformComponentStore: PackedStore {
    private enum Column: Int32 { case position, yaw, uniformScale }

    init() { super.init(schema: [.vec3, .float32, .float32]) }

    package var position: UnsafeMutablePointer<SIMDVector3> {
        columnData(Column.position.rawValue)!.assumingMemoryBound(to: SIMDVector3.self)
    }
    package var yaw: UnsafeMutablePointer<Float> { columnF32(Column.yaw.rawValue)! }
    package var uniformScale: UnsafeMutablePointer<Float> { columnF32(Column.uniformScale.rawValue)! }

    @discardableResult
    func assign(_ entity: Entity, position worldPosition: SIMDVector3, heading: Float, scale: Float) -> Int32 {
        let slot = attach(entity)
        guard slot >= 0 else { return slot }
        position[Int(slot)] = worldPosition
        yaw[Int(slot)] = heading
        uniformScale[Int(slot)] = scale
        return slot
    }
}
