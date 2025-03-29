#version 460 core

layout (location = 0) out vec4 oColor;
layout (binding = 2) uniform sampler2D uFramebuffer;

const float unit = 10.0 / 255.0;

void main() {
    vec3 prevColor = texelFetch(uFramebuffer, ivec2(gl_FragCoord.xy), 0).rgb;
    oColor = vec4(vec3(1) - prevColor + unit, 1.0);
}