#version 460 core

layout (binding = 0, std430) readonly buffer ssbo0 {
    uint sVertex[];
};

struct VertexIdxAndTextureIdx {
    uint vertexIdx;
    uint data;
};

layout (binding = 1, std430) readonly buffer ssbo1 {
    VertexIdxAndTextureIdx sVertexIdxAndTextureIdx[];
};

layout (binding = 2, std430) readonly buffer ssbo2 {
    vec3 sChunkPos[];
};

struct LocalPosAndModelIdx {
    uint data1;
    uint data2;
};

layout (binding = 3, std430) readonly buffer ssbo3 {
    LocalPosAndModelIdx sLocalPosAndModelIdx[];
};

layout (binding = 4, std430) readonly buffer ssbo4 {
    vec3 sIndirectLight[];
};

uniform mat4 uViewProjection;

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

vec3 unpackModelPosition(uint data) {
    float x = bitfieldExtract(data, 0, 5);
    float y = bitfieldExtract(data, 5, 5);
    float z = bitfieldExtract(data, 10, 5);

    return vec3(x, y, z);
}

void main() {
    LocalPosAndModelIdx perQuadData = sLocalPosAndModelIdx[gl_VertexID / 6];
    
    vec3 localPosition = unpackLocalPosition(perQuadData.data1);
    uint modelIdx = unpackModelIdx(perQuadData.data1);

    VertexIdxAndTextureIdx perModelData = sVertexIdxAndTextureIdx[modelIdx];
    uint vertexIdx = perModelData.vertexIdx;

    uint perVertexData = sVertex[vertexIdx + (gl_VertexID % 6)];
    vec3 modelPosition = unpackModelPosition(perVertexData);

    vec4 worldPosition = vec4(modelPosition + localPosition + sChunkPos[gl_DrawID / 6], 1.0);

    gl_Position = uViewProjection * worldPosition;
}