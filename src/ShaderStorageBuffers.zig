const gl = @import("gl");
const stbi = @import("zstbi");
const assets = @import("assets.zig");
const ChunkMeshGenerator = @import("ChunkMeshGenerator.zig");
const ShaderStorageBuffer = @import("shader_storage_buffer.zig").ShaderStorageBuffer;
const Vec3f = @import("vec3f.zig").Vec3f;
const BlockKind = @import("block.zig").BlockKind;
const BlockModel = @import("block.zig").BlockModel;
const BlockVolumeScheme = @import("block.zig").BlockVolumeScheme;

const ShaderStorageBuffers = @This();

block_per_vertex: ShaderStorageBuffer(BlockModel.PerVertexData),
chunk_bounding_box: ShaderStorageBuffer(Vec3f),
chunk_bounding_box_lines: ShaderStorageBuffer(Vec3f),
selected_block: ShaderStorageBuffer(Vec3f),

pub fn init() !ShaderStorageBuffers {
    const block_per_vertex: ShaderStorageBuffer(BlockModel.PerVertexData) = .initFromSliceAndBind(0, BlockModel.PER_VERTEX_BUFFER, gl.DYNAMIC_STORAGE_BIT);
    block_per_vertex.label("Block PerVertex Buffer");

    const chunk_bounding_box: ShaderStorageBuffer(Vec3f) = .initFromSliceAndBind(5, ChunkMeshGenerator.BOUNDING_BOX_BUFFER, gl.DYNAMIC_STORAGE_BIT);
    chunk_bounding_box.label("Chunk Bounding Box Buffer");

    const chunk_bounding_box_lines: ShaderStorageBuffer(Vec3f) = .initFromSlice(ChunkMeshGenerator.BOUNDING_BOX_LINES_BUFFER, gl.DYNAMIC_STORAGE_BIT);
    chunk_bounding_box_lines.label("Chunk Bounding Box Lines Buffer");

    const selected_block: ShaderStorageBuffer(Vec3f) = .initFromSliceAndBind(13, BlockVolumeScheme.BLOCK_VOLUME_BUFFER, gl.DYNAMIC_STORAGE_BIT);
    selected_block.label("Selected Block Buffer");

    return .{
        .block_per_vertex = block_per_vertex,
        .chunk_bounding_box = chunk_bounding_box,
        .chunk_bounding_box_lines = chunk_bounding_box_lines,
        .selected_block = selected_block,
    };
}
