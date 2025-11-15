#version 460 core

layout (binding = 13, std430) readonly buffer ssbo13 {
    vec3 sLineVertices[];
};

layout (binding = 0, std140) uniform ubo0 {
    mat4 uViewProjection;
    vec3 uSelectedBlockPosition;
    vec3 uSelectorPosition;
};

void main() {
    vec4 worldPosition = vec4(uSelectorPosition + sLineVertices[gl_VertexID], 1.0);
    gl_Position = uViewProjection * worldPosition;
}