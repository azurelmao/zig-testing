#version 460 core

in vec2 pTextureUV;

layout (location = 0) out vec4 oColor;
layout (binding = 2) uniform sampler2D uFramebuffer;
layout (binding = 3) uniform sampler2D uTexture;

vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

const float unit = 50.0 / 255.0;

void main() {
    vec3 prevColor = texelFetch(uFramebuffer, ivec2(gl_FragCoord.xy), 0).rgb;
    vec3 invertedColor = 1 - prevColor;
    
    vec3 finalColor = hsv2rgb(rgb2hsv(invertedColor) + vec3(0, unit, 0));

    oColor = vec4(finalColor, 1.0) * texture(uTexture, pTextureUV).rrrr;
}