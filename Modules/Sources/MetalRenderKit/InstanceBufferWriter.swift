import GameCore
import Metal
import simd

/// Writes one instance's transform + color into a raw Float buffer using the
/// same row-major layout as `InstancePool`/`InstancedRenderSystem`.
/// Shared by every one-off, non-population draw: the ground plane and each of
/// the turret rig's individual parts.
package enum InstanceBufferWriter {
    package static func write(_ buffer: MTLBuffer, worldMatrix: simd_float4x4, color: RGBA) {
        let c = worldMatrix.columns
        let ptr = buffer.contents().assumingMemoryBound(to: Float.self)
        ptr[0] = c.0.x; ptr[1] = c.1.x; ptr[2] = c.2.x; ptr[3] = c.3.x
        ptr[4] = c.0.y; ptr[5] = c.1.y; ptr[6] = c.2.y; ptr[7] = c.3.y
        ptr[8] = c.0.z; ptr[9] = c.1.z; ptr[10] = c.2.z; ptr[11] = c.3.z
        ptr[12] = color.r; ptr[13] = color.g; ptr[14] = color.b; ptr[15] = color.a
    }
}
