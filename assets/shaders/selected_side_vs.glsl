#version 460 core

layout (binding = 0, std430) readonly buffer ssbo0 {
    uint sPerVertex[];
};

layout (binding = 0, std140) uniform ubo0 {
    mat4 uViewProjection;
    vec3 uSelectedBlockPosition;
    vec3 uSelectorPosition;
};

uniform uint uFaceIdx;

vec3 unpackModelPosition(uint data) {
    float x = bitfieldExtract(data, 0, 5);
    float y = bitfieldExtract(data, 5, 5);
    float z = bitfieldExtract(data, 10, 5);

    return vec3(x, y, z);
}

void main() {
    uint vertexIdx = uFaceIdx + (gl_VertexID % 6);

    uint perVertexData = sPerVertex[vertexIdx];
    vec3 modelPosition = unpackModelPosition(perVertexData) / 16.0;

    vec4 worldPosition = vec4(uSelectedBlockPosition + modelPosition, 1.0);

    gl_Position = uViewProjection * worldPosition;
}