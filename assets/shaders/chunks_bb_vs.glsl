#version 460 core

layout (binding = 5, std430) readonly buffer ssbo5 {
    vec3 sBoundingBox[];
};

layout (binding = 0, std140) uniform ubo0 {
    mat4 uViewProjection;
    vec3 uSelectedBlockPosition;
    vec3 uSelectorPosition;
};

flat out uint pDrawCommandId;

void main() {
    pDrawCommandId = gl_InstanceID * 6;

    vec4 worldPosition = vec4(sBoundingBox[gl_VertexID] + sChunkPos[gl_InstanceID], 1.0);
    gl_Position = uViewProjection * worldPosition;
}