import Foundation
import Metal
import simd

/// Device-level Metal state shared by the whole renderer: the command queue,
/// the compiled shader library, the one render pipeline every batch draws
/// through, and the depth-stencil state. Built once at startup.
package final class MetalContext {
    package let device: MTLDevice
    package let commandQueue: MTLCommandQueue
    package let pipelineState: MTLRenderPipelineState
    package let depthStencilState: MTLDepthStencilState

    package init?(device: MTLDevice, colorPixelFormat: MTLPixelFormat, depthPixelFormat: MTLPixelFormat) {
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        commandQueue = queue
        // `Shaders.metal` lives in this module, not in the app target, so
        // Xcode compiles it into THIS module's own resource bundle. A plain
        // `makeDefaultLibrary()` only ever looks in the main bundle and would
        // come back empty. This one line is the whole price the package split
        // charges for resources — paid here, once, instead of leaving a
        // shader file stranded in the app shell.
        guard let library = try? device.makeDefaultLibrary(bundle: Bundle.module) else { return nil }

        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float3
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.stride * 3
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.stride * 6
        vertexDescriptor.layouts[0].stepFunction = .perVertex

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "instanced_vertex_main")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "instanced_fragment_main")
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        pipelineDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = depthPixelFormat

        guard let pipeline = try? device.makeRenderPipelineState(descriptor: pipelineDescriptor) else { return nil }
        pipelineState = pipeline

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: depthDescriptor) else { return nil }
        depthStencilState = depthState
    }
}

/// Per-frame camera/lighting uniforms. Field order and every field's type
/// (`SIMD4<Float>`, never `SIMD3<Float>`) must match `FrameUniforms` in
/// Shaders.metal exactly — see that file's comment on why float4 is used
/// throughout even where only three components carry data.
package struct FrameUniforms {
    package var viewProjection: simd_float4x4
    package var lightDirection: SIMD4<Float>
    package var lightColor: SIMD4<Float>
    package var ambientColor: SIMD4<Float>
    package var cameraPosition: SIMD4<Float>

    // Spelled out because a memberwise initializer is only ever internal, and
    // the frame driver that fills this lives in another module.
    package init(viewProjection: simd_float4x4,
                 lightDirection: SIMD4<Float>,
                 lightColor: SIMD4<Float>,
                 ambientColor: SIMD4<Float>,
                 cameraPosition: SIMD4<Float>) {
        self.viewProjection = viewProjection
        self.lightDirection = lightDirection
        self.lightColor = lightColor
        self.ambientColor = ambientColor
        self.cameraPosition = cameraPosition
    }
}
