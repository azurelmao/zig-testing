#version 460 core

layout(binding = 0, std430) readonly buffer ssbo1 {
    uint sVertex[];
};

struct VertexIdxAndTextureIdx {
    uint vertexIdx;
    uint data;
};

layout(binding = 1, std430) readonly buffer ssbo2 {
    VertexIdxAndTextureIdx sVertexIdxAndTextureIdx[];
};

layout(binding = 2, std430) readonly buffer ssbo3 {
    vec3 sChunkPos[];
};

layout(binding = 3, std430) readonly buffer ssbo4 {
    uint sLocalPosAndFaceIdx[];
};

uniform mat4 uViewProjection;

out vec2 pTextureUV;
flat out uint pTextureIdx;
flat out float pNormalLight;

vec3 unpackLocalPosition(uint data) {
    float x = bitfieldExtract(data, 0, 5);
    float y = bitfieldExtract(data, 5, 5);
    float z = bitfieldExtract(data, 10, 5);

    return vec3(x, y, z);
}

uint unpackFaceIdx(uint data) {
    uint faceIdx = bitfieldExtract(data, 15, 17);

    return faceIdx;
}

uint unpackTextureIdx(uint data) {
    uint textureIdx = bitfieldExtract(data, 32, 11);

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

void main() {
    uint perVoxelData = sLocalPosAndFaceIdx[gl_VertexID / 6];
    
    vec3 localPosition = unpackLocalPosition(perVoxelData);
    uint faceIdx = unpackFaceIdx(perVoxelData);

    VertexIdxAndTextureIdx perFaceData = sVertexIdxAndTextureIdx[faceIdx];
    uint vertexIdx = perFaceData.vertexIdx;
    uint textureIdx = unpackTextureIdx(perFaceData.data);

    uint perVertexData = sVertex[vertexIdx + (gl_VertexID % 6)];
    vec3 modelPosition = unpackModelPosition(perVertexData);
    vec2 textureUV = unpackTextureUV(perVertexData);
    
    pTextureUV = textureUV;
    pTextureIdx = textureIdx;
    pNormalLight = normalLight[gl_DrawID % 6];
    gl_Position = uViewProjection * vec4(modelPosition + localPosition + sChunkPos[gl_DrawID / 6], 1.0);
}

// iXXX for input
// pXXX for pass(ing to frag shader)
// uXXX for uniform
// sXXX for ssbo
