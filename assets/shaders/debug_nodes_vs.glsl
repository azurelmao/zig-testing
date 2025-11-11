#version 460 core

layout (binding = 13, std430) readonly buffer ssbo13 {
    vec3 sLineVertices[];
};

layout (binding = 15) readonly buffer ssbo15 {
    vec3 sNodePositions[];
};

layout (binding = 0, std140) uniform ubo0 {
    mat4 uViewProjection;
    vec3 uSelectedBlockPosition;
};

void main() {
    vec4 worldPosition = vec4(sNodePositions[gl_InstanceID] + sLineVertices[gl_VertexID], 1.0);
    gl_Position = uViewProjection * worldPosition;
}