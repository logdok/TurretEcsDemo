import simd

/// Small hand-rolled camera/transform matrix helpers. World space convention
/// matches the game layer exactly: right-handed, Y up, and yaw = 0 points
/// along +Z with `sin(yaw)` feeding X and `cos(yaw)` feeding Z (see
/// `TurretFiringSystem.direction`) — the same convention the row-major
/// instance-buffer formulas in `InstancedRenderSystem` rely on.
package enum MathUtilities {
    /// Right-handed perspective projection into Metal's clip space (depth in `[0, 1]`).
    package static func perspective(fovyRadians: Float, aspect: Float, nearZ: Float, farZ: Float) -> simd_float4x4 {
        let yScale = 1 / tan(fovyRadians * 0.5)
        let xScale = yScale / aspect
        let zRange = farZ - nearZ
        let zScale = farZ / -zRange
        let wzScale = -farZ * nearZ / zRange
        return simd_float4x4(columns: (
            SIMD4<Float>(xScale, 0, 0, 0),
            SIMD4<Float>(0, yScale, 0, 0),
            SIMD4<Float>(0, 0, zScale, -1),
            SIMD4<Float>(0, 0, wzScale, 0)
        ))
    }

    /// Right-handed look-at (camera space forward is -Z, matching `perspective` above).
    package static func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let f = simd_normalize(center - eye)
        let s = simd_normalize(simd_cross(f, up))
        let u = simd_cross(s, f)
        return simd_float4x4(columns: (
            SIMD4<Float>(s.x, u.x, -f.x, 0),
            SIMD4<Float>(s.y, u.y, -f.y, 0),
            SIMD4<Float>(s.z, u.z, -f.z, 0),
            SIMD4<Float>(-simd_dot(s, eye), -simd_dot(u, eye), simd_dot(f, eye), 1)
        ))
    }

    package static func translation(_ t: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(t.x, t.y, t.z, 1)
        ))
    }

    package static func scale(_ s: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4<Float>(s.x, 0, 0, 0),
            SIMD4<Float>(0, s.y, 0, 0),
            SIMD4<Float>(0, 0, s.z, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    /// Rotation about Y. `rotationY(a) * (0,0,1) == (sin(a), 0, cos(a))` —
    /// the same yaw convention used everywhere in the game layer.
    package static func rotationY(_ radians: Float) -> simd_float4x4 {
        let c = cos(radians), s = sin(radians)
        return simd_float4x4(columns: (
            SIMD4<Float>(c, 0, -s, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(s, 0, c, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    /// Rotation about X, standard right-handed form. The turret rig applies
    /// this with `angle = -pitch`, since local +Z tilts upward under a
    /// NEGATIVE rotation about X (see `TurretPresenter`).
    package static func rotationX(_ radians: Float) -> simd_float4x4 {
        let c = cos(radians), s = sin(radians)
        return simd_float4x4(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, c, s, 0),
            SIMD4<Float>(0, -s, c, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }
}
