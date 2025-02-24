const std = @import("std");
const gl = @import("gl");
const print = std.debug.print;
const Chunk = @import("Chunk.zig");
const LocalPos = Chunk.LocalPos;
const Light = Chunk.Light;
const Block = @import("block.zig").Block;

const Self = @This();

layers: [2]SingleChunkMeshFaces,

const SingleChunkMeshFaces = struct {
    faces: [6]std.ArrayList(LocalPosAndModelIdx),

    pub fn new(allocator: std.mem.Allocator) SingleChunkMeshFaces {
        var faces: [6]std.ArrayList(LocalPosAndModelIdx) = undefined;

        for (0..6) |face_idx| {
            faces[face_idx] = std.ArrayList(LocalPosAndModelIdx).init(allocator);
        }

        return .{ .faces = faces };
    }
};

pub const LocalPosAndModelIdx = packed struct(u64) {
    x: u5,
    y: u5,
    z: u5,
    model_idx: u17,
    light: Chunk.Light,
    _: u16 = 0,
};

pub fn new(allocator: std.mem.Allocator) Self {
    var layers: [2]SingleChunkMeshFaces = undefined;

    for (0..2) |layer_idx| {
        layers[layer_idx] = SingleChunkMeshFaces.new(allocator);
    }

    return .{ .layers = layers };
}

pub const NeighborChunks = struct {
    west: ?Chunk,
    east: ?Chunk,
    north: ?Chunk,
    south: ?Chunk,
};

