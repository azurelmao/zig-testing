#version 460 core

out vec2 pTextureUV;
uniform vec2 uWindowSize;

const vec4[6] vertices = vec4[6](
    vec4(1, 1, 1, 0),
    vec4(0, 1, 0, 0),
    vec4(0, 0, 0, 1),
    vec4(0, 0, 0, 1),
    vec4(1, 0, 1, 1),
    vec4(1, 1, 1, 0)
);

const float crosshairSize = 8;

void main() {
    vec4 vertex = vertices[gl_VertexID];

    vec2 position = (vertex.xy * crosshairSize * 2 - crosshairSize) / uWindowSize;

    pTextureUV = vertex.zw;
    gl_Position = vec4(position, 0, 1);
}