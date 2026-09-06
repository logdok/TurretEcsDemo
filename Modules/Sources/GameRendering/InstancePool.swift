import GameCore
import GameSimulation
import Metal
import MetalRenderKit

/// One instanced draw batch: one mesh, one per-instance data buffer, one draw
/// call.
///
/// BUFFER LAYOUT (row-major 3x4 transform + per-instance color):
/// ```
/// [ bx.x, by.x, bz.x, ox,
///   bx.y, by.y, bz.y, oy,
///   bx.z, by.z, bz.z, oz,
///   r, g, b, a ]
/// ```
/// stride 16. `bufferContents` is exposed directly because the render system
/// writes into it inside a tight per-instance loop reaching into the
/// thousands; routing every write through a method call would cost more than
/// the write itself. Treat it as owned by `InstancedRenderSystem`.
package final class InstancePool {
    package static let transformFloats = 12
    package static let colorFloats = 4
    package static let stride = transformFloats + colorFloats

    package let archetypeId: Int32
    package let capacity: Int
    /// The batch's base color (`RenderArchetypeConfig.albedo`), applied
    /// against each instance's own tint at write time, since the
    /// hand-written shader does not fold the two together on the GPU.
    package let archetypeAlbedo: RGBA
    package let mesh: GreyboxMesh
    package let buffer: MTLBuffer
    /// Direct pointer into `buffer`'s shared storage, valid for the buffer's
    /// entire lifetime — capacity is fixed at build time and never
    /// reallocated at runtime; the visible population is managed purely
    /// through `commit`'s count.
    package let bufferContents: UnsafeMutablePointer<Float>

    package private(set) var visibleCount: Int = 0

    package init?(device: MTLDevice, config: RenderArchetypeConfig, capacity batchCapacity: Int) {
        archetypeId = config.archetypeId
        capacity = max(batchCapacity, 1)
        archetypeAlbedo = config.albedo

        let meshData = GreyboxMeshLibrary.generate(kind: config.meshKind, dimensions: config.dimensions)
        guard let builtMesh = GreyboxMesh(device: device, data: meshData) else { return nil }
        mesh = builtMesh

        let byteLength = capacity * InstancePool.stride * MemoryLayout<Float>.stride
        guard let instanceBuffer = device.makeBuffer(length: byteLength, options: .storageModeShared) else { return nil }
        buffer = instanceBuffer
        bufferContents = buffer.contents().assumingMemoryBound(to: Float.self)
    }

    /// Reveals exactly `activeInstances` of the already-written buffer.
    package func commit(_ activeInstances: Int) {
        visibleCount = min(activeInstances, capacity)
    }
}
