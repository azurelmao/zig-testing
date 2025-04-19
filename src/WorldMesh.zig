const std = @import("std");
const gl = @import("gl");
const Block = @import("block.zig").Block;
const Chunk = @import("Chunk.zig");
const World = @import("World.zig");
const Vec3f = @import("vec3f.zig").Vec3f;
const Camera = @import("Camera.zig");
const ShaderStorageBufferWithArrayList = @import("shader_storage_buffer.zig").ShaderStorageBufferWithArrayList;
const ChunkMesh = @import("ChunkMesh.zig");

const WorldMesh = @This();

layers: [Block.Layer.len]WorldMeshLayer,
pos: ShaderStorageBufferWithArrayList(Vec3f),

pub const WorldMeshLayer = struct {
    len: std.ArrayListUnmanaged(usize),
    mesh: ShaderStorageBufferWithArrayList(ChunkMesh.BlockVertex),
    command: ShaderStorageBufferWithArrayList(DrawArraysIndirectCommand),

    pub fn init() WorldMeshLayer {
        return .{
            .len = .empty,
            .mesh = .init(World.VOLUME * 1000, gl.DYNAMIC_STORAGE_BIT),
            .command = .init(World.VOLUME, gl.DYNAMIC_STORAGE_BIT | gl.MAP_READ_BIT | gl.MAP_WRITE_BIT),
        };
    }
};

const DrawArraysIndirectCommand = packed struct {
    count: gl.uint,
    instance_count: gl.uint,
    first_vertex: gl.uint,
    base_instance: gl.uint,
};

pub fn init() WorldMesh {
    var layers: [Block.Layer.len]WorldMeshLayer = undefined;

    inline for (0..Block.Layer.len) |i| {
        layers[i] = .init();
    }

    return .{
        .layers = layers,
        .pos = .initAndBind(2, World.VOLUME, gl.DYNAMIC_STORAGE_BIT),
    };
}

pub fn uploadCommandBuffers(self: *WorldMesh) void {
    inline for (0..Block.Layer.len) |layer_idx| {
        const world_mesh_layer = &self.layers[layer_idx];
        world_mesh_layer.command.uploadAndOrResize();
    }
}

pub fn clearCommandBuffers(self: *WorldMesh) void {
    for (0..self.pos.data.items.len) |chunk_mesh_idx_| {
        const chunk_mesh_idx = chunk_mesh_idx_ * 6;

        inline for (0..Block.Layer.len) |layer_idx| {
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

        inline for (0..Block.Layer.len) |layer_idx| {
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

        const neighbor_chunks: ChunkMesh.NeighborChunks = expr: {
            var chunks: [6]?*Chunk = undefined;

            for (0..6) |face_idx| {
                chunks[face_idx] = world.getChunkOrNull(chunk_pos.add(Chunk.Pos.Offsets[face_idx]));
            }

            break :expr .{ .chunks = chunks };
        };

        try self.pos.data.append(allocator, chunk_pos.toVec3f());

        if (chunk.num_of_air != Chunk.Volume) {
            try chunk_mesh.generate(chunk, &neighbor_chunks);

            inline for (0..Block.Layer.len) |layer_idx| {
                const world_mesh_layer = &self.layers[layer_idx];
                const single_chunk_mesh_layer = &chunk_mesh.layers[layer_idx];

                inline for (0..6) |face_idx| {
                    const single_chunk_mesh_face = &single_chunk_mesh_layer.faces[face_idx];
                    const len: gl.uint = @intCast(single_chunk_mesh_face.items.len);

                    try world_mesh_layer.len.append(allocator, len);

                    const command = DrawArraysIndirectCommand{
                        .first_vertex = @intCast(world_mesh_layer.mesh.data.items.len * 6),
                        .count = @intCast(len * 6),
                        .instance_count = if (len > 0) 1 else 0,
                        .base_instance = if (len > 0) 1 else 0,
                    };

                    try world_mesh_layer.command.data.append(allocator, command);
                    try world_mesh_layer.mesh.data.appendSlice(allocator, single_chunk_mesh_face.items);
                    single_chunk_mesh_face.clearRetainingCapacity();
                }
            }
        } else {
            inline for (0..Block.Layer.len) |layer_idx| {
                const world_mesh_layer = &self.layers[layer_idx];

                try world_mesh_layer.len.appendNTimes(allocator, 0, 6);

                const command = DrawArraysIndirectCommand{
                    .first_vertex = @intCast(world_mesh_layer.mesh.data.items.len * 6),
                    .count = 0,
                    .instance_count = 0,
                    .base_instance = 0,
                };

                try world_mesh_layer.command.data.appendNTimes(allocator, command, 6);
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
            inline for (0..Block.Layer.len) |layer_idx| {
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

        const point = chunk_mesh_pos.addScalar(Chunk.Center).subtract(camera.position);
        if ((point.dot(camera.direction) < -Chunk.Radius) or
            (point.dot(left_nrm) < -Chunk.Radius) or
            (point.dot(right_nrm) < -Chunk.Radius) or
            (point.dot(bottom_nrm) < -Chunk.Radius) or
            (point.dot(top_nrm) < -Chunk.Radius) or
            (point.dot(camera.direction.negate()) < -(camera.far + Chunk.Radius)))
        {
            inline for (0..Block.Layer.len) |layer_idx| {
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
            inline for (0..Block.Layer.len) |layer_idx| {
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
            inline for (0..Block.Layer.len) |layer_idx| {
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
            inline for (0..Block.Layer.len) |layer_idx| {
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
            inline for (0..Block.Layer.len) |layer_idx| {
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
            inline for (0..Block.Layer.len) |layer_idx| {
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
            inline for (0..Block.Layer.len) |layer_idx| {
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
            inline for (0..Block.Layer.len) |layer_idx| {
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
            inline for (0..Block.Layer.len) |layer_idx| {
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
            inline for (0..Block.Layer.len) |layer_idx| {
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
