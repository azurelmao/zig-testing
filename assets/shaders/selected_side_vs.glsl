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

vec3 unpackModelPosition(uint data) {
    float x = bitfieldExtract(data, 0, 5);
    float y = bitfieldExtract(data, 5, 5);
    float z = bitfieldExtract(data, 10, 5);

    return vec3(x, y, z);
}

layout (binding = 0, std140) uniform ubo0 {
    mat4 uViewProjection;
    vec3 uSelectedBlockPosition;
};
uniform uint uModelIdx;

void main() {
    VertexIdxAndTextureIdx perModelData = sVertexIdxAndTextureIdx[uModelIdx];
    uint vertexIdx = perModelData.vertexIdx;

    uint perVertexData = sVertex[vertexIdx + gl_VertexID];
    vec3 modelPosition = unpackModelPosition(perVertexData);

    vec4 worldPosition = vec4(uSelectedBlockPosition + modelPosition, 1.0);

    gl_Position = uViewProjection * worldPosition;
}