#version 460 core

in vec2 pTextureUV;
flat in uint pTextureIdx;

layout (location = 0) out vec4 oColor;
layout (binding = 1) uniform sampler2DArray uTexture;

void main() {
    float value = texture(uTexture, vec3(pTextureUV, pTextureIdx)).r;
    oColor = vec4(value);
}