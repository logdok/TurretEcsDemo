import AegisECS
import GameCore
import simd

/// The game layer uses AegisECS's `SIMDVector3` (matching its broadphase and
/// component-store APIs); the rendering layer uses Apple's native
/// `SIMD3<Float>`/`simd_float4x4` (matching Metal). This is the one small
/// seam between the two.
extension SIMDVector3 {
    package var simd3: SIMD3<Float> { SIMD3<Float>(x, y, z) }
}
