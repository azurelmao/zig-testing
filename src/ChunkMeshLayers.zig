const std = @import("std");
const gl = @import("gl");
const Block = @import("block.zig").Block;
const Chunk = @import("Chunk.zig");
const World = @import("World.zig");
const Vec3f = @import("vec3f.zig").Vec3f;
const ShaderStorageBuffer = @import("buffer.zig").ShaderStorageBuffer;
const SingleChunkMeshLayers = @import("SingleChunkMeshLayers.zig");

const ChunkMeshLayers = @This();

layers: [Block.Layer.len]ChunkMeshBuffers,
pos: ShaderStorageBuffer(Vec3f),

pub const ChunkMeshBuffers = struct {
    len: std.ArrayListUnmanaged(usize),
    mesh: ShaderStorageBuffer(SingleChunkMeshLayers.LocalPosAndModelIdx),
    command: ShaderStorageBuffer(DrawArraysIndirectCommand),

    pub fn init() ChunkMeshBuffers {
        return .{
            .len = .empty,
            .mesh = .init(gl.DYNAMIC_STORAGE_BIT),
            .command = .init(gl.DYNAMIC_STORAGE_BIT | gl.MAP_READ_BIT | gl.MAP_WRITE_BIT),
        };
    }
};

const DrawArraysIndirectCommand = packed struct {
    count: gl.uint,
    instance_count: gl.uint,
    first_vertex: gl.uint,
    base_instance: gl.uint,
};

pub fn init() ChunkMeshLayers {
    var layers: [Block.Layer.len]ChunkMeshBuffers = undefined;

    inline for (0..Block.Layer.len) |i| {
        layers[i] = .init();
    }

    return .{
        .layers = layers,
        .pos = .init(gl.DYNAMIC_STORAGE_BIT),
    };
}

pub fn uploadCommandBuffers(self: *ChunkMeshLayers) void {
    inline for (0..Block.Layer.len) |layer_idx| {
        const chunk_mesh_layer = &self.layers[layer_idx];
        chunk_mesh_layer.command.uploadBuffer();
    }
}

pub fn draw(self: *ChunkMeshLayers) void {
    inline for (0..Block.Layer.len) |layer_idx| {
        const chunk_mesh_layer = &self.layers[layer_idx];

        if (chunk_mesh_layer.mesh.buffer.items.len > 0) {
            chunk_mesh_layer.mesh.bindBuffer(3);
            gl.BindBuffer(gl.DRAW_INDIRECT_BUFFER, chunk_mesh_layer.command.unmanaged.handle);

            gl.MemoryBarrier(gl.SHADER_STORAGE_BARRIER_BIT);
            gl.MultiDrawArraysIndirect(gl.TRIANGLES, null, @intCast(chunk_mesh_layer.command.buffer.items.len), 0);
            gl.MemoryBarrier(gl.SHADER_STORAGE_BARRIER_BIT);
        }
    }
}

pub fn generate(self: *ChunkMeshLayers, allocator: std.mem.Allocator, world: *World) !void {
    var single_chunk_mesh_layers = SingleChunkMeshLayers.new(allocator);

    var chunk_iter = world.chunks.valueIterator();
    while (chunk_iter.next()) |chunk| {
        const chunk_pos = chunk.pos;

        const neighbor_chunks: SingleChunkMeshLayers.NeighborChunks = expr: {
            var chunks: [6]?*Chunk = undefined;

            for (0..6) |face_idx| {
                chunks[face_idx] = world.getChunkOrNull(chunk_pos.add(Chunk.Pos.Offsets[face_idx]));
            }

            break :expr .{ .chunks = chunks };
        };

        try self.pos.buffer.append(allocator, chunk_pos.toVec3f());

        if (chunk.num_of_air != 0 and chunk.num_of_air != Chunk.Volume) {
            try single_chunk_mesh_layers.generate(chunk, &neighbor_chunks);

            inline for (0..Block.Layer.len) |layer_idx| {
                const chunk_mesh_layer = &self.layers[layer_idx];
                const single_chunk_mesh_layer = &single_chunk_mesh_layers.layers[layer_idx];

                inline for (0..6) |face_idx| {
                    const single_chunk_mesh_face = &single_chunk_mesh_layer.faces[face_idx];
                    const len: gl.uint = @intCast(single_chunk_mesh_face.items.len);

                    try chunk_mesh_layer.len.append(allocator, len);

                    const command = DrawArraysIndirectCommand{
                        .first_vertex = @intCast(chunk_mesh_layer.mesh.buffer.items.len * 6),
                        .count = @intCast(len * 6),
                        .instance_count = if (len > 0) 1 else 0,
                        .base_instance = 0,
                    };

                    try chunk_mesh_layer.command.buffer.append(allocator, command);
                    try chunk_mesh_layer.mesh.buffer.appendSlice(allocator, single_chunk_mesh_face.items);
                    single_chunk_mesh_face.clearRetainingCapacity();
                }
            }
        } else {
            inline for (0..Block.Layer.len) |layer_idx| {
                const chunk_mesh_layer = &self.layers[layer_idx];

                try chunk_mesh_layer.len.appendNTimes(allocator, 0, 6);

                inline for (0..6) |_| {
                    const command = DrawArraysIndirectCommand{
                        .first_vertex = @intCast(chunk_mesh_layer.mesh.buffer.items.len * 6),
                        .count = 0,
                        .instance_count = 0,
                        .base_instance = 0,
                    };

                    try chunk_mesh_layer.command.buffer.append(allocator, command);
                }
            }
        }
    }
}