pub fn generate(single_chunk_mesh_layers: *Self, chunk: Chunk, neighbor_chunks: *const NeighborChunks) !void {
    var single_chunk_mesh_faces = &single_chunk_mesh_layers.layers[0];

    for (0..Chunk.Size) |x| {
        for (0..Chunk.Size) |y| {
            for (0..Chunk.Size) |z| {
                const pos = LocalPos{ .x = @intCast(x), .y = @intCast(y), .z = @intCast(z) };
                const block = chunk.getBlock(pos);

                if (block == .air) {
                    continue;
                }

                if (block == .water) {
                    single_chunk_mesh_faces = &single_chunk_mesh_layers.layers[1];
                } else {
                    single_chunk_mesh_faces = &single_chunk_mesh_layers.layers[0];
                }

                const model_indices = Block.BLOCK_TO_MODEL_INDICES[@intFromEnum(block)];

                if (inWestEdge(pos)) {
                    if (neighbor_chunks.west) |neighbor_chunk| {
                        const neighbor_block = getWestNeighborBlock(neighbor_chunk, pos);
                        const neighbor_light = getWestNeighborLight(neighbor_chunk, pos);

                        if (neighbor_block.isNotSolid() and neighbor_block != block) {
                            try single_chunk_mesh_faces.faces[0].append(.{
                                .x = pos.x,
                                .y = pos.y,
                                .z = pos.z,
                                .model_idx = model_indices.faces[0],
                                .light = neighbor_light,
                            });
                        }
                    }
                } else {
                    const neighbor_block = getWestBlock(chunk, pos);
                    const neighbor_light = getWestLight(chunk, pos);

                    if (neighbor_block.isNotSolid() and neighbor_block != block) {
                        try single_chunk_mesh_faces.faces[0].append(.{
                            .x = pos.x,
                            .y = pos.y,
                            .z = pos.z,
                            .model_idx = model_indices.faces[0],
                            .light = neighbor_light,
                        });
                    }
                }

                if (inEastEdge(pos)) {
                    if (neighbor_chunks.east) |neighbor_chunk| {
                        const neighbor_block = getEastNeighborBlock(neighbor_chunk, pos);
                        const neighbor_light = getEastNeighborLight(neighbor_chunk, pos);

                        if (neighbor_block.isNotSolid() and neighbor_block != block) {
                            try single_chunk_mesh_faces.faces[1].append(.{
                                .x = pos.x,
                                .y = pos.y,
                                .z = pos.z,
                                .model_idx = model_indices.faces[1],
                                .light = neighbor_light,
                            });
                        }
                    }
                } else {
                    const neighbor_block = getEastBlock(chunk, pos);
                    const neighbor_light = getEastLight(chunk, pos);

                    if (neighbor_block.isNotSolid() and neighbor_block != block) {
                        try single_chunk_mesh_faces.faces[1].append(.{
                            .x = pos.x,
                            .y = pos.y,
                            .z = pos.z,
                            .model_idx = model_indices.faces[1],
                            .light = neighbor_light,
                        });
                    }
                }

                if (inBottomEdge(pos)) {
                    // :ditto:
                } else {
                    const neighbor_block = getBottomBlock(chunk, pos);
                    const neighbor_light = getBottomLight(chunk, pos);

                    if (neighbor_block.isNotSolid() and neighbor_block != block) {
                        try single_chunk_mesh_faces.faces[2].append(.{
                            .x = pos.x,
                            .y = pos.y,
                            .z = pos.z,
                            .model_idx = model_indices.faces[2],
                            .light = neighbor_light,
                        });
                    }
                }

                if (inTopEdge(pos)) {
                    // :ditto:
                } else {
                    const neighbor_block = getTopBlock(chunk, pos);
                    const neighbor_light = getTopLight(chunk, pos);

                    if (neighbor_block.isNotSolid() and neighbor_block != block) {
                        try single_chunk_mesh_faces.faces[3].append(.{
                            .x = pos.x,
                            .y = pos.y,
                            .z = pos.z,
                            .model_idx = model_indices.faces[3],
                            .light = neighbor_light,
                        });
                    }
                }

                if (inNorthEdge(pos)) {
                    if (neighbor_chunks.north) |neighbor_chunk| {
                        const neighbor_block = getNorthNeighborBlock(neighbor_chunk, pos);
                        const neighbor_light = getNorthNeighborLight(neighbor_chunk, pos);

                        if (neighbor_block.isNotSolid() and neighbor_block != block) {
                            try single_chunk_mesh_faces.faces[4].append(.{
                                .x = pos.x,
                                .y = pos.y,
                                .z = pos.z,
                                .model_idx = model_indices.faces[4],
                                .light = neighbor_light,
                            });
                        }
                    }
                } else {
                    const neighbor_block = getNorthBlock(chunk, pos);
                    const neighbor_light = getNorthLight(chunk, pos);

                    if (neighbor_block.isNotSolid() and neighbor_block != block) {
                        try single_chunk_mesh_faces.faces[4].append(.{
                            .x = pos.x,
                            .y = pos.y,
                            .z = pos.z,
                            .model_idx = model_indices.faces[4],
                            .light = neighbor_light,
                        });
                    }
                }

                if (inSouthEdge(pos)) {
                    if (neighbor_chunks.south) |neighbor_chunk| {
                        const neighbor_block = getSouthNeighborBlock(neighbor_chunk, pos);
                        const neighbor_light = getSouthNeighborLight(neighbor_chunk, pos);

                        if (neighbor_block.isNotSolid() and neighbor_block != block) {
                            try single_chunk_mesh_faces.faces[5].append(.{
                                .x = pos.x,
                                .y = pos.y,
                                .z = pos.z,
                                .model_idx = model_indices.faces[5],
                                .light = neighbor_light,
                            });
                        }
                    }
                } else {
                    const neighbor_block = getSouthBlock(chunk, pos);
                    const neighbor_light = getSouthLight(chunk, pos);

                    if (neighbor_block.isNotSolid() and neighbor_block != block) {
                        try single_chunk_mesh_faces.faces[5].append(.{
                            .x = pos.x,
                            .y = pos.y,
                            .z = pos.z,
                            .model_idx = model_indices.faces[5],
                            .light = neighbor_light,
                        });
                    }
                }
            }
        }
    }
}

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

fn getWestBlock(chunk: Chunk, pos: LocalPos) Block {
    const offset_pos = LocalPos{ .x = pos.x - 1, .y = pos.y, .z = pos.z };
    return chunk.getBlock(offset_pos);
}

fn getEastBlock(chunk: Chunk, pos: LocalPos) Block {
    const offset_pos = LocalPos{ .x = pos.x + 1, .y = pos.y, .z = pos.z };
    return chunk.getBlock(offset_pos);
}

fn getBottomBlock(chunk: Chunk, pos: LocalPos) Block {
    const offset_pos = LocalPos{ .x = pos.x, .y = pos.y - 1, .z = pos.z };
    return chunk.getBlock(offset_pos);
}

