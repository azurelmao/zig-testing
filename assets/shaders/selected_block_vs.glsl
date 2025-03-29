#version 460 core

layout (binding = 13, std430) readonly buffer ssbo13 {
    vec3 sLineVertices[];
};

uniform mat4 uViewProjection;
uniform vec3 uBlockPosition;

void main() {
    vec4 worldPosition = vec4(uBlockPosition + sLineVertices[gl_VertexID], 1.0);
    gl_Position = uViewProjection * worldPosition;
}