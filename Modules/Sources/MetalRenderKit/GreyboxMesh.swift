import Metal

/// A `GreyboxMeshLibrary.MeshData` uploaded to GPU buffers once. Meshes are
/// static and shared by every instance in a batch — only the per-instance
/// transform/color buffer changes frame to frame (see `InstancePool`).
package final class GreyboxMesh {
    package let vertexBuffer: MTLBuffer
    package let indexBuffer: MTLBuffer
    package let indexCount: Int

    package init?(device: MTLDevice, data: GreyboxMeshLibrary.MeshData) {
        let vertexData = data.interleavedVertexData()
        guard !vertexData.isEmpty, !data.indices.isEmpty,
              let vertexBuffer = device.makeBuffer(
                bytes: vertexData, length: vertexData.count * MemoryLayout<Float>.stride, options: .storageModeShared),
              let indexBuffer = device.makeBuffer(
                bytes: data.indices, length: data.indices.count * MemoryLayout<UInt16>.stride, options: .storageModeShared)
        else { return nil }
        self.vertexBuffer = vertexBuffer
        self.indexBuffer = indexBuffer
        indexCount = data.indices.count
    }
}
