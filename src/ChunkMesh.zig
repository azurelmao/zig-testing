const std = @import("std");
const gl = @import("gl");
const Vec3f = @import("vec3f.zig").Vec3f;
const Chunk = @import("Chunk.zig");
const LocalPos = Chunk.LocalPos;
const Light = @import("light.zig").Light;
const BlockLayer = @import("block.zig").BlockLayer;
const Side = @import("side.zig").Side;

const ChunkMesh = @This();

layers: [BlockLayer.len]ChunkMeshLayer,

pub const ChunkMeshLayer = struct {
    faces: [6]std.ArrayListUnmanaged(Vertex),

    pub fn init() ChunkMeshLayer {
        return .{ .faces = @splat(.empty) };
    }
};

pub const Vertex = packed struct(u64) {
    x: u5,
    y: u5,
    z: u5,
    model_idx: u17,
    light: Light,
    indirect_light_color: u1,
    _: u15 = 0,
};

pub fn init() ChunkMesh {
    return .{ .layers = @splat(.init()) };
}

pub const NeighborChunks = struct {
    chunks: [6]?*Chunk,

    const inEdge = .{
        inWestEdge,
        inEastEdge,
        inBottomEdge,
        inTopEdge,
        inNorthEdge,
        inSouthEdge,
    };

    const getPos = .{
        getWestPos,
        getEastPos,
        getBottomPos,
        getTopPos,
        getNorthPos,
        getSouthPos,
    };

    const getNeighborPos = .{
        getWestNeighborPos,
        getEastNeighborPos,
        getBottomNeighborPos,
        getTopNeighborPos,
        getNorthNeighborPos,
        getSouthNeighborPos,
    };

    fn inWestEdge(pos: LocalPos) bool {
        return pos.x == 0;
    }

    fn inEastEdge(pos: LocalPos) bool {
        return pos.x == Chunk.EDGE;
    }

    fn inBottomEdge(pos: LocalPos) bool {
        return pos.y == 0;
    }

    fn inTopEdge(pos: LocalPos) bool {
        return pos.y == Chunk.EDGE;
    }

    fn inNorthEdge(pos: LocalPos) bool {
        return pos.z == 0;
    }

    fn inSouthEdge(pos: LocalPos) bool {
        return pos.z == Chunk.EDGE;
    }

    pub fn getWestPos(pos: LocalPos) LocalPos {
        var new_pos = pos;
        new_pos.x -= 1;
        return new_pos;
    }

    pub fn getEastPos(pos: LocalPos) LocalPos {
        var new_pos = pos;
        new_pos.x += 1;
        return new_pos;
    }

    pub fn getBottomPos(pos: LocalPos) LocalPos {
        var new_pos = pos;
        new_pos.y -= 1;
        return new_pos;
    }

    pub fn getTopPos(pos: LocalPos) LocalPos {
        var new_pos = pos;
        new_pos.y += 1;
        return new_pos;
    }

    pub fn getNorthPos(pos: LocalPos) LocalPos {
        var new_pos = pos;
        new_pos.z -= 1;
        return new_pos;
    }

    pub fn getSouthPos(pos: LocalPos) LocalPos {
        var new_pos = pos;
        new_pos.z += 1;
        return new_pos;
    }

    pub fn getWestNeighborPos(pos: LocalPos) LocalPos {
        var new_pos = pos;
        new_pos.x = Chunk.EDGE;
        return new_pos;
    }

    pub fn getEastNeighborPos(pos: LocalPos) LocalPos {
        var new_pos = pos;
        new_pos.x = 0;
        return new_pos;
    }

    pub fn getBottomNeighborPos(pos: LocalPos) LocalPos {
        var new_pos = pos;
        new_pos.y = Chunk.EDGE;
        return new_pos;
    }

    pub fn getTopNeighborPos(pos: LocalPos) LocalPos {
        var new_pos = pos;
        new_pos.y = 0;
        return new_pos;
    }

    pub fn getNorthNeighborPos(pos: LocalPos) LocalPos {
        var new_pos = pos;
        new_pos.z = Chunk.EDGE;
        return new_pos;
    }

    pub fn getSouthNeighborPos(pos: LocalPos) LocalPos {
        var new_pos = pos;
        new_pos.z = 0;
        return new_pos;
    }
};

pub fn generate(chunk_mesh: *ChunkMesh, allocator: std.mem.Allocator, chunk: *Chunk, neighbor_chunks: *const NeighborChunks) !void {
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

                const model_indices = block.kind.getModelIndices();

                inline for (Side.values) |side| {
                    const side_idx = side.idx();

                    if (NeighborChunks.inEdge[side_idx](pos)) {
                        if (neighbor_chunks.chunks[side_idx]) |neighbor_chunk| {
                            const neighbor_pos = NeighborChunks.getNeighborPos[side_idx](pos);
                            const neighbor_block = neighbor_chunk.getBlock(neighbor_pos);

                            if (neighbor_block.kind.isNotSolid() and neighbor_block.kind != block.kind) {
                                const neighbor_light = neighbor_chunk.getLight(neighbor_pos);

                                try chunk_mesh_layer.faces[side_idx].append(allocator, .{
                                    .x = pos.x,
                                    .y = pos.y,
                                    .z = pos.z,
                                    .model_idx = model_indices.faces[side_idx],
                                    .light = neighbor_light,
                                    .indirect_light_color = if (neighbor_block.kind == .water) 1 else 0,
                                });
                            }
                        }
                    } else {
                        const neighbor_pos = NeighborChunks.getPos[side_idx](pos);
                        const neighbor_block = chunk.getBlock(neighbor_pos);

                        if (neighbor_block.kind.isNotSolid() and neighbor_block.kind != block.kind) {
                            const neighbor_light = chunk.getLight(neighbor_pos);

                            try chunk_mesh_layer.faces[side_idx].append(allocator, .{
                                .x = pos.x,
                                .y = pos.y,
                                .z = pos.z,
                                .model_idx = model_indices.faces[side_idx],
                                .light = neighbor_light,
                                .indirect_light_color = if (neighbor_block.kind == .water) 1 else 0,
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
