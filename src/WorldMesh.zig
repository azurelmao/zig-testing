const std = @import("std");
const gl = @import("gl");
const vma = @import("vma.zig");
const BlockLayer = @import("block.zig").BlockLayer;
const Chunk = @import("Chunk.zig");
const World = @import("World.zig");
const Vec3f = @import("vec3f.zig").Vec3f;
const Camera = @import("Camera.zig");
const ShaderStorageBufferWithArrayList = @import("shader_storage_buffer.zig").ShaderStorageBufferWithArrayList;
const ChunkMesh = @import("ChunkMesh.zig");
const ChunkMeshLayer = ChunkMesh.ChunkMeshLayer;

const WorldMesh = @This();

layers: [BlockLayer.len]WorldMeshLayer,
pos: ShaderStorageBufferWithArrayList(Vec3f),

pub fn init() WorldMesh {
    var layers: [BlockLayer.len]WorldMeshLayer = undefined;

    inline for (0..BlockLayer.len) |i| {
        layers[i] = .init();
    }

    return .{
        .layers = layers,
        .pos = .initAndBind(2, World.VOLUME, gl.DYNAMIC_STORAGE_BIT),
    };
}

const WorldMeshLayer = struct {
    virtual_block_size: usize,
    virtual_block: vma.VirtualBlock,
    chunk_pos_to_virtual_alloc: std.AutoHashMapUnmanaged(Chunk.Pos, vma.VirtualAllocation),
    mesh: ShaderStorageBufferWithArrayList(ChunkMesh.Vertex),
    command: ShaderStorageBufferWithArrayList(DrawArraysIndirectCommand),

    const INITIAL_MESH_SIZE = World.VOLUME * 1000;

    pub fn init() !WorldMeshLayer {
        return .{
            .virtual_block_size = INITIAL_MESH_SIZE,
            .virtual_block = try .init(.{ .size = INITIAL_MESH_SIZE }),
            .chunk_pos_to_virtual_alloc = .empty,
            .mesh = .init(INITIAL_MESH_SIZE, gl.DYNAMIC_STORAGE_BIT),
            .command = .init(World.VOLUME, gl.DYNAMIC_STORAGE_BIT | gl.MAP_READ_BIT | gl.MAP_WRITE_BIT),
        };
    }

    pub fn suballoc(self: *WorldMeshLayer, allocator: std.mem.Allocator, chunk_mesh_layer: *ChunkMeshLayer) !void {
        var total_allocation_size: usize = 0;
        for (chunk_mesh_layer.faces) |*chunk_mesh_face| {
            total_allocation_size += chunk_mesh_face.items.len;
        }

        const allocation = self.virtual_block.alloc(.{ .size = @intCast(total_allocation_size) }) catch self.resizeMesh(allocator, total_allocation_size);

        self.chunk_pos_to_virtual_alloc.append(allocator, allocation);

        for (chunk_mesh_layer.faces) |*chunk_mesh_face| {
            const chunk_mesh_face_len = chunk_mesh_face.items.len;

            const command: DrawArraysIndirectCommand = .{
                .first_vertex = @intCast(self.mesh.data.items.len * 6),
                .count = @intCast(chunk_mesh_face_len * 6),
                .instance_count = if (chunk_mesh_face_len > 0) 1 else 0,
                .base_instance = if (chunk_mesh_face_len > 0) 1 else 0,
            };

            try self.mesh.data.appendSlice(allocator, chunk_mesh_face.items);

            self.command.data.append(allocator, command);
        }
    }

    pub fn resizeMesh(self: *WorldMeshLayer, allocator: std.mem.Allocator, total_allocation_size: usize) void {
        const new_block_size = self.virtual_block_size + total_allocation_size * 5;
        const new_block: vma.VirtualBlock = .init(.{ .size = new_block_size });
        const new_mesh_data = try allocator.alloc(ChunkMesh.Vertex, new_block_size);

        var new_offset: usize = 0;
        var iter = self.chunk_pos_to_virtual_alloc.valueIterator();
        for (iter.next()) |virtual_allocation| {
            const old_allocation_info = self.virtual_block.allocInfo(virtual_allocation);

            const old_offset = old_allocation_info.offset;
            const old_end = old_offset + old_allocation_info.size;

            const new_end = new_offset + old_allocation_info.size;
            @memcpy(new_mesh_data[new_offset..new_end], self.mesh.data.items[old_offset..old_end]);

            new_block.alloc(.{ .size = old_allocation_info.size });

            new_offset = new_end;
        }

        self.mesh.data.deinit(allocator);
        self.mesh.data = .fromOwnedSlice(new_mesh_data);
        self.virtual_block_size = new_block_size;
        self.virtual_block = new_block;
    }

    pub fn free(self: *WorldMeshLayer, chunk_pos: Chunk.Pos) !void {
        self.virtual_block.free(self.chunk_pos_to_virtual_alloc.get(chunk_pos));
        self.chunk_pos_to_virtual_alloc.remove(chunk_pos);
    }
};

