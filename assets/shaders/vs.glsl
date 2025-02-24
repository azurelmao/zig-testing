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

struct LocalPosAndModelIdx {
    uint data1;
    uint data2;
};

layout(binding = 3, std430) readonly buffer ssbo4 {
    LocalPosAndModelIdx sLocalPosAndModelIdx[];
};

uniform mat4 uViewProjection;

out vec2 pTextureUV;
flat out uint pTextureIdx;
flat out float pNormalLight;
flat out vec3 pBlockLight;
flat out float pSunLight;

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

float unpackSunLight(uint data) {
    float sunLight = bitfieldExtract(data, 12, 4);

    return sunLight / 15.0;
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
    LocalPosAndModelIdx perQuadData = sLocalPosAndModelIdx[gl_VertexID / 6];
    
    vec3 localPosition = unpackLocalPosition(perQuadData.data1);
    uint modelIdx = unpackModelIdx(perQuadData.data1);
    vec3 blockLight = unpackBlockLight(perQuadData.data2);
    float sunLight = unpackSunLight(perQuadData.data2);

    VertexIdxAndTextureIdx perModelData = sVertexIdxAndTextureIdx[modelIdx];
    uint vertexIdx = perModelData.vertexIdx;
    uint textureIdx = unpackTextureIdx(perModelData.data);

    uint perVertexData = sVertex[vertexIdx + (gl_VertexID % 6)];
    vec3 modelPosition = unpackModelPosition(perVertexData);
    vec2 textureUV = unpackTextureUV(perVertexData);
    
    pTextureUV = textureUV;
    pTextureIdx = textureIdx;
    pNormalLight = normalLight[gl_DrawID % 6];
    pBlockLight = blockLight;
    pSunLight = sunLight;
    gl_Position = uViewProjection * vec4(modelPosition + localPosition + sChunkPos[gl_DrawID / 6], 1.0);
}

// iXXX for input
// pXXX for pass(ing to frag shader)
// uXXX for uniform
// sXXX for ssbo
