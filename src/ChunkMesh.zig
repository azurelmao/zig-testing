const std = @import("std");
const gl = @import("gl");
const Vec3f = @import("vec3f.zig").Vec3f;
const Chunk = @import("Chunk.zig");
const LocalPos = Chunk.LocalPos;
const Light = @import("light.zig").Light;
const BlockLayer = @import("block.zig").BlockLayer;

const ChunkMesh = @This();

layers: [BlockLayer.len]ChunkMeshLayer,

const ChunkMeshLayer = struct {
    faces: [6]std.ArrayList(Vertex),

    pub fn init(allocator: std.mem.Allocator) ChunkMeshLayer {
        var faces: [6]std.ArrayList(Vertex) = undefined;

        for (0..6) |face_idx| {
            faces[face_idx] = .init(allocator);
        }

        return .{ .faces = faces };
    }
};

pub const Vertex = packed struct(u64) {
    x: u5,
    y: u5,
    z: u5,
    model_idx: u17,
    light: Light,
    _: u16 = 0,
};

pub fn init(allocator: std.mem.Allocator) ChunkMesh {
    var layers: [BlockLayer.len]ChunkMeshLayer = undefined;

    inline for (0..BlockLayer.len) |layer_idx| {
        layers[layer_idx] = .init(allocator);
    }

    return .{ .layers = layers };
}

pub const NeighborChunks = struct {
    chunks: [6]?*Chunk,

    const inEDGE = .{
        inWestEDGE,
        inEastEDGE,
        inBottomEDGE,
        inTopEDGE,
        inNorthEDGE,
        inSouthEDGE,
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

    fn inWestEDGE(pos: LocalPos) bool {
        return pos.x == 0;
    }

    fn inEastEDGE(pos: LocalPos) bool {
        return pos.x == Chunk.EDGE;
    }

    fn inBottomEDGE(pos: LocalPos) bool {
        return pos.y == 0;
    }

    fn inTopEDGE(pos: LocalPos) bool {
        return pos.y == Chunk.EDGE;
    }

    fn inNorthEDGE(pos: LocalPos) bool {
        return pos.z == 0;
    }

    fn inSouthEDGE(pos: LocalPos) bool {
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

pub fn generate(chunk_mesh: *ChunkMesh, chunk: *Chunk, neighbor_chunks: *const NeighborChunks) !void {
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

                inline for (0..6) |face_idx| {
                    if (NeighborChunks.inEDGE[face_idx](pos)) {
                        if (neighbor_chunks.chunks[face_idx]) |neighbor_chunk| {
                            const neighbor_pos = NeighborChunks.getNeighborPos[face_idx](pos);
                            const neighbor_block = neighbor_chunk.getBlock(neighbor_pos);
                            const neighbor_light = neighbor_chunk.getLight(neighbor_pos);

                            if (neighbor_block.kind.isNotSolid() and neighbor_block.kind != block.kind) {
                                try chunk_mesh_layer.faces[face_idx].append(.{
                                    .x = pos.x,
                                    .y = pos.y,
                                    .z = pos.z,
                                    .model_idx = model_indices.faces[face_idx],
                                    .light = neighbor_light,
                                });
                            }
                        }
                    } else {
                        const neighbor_pos = NeighborChunks.getPos[face_idx](pos);
                        const neighbor_block = chunk.getBlock(neighbor_pos);
                        const neighbor_light = chunk.getLight(neighbor_pos);

                        if (neighbor_block.kind.isNotSolid() and neighbor_block.kind != block.kind) {
                            try chunk_mesh_layer.faces[face_idx].append(.{
                                .x = pos.x,
                                .y = pos.y,
                                .z = pos.z,
                                .model_idx = model_indices.faces[face_idx],
                                .light = neighbor_light,
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
