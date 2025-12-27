#version 460 core

#extension GL_ARB_bindless_texture : require

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

vec3 unpackLocalPosition(uint data) {
    float x = bitfieldExtract(data, 0, 5);
    float y = bitfieldExtract(data, 5, 5);
    float z = bitfieldExtract(data, 10, 5);

    return vec3(x, y, z);
}

uint unpackModelFaceIdx(uint data) {
    uint modelFaceIdx = bitfieldExtract(data, 15, 17);

    return modelFaceIdx;
}

uint unpackIndirectLightTintIdx(uint data) {
    uint indirectLightTint = bitfieldExtract(data, 0, 1);

    return indirectLightTint;
}

uint unpackNormal(uint data) {
    uint normal = bitfieldExtract(data, 1, 3);

    return normal;
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

uint unpackTextureIdx(uint data) {
    uint textureIdx = bitfieldExtract(data, 0, 11);

    return textureIdx;
}

layout (binding = 0, std140) uniform ubo0 {
    mat4 uViewProjection;
    vec3 uSelectedBlockPosition;
};

out vec2 pTextureUV;
flat out uint pTextureIdx;
flat out uint pNormal;
flat out uint pIndirectLightTintIdx;
flat out uint pLightTextureIdx;
flat out int pDrawId;

out vec3 pLocalModelPosition;
out vec3 pWorldPosition;

void main() {
    uint faceIdx = gl_VertexID / 6;
    PerFaceData perFaceData = sPerFace[faceIdx];
    
    vec3 localPosition = unpackLocalPosition(perFaceData.data1);
    uint modelFaceIdx = unpackModelFaceIdx(perFaceData.data1);
    uint indirectLightTintIdx = unpackIndirectLightTintIdx(perFaceData.data2);
    uint normal = unpackNormal(perFaceData.data2);

    uint vertexIdx = modelFaceIdx + (gl_VertexID % 6);

    uint perVertexData = sPerVertex[vertexIdx];
    vec3 modelPosition = unpackModelPosition(perVertexData) / 16.0;
    vec2 textureUV = unpackTextureUV(perVertexData);
    uint textureIdx = unpackTextureIdx(sPerVertex[modelFaceIdx + 6]); // because textureIdx is the 7th value for every face
    
    pTextureUV = textureUV / 16.0;
    pTextureIdx = textureIdx;
    pIndirectLightTintIdx = indirectLightTintIdx;
    pLightTextureIdx = gl_BaseInstance;
    pNormal = normal;
    pDrawId = gl_DrawID;

    vec4 worldPosition = vec4(modelPosition + localPosition + sChunkMeshPos[gl_DrawID], 1.0);

    pLocalModelPosition = modelPosition + localPosition;
    pWorldPosition = worldPosition.xyz;
    gl_Position = uViewProjection * worldPosition;
}

// iXXX for input
// pXXX for pass(ing to frag shader)
// uXXX for uniform
// sXXX for ssbo
