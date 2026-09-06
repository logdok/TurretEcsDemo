import AegisECS
import Foundation
import GameCore

/// Procedural primitives for the greybox pass.
///
/// Every primitive here is pure geometry: it takes numbers and returns
/// vertices. Which mesh a given ENEMY archetype gets is not decided here —
/// that mapping lives in `GameRendering`, the one module allowed to know both
/// this library and the game's own archetype table.
///
/// Segment counts are deliberately far below typical defaults: a default UV
/// sphere is 64x32 segments, which at ten thousand instances would dominate
/// an entire frame on a mobile GPU by itself. Silhouette quality costs
/// nothing here — instance count is what matters.
package enum GreyboxMeshLibrary {
    package static let radialSegments = 8
    package static let rings = 3

    package struct MeshData {
        var positions: [SIMDVector3] = []
        var normals: [SIMDVector3] = []
        var indices: [UInt16] = []

        /// Position (xyz) + normal (xyz) interleaved, stride 6 floats — ready
        /// to hand straight to a `MTLBuffer`.
        package func interleavedVertexData() -> [Float] {
            var data: [Float] = []
            data.reserveCapacity(positions.count * 6)
            for i in 0..<positions.count {
                let p = positions[i], n = normals[i]
                data.append(contentsOf: [p.x, p.y, p.z, n.x, n.y, n.z])
            }
            return data
        }
    }

    /// A plain tapered cylinder — used directly by `TurretPresenter` for the
    /// pedestal and core column, which are not archetype-driven.
    package static func cylinder(topRadius: Float, bottomRadius: Float, height: Float) -> MeshData {
        var positions: [SIMDVector3] = []
        var normals: [SIMDVector3] = []
        var indices: [UInt16] = []
        let segments = radialSegments
        let halfHeight = height * 0.5
        let slopeAngle = atan2(bottomRadius - topRadius, height)
        let cosSlope = cos(slopeAngle)
        let sinSlope = sin(slopeAngle)

        for i in 0..<segments {
            let theta0 = Float(i) / Float(segments) * 2 * Float.pi
            let theta1 = Float(i + 1) / Float(segments) * 2 * Float.pi
            let c0 = cos(theta0), s0 = sin(theta0)
            let c1 = cos(theta1), s1 = sin(theta1)

            let bottomA = SIMDVector3(c0 * bottomRadius, -halfHeight, s0 * bottomRadius)
            let topA = SIMDVector3(c0 * topRadius, halfHeight, s0 * topRadius)
            let topB = SIMDVector3(c1 * topRadius, halfHeight, s1 * topRadius)
            let bottomB = SIMDVector3(c1 * bottomRadius, -halfHeight, s1 * bottomRadius)

            let normalA = SIMDVector3(c0 * cosSlope, sinSlope, s0 * cosSlope)
            let normalB = SIMDVector3(c1 * cosSlope, sinSlope, s1 * cosSlope)

            let base = UInt16(positions.count)
            positions.append(contentsOf: [bottomA, topA, topB, bottomB])
            normals.append(contentsOf: [normalA, normalA, normalB, normalB])
            indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
        }

        if bottomRadius > 0.0001 {
            appendCap(radius: bottomRadius, y: -halfHeight, normal: SIMDVector3(0, -1, 0), upward: false,
                      segments: segments, positions: &positions, normals: &normals, indices: &indices)
        }
        if topRadius > 0.0001 {
            appendCap(radius: topRadius, y: halfHeight, normal: SIMDVector3(0, 1, 0), upward: true,
                      segments: segments, positions: &positions, normals: &normals, indices: &indices)
        }
        return MeshData(positions: positions, normals: normals, indices: indices)
    }

    private static func appendCap(radius: Float, y: Float, normal: SIMDVector3, upward: Bool, segments: Int,
                                   positions: inout [SIMDVector3], normals: inout [SIMDVector3], indices: inout [UInt16]) {
        let centerIndex = UInt16(positions.count)
        positions.append(SIMDVector3(0, y, 0))
        normals.append(normal)
        var ring: [UInt16] = []
        for i in 0..<segments {
            let theta = Float(i) / Float(segments) * 2 * Float.pi
            positions.append(SIMDVector3(cos(theta) * radius, y, sin(theta) * radius))
            normals.append(normal)
            ring.append(UInt16(positions.count - 1))
        }
        for i in 0..<segments {
            let a = ring[i]
            let b = ring[(i + 1) % segments]
            indices.append(contentsOf: upward ? [centerIndex, b, a] : [centerIndex, a, b])
        }
    }

    package static func box(size: SIMDVector3) -> MeshData {
        let hx = size.x * 0.5, hy = size.y * 0.5, hz = size.z * 0.5
        var positions: [SIMDVector3] = []
        var normals: [SIMDVector3] = []
        var indices: [UInt16] = []

        func quad(_ normal: SIMDVector3, _ a: SIMDVector3, _ b: SIMDVector3, _ c: SIMDVector3, _ d: SIMDVector3) {
            let base = UInt16(positions.count)
            positions.append(contentsOf: [a, b, c, d])
            normals.append(contentsOf: [normal, normal, normal, normal])
            indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
        }

        quad(SIMDVector3(0, 0, 1), SIMDVector3(-hx, -hy, hz), SIMDVector3(hx, -hy, hz), SIMDVector3(hx, hy, hz), SIMDVector3(-hx, hy, hz))
        quad(SIMDVector3(0, 0, -1), SIMDVector3(hx, -hy, -hz), SIMDVector3(-hx, -hy, -hz), SIMDVector3(-hx, hy, -hz), SIMDVector3(hx, hy, -hz))
        quad(SIMDVector3(1, 0, 0), SIMDVector3(hx, -hy, hz), SIMDVector3(hx, -hy, -hz), SIMDVector3(hx, hy, -hz), SIMDVector3(hx, hy, hz))
        quad(SIMDVector3(-1, 0, 0), SIMDVector3(-hx, -hy, -hz), SIMDVector3(-hx, -hy, hz), SIMDVector3(-hx, hy, hz), SIMDVector3(-hx, hy, -hz))
        quad(SIMDVector3(0, 1, 0), SIMDVector3(-hx, hy, hz), SIMDVector3(hx, hy, hz), SIMDVector3(hx, hy, -hz), SIMDVector3(-hx, hy, -hz))
        quad(SIMDVector3(0, -1, 0), SIMDVector3(-hx, -hy, -hz), SIMDVector3(hx, -hy, -hz), SIMDVector3(hx, -hy, hz), SIMDVector3(-hx, -hy, hz))

        return MeshData(positions: positions, normals: normals, indices: indices)
    }

    /// A ring of `segments + 1` (position, normal) pairs at height `y` and
    /// radius `radius`; `normalY`/`normalRadial` weight the outward normal's
    /// vertical vs. radial component (both zero-length pole rings just repeat
    /// a single straight-up/-down normal, which is the correct limit).
    private static func ringPoints(y: Float, radius: Float, normalY: Float, normalRadial: Float, segments: Int)
        -> [(position: SIMDVector3, normal: SIMDVector3)] {
        var points: [(SIMDVector3, SIMDVector3)] = []
        for i in 0...segments {
            let theta = Float(i) / Float(segments) * 2 * Float.pi
            let c = cos(theta), s = sin(theta)
            let position = SIMDVector3(c * radius, y, s * radius)
            let normal = SIMDVector3(c * normalRadial, normalY, s * normalRadial).normalized()
            points.append((position, normal))
        }
        return points
    }

    /// Stitches two adjacent latitude rings (`ringA` above `ringB`) into a
    /// smooth-shaded band. Winding verified by explicit cross-product
    /// derivation to point outward regardless of the two rings' absolute
    /// height or radius (so it works unmodified for both a sphere's bands and
    /// a capsule's polar caps, where one ring degenerates to a single point).
    private static func stitchRings(_ ringA: [(position: SIMDVector3, normal: SIMDVector3)],
                                     _ ringB: [(position: SIMDVector3, normal: SIMDVector3)],
                                     positions: inout [SIMDVector3], normals: inout [SIMDVector3], indices: inout [UInt16]) {
        let segments = ringA.count - 1
        let base = UInt16(positions.count)
        for p in ringA { positions.append(p.position); normals.append(p.normal) }
        let ringBBase = UInt16(positions.count)
        for p in ringB { positions.append(p.position); normals.append(p.normal) }

        for i in 0..<segments {
            let a = base + UInt16(i)
            let b = base + UInt16(i + 1)
            let c = ringBBase + UInt16(i + 1)
            let d = ringBBase + UInt16(i)
            indices.append(contentsOf: [a, d, c, a, c, b])
        }
    }

    package static func sphere(radius: Float) -> MeshData {
        var positions: [SIMDVector3] = []
        var normals: [SIMDVector3] = []
        var indices: [UInt16] = []
        let segments = radialSegments
        let latBands = max(rings * 2, 2)

        var ringStack: [[(position: SIMDVector3, normal: SIMDVector3)]] = []
        for band in 0...latBands {
            let phi = Float(band) / Float(latBands) * Float.pi
            let y = cos(phi), r = sin(phi)
            ringStack.append(ringPoints(y: y * radius, radius: r * radius, normalY: y, normalRadial: r, segments: segments))
        }
        for i in 0..<(ringStack.count - 1) {
            stitchRings(ringStack[i], ringStack[i + 1], positions: &positions, normals: &normals, indices: &indices)
        }
        return MeshData(positions: positions, normals: normals, indices: indices)
    }

    package static func capsule(radius: Float, height: Float) -> MeshData {
        var positions: [SIMDVector3] = []
        var normals: [SIMDVector3] = []
        var indices: [UInt16] = []
        let segments = radialSegments
        let latBands = max(rings, 1)
        let halfCylinder = max(height - radius * 2, 0) * 0.5

        var ringStack: [[(position: SIMDVector3, normal: SIMDVector3)]] = []
        // North pole.
        ringStack.append(ringPoints(y: halfCylinder + radius, radius: 0, normalY: 1, normalRadial: 0, segments: segments))
        // Top hemisphere, pole (exclusive) down to its equator (inclusive).
        for k in 1...latBands {
            let phi = Float(k) / Float(latBands) * (Float.pi * 0.5)
            ringStack.append(ringPoints(y: halfCylinder + radius * cos(phi), radius: radius * sin(phi),
                                         normalY: cos(phi), normalRadial: sin(phi), segments: segments))
        }
        // A straight cylindrical midsection only needs a second ring at the bottom equator.
        if halfCylinder > 0.0001 {
            ringStack.append(ringPoints(y: -halfCylinder, radius: radius, normalY: 0, normalRadial: 1, segments: segments))
        }
        // Bottom hemisphere, equator (exclusive) down to the pole (inclusive).
        for k in 1...latBands {
            let phi = Float(k) / Float(latBands) * (Float.pi * 0.5)
            ringStack.append(ringPoints(y: -halfCylinder - radius * sin(phi), radius: radius * cos(phi),
                                         normalY: -sin(phi), normalRadial: cos(phi), segments: segments))
        }

        for i in 0..<(ringStack.count - 1) {
            stitchRings(ringStack[i], ringStack[i + 1], positions: &positions, normals: &normals, indices: &indices)
        }
        return MeshData(positions: positions, normals: normals, indices: indices)
    }

    /// A simplified flying-wing "jet drone" silhouette: a flattened diamond
    /// body — pointed nose, wide flat wingspan at the middle, pointed tail —
    /// plus two small wingtip fins. Loosely modeled on stealth-UAV
    /// flying-wing references, reduced to a low-poly greybox: a stretched,
    /// flattened octahedron (8 flat-shaded triangles, matching the faceted
    /// look of the box/cylinder archetypes rather than the smooth-shaded
    /// round ones — a drone should read as angular, not rounded) plus two
    /// small double-sided fin triangles. Nose points along local +Z, the
    /// same "forward" axis yaw=0 already means for every archetype, so no
    /// change to `InstancedRenderSystem`'s yaw-only rotation is needed.
    ///
    /// Comparable vertex/triangle count to a plain box — cheap enough for
    /// this archetype's population, which (unlike the missile archetype)
    /// scales with the rest of the hostile population, up to
    /// `SimulationConfig.maxEnemyCapacity`.
    package static func flyingWing(wingspan: Float, height: Float, length: Float) -> MeshData {
        var positions: [SIMDVector3] = []
        var normals: [SIMDVector3] = []
        var indices: [UInt16] = []

        let halfSpan = wingspan * 0.5
        let halfHeight = height * 0.5
        let noseZ = length * 0.5
        let tailZ = -length * 0.5

        let nose = SIMDVector3(0, 0, noseZ)
        let tail = SIMDVector3(0, 0, tailZ)
        let leftTip = SIMDVector3(-halfSpan, 0, 0)
        let rightTip = SIMDVector3(halfSpan, 0, 0)
        let top = SIMDVector3(0, halfHeight, 0)
        let bottom = SIMDVector3(0, -halfHeight, 0)

        func triangle(_ a: SIMDVector3, _ b: SIMDVector3, _ c: SIMDVector3) {
            let normal = (b - a).cross(c - a).normalized()
            let base = UInt16(positions.count)
            positions.append(contentsOf: [a, b, c])
            normals.append(contentsOf: [normal, normal, normal])
            indices.append(contentsOf: [base, base + 1, base + 2])
        }

        // Nose-side faces, cycling top -> right -> bottom -> left; winding
        // verified by cross-product against each face's own centroid.
        triangle(nose, top, leftTip)
        triangle(nose, rightTip, top)
        triangle(nose, bottom, rightTip)
        triangle(nose, leftTip, bottom)
        // Tail-side faces, same cycle.
        triangle(tail, leftTip, top)
        triangle(tail, top, rightTip)
        triangle(tail, rightTip, bottom)
        triangle(tail, bottom, leftTip)

        // Wingtip fins: small double-sided triangles (visible from both
        // sides regardless of winding, so no orientation check needed here),
        // swept back toward the tail like the reference's winglets.
        func doubleSidedTriangle(_ a: SIMDVector3, _ b: SIMDVector3, _ c: SIMDVector3) {
            let normal = (b - a).cross(c - a).normalized()
            var base = UInt16(positions.count)
            positions.append(contentsOf: [a, b, c])
            normals.append(contentsOf: [normal, normal, normal])
            indices.append(contentsOf: [base, base + 1, base + 2])
            base = UInt16(positions.count)
            positions.append(contentsOf: [a, b, c])
            normals.append(contentsOf: [-normal, -normal, -normal])
            indices.append(contentsOf: [base, base + 2, base + 1])
        }

        let finHeight = height * 2.6
        let finSweep = length * 0.16
        let leftFinRoot = SIMDVector3(leftTip.x * 0.92, 0, leftTip.z - finSweep)
        let leftFinTip = SIMDVector3(leftTip.x * 0.88, finHeight, leftTip.z - finSweep * 0.55)
        doubleSidedTriangle(leftTip, leftFinRoot, leftFinTip)

        let rightFinRoot = SIMDVector3(rightTip.x * 0.92, 0, rightTip.z - finSweep)
        let rightFinTip = SIMDVector3(rightTip.x * 0.88, finHeight, rightTip.z - finSweep * 0.55)
        doubleSidedTriangle(rightTip, rightFinTip, rightFinRoot)

        return MeshData(positions: positions, normals: normals, indices: indices)
    }

    /// A ballistic-missile silhouette: cylindrical body, conical nose, and
    /// four tail fins in an X pattern. Elongated along local Y — the same
    /// axis the earlier capsule mesh used — so `InstancedRenderSystem`'s
    /// existing "forward -> Y column"
    /// look-along-velocity basis for this archetype needs no changes.
    ///
    /// Affordable to make more detailed than the mass ground archetypes:
    /// the missile population is capped two orders of magnitude smaller
    /// (`SimulationConfig.maxMissileCapacity`, 32 — see
    /// `InstancedRenderSystem`'s own comment on that budget), so the extra
    /// triangles here come nowhere near the hot-loop/fill-rate cost of the
    /// up-to-10k ground archetypes.
    package static func missile(bodyRadius: Float, totalLength: Float) -> MeshData {
        var positions: [SIMDVector3] = []
        var normals: [SIMDVector3] = []
        var indices: [UInt16] = []
        let segments = radialSegments

        let noseLength = totalLength * 0.32
        let bodyLength = totalLength - noseLength
        let tailY = -totalLength * 0.5
        let bodyTopY = tailY + bodyLength
        let noseTipY = tailY + totalLength

        appendCap(radius: bodyRadius, y: tailY, normal: SIMDVector3(0, -1, 0), upward: false,
                  segments: segments, positions: &positions, normals: &normals, indices: &indices)

        let bodyBottom = ringPoints(y: tailY, radius: bodyRadius, normalY: 0, normalRadial: 1, segments: segments)
        let bodyTop = ringPoints(y: bodyTopY, radius: bodyRadius, normalY: 0, normalRadial: 1, segments: segments)
        stitchRings(bodyBottom, bodyTop, positions: &positions, normals: &normals, indices: &indices)

        // Cone: constant slope along its whole slant, so the base ring and
        // the degenerate tip ring share the same tilted normal direction.
        let coneSlope = atan2(bodyRadius, noseLength)
        let noseNormalY = sin(coneSlope)
        let noseNormalRadial = cos(coneSlope)
        let noseBase = ringPoints(y: bodyTopY, radius: bodyRadius, normalY: noseNormalY, normalRadial: noseNormalRadial, segments: segments)
        let noseTip = ringPoints(y: noseTipY, radius: 0, normalY: noseNormalY, normalRadial: noseNormalRadial, segments: segments)
        stitchRings(noseBase, noseTip, positions: &positions, normals: &normals, indices: &indices)

        // Tail fins: thin double-sided triangles so at least some are always
        // visibly edge-lit rather than all four vanishing at once when the
        // camera happens to line up with a single-sided face's back.
        let finSpan = bodyRadius * 2.2
        let finLength = bodyLength * 0.42
        let finCount = 4
        func finVertex(_ radius: Float, _ y: Float, _ theta: Float) -> SIMDVector3 {
            SIMDVector3(cos(theta) * radius, y, sin(theta) * radius)
        }
        func doubleSidedTriangle(_ a: SIMDVector3, _ b: SIMDVector3, _ c: SIMDVector3) {
            let normal = (b - a).cross(c - a).normalized()
            var base = UInt16(positions.count)
            positions.append(contentsOf: [a, b, c])
            normals.append(contentsOf: [normal, normal, normal])
            indices.append(contentsOf: [base, base + 1, base + 2])
            base = UInt16(positions.count)
            positions.append(contentsOf: [a, b, c])
            normals.append(contentsOf: [-normal, -normal, -normal])
            indices.append(contentsOf: [base, base + 2, base + 1])
        }
        for i in 0..<finCount {
            let theta = Float(i) / Float(finCount) * 2 * Float.pi + Float.pi / 4
            let inner = finVertex(bodyRadius, tailY + finLength, theta)
            let tailInner = finVertex(bodyRadius, tailY, theta)
            let tailOuter = finVertex(bodyRadius + finSpan, tailY, theta)
            doubleSidedTriangle(inner, tailInner, tailOuter)
        }

        return MeshData(positions: positions, normals: normals, indices: indices)
    }

    /// Merges an already-built `MeshData` into an accumulating mesh, translated
    /// by `offset`. Used to compose several primitives (built by the ordinary
    /// primitive functions above) into one static instanced mesh — the same
    /// "build the pieces, then merge" approach `missile` already uses for its
    /// body/nose/fins, generalised into a reusable helper because `tank` needs
    /// it for three independently-shaped pieces instead of pieces that all
    /// share one ring-stitching origin.
    private static func appendSubMesh(_ sub: MeshData, offset: SIMDVector3,
                                       positions: inout [SIMDVector3], normals: inout [SIMDVector3], indices: inout [UInt16]) {
        let base = UInt16(positions.count)
        positions.append(contentsOf: sub.positions.map { $0 + offset })
        normals.append(contentsOf: sub.normals)
        indices.append(contentsOf: sub.indices.map { $0 + base })
    }

    /// A tracked-vehicle silhouette: a low boxy hull, a turret cupola set
    /// back on top, and a barrel projecting forward from the turret — three
    /// `box`/`cylinder` primitives merged into one mesh via `appendSubMesh`.
    /// Nose points along local +Z, the same "forward" axis yaw=0 already
    /// means for every other ground archetype, so no change to
    /// `InstancedRenderSystem`'s yaw-only rotation is needed.
    ///
    /// `dimensions` is interpreted the same way a caller would read any other
    /// archetype's bounding size: X = hull width, Z = hull length, Y = the
    /// TOTAL height including the turret (so the mesh's vertical centre — and
    /// therefore local Y = 0 — lands at the same fraction of overall height
    /// every other archetype uses, keeping `EnemyArchetypeConfig.cruiseAltitude`
    /// meaningful without a special case for this shape).
    package static func tank(dimensions: SIMDVector3) -> MeshData {
        let width = dimensions.x
        let length = dimensions.z
        let totalHeight = dimensions.y
        let hullHeight = totalHeight * 0.55
        let turretHeight = totalHeight - hullHeight
        let turretSize = width * 0.62
        // A tiny negative overlap so the turret's flat bottom face sinks
        // slightly into the hull instead of sitting exactly coplanar with its
        // top face — an exactly shared plane is a standing invitation to
        // z-fighting along that seam.
        let turretEmbed = hullHeight * 0.05
        let turretCenterZ = -length * 0.06
        let barrelRadius = width * 0.07
        let barrelLength = length * 0.65

        var positions: [SIMDVector3] = []
        var normals: [SIMDVector3] = []
        var indices: [UInt16] = []

        let hullBottom = -totalHeight * 0.5
        let hull = box(size: SIMDVector3(width, hullHeight, length))
        appendSubMesh(hull, offset: SIMDVector3(0, hullBottom + hullHeight * 0.5, 0),
                      positions: &positions, normals: &normals, indices: &indices)

        let turretBottom = hullBottom + hullHeight - turretEmbed
        let turret = box(size: SIMDVector3(turretSize, turretHeight, turretSize))
        appendSubMesh(turret, offset: SIMDVector3(0, turretBottom + turretHeight * 0.5, turretCenterZ),
                      positions: &positions, normals: &normals, indices: &indices)

        // `cylinder()` is built along its own local Y; rotating (x, y, z) ->
        // (x, -z, y) is a proper (determinant +1) rotation that carries that
        // axis onto local Z without flipping any winding, so the barrel
        // still faces forward like every other yaw-only archetype.
        let rawBarrel = cylinder(topRadius: barrelRadius, bottomRadius: barrelRadius, height: barrelLength)
        let barrel = MeshData(
            positions: rawBarrel.positions.map { SIMDVector3($0.x, -$0.z, $0.y) },
            normals: rawBarrel.normals.map { SIMDVector3($0.x, -$0.z, $0.y) },
            indices: rawBarrel.indices)
        let turretFrontZ = turretCenterZ + turretSize * 0.5
        // Sunk slightly into the turret for the same reason the turret is
        // sunk into the hull: the cylinder's flat back cap would otherwise
        // sit exactly on the turret's front face.
        let barrelCenterZ = turretFrontZ - barrelRadius * 0.5 + barrelLength * 0.5
        appendSubMesh(barrel, offset: SIMDVector3(0, turretBottom + turretHeight * 0.5, barrelCenterZ),
                      positions: &positions, normals: &normals, indices: &indices)

        return MeshData(positions: positions, normals: normals, indices: indices)
    }

    /// A large flat quad facing +Y — the ground.
    package static func plane(size: Float) -> MeshData {
        let h = size * 0.5
        let up = SIMDVector3(0, 1, 0)
        return MeshData(
            positions: [SIMDVector3(-h, 0, h), SIMDVector3(h, 0, h), SIMDVector3(h, 0, -h), SIMDVector3(-h, 0, -h)],
            normals: [up, up, up, up],
            indices: [0, 1, 2, 0, 2, 3])
    }
}
