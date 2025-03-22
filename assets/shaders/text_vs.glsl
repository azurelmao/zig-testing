#version 460 core

struct Vertex {
    float x;
    float y;
    float u;
    float v;
    uint idx;
};

layout (binding = 11, std430) readonly buffer ssbo11 {
    Vertex sTextVertices[];
};

out vec2 pTextureUV;
flat out uint pTextureIdx;

void main() {
    Vertex vertex = sTextVertices[gl_VertexID];

    pTextureUV = vec2(vertex.u, vertex.v);
    pTextureIdx = vertex.idx;
    gl_Position = vec4(vertex.x, vertex.y, 0.0, 1.0);
}