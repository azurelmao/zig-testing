#version 460 core

layout (binding = 1, std430) readonly buffer ssbo1 {
    vec3 sBoundingBoxLines[];
};

layout (binding = 2, std430) readonly buffer ssbo2 {
    vec3 sVisibleChunkMeshPositions[];
};

layout (binding = 0, std140) uniform ubo0 {
    mat4 uViewProjection;
    vec3 uSelectedBlockPosition;
    vec3 uSelectorPosition;
};

void main() {
    vec3 chunkMeshPosition = sVisibleChunkMeshPositions[gl_InstanceID];

    vec3 worldPosition = sBoundingBoxLines[gl_VertexID] + chunkMeshPosition;

    gl_Position = uViewProjection * vec4(worldPosition, 1);
}