const DrawArraysIndirectCommand = extern struct {
    count: gl.uint,
    instance_count: gl.uint,
    first_vertex: gl.uint,
    base_instance: gl.uint,
};

pub fn uploadCommandBuffers(self: *WorldMesh) void {
    inline for (0..BlockLayer.len) |layer_idx| {
        const world_mesh_layer = &self.layers[layer_idx];
        world_mesh_layer.command.uploadAndOrResize();
    }
}

pub fn clearCommandBuffers(self: *WorldMesh) void {
    for (0..self.pos.data.items.len) |chunk_mesh_idx_| {
        const chunk_mesh_idx = chunk_mesh_idx_ * 6;

        inline for (0..BlockLayer.len) |layer_idx| {
            const world_mesh_layer = &self.layers[layer_idx];

            inline for (0..6) |face_idx| {
                world_mesh_layer.command.data.items[chunk_mesh_idx + face_idx].instance_count = 0;
            }
        }
    }
}

pub fn resetCommandBuffers(self: *WorldMesh) void {
    for (0..self.pos.data.items.len) |chunk_mesh_idx_| {
        const chunk_mesh_idx = chunk_mesh_idx_ * 6;

        inline for (0..BlockLayer.len) |layer_idx| {
            const world_mesh_layer = &self.layers[layer_idx];

            inline for (0..6) |face_idx| {
                world_mesh_layer.command.data.items[chunk_mesh_idx + face_idx].instance_count = if (world_mesh_layer.len.items[chunk_mesh_idx + face_idx] > 0) 1 else 0;
            }
        }
    }
}

pub fn generate(self: *WorldMesh, allocator: std.mem.Allocator, world: *World) !void {
    var chunk_mesh = ChunkMesh.init(allocator);

    var chunk_iter = world.chunks.valueIterator();
    while (chunk_iter.next()) |chunk| {
        const chunk_pos = chunk.pos;
        const neighbor_chunks = world.getNeighborChunks(chunk_pos);

        try self.pos.data.append(allocator, chunk_pos.toVec3f());

        if (chunk.num_of_air != Chunk.VOLUME) {
            try chunk_mesh.generate(allocator, chunk, &neighbor_chunks);

            for (self.layers, chunk_mesh.layers) |*world_mesh_layer, *chunk_mesh_layer| {
                try world_mesh_layer.suballoc(allocator, chunk_mesh_layer);

                for (chunk_mesh_layer.faces) |*chunk_mesh_face| {
                    chunk_mesh_face.clearRetainingCapacity();
                }
            }
        }
    }
}

