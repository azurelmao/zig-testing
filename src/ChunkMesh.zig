const std = @import("std");
const gl = @import("gl");
const Vec3f = @import("vec3f.zig").Vec3f;
const Chunk = @import("Chunk.zig");
const LocalPos = Chunk.LocalPos;
const Light = @import("light.zig").Light;
const BlockLayer = @import("block.zig").BlockLayer;
const Dir = @import("dir.zig").Dir;
const World = @import("World.zig");
const NeighborChunks = World.NeighborChunks;

const ChunkMesh = @This();

layers: [BlockLayer.len]ChunkMeshLayer,

pub const ChunkMeshLayer = struct {
    faces: [6]std.ArrayListUnmanaged(PerFaceData),

    pub const empty: ChunkMeshLayer = .{ .faces = @splat(.empty) };
};

pub const PerFaceData = packed struct(u64) {
    x: u5,
    y: u5,
    z: u5,
    model_face_idx: u17,
    indirect_light_tint: u1,
    normal: Dir,
    _: u28 = 0,
};

pub const empty: ChunkMesh = .{ .layers = @splat(.empty) };

pub fn generate(chunk_mesh: *ChunkMesh, gpa: std.mem.Allocator, chunk: *Chunk, neighbor_chunks: *const NeighborChunks) !void {
    var chunk_mesh_layer: *ChunkMeshLayer = undefined;

    for (0..Chunk.SIZE) |x| {
        for (0..Chunk.SIZE) |y| {
            for (0..Chunk.SIZE) |z| {
                const local_pos = LocalPos{ .x = @intCast(x), .y = @intCast(y), .z = @intCast(z) };
                const block = chunk.getBlock(local_pos);

                if (block.kind.getModelScheme() == null) continue;

                chunk_mesh_layer = &chunk_mesh.layers[block.kind.getLayer().idx()];

                const block_model = block.kind.getModel();
                const mesh_flags = block.kind.getMeshFlags();

                inline for (Dir.values) |dir| skip: {
                    const dir_idx = dir.idx();
                    const block_model_indices = block_model.faces.get(dir);

                    if (block_model_indices.len == 0) break :skip;

                    if (NeighborChunks.inEdge[dir_idx](local_pos)) {
                        if (neighbor_chunks.chunks.get(dir)) |neighbor_chunk| {
                            const neighbor_pos = NeighborChunks.getNeighborPos[dir_idx](local_pos);
                            const neighbor_block = neighbor_chunk.getBlock(neighbor_pos);
                            const neighbor_mesh_flags = neighbor_block.kind.getMeshFlags();

                            if (mesh_flags.makes_same_kind_neighbor_blocks_emit_mesh or
                                (neighbor_mesh_flags.makes_neighbor_blocks_emit_mesh and
                                    (neighbor_block.kind != block.kind or neighbor_mesh_flags.makes_same_kind_neighbor_blocks_emit_mesh)))
                            {
                                for (block_model_indices) |block_model_face_idx| {
                                    try chunk_mesh_layer.faces[dir_idx].append(gpa, .{
                                        .x = local_pos.x,
                                        .y = local_pos.y,
                                        .z = local_pos.z,
                                        .model_face_idx = block_model_face_idx,
                                        .indirect_light_tint = if (neighbor_block.kind == .water) 1 else 0,
                                        .normal = dir,
                                    });
                                }
                            }
                        }
                    } else {
                        const neighbor_pos = NeighborChunks.getPos[dir_idx](local_pos);
                        const neighbor_block = chunk.getBlock(neighbor_pos);
                        const neighbor_mesh_flags = neighbor_block.kind.getMeshFlags();

                        if (mesh_flags.makes_same_kind_neighbor_blocks_emit_mesh or
                            (neighbor_mesh_flags.makes_neighbor_blocks_emit_mesh and
                                (neighbor_block.kind != block.kind or neighbor_mesh_flags.makes_same_kind_neighbor_blocks_emit_mesh)))
                        {
                            for (block_model_indices) |block_model_face_idx| {
                                try chunk_mesh_layer.faces[dir_idx].append(gpa, .{
                                    .x = local_pos.x,
                                    .y = local_pos.y,
                                    .z = local_pos.z,
                                    .model_face_idx = block_model_face_idx,
                                    .indirect_light_tint = if (neighbor_block.kind == .water) 1 else 0,
                                    .normal = dir,
                                });
                            }
                        }
                    }
                }
            }
        }
    }
}

