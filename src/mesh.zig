const std = @import("std");
const gl = @import("gl");
const print = std.debug.print;
const Chunk = @import("Chunk.zig");
const LocalPos = Chunk.LocalPos;
const Block = @import("block.zig").Block;
const main = @import("main.zig");
const SingleChunkMeshLayers = main.SingleChunkMeshLayers;

pub const LocalPosAndFaceIdx = packed struct(u32) {
    x: u5,
    y: u5,
    z: u5,
    face_idx: u17,
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

pub const NeighborChunks = struct {
    west: ?Chunk,
    east: ?Chunk,
    north: ?Chunk,
    south: ?Chunk,
};

pub const FaceIndices = packed struct {
    west: u17,
    east: u17,
    bottom: u17,
    top: u17,
    north: u17,
    south: u17,
};

pub fn generate(single_chunk_mesh_layers: *SingleChunkMeshLayers, block_to_face_indices: std.AutoHashMap(Block, FaceIndices), chunk: Chunk, neighbor_chunks: *const NeighborChunks) !void {
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

                const face_indices = block_to_face_indices.get(block) orelse std.debug.panic("Solid block {s} is missing its model", .{@tagName(block)});

                if (inWestEdge(pos)) {
                    if (neighbor_chunks.west) |neighbor_chunk| {
                        const neighbor_block = getWestNeighborBlock(neighbor_chunk, pos);

                        if (neighbor_block.isNotSolid() and neighbor_block != block) {
                            try single_chunk_mesh_faces.faces[0].append(.{ .x = pos.x, .y = pos.y, .z = pos.z, .face_idx = face_indices.west });
                        }
                    }
                } else {
                    const neighbor_block = getWestBlock(chunk, pos);

                    if (neighbor_block.isNotSolid() and neighbor_block != block) {
                        try single_chunk_mesh_faces.faces[0].append(.{ .x = pos.x, .y = pos.y, .z = pos.z, .face_idx = face_indices.west });
                    }
                }

                if (inEastEdge(pos)) {
                    if (neighbor_chunks.east) |neighbor_chunk| {
                        const neighbor_block = getEastNeighborBlock(neighbor_chunk, pos);

                        if (neighbor_block.isNotSolid() and neighbor_block != block) {
                            try single_chunk_mesh_faces.faces[1].append(.{ .x = pos.x, .y = pos.y, .z = pos.z, .face_idx = face_indices.east });
                        }
                    }
                } else {
                    const neighbor_block = getEastBlock(chunk, pos);

                    if (neighbor_block.isNotSolid() and neighbor_block != block) {
                        try single_chunk_mesh_faces.faces[1].append(.{ .x = pos.x, .y = pos.y, .z = pos.z, .face_idx = face_indices.east });
                    }
                }

                if (inBottomEdge(pos)) {
                    // :ditto:
                } else {
                    const neighbor_block = getBottomBlock(chunk, pos);

                    if (neighbor_block.isNotSolid() and neighbor_block != block) {
                        try single_chunk_mesh_faces.faces[2].append(.{ .x = pos.x, .y = pos.y, .z = pos.z, .face_idx = face_indices.bottom });
                    }
                }

                if (inTopEdge(pos)) {
                    // :ditto:
                } else {
                    const neighbor_block = getTopBlock(chunk, pos);

                    if (neighbor_block.isNotSolid() and neighbor_block != block) {
                        try single_chunk_mesh_faces.faces[3].append(.{ .x = pos.x, .y = pos.y, .z = pos.z, .face_idx = face_indices.top });
                    }
                }

                if (inNorthEdge(pos)) {
                    if (neighbor_chunks.north) |neighbor_chunk| {
                        const neighbor_block = getNorthNeighborBlock(neighbor_chunk, pos);

                        if (neighbor_block.isNotSolid() and neighbor_block != block) {
                            try single_chunk_mesh_faces.faces[4].append(.{ .x = pos.x, .y = pos.y, .z = pos.z, .face_idx = face_indices.north });
                        }
                    }
                } else {
                    const neighbor_block = getNorthBlock(chunk, pos);

                    if (neighbor_block.isNotSolid() and neighbor_block != block) {
                        try single_chunk_mesh_faces.faces[4].append(.{ .x = pos.x, .y = pos.y, .z = pos.z, .face_idx = face_indices.north });
                    }
                }

                if (inSouthEdge(pos)) {
                    if (neighbor_chunks.south) |neighbor_chunk| {
                        const neighbor_block = getSouthNeighborBlock(neighbor_chunk, pos);

                        if (neighbor_block.isNotSolid() and neighbor_block != block) {
                            try single_chunk_mesh_faces.faces[5].append(.{ .x = pos.x, .y = pos.y, .z = pos.z, .face_idx = face_indices.south });
                        }
                    }
                } else {
                    const neighbor_block = getSouthBlock(chunk, pos);

                    if (neighbor_block.isNotSolid() and neighbor_block != block) {
                        try single_chunk_mesh_faces.faces[5].append(.{ .x = pos.x, .y = pos.y, .z = pos.z, .face_idx = face_indices.south });
                    }
                }
            }
        }
    }
}
