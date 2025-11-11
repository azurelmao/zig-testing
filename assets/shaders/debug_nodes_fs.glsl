#version 460 core

layout (location = 0) out vec4 oColor;
uniform vec3 uColor;

void main() {
    oColor = vec4(uColor, 0.2);
}