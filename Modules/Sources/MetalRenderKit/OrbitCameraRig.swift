import simd

/// Orbit camera with drag-to-rotate and pinch-to-zoom.
///
/// Input is driven directly by `UIPanGestureRecognizer`/
/// `UIPinchGestureRecognizer` in the hosting view (see `MetalView`), which
/// already guarantees mutual exclusivity: a pan recognizer limited to one
/// touch and a pinch recognizer needing two never fire on the same gesture.
package final class OrbitCameraRig {
    package init() {}

    package static let minPitch: Float = 0.12
    package static let maxPitch: Float = 1.45
    package static let orbitSensitivity: Float = 0.006

    package var focusPoint: SIMD3<Float> = .zero
    package var minimumDistance: Float = 16.0
    package var maximumDistance: Float = 220.0

    package private(set) var orbitYaw: Float = 0.7
    package private(set) var orbitPitch: Float = 0.62
    package private(set) var orbitDistance: Float = 78.0

    package func configure(arenaRadius: Float) {
        maximumDistance = max(maximumDistance, arenaRadius * 2.0)
        orbitDistance = min(max(arenaRadius * 0.85, minimumDistance), maximumDistance)
    }

    /// `translation` is the drag delta in points since the last call (screen
    /// space: x right, y down).
    package func applyDrag(translation: SIMD2<Float>) {
        orbitYaw -= translation.x * Self.orbitSensitivity
        orbitPitch += translation.y * Self.orbitSensitivity
        orbitPitch = min(max(orbitPitch, Self.minPitch), Self.maxPitch)
    }

    /// `scale` is the pinch gesture's incremental scale factor since the last
    /// call: `>1` means the fingers spread apart, which brings the camera
    /// closer.
    package func applyPinch(scale: Float) {
        guard scale > 0.0001 else { return }
        orbitDistance /= scale
        orbitDistance = min(max(orbitDistance, minimumDistance), maximumDistance)
    }

    package var eyePosition: SIMD3<Float> {
        let horizontal = cos(orbitPitch) * orbitDistance
        return focusPoint + SIMD3<Float>(sin(orbitYaw) * horizontal, sin(orbitPitch) * orbitDistance, cos(orbitYaw) * horizontal)
    }

    package func viewMatrix() -> simd_float4x4 {
        MathUtilities.lookAt(eye: eyePosition, center: focusPoint, up: SIMD3<Float>(0, 1, 0))
    }
}
