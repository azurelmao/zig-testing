#version 460 core

in vec2 pTextureUV;
flat in uint pTextureIdx;

flat in float pNormalLight;
flat in vec3 pLight;

in vec3 pVertexPosition;

layout (location = 0) out vec4 oColor;
layout (binding = 0, location = 1) uniform sampler2DArray uTexture;
uniform vec3 uCameraPosition;

vec4 linearFog(vec4 inColor, float vertexDistance, float fogStart, float fogEnd, vec4 fogColor) {
    if (vertexDistance <= fogStart) {
        return inColor;
    }

    float fogValue = vertexDistance < fogEnd ? smoothstep(fogStart, fogEnd, vertexDistance) : 1.0;
    return vec4(mix(inColor.rgb, fogColor.rgb, fogValue * fogColor.a), inColor.a);
}

const vec4 fogColor = vec4(0.47843137254901963, 0.6588235294117647, 0.9921568627450981, 1.0);

void main() {
    vec4 texColor = texture(uTexture, vec3(pTextureUV, pTextureIdx));
    vec4 color = vec4(texColor.rgb * pNormalLight * pLight, texColor.a);

    oColor = linearFog(color, distance(uCameraPosition, pVertexPosition), 153.6, 691.2, fogColor);
}

// oXXX for output
// iXXX for input
// pXXX for pass(ed from vertex shader)
// uXXX for uniform
// sXXX for ssbo
