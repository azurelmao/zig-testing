#version 460 core

in vec2 pTextureUV;
flat in uint pTextureIdx;
flat in float pNormalLight;
flat in vec3 pBlockLight;
flat in float pSunLight;

layout (location = 0) out vec4 oColor;

layout (binding = 0, location = 1) uniform sampler2DArray uTexture;

void main() {
    vec4 texColor = texture(uTexture, vec3(pTextureUV, pTextureIdx));
    vec3 light = vec3(
        max(pBlockLight.r, pSunLight), 
        max(pBlockLight.g, pSunLight), 
        max(pBlockLight.b, pSunLight)
    );

    oColor = vec4(texColor.rgb * pNormalLight * light, texColor.a);
}

// oXXX for output
// iXXX for input
// pXXX for pass(ed from vertex shader)
// uXXX for uniform
// sXXX for ssbo
