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

uniform mat4 uViewProjection;
uniform vec3 uBlockPosition;
uniform uint uModelIdx;

vec3 unpackModelPosition(uint data) {
    float x = bitfieldExtract(data, 0, 5);
    float y = bitfieldExtract(data, 5, 5);
    float z = bitfieldExtract(data, 10, 5);

    return vec3(x, y, z);
}

out vec3 dModelPosition;
out vec3 dBlockPosition;
out vec4 dWorldPosition;

void main() {
    VertexIdxAndTextureIdx perModelData = sVertexIdxAndTextureIdx[uModelIdx];
    uint vertexIdx = perModelData.vertexIdx;

    uint perVertexData = sVertex[vertexIdx + gl_VertexID];
    vec3 modelPosition = unpackModelPosition(perVertexData);

    vec4 worldPosition = vec4(uBlockPosition + modelPosition, 1.0);

    dModelPosition = modelPosition;
    dBlockPosition = uBlockPosition;
    dWorldPosition = worldPosition;

    gl_Position = uViewProjection * worldPosition;
}