fn getTopBlock(chunk: Chunk, pos: LocalPos) Block {
    const offset_pos = LocalPos{ .x = pos.x, .y = pos.y + 1, .z = pos.z };
    return chunk.getBlock(offset_pos);
}

fn getNorthBlock(chunk: Chunk, pos: LocalPos) Block {
    const offset_pos = LocalPos{ .x = pos.x, .y = pos.y, .z = pos.z - 1 };
    return chunk.getBlock(offset_pos);
}

fn getSouthBlock(chunk: Chunk, pos: LocalPos) Block {
    const offset_pos = LocalPos{ .x = pos.x, .y = pos.y, .z = pos.z + 1 };
    return chunk.getBlock(offset_pos);
}

fn getWestNeighborBlock(neighbor_chunk: Chunk, pos: LocalPos) Block {
    const offset_pos = LocalPos{ .x = Chunk.Edge, .y = pos.y, .z = pos.z };
    return neighbor_chunk.getBlock(offset_pos);
}

fn getEastNeighborBlock(neighbor_chunk: Chunk, pos: LocalPos) Block {
    const offset_pos = LocalPos{ .x = 0, .y = pos.y, .z = pos.z };
    return neighbor_chunk.getBlock(offset_pos);
}

fn getNorthNeighborBlock(neighbor_chunk: Chunk, pos: LocalPos) Block {
    const offset_pos = LocalPos{ .x = pos.x, .y = pos.y, .z = Chunk.Edge };
    return neighbor_chunk.getBlock(offset_pos);
}

fn getSouthNeighborBlock(neighbor_chunk: Chunk, pos: LocalPos) Block {
    const offset_pos = LocalPos{ .x = pos.x, .y = pos.y, .z = 0 };
    return neighbor_chunk.getBlock(offset_pos);
}

fn getWestLight(chunk: Chunk, pos: LocalPos) Light {
    const offset_pos = LocalPos{ .x = pos.x - 1, .y = pos.y, .z = pos.z };
    return chunk.getLight(offset_pos);
}

fn getEastLight(chunk: Chunk, pos: LocalPos) Light {
    const offset_pos = LocalPos{ .x = pos.x + 1, .y = pos.y, .z = pos.z };
    return chunk.getLight(offset_pos);
}

fn getBottomLight(chunk: Chunk, pos: LocalPos) Light {
    const offset_pos = LocalPos{ .x = pos.x, .y = pos.y - 1, .z = pos.z };
    return chunk.getLight(offset_pos);
}

fn getTopLight(chunk: Chunk, pos: LocalPos) Light {
    const offset_pos = LocalPos{ .x = pos.x, .y = pos.y + 1, .z = pos.z };
    return chunk.getLight(offset_pos);
}

fn getNorthLight(chunk: Chunk, pos: LocalPos) Light {
    const offset_pos = LocalPos{ .x = pos.x, .y = pos.y, .z = pos.z - 1 };
    return chunk.getLight(offset_pos);
}

fn getSouthLight(chunk: Chunk, pos: LocalPos) Light {
    const offset_pos = LocalPos{ .x = pos.x, .y = pos.y, .z = pos.z + 1 };
    return chunk.getLight(offset_pos);
}

fn getWestNeighborLight(neighbor_chunk: Chunk, pos: LocalPos) Light {
    const offset_pos = LocalPos{ .x = Chunk.Edge, .y = pos.y, .z = pos.z };
    return neighbor_chunk.getLight(offset_pos);
}

fn getEastNeighborLight(neighbor_chunk: Chunk, pos: LocalPos) Light {
    const offset_pos = LocalPos{ .x = 0, .y = pos.y, .z = pos.z };
    return neighbor_chunk.getLight(offset_pos);
}

fn getNorthNeighborLight(neighbor_chunk: Chunk, pos: LocalPos) Light {
    const offset_pos = LocalPos{ .x = pos.x, .y = pos.y, .z = Chunk.Edge };
    return neighbor_chunk.getLight(offset_pos);
}

fn getSouthNeighborLight(neighbor_chunk: Chunk, pos: LocalPos) Light {
    const offset_pos = LocalPos{ .x = pos.x, .y = pos.y, .z = 0 };
    return neighbor_chunk.getLight(offset_pos);
}
