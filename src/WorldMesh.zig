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
const Dir = @import("dir.zig").Dir;
const Light = @import("light.zig").Light;

const WorldMesh = @This();

chunk_mesh: ChunkMesh,
layers: [BlockLayer.len]WorldMeshLayer,
visible_chunk_meshes: std.ArrayListUnmanaged(VisibleChunkMesh),
visible_chunk_mesh_pos: ShaderStorageBufferWithArrayList(Vec3f),
chunk_pos_to_light_texture: std.AutoHashMapUnmanaged(Chunk.Pos, gl.uint64),

const VisibleChunkMesh = struct {
    pos: Chunk.Pos,
    visibility: Visibility,
};

const Visibility = packed struct(u6) {
    west: bool, // -x
    east: bool, // +x
    bottom: bool, // -y
    top: bool, // +y
    north: bool, // -z
    south: bool, // +z

    pub const full: Visibility = .{
        .west = true,
        .east = true,
        .bottom = true,
        .top = true,
        .north = true,
        .south = true,
    };
};

pub fn init(gpa: std.mem.Allocator) !WorldMesh {
    var layers: [BlockLayer.len]WorldMeshLayer = undefined;

    for (&layers) |*world_mesh_layer| {
        world_mesh_layer.* = try .init(gpa);
    }

    return .{
        .chunk_mesh = .empty,
        .layers = layers,
        .visible_chunk_meshes = .empty,
        .visible_chunk_mesh_pos = try .initAndBind(gpa, 12, WorldMeshLayer.INITIAL_COMMAND_SIZE, gl.DYNAMIC_STORAGE_BIT),
        .chunk_pos_to_light_texture = .empty,
    };
}

