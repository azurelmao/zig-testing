const std = @import("std");
const gl = @import("gl");
const Chunk = @import("Chunk.zig");
const LocalPos = Chunk.LocalPos;
const Light = Chunk.Light;
const Block = @import("block.zig").Block;

const SingleChunkMeshLayers = @This();

layers: [Block.Layer.len]SingleChunkMeshFaces,

const SingleChunkMeshFaces = struct {
    faces: [6]std.ArrayList(BlockVertex),

    pub fn new(allocator: std.mem.Allocator) SingleChunkMeshFaces {
        var faces: [6]std.ArrayList(BlockVertex) = undefined;

        for (0..6) |face_idx| {
            faces[face_idx] = std.ArrayList(BlockVertex).init(allocator);
        }

        return .{ .faces = faces };
    }
};

pub const BlockVertex = packed struct(u64) {
    x: u5,
    y: u5,
    z: u5,
    model_idx: u17,
    light: Chunk.Light,
    _: u16 = 0,
};

pub fn new(allocator: std.mem.Allocator) SingleChunkMeshLayers {
    var layers: [Block.Layer.len]SingleChunkMeshFaces = undefined;

    inline for (0..Block.Layer.len) |layer_idx| {
        layers[layer_idx] = SingleChunkMeshFaces.new(allocator);
    }

    return .{ .layers = layers };
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
        return pos.x == Chunk.Edge;
    }

    fn inBottomEdge(pos: LocalPos) bool {
        return pos.y == 0;
    }

    fn inTopEdge(pos: LocalPos) bool {
        return pos.y == Chunk.Edge;
    }

    fn inNorthEdge(pos: LocalPos) bool {
        return pos.z == 0;
    }

    fn inSouthEdge(pos: LocalPos) bool {
        return pos.z == Chunk.Edge;
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
        new_pos.x = Chunk.Edge;
        return new_pos;
    }

    pub fn getEastNeighborPos(pos: LocalPos) LocalPos {
        var new_pos = pos;
        new_pos.x = 0;
        return new_pos;
    }

    pub fn getBottomNeighborPos(pos: LocalPos) LocalPos {
        var new_pos = pos;
        new_pos.y = Chunk.Edge;
        return new_pos;
    }

    pub fn getTopNeighborPos(pos: LocalPos) LocalPos {
        var new_pos = pos;
        new_pos.y = 0;
        return new_pos;
    }

    pub fn getNorthNeighborPos(pos: LocalPos) LocalPos {
        var new_pos = pos;
        new_pos.z = Chunk.Edge;
        return new_pos;
    }

    pub fn getSouthNeighborPos(pos: LocalPos) LocalPos {
        var new_pos = pos;
        new_pos.z = 0;
        return new_pos;
    }
};

pub fn generate(single_chunk_mesh_layers: *SingleChunkMeshLayers, chunk: *Chunk, neighbor_chunks: *const NeighborChunks) !void {
    var single_chunk_mesh_faces: *SingleChunkMeshFaces = undefined;

    for (0..Chunk.Size) |x| {
        for (0..Chunk.Size) |y| {
            for (0..Chunk.Size) |z| {
                const pos = LocalPos{ .x = @intCast(x), .y = @intCast(y), .z = @intCast(z) };
                const block = chunk.getBlock(pos);

                if (block == .air) {
                    continue;
                }

                single_chunk_mesh_faces = &single_chunk_mesh_layers.layers[block.getLayer().idx()];

                const model_indices = block.getModelIndices();

                inline for (0..6) |face_idx| {
                    if (NeighborChunks.inEdge[face_idx](pos)) {
                        if (neighbor_chunks.chunks[face_idx]) |neighbor_chunk| {
                            const neighbor_pos = NeighborChunks.getNeighborPos[face_idx](pos);
                            const neighbor_block = neighbor_chunk.getBlock(neighbor_pos);
                            const neighbor_light = neighbor_chunk.getLight(neighbor_pos);

                            if (neighbor_block.isNotSolid() and neighbor_block != block) {
                                try single_chunk_mesh_faces.faces[face_idx].append(.{
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

                        if (neighbor_block.isNotSolid() and neighbor_block != block) {
                            try single_chunk_mesh_faces.faces[face_idx].append(.{
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