pub const BOUNDING_BOX_LINES_BUFFER: []const Vec3f = &.{
    .{ .x = 0, .y = 0, .z = 0 },
    .{ .x = 0, .y = 0, .z = Chunk.SIZE },
    .{ .x = Chunk.SIZE, .y = 0, .z = 0 },
    .{ .x = Chunk.SIZE, .y = 0, .z = Chunk.SIZE },

    .{ .x = 0, .y = 0, .z = 0 },
    .{ .x = Chunk.SIZE, .y = 0, .z = 0 },
    .{ .x = 0, .y = 0, .z = Chunk.SIZE },
    .{ .x = Chunk.SIZE, .y = 0, .z = Chunk.SIZE },

    .{ .x = 0, .y = Chunk.SIZE, .z = 0 },
    .{ .x = 0, .y = Chunk.SIZE, .z = Chunk.SIZE },
    .{ .x = Chunk.SIZE, .y = Chunk.SIZE, .z = 0 },
    .{ .x = Chunk.SIZE, .y = Chunk.SIZE, .z = Chunk.SIZE },

    .{ .x = 0, .y = Chunk.SIZE, .z = 0 },
    .{ .x = Chunk.SIZE, .y = Chunk.SIZE, .z = 0 },
    .{ .x = 0, .y = Chunk.SIZE, .z = Chunk.SIZE },
    .{ .x = Chunk.SIZE, .y = Chunk.SIZE, .z = Chunk.SIZE },

    // vertical
    .{ .x = 0, .y = 0, .z = 0 },
    .{ .x = 0, .y = Chunk.SIZE, .z = 0 },

    .{ .x = 0, .y = 0, .z = Chunk.SIZE },
    .{ .x = 0, .y = Chunk.SIZE, .z = Chunk.SIZE },

    .{ .x = Chunk.SIZE, .y = 0, .z = 0 },
    .{ .x = Chunk.SIZE, .y = Chunk.SIZE, .z = 0 },

    .{ .x = Chunk.SIZE, .y = 0, .z = Chunk.SIZE },
    .{ .x = Chunk.SIZE, .y = Chunk.SIZE, .z = Chunk.SIZE },
};

pub const BOUNDING_BOX_BUFFER: []const Vec3f = west ++ east ++ bottom ++ top ++ north ++ south;

const west: []const Vec3f = &.{
    .{ .x = 0, .y = Chunk.SIZE, .z = Chunk.SIZE },
    .{ .x = 0, .y = Chunk.SIZE, .z = 0 },
    .{ .x = 0, .y = 0, .z = 0 },
    .{ .x = 0, .y = 0, .z = 0 },
    .{ .x = 0, .y = 0, .z = Chunk.SIZE },
    .{ .x = 0, .y = Chunk.SIZE, .z = Chunk.SIZE },
};

const east: []const Vec3f = &.{
    .{ .x = Chunk.SIZE, .y = 0, .z = 0 },
    .{ .x = Chunk.SIZE, .y = Chunk.SIZE, .z = 0 },
    .{ .x = Chunk.SIZE, .y = Chunk.SIZE, .z = Chunk.SIZE },
    .{ .x = Chunk.SIZE, .y = Chunk.SIZE, .z = Chunk.SIZE },
    .{ .x = Chunk.SIZE, .y = 0, .z = Chunk.SIZE },
    .{ .x = Chunk.SIZE, .y = 0, .z = 0 },
};

const bottom: []const Vec3f = &.{
    .{ .x = 0, .y = 0, .z = 0 },
    .{ .x = Chunk.SIZE, .y = 0, .z = 0 },
    .{ .x = Chunk.SIZE, .y = 0, .z = Chunk.SIZE },
    .{ .x = Chunk.SIZE, .y = 0, .z = Chunk.SIZE },
    .{ .x = 0, .y = 0, .z = Chunk.SIZE },
    .{ .x = 0, .y = 0, .z = 0 },
};

const top: []const Vec3f = &.{
    .{ .x = Chunk.SIZE, .y = Chunk.SIZE, .z = Chunk.SIZE },
    .{ .x = Chunk.SIZE, .y = Chunk.SIZE, .z = 0 },
    .{ .x = 0, .y = Chunk.SIZE, .z = 0 },
    .{ .x = 0, .y = Chunk.SIZE, .z = 0 },
    .{ .x = 0, .y = Chunk.SIZE, .z = Chunk.SIZE },
    .{ .x = Chunk.SIZE, .y = Chunk.SIZE, .z = Chunk.SIZE },
};

const north: []const Vec3f = &.{
    .{ .x = 0, .y = 0, .z = 0 },
    .{ .x = 0, .y = Chunk.SIZE, .z = 0 },
    .{ .x = Chunk.SIZE, .y = Chunk.SIZE, .z = 0 },
    .{ .x = Chunk.SIZE, .y = Chunk.SIZE, .z = 0 },
    .{ .x = Chunk.SIZE, .y = 0, .z = 0 },
    .{ .x = 0, .y = 0, .z = 0 },
};

const south: []const Vec3f = &.{
    .{ .x = Chunk.SIZE, .y = Chunk.SIZE, .z = Chunk.SIZE },
    .{ .x = 0, .y = Chunk.SIZE, .z = Chunk.SIZE },
    .{ .x = 0, .y = 0, .z = Chunk.SIZE },
    .{ .x = 0, .y = 0, .z = Chunk.SIZE },
    .{ .x = Chunk.SIZE, .y = 0, .z = Chunk.SIZE },
    .{ .x = Chunk.SIZE, .y = Chunk.SIZE, .z = Chunk.SIZE },
};