pub fn cull(self: *WorldMesh, camera: *const Camera) u32 {
    const left_nrm = Vec3f.new(camera.plane_left[0], camera.plane_left[1], camera.plane_left[2]).normalize();
    const right_nrm = Vec3f.new(camera.plane_right[0], camera.plane_right[1], camera.plane_right[2]).normalize();
    const bottom_nrm = Vec3f.new(camera.plane_bottom[0], camera.plane_bottom[1], camera.plane_bottom[2]).normalize();
    const top_nrm = Vec3f.new(camera.plane_top[0], camera.plane_top[1], camera.plane_top[2]).normalize();

    const camera_chunk_pos = camera.position.toChunkPos();

    var visible_num: u32 = 0;
    for (self.pos.data.items, 0..) |chunk_mesh_pos, chunk_mesh_idx_| {
        const chunk_pos = chunk_mesh_pos.toChunkPos();
        const chunk_mesh_idx = chunk_mesh_idx_ * 6;

        if (chunk_pos.equal(camera_chunk_pos)) {
            inline for (0..BlockLayer.len) |layer_idx| {
                const world_mesh_layer = &self.layers[layer_idx];

                inline for (0..6) |face_idx| {
                    if (world_mesh_layer.len.items[chunk_mesh_idx + face_idx] > 0) {
                        world_mesh_layer.command.data.items[chunk_mesh_idx + face_idx].instance_count = 1;
                        world_mesh_layer.command.data.items[chunk_mesh_idx + face_idx].base_instance = 1;
                        visible_num += 6;
                    }
                }
            }

            continue;
        }

        const point = chunk_mesh_pos.addScalar(Chunk.CENTER).subtract(camera.position);
        if ((point.dot(camera.direction) < -Chunk.RADIUS) or
            (point.dot(left_nrm) < -Chunk.RADIUS) or
            (point.dot(right_nrm) < -Chunk.RADIUS) or
            (point.dot(bottom_nrm) < -Chunk.RADIUS) or
            (point.dot(top_nrm) < -Chunk.RADIUS) or
            (point.dot(camera.direction.negate()) < -(camera.far + Chunk.RADIUS)))
        {
            inline for (0..BlockLayer.len) |layer_idx| {
                const world_mesh_layer = &self.layers[layer_idx];

                inline for (0..6) |face_idx| {
                    world_mesh_layer.command.data.items[chunk_mesh_idx + face_idx].instance_count = 0;
                    world_mesh_layer.command.data.items[chunk_mesh_idx + face_idx].base_instance = 0;
                }
            }

            continue;
        }

        const diff = camera_chunk_pos.subtract(chunk_pos);

        if (diff.x < 0) {
            inline for (0..BlockLayer.len) |layer_idx| {
                const world_mesh_layer = &self.layers[layer_idx];

                if (world_mesh_layer.len.items[chunk_mesh_idx] > 0) {
                    world_mesh_layer.command.data.items[chunk_mesh_idx].instance_count = 1;
                    world_mesh_layer.command.data.items[chunk_mesh_idx].base_instance = 1;
                    visible_num += 1;
                }

                world_mesh_layer.command.data.items[chunk_mesh_idx + 1].instance_count = 0;
                world_mesh_layer.command.data.items[chunk_mesh_idx + 1].base_instance = 0;
            }
        } else if (diff.x != 0) {
            inline for (0..BlockLayer.len) |layer_idx| {
                const world_mesh_layer = &self.layers[layer_idx];

                world_mesh_layer.command.data.items[chunk_mesh_idx].instance_count = 0;
                world_mesh_layer.command.data.items[chunk_mesh_idx].base_instance = 0;

                if (world_mesh_layer.len.items[chunk_mesh_idx + 1] > 0) {
                    world_mesh_layer.command.data.items[chunk_mesh_idx + 1].instance_count = 1;
                    world_mesh_layer.command.data.items[chunk_mesh_idx + 1].base_instance = 1;
                    visible_num += 1;
                }
            }
        } else {
            inline for (0..BlockLayer.len) |layer_idx| {
                const world_mesh_layer = &self.layers[layer_idx];

                if (world_mesh_layer.len.items[chunk_mesh_idx] > 0) {
                    world_mesh_layer.command.data.items[chunk_mesh_idx].instance_count = 1;
                    world_mesh_layer.command.data.items[chunk_mesh_idx].base_instance = 1;
                    visible_num += 1;
                }

                if (world_mesh_layer.len.items[chunk_mesh_idx + 1] > 0) {
                    world_mesh_layer.command.data.items[chunk_mesh_idx + 1].instance_count = 1;
                    world_mesh_layer.command.data.items[chunk_mesh_idx + 1].base_instance = 1;
                    visible_num += 1;
                }
            }
        }

        if (diff.y < 0) {
            inline for (0..BlockLayer.len) |layer_idx| {
                const world_mesh_layer = &self.layers[layer_idx];

                if (world_mesh_layer.len.items[chunk_mesh_idx + 2] > 0) {
                    world_mesh_layer.command.data.items[chunk_mesh_idx + 2].instance_count = 1;
                    world_mesh_layer.command.data.items[chunk_mesh_idx + 2].base_instance = 1;
                    visible_num += 1;
                }

                world_mesh_layer.command.data.items[chunk_mesh_idx + 3].instance_count = 0;
                world_mesh_layer.command.data.items[chunk_mesh_idx + 3].base_instance = 0;
            }
        } else if (diff.y != 0) {
            inline for (0..BlockLayer.len) |layer_idx| {
                const world_mesh_layer = &self.layers[layer_idx];

                world_mesh_layer.command.data.items[chunk_mesh_idx + 2].instance_count = 0;
                world_mesh_layer.command.data.items[chunk_mesh_idx + 2].base_instance = 0;

                if (world_mesh_layer.len.items[chunk_mesh_idx + 3] > 0) {
                    world_mesh_layer.command.data.items[chunk_mesh_idx + 3].instance_count = 1;
                    world_mesh_layer.command.data.items[chunk_mesh_idx + 3].base_instance = 1;
                    visible_num += 1;
                }
            }
        } else {
            inline for (0..BlockLayer.len) |layer_idx| {
                const world_mesh_layer = &self.layers[layer_idx];

                if (world_mesh_layer.len.items[chunk_mesh_idx + 2] > 0) {
                    world_mesh_layer.command.data.items[chunk_mesh_idx + 2].instance_count = 1;
                    world_mesh_layer.command.data.items[chunk_mesh_idx + 2].base_instance = 1;
                    visible_num += 1;
                }

                if (world_mesh_layer.len.items[chunk_mesh_idx + 3] > 0) {
                    world_mesh_layer.command.data.items[chunk_mesh_idx + 3].instance_count = 1;
                    world_mesh_layer.command.data.items[chunk_mesh_idx + 3].base_instance = 1;
                    visible_num += 1;
                }
            }
        }

        if (diff.z < 0) {
            inline for (0..BlockLayer.len) |layer_idx| {
                const world_mesh_layer = &self.layers[layer_idx];

                if (world_mesh_layer.len.items[chunk_mesh_idx + 4] > 0) {
                    world_mesh_layer.command.data.items[chunk_mesh_idx + 4].instance_count = 1;
                    world_mesh_layer.command.data.items[chunk_mesh_idx + 4].base_instance = 1;
                    visible_num += 1;
                }

                world_mesh_layer.command.data.items[chunk_mesh_idx + 5].instance_count = 0;
                world_mesh_layer.command.data.items[chunk_mesh_idx + 5].base_instance = 0;
            }
        } else if (diff.z > 0) {
            inline for (0..BlockLayer.len) |layer_idx| {
                const world_mesh_layer = &self.layers[layer_idx];

                world_mesh_layer.command.data.items[chunk_mesh_idx + 4].instance_count = 0;
                world_mesh_layer.command.data.items[chunk_mesh_idx + 4].base_instance = 0;

                if (world_mesh_layer.len.items[chunk_mesh_idx + 5] > 0) {
                    world_mesh_layer.command.data.items[chunk_mesh_idx + 5].instance_count = 1;
                    world_mesh_layer.command.data.items[chunk_mesh_idx + 5].base_instance = 1;
                    visible_num += 1;
                }
            }
        } else {
            inline for (0..BlockLayer.len) |layer_idx| {
                const world_mesh_layer = &self.layers[layer_idx];

                if (world_mesh_layer.len.items[chunk_mesh_idx + 4] > 0) {
                    world_mesh_layer.command.data.items[chunk_mesh_idx + 4].instance_count = 1;
                    world_mesh_layer.command.data.items[chunk_mesh_idx + 4].base_instance = 1;
                    visible_num += 1;
                }

                if (world_mesh_layer.len.items[chunk_mesh_idx + 5] > 0) {
                    world_mesh_layer.command.data.items[chunk_mesh_idx + 5].instance_count = 1;
                    world_mesh_layer.command.data.items[chunk_mesh_idx + 5].base_instance = 1;
                    visible_num += 1;
                }
            }
        }
    }

    return visible_num;
}
