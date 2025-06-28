const gl = @import("gl");
const stbi = @import("zstbi");
const assets = @import("assets.zig");
const ChunkMesh = @import("ChunkMesh.zig");
const ShaderStorageBuffer = @import("shader_storage_buffer.zig").ShaderStorageBuffer;
const Vec3f = @import("vec3f.zig").Vec3f;
const BlockKind = @import("block.zig").BlockKind;
const BlockModel = @import("block.zig").BlockModel;

const ShaderStorageBuffers = @This();

block_vertex: ShaderStorageBuffer(BlockModel.Vertex),
block_face: ShaderStorageBuffer(BlockModel.FaceVertex),
indirect_light: ShaderStorageBuffer(Vec3f),
chunk_bounding_box: ShaderStorageBuffer(Vec3f),
chunk_bounding_box_lines: ShaderStorageBuffer(Vec3f),
selected_block: ShaderStorageBuffer(Vec3f),

pub fn init() !ShaderStorageBuffers {
    const block_vertex = ShaderStorageBuffer(BlockModel.Vertex).initFromSliceAndBind(0, BlockModel.VERTEX_BUFFER, gl.DYNAMIC_STORAGE_BIT);
    block_vertex.label("Block Vertex Buffer");

    const block_face = ShaderStorageBuffer(BlockModel.FaceVertex).initFromSliceAndBind(1, BlockModel.FACE_BUFFER, gl.DYNAMIC_STORAGE_BIT);
    block_face.label("Block Face Buffer");

    const indirect_light = try initIndirectLightBuffer();
    indirect_light.label("Indirect Light Buffer");

    const chunk_bounding_box = ShaderStorageBuffer(Vec3f).initFromSliceAndBind(5, ChunkMesh.BOUNDING_BOX_BUFFER, gl.DYNAMIC_STORAGE_BIT);
    chunk_bounding_box.label("Chunk Bounding Box Buffer");

    const chunk_bounding_box_lines = ShaderStorageBuffer(Vec3f).initFromSliceAndBind(11, ChunkMesh.BOUNDING_BOX_LINES_BUFFER, gl.DYNAMIC_STORAGE_BIT);
    chunk_bounding_box_lines.label("Chunk Bounding Box Lines Buffer");

    const selected_block = ShaderStorageBuffer(Vec3f).initFromSliceAndBind(13, BlockModel.BOUNDING_BOX_LINES_BUFFER, gl.DYNAMIC_STORAGE_BIT);
    selected_block.label("Selected Block Buffer");

    return .{
        .block_vertex = block_vertex,
        .block_face = block_face,
        .indirect_light = indirect_light,
        .chunk_bounding_box = chunk_bounding_box,
        .chunk_bounding_box_lines = chunk_bounding_box_lines,
        .selected_block = selected_block,
    };
}

fn initIndirectLightBuffer() !ShaderStorageBuffer(Vec3f) {
    var indirect_light_image = try stbi.Image.loadFromFile(assets.texturePath("indirect_light"), 4);
    defer indirect_light_image.deinit();

    var indirect_light_data: [16]Vec3f = undefined;
    for (0..(indirect_light_image.data.len / 4)) |idx| {
        const vec3 = Vec3f{
            .x = @as(gl.float, @floatFromInt(indirect_light_image.data[idx * 4])) / 255.0,
            .y = @as(gl.float, @floatFromInt(indirect_light_image.data[idx * 4 + 1])) / 255.0,
            .z = @as(gl.float, @floatFromInt(indirect_light_image.data[idx * 4 + 2])) / 255.0,
        };

        indirect_light_data[idx] = vec3;
    }

    return ShaderStorageBuffer(Vec3f).initFromSliceAndBind(4, &indirect_light_data, gl.DYNAMIC_STORAGE_BIT);
}
