#version 460 core

#extension GL_ARB_bindless_texture : require

in vec2 pTextureUV;
flat in uint pTextureIdx;
flat in uint pIndirectLightTintIdx;
flat in uint pNormal;
flat in sampler3D pLightTexture;

in vec3 pLocalModelPosition;
in vec3 pWorldPosition;

layout (location = 0) out vec4 oColor;
layout (binding = 0) uniform sampler2DArray uTexture;
uniform vec3 uCameraPosition;

const float[6] NormalLight = float[](
    0.6,
    0.6,
    0.4,
    1.0,
    0.8,
    0.8
);

const float[6] NormalLightInverted = float[](
    0.6,
    0.6,
    1.0,
    0.4,
    0.8,
    0.8
);

const vec3[6] NormalOffset = vec3[](
    vec3(-0.5, 0, 0), // west
    vec3(0.5, 0, 0), // east
    vec3(0, -0.5, 0), // bottom
    vec3(0, 0.5, 0), // top
    vec3(0, 0, -0.5), // north
    vec3(0, 0, 0.5) // south
);

const vec3[2] IndirectLightTint = vec3[](
    vec3(1),
    vec3(207, 221, 255) / 255.0
);

const vec4 FOG_COLOR = vec4(vec3(122, 168, 253) / 255.0, 1.0);
const float CHUNK_SIZE = 32.0;
const float OVERLAP_WIDTH = 1.0;
const float LIGHT_TEXTURE_SIZE = CHUNK_SIZE + OVERLAP_WIDTH * 2.0;
const float LIGHT_TEXTURE_SIZE_INVERSE = 1.0 / LIGHT_TEXTURE_SIZE;

vec4 linearFog(vec4 inColor, float vertexDistance, float fogStart, float fogEnd, vec4 fogColor) {
    if (vertexDistance <= fogStart) {
        return inColor;
    }

    float fogValue = vertexDistance < fogEnd ? smoothstep(fogStart, fogEnd, vertexDistance) : 1.0;
    return vec4(mix(inColor.rgb, fogColor.rgb, fogValue * fogColor.a), inColor.a);
}

void main() {
    float normalLight;

    if (gl_FrontFacing) {
        normalLight = NormalLight[pNormal];
    } else {
        normalLight = NormalLightInverted[pNormal];
    }

    vec4 texColor = texture(uTexture, vec3(pTextureUV, pTextureIdx));
    vec4 light = texture(pLightTexture, (pLocalModelPosition + NormalOffset[pNormal] + OVERLAP_WIDTH) * LIGHT_TEXTURE_SIZE_INVERSE, 0).abgr;

    vec3 blockLight = light.rgb;
    vec3 indirectLightTint = IndirectLightTint[pIndirectLightTintIdx];
    vec3 indirectLight = light.aaa * indirectLightTint;
    vec3 newLight = max(blockLight, indirectLight);

    vec4 color = vec4(texColor.rgb * newLight * normalLight, texColor.a);

    oColor = linearFog(color, distance(uCameraPosition, pWorldPosition), 153.6, 691.2, FOG_COLOR);
}

// oXXX for output
// iXXX for input
// pXXX for pass(ed from vertex shader)
// uXXX for uniform
// sXXX for ssbo