pub const WorldMeshLayer = struct {
    virtual_block: vma.VirtualBlock,
    chunk_pos_to_suballoc: std.AutoArrayHashMapUnmanaged(Chunk.Pos, Suballocation),
    mesh: ShaderStorageBufferWithArrayList(ChunkMesh.PerFaceData),
    command: ShaderStorageBufferWithArrayList(DrawArraysIndirectCommand),
    light_textures: ShaderStorageBufferWithArrayList(gl.uint64),
    chunk_mesh_pos: ShaderStorageBufferWithArrayList(Vec3f),

    const SIX_CHUNK_MESHES = 6;
    const SIX_FACES = 6;
    const AVERAGE_CHUNK_MESH_SIZE = 3000;

    const INITIAL_MESH_SIZE = World.VOLUME * AVERAGE_CHUNK_MESH_SIZE;
    pub const MESH_INCREMENT_SIZE = SIX_CHUNK_MESHES * AVERAGE_CHUNK_MESH_SIZE;
    const INITIAL_COMMAND_SIZE = World.VOLUME * 2 * SIX_FACES;
    pub const COMMAND_INCREMENT_SIZE = SIX_CHUNK_MESHES * SIX_FACES;

    const Suballocation = struct {
        virtual_alloc: vma.VirtualAllocation,
        face_sizes: [6]usize,
    };

    pub fn init(gpa: std.mem.Allocator) !WorldMeshLayer {
        return .{
            .virtual_block = .init(.{ .size = INITIAL_MESH_SIZE }),
            .chunk_pos_to_suballoc = .empty,
            .mesh = try .init(gpa, INITIAL_MESH_SIZE, gl.DYNAMIC_STORAGE_BIT),
            .command = try .init(gpa, INITIAL_COMMAND_SIZE, gl.DYNAMIC_STORAGE_BIT | gl.MAP_READ_BIT | gl.MAP_WRITE_BIT),
            .light_textures = try .init(gpa, INITIAL_COMMAND_SIZE, gl.DYNAMIC_STORAGE_BIT),
            .chunk_mesh_pos = try .init(gpa, INITIAL_COMMAND_SIZE, gl.DYNAMIC_STORAGE_BIT),
        };
    }

    pub fn suballoc(self: *WorldMeshLayer, gpa: std.mem.Allocator, chunk_mesh_layer: *ChunkMeshLayer, chunk_pos: Chunk.Pos) !void {
        var total_suballocation_size: usize = 0;
        for (chunk_mesh_layer.faces) |chunk_mesh_face| {
            total_suballocation_size += chunk_mesh_face.items.len;
        }

        if (total_suballocation_size == 0) return;

        const virtual_alloc = self.virtual_block.alloc(.{ .size = @intCast(total_suballocation_size) }) catch expr: {
            try self.resize(gpa, self.mesh.data.items.len + total_suballocation_size + MESH_INCREMENT_SIZE);

            break :expr self.virtual_block.alloc(.{ .size = @intCast(total_suballocation_size) }) catch unreachable;
        };

        const virtual_alloc_info = self.virtual_block.allocInfo(virtual_alloc);

        if (virtual_alloc_info.offset + total_suballocation_size > self.mesh.data.items.len) {
            try self.mesh.data.resize(gpa, virtual_alloc_info.offset + total_suballocation_size);
        }

        var face_sizes: [6]usize = undefined;
        var offset: usize = virtual_alloc_info.offset;
        for (chunk_mesh_layer.faces, 0..) |chunk_mesh_face, dir_idx| {
            const face_size = chunk_mesh_face.items.len;

            if (chunk_mesh_face.items.len > 0) {
                @memcpy(self.mesh.data.items[offset .. offset + face_size], chunk_mesh_face.items);
                offset += face_size;
            }

            face_sizes[dir_idx] = face_size;
        }

        const suballocation: Suballocation = .{
            .virtual_alloc = virtual_alloc,
            .face_sizes = face_sizes,
        };

        try self.chunk_pos_to_suballoc.put(gpa, chunk_pos, suballocation);
    }

    fn resize(self: *WorldMeshLayer, gpa: std.mem.Allocator, len: usize) !void {
        const new_virtual_block: vma.VirtualBlock = .init(.{ .size = len });
        const new_mesh_data = try gpa.alloc(ChunkMesh.PerFaceData, len);
        var new_chunk_pos_to_suballoc: std.AutoArrayHashMapUnmanaged(Chunk.Pos, Suballocation) = .empty;

        var iter = self.chunk_pos_to_suballoc.iterator();
        while (iter.next()) |entry| {
            const chunk_pos = entry.key_ptr;
            const old_suballocation = entry.value_ptr;

            const old_virtual_alloc_info = self.virtual_block.allocInfo(old_suballocation.virtual_alloc);
            const old_offset = old_virtual_alloc_info.offset;
            const size = old_virtual_alloc_info.size;

            const new_virtual_alloc = new_virtual_block.alloc(.{ .size = size }) catch unreachable;

            const new_virtual_alloc_info = new_virtual_block.allocInfo(new_virtual_alloc);
            const new_offset = new_virtual_alloc_info.offset;

            @memcpy(new_mesh_data[new_offset .. new_offset + size], self.mesh.data.items[old_offset .. old_offset + size]);

            const new_suballocation: Suballocation = .{
                .virtual_alloc = new_virtual_alloc,
                .face_sizes = old_suballocation.face_sizes,
            };

            try new_chunk_pos_to_suballoc.put(gpa, chunk_pos.*, new_suballocation);
        }

        self.virtual_block.deinit();
        self.mesh.data.deinit(gpa);
        self.chunk_pos_to_suballoc.deinit(gpa);

        self.mesh.data = .fromOwnedSlice(new_mesh_data);

        self.virtual_block = new_virtual_block;
        self.chunk_pos_to_suballoc = new_chunk_pos_to_suballoc;
    }

    pub fn free(self: *WorldMeshLayer, chunk_pos: Chunk.Pos) void {
        if (self.chunk_pos_to_suballoc.get(chunk_pos)) |suballocation| {
            self.virtual_block.free(suballocation.virtual_alloc);
            _ = self.chunk_pos_to_suballoc.orderedRemove(chunk_pos);
        }
    }
};

const DrawArraysIndirectCommand = extern struct {
    count: gl.uint,
    instance_count: gl.uint = 1,
    first_vertex: gl.uint,
    base_instance: gl.uint = 0, // unused
};

pub fn generateMesh(self: *WorldMesh, gpa: std.mem.Allocator, world: *World) !void {
    var chunk_iter = world.chunks.valueIterator();
    while (chunk_iter.next()) |chunk| {
        const chunk_pos = chunk.pos;
        const neighbor_chunks = world.getNeighborChunks6(chunk_pos);

        if (chunk.num_of_air != Chunk.VOLUME) {
            try self.chunk_mesh.generate(gpa, chunk, &neighbor_chunks);

            for (&self.layers, &self.chunk_mesh.layers) |*world_mesh_layer, *chunk_mesh_layer| {
                try world_mesh_layer.suballoc(gpa, chunk_mesh_layer, chunk_pos);

                for (&chunk_mesh_layer.faces) |*chunk_mesh_face| {
                    chunk_mesh_face.clearRetainingCapacity();
                }
            }
        }
    }
}

