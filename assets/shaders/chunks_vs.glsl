#version 460 core

layout (binding = 0, std430) readonly buffer ssbo0 {
    uint sPerVertex[];
};

struct PerFaceData {
    uint data1;
    uint data2;
};

layout (binding = 1, std430) readonly buffer ssbo1 {
    PerFaceData sPerFace[];
};

layout (binding = 2, std430) readonly buffer ssbo2 {
    vec3 sChunkMeshPos[];
};

layout (binding = 3, std430) readonly buffer ssbo3 {
    vec3 sIndirectLight[];
};

vec3 unpackLocalPosition(uint data) {
    float x = bitfieldExtract(data, 0, 5);
    float y = bitfieldExtract(data, 5, 5);
    float z = bitfieldExtract(data, 10, 5);

    return vec3(x, y, z);
}

uint unpackModelIdx(uint data) {
    uint modelIdx = bitfieldExtract(data, 15, 17);

    return modelIdx;
}

vec3 unpackBlockLight(uint data) {
    float red = bitfieldExtract(data, 0, 4);
    float green = bitfieldExtract(data, 4, 4);
    float blue = bitfieldExtract(data, 8, 4);

    return vec3(red, green, blue) / 15.0;
}

uint unpackIndirectLightIdx(uint data) {
    uint indirectLightIdx = bitfieldExtract(data, 12, 5);

    return indirectLightIdx;
}

uint unpackNormal(uint data) {
    uint normal = bitfieldExtract(data, 17, 3);

    return normal;
}

uint unpackTextureIdx(uint data) {
    uint textureIdx = bitfieldExtract(data, 20, 11);

    return textureIdx;
}

vec3 unpackModelPosition(uint data) {
    float x = bitfieldExtract(data, 0, 5);
    float y = bitfieldExtract(data, 5, 5);
    float z = bitfieldExtract(data, 10, 5);

    return vec3(x, y, z);
}

vec2 unpackTextureUV(uint data) {
    float u = bitfieldExtract(data, 15, 5);
    float v = bitfieldExtract(data, 20, 5);

    return vec2(u, v);
}

const float[6] normalLight = float[](
    0.6,
    0.6,
    0.4,
    1.0,
    0.8,
    0.8
);

layout (binding = 0, std140) uniform ubo0 {
    mat4 uViewProjection;
    vec3 uSelectedBlockPosition;
};

out vec2 pTextureUV;
flat out uint pTextureIdx;
flat out float pNormalLight;
flat out vec3 pLight;

out vec3 pVertexPosition;

void main() {
    PerFaceData perFaceData = sPerFace[gl_VertexID / 6];
    
    vec3 localPosition = unpackLocalPosition(perFaceData.data1);
    uint modelIdx = unpackModelIdx(perFaceData.data1);
    vec3 blockLight = unpackBlockLight(perFaceData.data2);
    uint indirectLightIdx = unpackIndirectLightIdx(perFaceData.data2);
    uint normal = unpackNormal(perFaceData.data2);
    uint textureIdx = unpackTextureIdx(perFaceData.data2);

    uint vertexIdx = (modelIdx * 36) + (normal * 6) + (gl_VertexID % 6);

    uint perVertexData = sPerVertex[vertexIdx];
    vec3 modelPosition = unpackModelPosition(perVertexData);
    vec2 textureUV = unpackTextureUV(perVertexData);
    
    pTextureUV = textureUV;
    pTextureIdx = textureIdx;

    pNormalLight = normalLight[normal];
    vec3 indirectLight = sIndirectLight[indirectLightIdx];

    pLight = vec3(
        max(blockLight.r, indirectLight.r), 
        max(blockLight.g, indirectLight.g), 
        max(blockLight.b, indirectLight.b)
    );

    vec4 worldPosition = vec4(modelPosition + localPosition + sChunkMeshPos[gl_DrawID], 1.0);

    pVertexPosition = worldPosition.xyz;
    gl_Position = uViewProjection * worldPosition;
}

// iXXX for input
// pXXX for pass(ing to frag shader)
// uXXX for uniform
// sXXX for ssbo
