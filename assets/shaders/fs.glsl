#version 460 core

in vec3 pTextureUVW;
// flat in uint pTextureIdx;
flat in float pNormalLight;

layout (location = 0) out vec4 oColor;

layout (binding = 0, location = 1) uniform sampler2DArray uTexture;

void main() {
    vec4 texColor = texture(uTexture, pTextureUVW);
    oColor = vec4(texColor.rgb * pNormalLight, texColor.a);
}

// oXXX for output
// iXXX for input
// pXXX for pass(ed from vertex shader)
// uXXX for uniform
// sXXX for ssbo