pub fn generateChunkMesh(self: *WorldMesh, gpa: std.mem.Allocator, world: *World, chunk_pos: Chunk.Pos) !void {
    const chunk = try world.getChunk(chunk_pos);
    const neighbor_chunks = world.getNeighborChunks6(chunk_pos);

    if (chunk.num_of_air != Chunk.VOLUME) {
        try self.chunk_mesh.generate(gpa, chunk, &neighbor_chunks);

        for (&self.layers, &self.chunk_mesh.layers) |*world_mesh_layer, *chunk_mesh_layer| {
            try world_mesh_layer.suballoc(gpa, chunk_mesh_layer, chunk_pos);

            for (&chunk_mesh_layer.faces) |*chunk_mesh_face| {
                chunk_mesh_face.clearRetainingCapacity();
            }
        }
    }
}

pub fn invalidateChunkMesh(self: *WorldMesh, chunk_pos: Chunk.Pos) void {
    for (&self.layers) |*world_mesh_layer| {
        world_mesh_layer.free(chunk_pos);
    }
}

pub fn generateVisibleChunkMeshes(self: *WorldMesh, gpa: std.mem.Allocator, world: *const World, camera: *const Camera) !void {
    self.visible_chunk_meshes.clearRetainingCapacity();
    self.visible_chunk_mesh_pos.data.clearRetainingCapacity();

    const left_nrm = Vec3f.init(camera.plane_left[0], camera.plane_left[1], camera.plane_left[2]).normalize();
    const right_nrm = Vec3f.init(camera.plane_right[0], camera.plane_right[1], camera.plane_right[2]).normalize();
    const bottom_nrm = Vec3f.init(camera.plane_bottom[0], camera.plane_bottom[1], camera.plane_bottom[2]).normalize();
    const top_nrm = Vec3f.init(camera.plane_top[0], camera.plane_top[1], camera.plane_top[2]).normalize();

    const camera_chunk_pos = camera.position.toChunkPos();

    var iter = world.chunks.keyIterator();
    while (iter.next()) |chunk_pos| {
        const chunk_mesh_pos = chunk_pos.toVec3f();

        if (chunk_pos.equal(camera_chunk_pos)) {
            try self.visible_chunk_meshes.append(gpa, .{ .pos = chunk_pos.*, .visibility = .full });
            try self.visible_chunk_mesh_pos.data.append(gpa, chunk_mesh_pos);
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
            continue;
        }

        const diff = camera_chunk_pos.subtract(chunk_pos.*);
        var visibility: Visibility = undefined;

        if (diff.x < 0) {
            visibility.west = true;
            visibility.east = false;
        } else if (diff.x != 0) {
            visibility.west = false;
            visibility.east = true;
        } else {
            visibility.west = true;
            visibility.east = true;
        }

        if (diff.y < 0) {
            visibility.bottom = true;
            visibility.top = false;
        } else if (diff.y != 0) {
            visibility.bottom = false;
            visibility.top = true;
        } else {
            visibility.bottom = true;
            visibility.top = true;
        }

        if (diff.z < 0) {
            visibility.north = true;
            visibility.south = false;
        } else if (diff.z != 0) {
            visibility.north = false;
            visibility.south = true;
        } else {
            visibility.north = true;
            visibility.south = true;
        }

        try self.visible_chunk_meshes.append(gpa, .{ .pos = chunk_pos.*, .visibility = visibility });
        try self.visible_chunk_mesh_pos.data.append(gpa, chunk_mesh_pos);
    }

    self.visible_chunk_mesh_pos.ssbo.upload(self.visible_chunk_mesh_pos.data.items) catch |err| switch (err) {
        error.DataTooLarge => {
            self.visible_chunk_mesh_pos.ssbo.resize(self.visible_chunk_mesh_pos.data.items.len, WorldMesh.WorldMeshLayer.COMMAND_INCREMENT_SIZE);
            self.visible_chunk_mesh_pos.ssbo.upload(self.visible_chunk_mesh_pos.data.items) catch unreachable;
        },
        else => unreachable,
    };
}

