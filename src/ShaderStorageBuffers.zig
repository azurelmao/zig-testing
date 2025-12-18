const gl = @import("gl");
const stbi = @import("zstbi");
const assets = @import("assets.zig");
const ChunkMesh = @import("ChunkMesh.zig");
const ShaderStorageBuffer = @import("shader_storage_buffer.zig").ShaderStorageBuffer;
const Vec3f = @import("vec3f.zig").Vec3f;
const BlockKind = @import("block.zig").BlockKind;
const BlockModel = @import("block.zig").BlockModel;
const BlockVolumeScheme = @import("block.zig").BlockVolumeScheme;

const ShaderStorageBuffers = @This();

block_per_vertex: ShaderStorageBuffer(BlockModel.PerVertexData),
indirect_light: ShaderStorageBuffer(Vec3f),
chunk_bounding_box: ShaderStorageBuffer(Vec3f),
chunk_bounding_box_lines: ShaderStorageBuffer(Vec3f),
selected_block: ShaderStorageBuffer(Vec3f),

pub fn init() !ShaderStorageBuffers {
    const block_per_vertex: ShaderStorageBuffer(BlockModel.PerVertexData) = .initFromSliceAndBind(0, BlockModel.PER_VERTEX_BUFFER, gl.DYNAMIC_STORAGE_BIT);
    block_per_vertex.label("Block PerVertex Buffer");

    const indirect_light = try initIndirectLightBuffer();
    indirect_light.label("Indirect Light Buffer");

    const chunk_bounding_box: ShaderStorageBuffer(Vec3f) = .initFromSliceAndBind(5, ChunkMesh.BOUNDING_BOX_BUFFER, gl.DYNAMIC_STORAGE_BIT);
    chunk_bounding_box.label("Chunk Bounding Box Buffer");

    const chunk_bounding_box_lines: ShaderStorageBuffer(Vec3f) = .initFromSliceAndBind(11, ChunkMesh.BOUNDING_BOX_LINES_BUFFER, gl.DYNAMIC_STORAGE_BIT);
    chunk_bounding_box_lines.label("Chunk Bounding Box Lines Buffer");

    const selected_block: ShaderStorageBuffer(Vec3f) = .initFromSliceAndBind(13, BlockVolumeScheme.BLOCK_VOLUME_BUFFER, gl.DYNAMIC_STORAGE_BIT);
    selected_block.label("Selected Block Buffer");

    return .{
        .block_per_vertex = block_per_vertex,
        .indirect_light = indirect_light,
        .chunk_bounding_box = chunk_bounding_box,
        .chunk_bounding_box_lines = chunk_bounding_box_lines,
        .selected_block = selected_block,
    };
}

fn initIndirectLightBuffer() !ShaderStorageBuffer(Vec3f) {
    var indirect_light_image: stbi.Image = try .loadFromFile(assets.texturePath("indirect_light"), 4);
    defer indirect_light_image.deinit();

    const height = 2;
    const width = 16;
    const len = width * height;

    var indirect_light_data: [len]Vec3f = undefined;
    for (0..height) |y| {
        for (0..(indirect_light_image.data.len / 4 / height)) |x| {
            const idx = y * 16 + x;

            const vec3: Vec3f = .{
                .x = @as(gl.float, @floatFromInt(indirect_light_image.data[idx * 4])) / 255.0,
                .y = @as(gl.float, @floatFromInt(indirect_light_image.data[idx * 4 + 1])) / 255.0,
                .z = @as(gl.float, @floatFromInt(indirect_light_image.data[idx * 4 + 2])) / 255.0,
            };

            indirect_light_data[idx] = vec3;
        }
    }

    return .initFromSliceAndBind(3, &indirect_light_data, gl.DYNAMIC_STORAGE_BIT);
}
