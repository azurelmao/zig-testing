#version 460 core

layout (binding = 2, std430) readonly buffer ssbo2 {
    vec3 sChunkPos[];
};

layout (binding = 5, std430) readonly buffer ssbo5 {
    vec3 sBoundingBox[];
};

uniform mat4 uViewProjection;

void main() {
    vec4 worldPosition = vec4(sBoundingBox[gl_VertexID] + sChunkPos[gl_InstanceID], 1.0);
    gl_Position = uViewProjection * worldPosition;
}