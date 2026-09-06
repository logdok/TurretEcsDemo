import AegisECS
import Foundation

// AegisECS's SIMDVector3 deliberately ships with no operators (see the
// package's own full-example chapter, which writes field-by-field arithmetic
// inline). The game layer reads far more naturally with them, so they are
// added here as an extension rather than inlined at every call site.

extension SIMDVector3 {
    package static let zero = SIMDVector3(0, 0, 0)
    package static let up = SIMDVector3(0, 1, 0)
    package static let right = SIMDVector3(1, 0, 0)
    package static let forward = SIMDVector3(0, 0, 1)

    package static func + (l: SIMDVector3, r: SIMDVector3) -> SIMDVector3 { SIMDVector3(l.x + r.x, l.y + r.y, l.z + r.z) }
    package static func - (l: SIMDVector3, r: SIMDVector3) -> SIMDVector3 { SIMDVector3(l.x - r.x, l.y - r.y, l.z - r.z) }
    package static func * (l: SIMDVector3, s: Float) -> SIMDVector3 { SIMDVector3(l.x * s, l.y * s, l.z * s) }
    package static func / (l: SIMDVector3, s: Float) -> SIMDVector3 { SIMDVector3(l.x / s, l.y / s, l.z / s) }
    package static prefix func - (v: SIMDVector3) -> SIMDVector3 { SIMDVector3(-v.x, -v.y, -v.z) }

    package func dot(_ o: SIMDVector3) -> Float { x * o.x + y * o.y + z * o.z }
    package func cross(_ o: SIMDVector3) -> SIMDVector3 {
        SIMDVector3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x)
    }

    package var lengthSquared: Float { x * x + y * y + z * z }
    package var length: Float { lengthSquared.squareRoot() }

    package func normalized() -> SIMDVector3 {
        let len = length
        return len > 0.00001 ? self / len : .zero
    }

    package func distanceSquared(to o: SIMDVector3) -> Float {
        let dx = x - o.x, dy = y - o.y, dz = z - o.z
        return dx * dx + dy * dy + dz * dz
    }

    package func distance(to o: SIMDVector3) -> Float { distanceSquared(to: o).squareRoot() }
}

/// Colour value: four floats, r/g/b/a in that order — matches AegisECS's
/// `.vec4` column layout exactly, so it can back a tint column directly.
package struct RGBA {
    package var r: Float
    package var g: Float
    package var b: Float
    package var a: Float

    package init(_ r: Float, _ g: Float, _ b: Float, _ a: Float = 1.0) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    package static let white = RGBA(1, 1, 1, 1)
}
