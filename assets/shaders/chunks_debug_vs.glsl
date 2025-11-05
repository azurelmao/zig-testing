#version 460 core

layout (binding = 11, std430) readonly buffer ssbo11 {
    vec3 sBoundingBoxLines[];
};

layout (binding = 12, std430) readonly buffer ssbo12 {
    vec3 sVisibleChunkMeshPos[];
};

layout (binding = 0, std140) uniform ubo0 {
    mat4 uViewProjection;
    vec3 uSelectedBlockPosition;
};

void main() {
    vec4 worldPosition = vec4(sBoundingBoxLines[gl_VertexID] + sVisibleChunkMeshPos[gl_InstanceID], 1.0);
    gl_Position = uViewProjection * worldPosition;
}