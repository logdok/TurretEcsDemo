#include <metal_stdlib>
using namespace metal;

// Mirrors MathUtilities/FrameUniforms on the Swift side exactly. Every vector
// is a full float4 (never float3) specifically to sidestep Metal's constant-
// buffer float3 alignment/padding rules, which do not always match a naive
// Swift-side SIMD3<Float> layout — using float4 everywhere removes the
// ambiguity entirely.
struct FrameUniforms {
    float4x4 viewProjection;
    float4 lightDirection;   // xyz used
    float4 lightColor;       // xyz used
    float4 ambientColor;     // rgb = color, a = energy
    float4 cameraPosition;   // xyz used
};

// One instance's worth of data, matching `InstancePool`/
// `InstancedRenderSystem` on the Swift side byte for byte: three rows of a
// row-major 3x4 transform, then an RGBA tint — 16 floats per instance,
// stride 16, written directly by `InstancedRenderSystem` with no
// intermediate struct on the CPU side either.
struct InstanceData {
    float4 row0;
    float4 row1;
    float4 row2;
    float4 color;
};

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
};

struct VertexOut {
    float4 clipPosition [[position]];
    float3 worldPosition;
    float3 worldNormal;
    float4 color;
};

vertex VertexOut instanced_vertex_main(
    VertexIn in [[stage_in]],
    constant InstanceData *instances [[buffer(2)]],
    constant FrameUniforms &uniforms [[buffer(1)]],
    uint instanceID [[instance_id]])
{
    InstanceData inst = instances[instanceID];

    float3 worldPosition;
    worldPosition.x = dot(inst.row0.xyz, in.position) + inst.row0.w;
    worldPosition.y = dot(inst.row1.xyz, in.position) + inst.row1.w;
    worldPosition.z = dot(inst.row2.xyz, in.position) + inst.row2.w;

    // Uniform scale is baked into the rows, so the same 3x3 part (not an
    // inverse-transpose) is correct for normals too — it only rescales
    // length, which the normalize below removes.
    float3 worldNormal;
    worldNormal.x = dot(inst.row0.xyz, in.normal);
    worldNormal.y = dot(inst.row1.xyz, in.normal);
    worldNormal.z = dot(inst.row2.xyz, in.normal);

    VertexOut out;
    out.clipPosition = uniforms.viewProjection * float4(worldPosition, 1.0);
    out.worldPosition = worldPosition;
    out.worldNormal = normalize(worldNormal);
    out.color = inst.color;
    return out;
}

fragment float4 instanced_fragment_main(
    VertexOut in [[stage_in]],
    constant FrameUniforms &uniforms [[buffer(1)]])
{
    float3 normal = normalize(in.worldNormal);
    float3 lightDir = normalize(uniforms.lightDirection.xyz);
    float diffuseTerm = max(dot(normal, -lightDir), 0.0);

    float3 viewDir = normalize(uniforms.cameraPosition.xyz - in.worldPosition);
    float3 halfVector = normalize(-lightDir + viewDir);
    // Low, fixed-intensity highlight — matches the source material's rough
    // (roughness 0.7-0.85), non-metallic greybox look rather than a shiny one.
    float specularTerm = pow(max(dot(normal, halfVector), 0.0), 20.0) * 0.12;

    float3 ambient = uniforms.ambientColor.rgb * uniforms.ambientColor.a;
    float3 lit = in.color.rgb * (ambient + uniforms.lightColor.rgb * diffuseTerm) + specularTerm;
    return float4(lit, in.color.a);
}