pub fn generateLightTextures(self: *WorldMesh, gpa: std.mem.Allocator, world: *const World) !void {
    // handle making non-resident when prev len != 0

    self.chunk_pos_to_light_texture.clearRetainingCapacity();

    // temporary
    // const chunk = try world.getChunk(.{ .x = 0, .y = 0, .z = 0 });
    // _ = gpa;

    var iter = world.chunks.valueIterator();
    while (iter.next()) |chunk| {
        var handle: gl.uint = undefined;
        gl.CreateTextures(gl.TEXTURE_3D, 1, @ptrCast(&handle));
        gl.TextureStorage3D(handle, 1, gl.RGBA4, Chunk.SIZE + 2, Chunk.SIZE + 2, Chunk.SIZE + 2);

        // Fill with black for testing
        for (0..Chunk.SIZE + 2) |x| {
            for (0..Chunk.SIZE + 2) |y| {
                for (0..Chunk.SIZE + 2) |z| {
                    gl.TextureSubImage3D(
                        handle,
                        0,
                        @intCast(x),
                        @intCast(y),
                        @intCast(z),
                        1,
                        1,
                        1,
                        gl.RGBA,
                        gl.UNSIGNED_SHORT_4_4_4_4,
                        @ptrCast(&Light{ .red = 0, .green = 0, .blue = 0, .indirect = 0 }),
                    );
                }
            }
        }

        // Main volume from chunk
        gl.TextureSubImage3D(
            handle,
            0,
            1,
            1,
            1,
            Chunk.SIZE,
            Chunk.SIZE,
            Chunk.SIZE,
            gl.RGBA,
            gl.UNSIGNED_SHORT_4_4_4_4,
            @ptrCast(chunk.light),
        );

        // Light overlap from neighboring side chunks
        const neighbor_chunks = world.getNeighborChunks27(chunk.pos);

        if (neighbor_chunks.chunks.get(.west)) |neighbor_chunk| {
            for (0..Chunk.SIZE) |y| {
                for (0..Chunk.SIZE) |z| {
                    const light = neighbor_chunk.getLight(.{ .x = Chunk.EDGE, .y = @intCast(y), .z = @intCast(z) });

                    gl.TextureSubImage3D(
                        handle,
                        0,
                        0,
                        @intCast(y + 1),
                        @intCast(z + 1),
                        1,
                        1,
                        1,
                        gl.RGBA,
                        gl.UNSIGNED_SHORT_4_4_4_4,
                        @ptrCast(&light),
                    );
                }
            }
        }

        if (neighbor_chunks.chunks.get(.bottom_west)) |neighbor_chunk| {
            for (0..Chunk.SIZE) |z| {
                const light = neighbor_chunk.getLight(.{ .x = Chunk.EDGE, .y = Chunk.EDGE, .z = @intCast(z) });

                gl.TextureSubImage3D(
                    handle,
                    0,
                    0,
                    0,
                    @intCast(z + 1),
                    1,
                    1,
                    1,
                    gl.RGBA,
                    gl.UNSIGNED_SHORT_4_4_4_4,
                    @ptrCast(&light),
                );
            }
        }

        if (neighbor_chunks.chunks.get(.top_west)) |neighbor_chunk| {
            for (0..Chunk.SIZE) |z| {
                const light = neighbor_chunk.getLight(.{ .x = Chunk.EDGE, .y = 0, .z = @intCast(z) });

                gl.TextureSubImage3D(
                    handle,
                    0,
                    0,
                    Chunk.SIZE + 1,
                    @intCast(z + 1),
                    1,
                    1,
                    1,
                    gl.RGBA,
                    gl.UNSIGNED_SHORT_4_4_4_4,
                    @ptrCast(&light),
                );
            }
        }

        if (neighbor_chunks.chunks.get(.east)) |neighbor_chunk| {
            for (0..Chunk.SIZE) |y| {
                for (0..Chunk.SIZE) |z| {
                    const light = neighbor_chunk.getLight(.{ .x = 0, .y = @intCast(y), .z = @intCast(z) });

                    gl.TextureSubImage3D(
                        handle,
                        0,
                        Chunk.SIZE + 1,
                        @intCast(y + 1),
                        @intCast(z + 1),
                        1,
                        1,
                        1,
                        gl.RGBA,
                        gl.UNSIGNED_SHORT_4_4_4_4,
                        @ptrCast(&light),
                    );
                }
            }
        }

        if (neighbor_chunks.chunks.get(.bottom_east)) |neighbor_chunk| {
            for (0..Chunk.SIZE) |z| {
                const light = neighbor_chunk.getLight(.{ .x = 0, .y = Chunk.EDGE, .z = @intCast(z) });

                gl.TextureSubImage3D(
                    handle,
                    0,
                    Chunk.SIZE + 1,
                    0,
                    @intCast(z + 1),
                    1,
                    1,
                    1,
                    gl.RGBA,
                    gl.UNSIGNED_SHORT_4_4_4_4,
                    @ptrCast(&light),
                );
            }
        }

        if (neighbor_chunks.chunks.get(.top_east)) |neighbor_chunk| {
            for (0..Chunk.SIZE) |z| {
                const light = neighbor_chunk.getLight(.{ .x = 0, .y = 0, .z = @intCast(z) });

                gl.TextureSubImage3D(
                    handle,
                    0,
                    Chunk.SIZE + 1,
                    Chunk.SIZE + 1,
                    @intCast(z + 1),
                    1,
                    1,
                    1,
                    gl.RGBA,
                    gl.UNSIGNED_SHORT_4_4_4_4,
                    @ptrCast(&light),
                );
            }
        }

        if (neighbor_chunks.chunks.get(.north)) |neighbor_chunk| {
            const local_pos: Chunk.LocalPos = .{ .x = 0, .y = 0, .z = Chunk.EDGE };

            gl.TextureSubImage3D(
                handle,
                0,
                1,
                1,
                0,
                Chunk.SIZE,
                Chunk.SIZE,
                1,
                gl.RGBA,
                gl.UNSIGNED_SHORT_4_4_4_4,
                @ptrCast(neighbor_chunk.light[local_pos.idx()..]),
            );
        }

        if (neighbor_chunks.chunks.get(.bottom_north)) |neighbor_chunk| {
            const local_pos: Chunk.LocalPos = .{ .x = 0, .y = Chunk.EDGE, .z = Chunk.EDGE };

            gl.TextureSubImage3D(
                handle,
                0,
                1,
                0,
                0,
                Chunk.SIZE,
                1,
                1,
                gl.RGBA,
                gl.UNSIGNED_SHORT_4_4_4_4,
                @ptrCast(neighbor_chunk.light[local_pos.idx()..]),
            );
        }

        if (neighbor_chunks.chunks.get(.top_north)) |neighbor_chunk| {
            const local_pos: Chunk.LocalPos = .{ .x = 0, .y = 0, .z = Chunk.EDGE };

            gl.TextureSubImage3D(
                handle,
                0,
                1,
                Chunk.SIZE + 1,
                0,
                Chunk.SIZE,
                1,
                1,
                gl.RGBA,
                gl.UNSIGNED_SHORT_4_4_4_4,
                @ptrCast(neighbor_chunk.light[local_pos.idx()..]),
            );
        }

        if (neighbor_chunks.chunks.get(.south)) |neighbor_chunk| {
            const local_pos: Chunk.LocalPos = .{ .x = 0, .y = 0, .z = 0 };

            gl.TextureSubImage3D(
                handle,
                0,
                1,
                1,
                Chunk.SIZE + 1,
                Chunk.SIZE,
                Chunk.SIZE,
                1,
                gl.RGBA,
                gl.UNSIGNED_SHORT_4_4_4_4,
                @ptrCast(neighbor_chunk.light[local_pos.idx()..]),
            );
        }

        if (neighbor_chunks.chunks.get(.bottom_south)) |neighbor_chunk| {
            const local_pos: Chunk.LocalPos = .{ .x = 0, .y = Chunk.EDGE, .z = 0 };

            gl.TextureSubImage3D(
                handle,
                0,
                1,
                0,
                Chunk.SIZE + 1,
                Chunk.SIZE,
                1,
                1,
                gl.RGBA,
                gl.UNSIGNED_SHORT_4_4_4_4,
                @ptrCast(neighbor_chunk.light[local_pos.idx()..]),
            );
        }

        if (neighbor_chunks.chunks.get(.top_south)) |neighbor_chunk| {
            const local_pos: Chunk.LocalPos = .{ .x = 0, .y = 0, .z = 0 };

            gl.TextureSubImage3D(
                handle,
                0,
                1,
                Chunk.SIZE + 1,
                Chunk.SIZE + 1,
                Chunk.SIZE,
                1,
                1,
                gl.RGBA,
                gl.UNSIGNED_SHORT_4_4_4_4,
                @ptrCast(neighbor_chunk.light[local_pos.idx()..]),
            );
        }

        if (neighbor_chunks.chunks.get(.north_west)) |neighbor_chunk| {
            for (0..Chunk.SIZE) |y| {
                const light = neighbor_chunk.getLight(.{ .x = Chunk.EDGE, .y = @intCast(y), .z = Chunk.EDGE });

                gl.TextureSubImage3D(
                    handle,
                    0,
                    0,
                    @intCast(y + 1),
                    0,
                    1,
                    1,
                    1,
                    gl.RGBA,
                    gl.UNSIGNED_SHORT_4_4_4_4,
                    @ptrCast(&light),
                );
            }
        }

        if (neighbor_chunks.chunks.get(.bottom_north_west)) |neighbor_chunk| {
            const light = neighbor_chunk.getLight(.{ .x = Chunk.EDGE, .y = Chunk.EDGE, .z = Chunk.EDGE });

            gl.TextureSubImage3D(
                handle,
                0,
                0,
                0,
                0,
                1,
                1,
                1,
                gl.RGBA,
                gl.UNSIGNED_SHORT_4_4_4_4,
                @ptrCast(&light),
            );
        }

        if (neighbor_chunks.chunks.get(.top_north_west)) |neighbor_chunk| {
            const light = neighbor_chunk.getLight(.{ .x = Chunk.EDGE, .y = 0, .z = Chunk.EDGE });

            gl.TextureSubImage3D(
                handle,
                0,
                0,
                Chunk.SIZE + 1,
                0,
                1,
                1,
                1,
                gl.RGBA,
                gl.UNSIGNED_SHORT_4_4_4_4,
                @ptrCast(&light),
            );
        }

        if (neighbor_chunks.chunks.get(.north_east)) |neighbor_chunk| {
            for (0..Chunk.SIZE) |y| {
                const light = neighbor_chunk.getLight(.{ .x = 0, .y = @intCast(y), .z = Chunk.EDGE });

                gl.TextureSubImage3D(
                    handle,
                    0,
                    Chunk.SIZE + 1,
                    @intCast(y + 1),
                    0,
                    1,
                    1,
                    1,
                    gl.RGBA,
                    gl.UNSIGNED_SHORT_4_4_4_4,
                    @ptrCast(&light),
                );
            }
        }

        if (neighbor_chunks.chunks.get(.bottom_north_east)) |neighbor_chunk| {
            const light = neighbor_chunk.getLight(.{ .x = 0, .y = Chunk.EDGE, .z = Chunk.EDGE });

            gl.TextureSubImage3D(
                handle,
                0,
                Chunk.SIZE + 1,
                0,
                0,
                1,
                1,
                1,
                gl.RGBA,
                gl.UNSIGNED_SHORT_4_4_4_4,
                @ptrCast(&light),
            );
        }

        if (neighbor_chunks.chunks.get(.top_north_east)) |neighbor_chunk| {
            const light = neighbor_chunk.getLight(.{ .x = 0, .y = 0, .z = Chunk.EDGE });

            gl.TextureSubImage3D(
                handle,
                0,
                Chunk.SIZE + 1,
                Chunk.SIZE + 1,
                0,
                1,
                1,
                1,
                gl.RGBA,
                gl.UNSIGNED_SHORT_4_4_4_4,
                @ptrCast(&light),
            );
        }

        if (neighbor_chunks.chunks.get(.south_west)) |neighbor_chunk| {
            for (0..Chunk.SIZE) |y| {
                const light = neighbor_chunk.getLight(.{ .x = Chunk.EDGE, .y = @intCast(y), .z = 0 });

                gl.TextureSubImage3D(
                    handle,
                    0,
                    0,
                    @intCast(y + 1),
                    Chunk.SIZE + 1,
                    1,
                    1,
                    1,
                    gl.RGBA,
                    gl.UNSIGNED_SHORT_4_4_4_4,
                    @ptrCast(&light),
                );
            }
        }

        if (neighbor_chunks.chunks.get(.bottom_south_west)) |neighbor_chunk| {
            const light = neighbor_chunk.getLight(.{ .x = Chunk.EDGE, .y = Chunk.EDGE, .z = 0 });

            gl.TextureSubImage3D(
                handle,
                0,
                0,
                0,
                Chunk.SIZE + 1,
                1,
                1,
                1,
                gl.RGBA,
                gl.UNSIGNED_SHORT_4_4_4_4,
                @ptrCast(&light),
            );
        }

        if (neighbor_chunks.chunks.get(.top_south_west)) |neighbor_chunk| {
            const light = neighbor_chunk.getLight(.{ .x = Chunk.EDGE, .y = 0, .z = 0 });

            gl.TextureSubImage3D(
                handle,
                0,
                0,
                Chunk.SIZE + 1,
                Chunk.SIZE + 1,
                1,
                1,
                1,
                gl.RGBA,
                gl.UNSIGNED_SHORT_4_4_4_4,
                @ptrCast(&light),
            );
        }

        if (neighbor_chunks.chunks.get(.south_east)) |neighbor_chunk| {
            for (0..Chunk.SIZE) |y| {
                const light = neighbor_chunk.getLight(.{ .x = 0, .y = @intCast(y), .z = 0 });

                gl.TextureSubImage3D(
                    handle,
                    0,
                    Chunk.SIZE + 1,
                    @intCast(y + 1),
                    Chunk.SIZE + 1,
                    1,
                    1,
                    1,
                    gl.RGBA,
                    gl.UNSIGNED_SHORT_4_4_4_4,
                    @ptrCast(&light),
                );
            }
        }

        if (neighbor_chunks.chunks.get(.bottom_south_east)) |neighbor_chunk| {
            const light = neighbor_chunk.getLight(.{ .x = 0, .y = Chunk.EDGE, .z = 0 });

            gl.TextureSubImage3D(
                handle,
                0,
                Chunk.SIZE + 1,
                0,
                Chunk.SIZE + 1,
                1,
                1,
                1,
                gl.RGBA,
                gl.UNSIGNED_SHORT_4_4_4_4,
                @ptrCast(&light),
            );
        }

        if (neighbor_chunks.chunks.get(.top_south_east)) |neighbor_chunk| {
            const light = neighbor_chunk.getLight(.{ .x = 0, .y = 0, .z = 0 });

            gl.TextureSubImage3D(
                handle,
                0,
                Chunk.SIZE + 1,
                Chunk.SIZE + 1,
                Chunk.SIZE + 1,
                1,
                1,
                1,
                gl.RGBA,
                gl.UNSIGNED_SHORT_4_4_4_4,
                @ptrCast(&light),
            );
        }

        if (neighbor_chunks.chunks.get(.bottom)) |neighbor_chunk| {
            for (0..Chunk.SIZE) |z| {
                const local_pos: Chunk.LocalPos = .{ .x = 0, .y = Chunk.EDGE, .z = @intCast(z) };

                gl.TextureSubImage3D(
                    handle,
                    0,
                    1,
                    0,
                    @intCast(z + 1),
                    Chunk.SIZE,
                    1,
                    1,
                    gl.RGBA,
                    gl.UNSIGNED_SHORT_4_4_4_4,
                    @ptrCast(neighbor_chunk.light[local_pos.idx()..]),
                );
            }
        }

        if (neighbor_chunks.chunks.get(.top)) |neighbor_chunk| {
            for (0..Chunk.SIZE) |z| {
                const local_pos: Chunk.LocalPos = .{ .x = 0, .y = 0, .z = @intCast(z) };

                gl.TextureSubImage3D(
                    handle,
                    0,
                    1,
                    Chunk.SIZE + 1,
                    @intCast(z + 1),
                    Chunk.SIZE,
                    1,
                    1,
                    gl.RGBA,
                    gl.UNSIGNED_SHORT_4_4_4_4,
                    @ptrCast(neighbor_chunk.light[local_pos.idx()..]),
                );
            }
        }

        gl.TextureParameteri(handle, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.TextureParameteri(handle, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        gl.TextureParameteri(handle, gl.TEXTURE_WRAP_R, gl.CLAMP_TO_EDGE);
        gl.TextureParameteri(handle, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        gl.TextureParameteri(handle, gl.TEXTURE_MAG_FILTER, gl.LINEAR);

        // gl.BindTextureUnit(3, handle);

        const descriptor = gl.GetTextureHandleARB(handle);
        if (descriptor == 0) std.debug.panic("Failed to create texture descriptor", .{});

        gl.MakeTextureHandleResidentARB(descriptor);

        try self.chunk_pos_to_light_texture.put(gpa, chunk.pos, descriptor);
    }
}

pub fn generateCommands(self: *WorldMesh, gpa: std.mem.Allocator) !void {
    for (BlockLayer.values) |block_layer| {
        const world_mesh_layer = &self.layers[block_layer.idx()];
        world_mesh_layer.command.data.clearRetainingCapacity();
        world_mesh_layer.chunk_mesh_pos.data.clearRetainingCapacity();
        world_mesh_layer.light_textures.data.clearRetainingCapacity();

        for (self.visible_chunk_meshes.items) |visible_chunk_mesh| {
            const chunk_pos = visible_chunk_mesh.pos;
            const chunk_mesh_pos = chunk_pos.toVec3f();
            const visibility = visible_chunk_mesh.visibility;

            const light_texture = self.chunk_pos_to_light_texture.get(chunk_pos) orelse unreachable;

            const suballocation = world_mesh_layer.chunk_pos_to_suballoc.get(chunk_pos) orelse continue;
            const virtual_alloc_info = world_mesh_layer.virtual_block.allocInfo(suballocation.virtual_alloc);

            const mask: u6 = if (block_layer == .water) comptime std.math.maxInt(u6) else @bitCast(visibility);

            var offset: usize = virtual_alloc_info.offset;
            var starting_offset: usize = 0;
            var total_size: usize = 0;

            for (Dir.values) |dir| {
                const face_size = suballocation.face_sizes[dir.idx()];

                if (((mask >> @intCast(dir.idx())) & 0b1 == 1) and face_size != 0) {
                    if (total_size == 0) starting_offset = offset;
                    total_size += face_size;
                } else if (total_size != 0) {
                    const command: DrawArraysIndirectCommand = .{
                        .first_vertex = @intCast(starting_offset * 6),
                        .count = @intCast(total_size * 6),
                    };

                    try world_mesh_layer.command.data.append(gpa, command);
                    try world_mesh_layer.chunk_mesh_pos.data.append(gpa, chunk_mesh_pos);
                    try world_mesh_layer.light_textures.data.append(gpa, light_texture);

                    starting_offset = 0;
                    total_size = 0;
                }

                offset += face_size;
            }

            if (total_size != 0) {
                const command: DrawArraysIndirectCommand = .{
                    .first_vertex = @intCast(starting_offset * 6),
                    .count = @intCast(total_size * 6),
                };

                try world_mesh_layer.command.data.append(gpa, command);
                try world_mesh_layer.chunk_mesh_pos.data.append(gpa, chunk_mesh_pos);
                try world_mesh_layer.light_textures.data.append(gpa, light_texture);
            }
        }
    }
}

pub fn uploadMesh(self: *WorldMesh) void {
    for (&self.layers) |*world_mesh_layer| {
        world_mesh_layer.mesh.ssbo.upload(world_mesh_layer.mesh.data.items) catch |err| switch (err) {
            error.DataTooLarge => {
                world_mesh_layer.mesh.ssbo.resize(world_mesh_layer.mesh.data.items.len, WorldMesh.WorldMeshLayer.MESH_INCREMENT_SIZE);
                world_mesh_layer.mesh.ssbo.upload(world_mesh_layer.mesh.data.items) catch unreachable;
            },
            else => unreachable,
        };
    }
}

pub fn uploadCommands(self: *WorldMesh) void {
    for (&self.layers) |*world_mesh_layer| {
        world_mesh_layer.command.ssbo.upload(world_mesh_layer.command.data.items) catch |err| switch (err) {
            error.DataTooLarge => {
                const new_len = world_mesh_layer.command.data.items.len;
                const extra_capacity = WorldMesh.WorldMeshLayer.COMMAND_INCREMENT_SIZE;

                world_mesh_layer.command.ssbo.resize(new_len, extra_capacity);
                world_mesh_layer.chunk_mesh_pos.ssbo.resize(new_len, extra_capacity);
                world_mesh_layer.light_textures.ssbo.resize(new_len, extra_capacity);
            },
            else => unreachable,
        };
        world_mesh_layer.chunk_mesh_pos.ssbo.upload(world_mesh_layer.chunk_mesh_pos.data.items) catch unreachable;
        world_mesh_layer.light_textures.ssbo.upload(world_mesh_layer.light_textures.data.items) catch unreachable;

        // for chunks_bb frag shader
        // world_mesh_layer.command.bind(6 + layer_idx);
    }
}
