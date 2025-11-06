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
    model_idx: u17,
    light: Light,
    indirect_light_color: u1,
    normal: Dir,
    texture_idx: u11,
    _: u1 = 0,
};

pub const empty: ChunkMesh = .{ .layers = @splat(.empty) };

pub fn generate(chunk_mesh: *ChunkMesh, gpa: std.mem.Allocator, chunk: *Chunk, neighbor_chunks: *const NeighborChunks) !void {
    var chunk_mesh_layer: *ChunkMeshLayer = undefined;

    for (0..Chunk.SIZE) |x| {
        for (0..Chunk.SIZE) |y| {
            for (0..Chunk.SIZE) |z| {
                const pos = LocalPos{ .x = @intCast(x), .y = @intCast(y), .z = @intCast(z) };
                const block = chunk.getBlock(pos);

                if (block.kind == .air) {
                    continue;
                }

                chunk_mesh_layer = &chunk_mesh.layers[block.kind.getLayer().idx()];

                const model_idx = block.kind.getModelIdx();
                const texture_scheme = block.kind.getTextureScheme();

                inline for (Dir.values) |dir| {
                    const dir_idx = dir.idx();

                    if (NeighborChunks.inEdge[dir_idx](pos)) {
                        if (neighbor_chunks.chunks[dir_idx]) |neighbor_chunk| {
                            const neighbor_pos = NeighborChunks.getNeighborPos[dir_idx](pos);
                            const neighbor_block = neighbor_chunk.getBlock(neighbor_pos);

                            if (neighbor_block.kind.isNotSolid() and neighbor_block.kind != block.kind) {
                                const neighbor_light = neighbor_chunk.getLight(neighbor_pos);

                                try chunk_mesh_layer.faces[dir_idx].append(gpa, .{
                                    .x = pos.x,
                                    .y = pos.y,
                                    .z = pos.z,
                                    .model_idx = model_idx,
                                    .light = neighbor_light,
                                    .indirect_light_color = if (neighbor_block.kind == .water) 1 else 0,
                                    .normal = dir,
                                    .texture_idx = texture_scheme.faces[dir_idx].idx(),
                                });
                            }
                        }
                    } else {
                        const neighbor_pos = NeighborChunks.getPos[dir_idx](pos);
                        const neighbor_block = chunk.getBlock(neighbor_pos);

                        if (neighbor_block.kind.isNotSolid() and neighbor_block.kind != block.kind) {
                            const neighbor_light = chunk.getLight(neighbor_pos);

                            try chunk_mesh_layer.faces[dir_idx].append(gpa, .{
                                .x = pos.x,
                                .y = pos.y,
                                .z = pos.z,
                                .model_idx = model_idx,
                                .light = neighbor_light,
                                .indirect_light_color = if (neighbor_block.kind == .water) 1 else 0,
                                .normal = dir,
                                .texture_idx = texture_scheme.faces[dir_idx].idx(),
                            });
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
