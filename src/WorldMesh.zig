const std = @import("std");
const gl = @import("gl");
const vma = @import("vma.zig");
const BlockLayer = @import("block.zig").BlockLayer;
const Chunk = @import("Chunk.zig");
const World = @import("World.zig");
const Vec3f = @import("vec3f.zig").Vec3f;
const Camera = @import("Camera.zig");
const ShaderStorageBufferWithArrayList = @import("shader_storage_buffer.zig").ShaderStorageBufferWithArrayList;
const ChunkMeshGenerator = @import("ChunkMeshGenerator.zig");
const ChunkMeshLayer = ChunkMeshGenerator.ChunkMeshLayer;
const Dir = @import("dir.zig").Dir;
const Light = @import("light.zig").Light;
const LightTexture = @import("LightTexture.zig");
const debug = @import("debug.zig");
const DedupArrayList = @import("dedup_arraylist.zig").DedupArrayList;

const WorldMesh = @This();

chunk_mesh_generator: ChunkMeshGenerator,
layers: [BlockLayer.len]WorldMeshLayer,
chunk_meshes_which_need_to_upload_light_texture_overlaps: DedupArrayList(Chunk.Pos),
visible_chunk_meshes: std.ArrayListUnmanaged(VisibleChunkMesh),
chunk_meshes: std.AutoArrayHashMapUnmanaged(Chunk.Pos, ChunkMesh),

const ChunkMesh = struct {
    light_texture: LightTexture,
};

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
        .chunk_mesh_generator = .empty,
        .layers = layers,
        .chunk_meshes_which_need_to_upload_light_texture_overlaps = .empty,
        .visible_chunk_meshes = .empty,
        .chunk_meshes = .empty,
    };
}

pub const WorldMeshLayer = struct {
    virtual_block: vma.VirtualBlock,
    chunk_pos_to_suballoc: std.AutoArrayHashMapUnmanaged(Chunk.Pos, Suballocation),
    mesh: ShaderStorageBufferWithArrayList(ChunkMeshGenerator.PerFaceData),
    command: ShaderStorageBufferWithArrayList(DrawArraysIndirectCommand),

    const SIX_CHUNK_MESHES = 6;
    const SIX_FACES = 6;
    const AVERAGE_CHUNK_MESH_SIZE = 3000;
    const AVERAGE_WORLD_VOLUME = 8 * 8 * 4;

    pub const INITIAL_MESH_SIZE = AVERAGE_WORLD_VOLUME * AVERAGE_CHUNK_MESH_SIZE;
    pub const MESH_INCREMENT_SIZE = SIX_CHUNK_MESHES * AVERAGE_CHUNK_MESH_SIZE;
    pub const INITIAL_COMMAND_SIZE = AVERAGE_WORLD_VOLUME * SIX_FACES;
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
        };
    }

    pub fn suballoc(world_mesh_layer: *WorldMeshLayer, gpa: std.mem.Allocator, chunk_mesh_layer: *ChunkMeshLayer, chunk_pos: Chunk.Pos) !void {
        var total_suballocation_size: usize = 0;
        for (chunk_mesh_layer.faces) |chunk_mesh_face| {
            total_suballocation_size += chunk_mesh_face.items.len;
        }

        if (total_suballocation_size == 0) return;

        const virtual_alloc = world_mesh_layer.virtual_block.alloc(.{ .size = @intCast(total_suballocation_size) }) catch expr: {
            try world_mesh_layer.resize(gpa, world_mesh_layer.mesh.data.items.len + total_suballocation_size + MESH_INCREMENT_SIZE);

            break :expr world_mesh_layer.virtual_block.alloc(.{ .size = @intCast(total_suballocation_size) }) catch unreachable;
        };

        const virtual_alloc_info = world_mesh_layer.virtual_block.allocInfo(virtual_alloc);

        if (virtual_alloc_info.offset + total_suballocation_size > world_mesh_layer.mesh.data.items.len) {
            try world_mesh_layer.mesh.data.resize(gpa, virtual_alloc_info.offset + total_suballocation_size);
        }

        var face_sizes: [6]usize = undefined;
        var offset: usize = virtual_alloc_info.offset;
        for (chunk_mesh_layer.faces, 0..) |chunk_mesh_face, dir_idx| {
            const face_size = chunk_mesh_face.items.len;

            if (chunk_mesh_face.items.len > 0) {
                @memcpy(world_mesh_layer.mesh.data.items[offset .. offset + face_size], chunk_mesh_face.items);
                offset += face_size;
            }

            face_sizes[dir_idx] = face_size;
        }

        const suballocation: Suballocation = .{
            .virtual_alloc = virtual_alloc,
            .face_sizes = face_sizes,
        };

        try world_mesh_layer.chunk_pos_to_suballoc.put(gpa, chunk_pos, suballocation);
    }

    fn resize(world_mesh_layer: *WorldMeshLayer, gpa: std.mem.Allocator, len: usize) !void {
        const new_virtual_block: vma.VirtualBlock = .init(.{ .size = len });
        const new_mesh_data = try gpa.alloc(ChunkMeshGenerator.PerFaceData, len);
        var new_chunk_pos_to_suballoc: std.AutoArrayHashMapUnmanaged(Chunk.Pos, Suballocation) = .empty;

        var iter = world_mesh_layer.chunk_pos_to_suballoc.iterator();
        while (iter.next()) |entry| {
            const chunk_pos = entry.key_ptr;
            const old_suballocation = entry.value_ptr;

            const old_virtual_alloc_info = world_mesh_layer.virtual_block.allocInfo(old_suballocation.virtual_alloc);
            const old_offset = old_virtual_alloc_info.offset;
            const size = old_virtual_alloc_info.size;

            const new_virtual_alloc = new_virtual_block.alloc(.{ .size = size }) catch unreachable;

            const new_virtual_alloc_info = new_virtual_block.allocInfo(new_virtual_alloc);
            const new_offset = new_virtual_alloc_info.offset;

            @memcpy(new_mesh_data[new_offset .. new_offset + size], world_mesh_layer.mesh.data.items[old_offset .. old_offset + size]);

            const new_suballocation: Suballocation = .{
                .virtual_alloc = new_virtual_alloc,
                .face_sizes = old_suballocation.face_sizes,
            };

            try new_chunk_pos_to_suballoc.put(gpa, chunk_pos.*, new_suballocation);
        }

        world_mesh_layer.virtual_block.deinit();
        world_mesh_layer.mesh.data.deinit(gpa);
        world_mesh_layer.chunk_pos_to_suballoc.deinit(gpa);

        world_mesh_layer.mesh.data = .fromOwnedSlice(new_mesh_data);

        world_mesh_layer.virtual_block = new_virtual_block;
        world_mesh_layer.chunk_pos_to_suballoc = new_chunk_pos_to_suballoc;
    }

    pub fn free(world_mesh_layer: *WorldMeshLayer, chunk_pos: Chunk.Pos) void {
        if (world_mesh_layer.chunk_pos_to_suballoc.get(chunk_pos)) |suballocation| {
            world_mesh_layer.virtual_block.free(suballocation.virtual_alloc);
            _ = world_mesh_layer.chunk_pos_to_suballoc.orderedRemove(chunk_pos);
        }
    }
};

const DrawArraysIndirectCommand = extern struct {
    count: gl.uint,
    instance_count: gl.uint = 1,
    first_vertex: gl.uint,
    base_instance: gl.uint = 0, // unused

    chunk_mesh_pos: Vec3f,
    light_texture: gl.uint64,
    _: u64 = undefined,
};

pub fn hasChunkMesh(world_mesh: WorldMesh, chunk_pos: Chunk.Pos) bool {
    return world_mesh.chunk_meshes.contains(chunk_pos);
}

pub fn getChunkMesh(world_mesh: WorldMesh, chunk_pos: Chunk.Pos) *ChunkMesh {
    return world_mesh.chunk_meshes.getPtr(chunk_pos) orelse unreachable;
}

pub fn getChunkMeshOrNull(world_mesh: WorldMesh, chunk_pos: Chunk.Pos) ?*ChunkMesh {
    return world_mesh.chunk_meshes.getPtr(chunk_pos);
}

pub fn putChunkMesh(world_mesh: *WorldMesh, gpa: std.mem.Allocator, chunk_pos: Chunk.Pos, chunk_mesh: ChunkMesh) !void {
    try world_mesh.chunk_meshes.put(gpa, chunk_pos, chunk_mesh);
}

pub const NeighborChunkMeshes27 = struct {
    chunk_meshes: std.EnumArray(LocalChunkPos, ?*ChunkMesh),

    pub const LocalChunkPos = enum(u5) {
        west = idx(-1, 0, 0),
        bottom_west = idx(-1, -1, 0),
        top_west = idx(-1, 1, 0),

        east = idx(1, 0, 0),
        bottom_east = idx(1, -1, 0),
        top_east = idx(1, 1, 0),

        north = idx(0, 0, -1),
        bottom_north = idx(0, -1, -1),
        top_north = idx(0, 1, -1),

        south = idx(0, 0, 1),
        bottom_south = idx(0, -1, 1),
        top_south = idx(0, 1, 1),

        north_west = idx(-1, 0, -1),
        bottom_north_west = idx(-1, -1, -1),
        top_north_west = idx(-1, 1, -1),

        north_east = idx(1, 0, -1),
        bottom_north_east = idx(1, -1, -1),
        top_north_east = idx(1, 1, -1),

        south_west = idx(-1, 0, 1),
        bottom_south_west = idx(-1, -1, 1),
        top_south_west = idx(-1, 1, 1),

        south_east = idx(1, 0, 1),
        bottom_south_east = idx(1, -1, 1),
        top_south_east = idx(1, 1, 1),

        bottom = idx(0, -1, 0),
        top = idx(0, 1, 0),
        middle = idx(0, 0, 0),

        pub fn idx(x: i11, y: i11, z: i11) u5 {
            const x2: u5 = @intCast(x + 1);
            const y2: u5 = @intCast(y + 1);
            const z2: u5 = @intCast(z + 1);

            return x2 + y2 * 3 + z2 * 9;
        }
    };
};

pub fn getNeighborChunkMeshes27(world_mesh: WorldMesh, chunk_pos: Chunk.Pos) NeighborChunkMeshes27 {
    var chunk_meshes: std.EnumArray(NeighborChunkMeshes27.LocalChunkPos, ?*ChunkMesh) = .initUndefined();

    for (0..3) |x_usize| {
        const x = @as(i11, @intCast(x_usize)) - 1;

        for (0..3) |y_usize| {
            const y = @as(i11, @intCast(y_usize)) - 1;

            for (0..3) |z_usize| {
                const z = @as(i11, @intCast(z_usize)) - 1;

                chunk_meshes.set(
                    @enumFromInt(NeighborChunkMeshes27.LocalChunkPos.idx(x, y, z)),
                    world_mesh.getChunkMeshOrNull(chunk_pos.add(.{ .x = x, .y = y, .z = z })),
                );
            }
        }
    }

    return .{ .chunk_meshes = chunk_meshes };
}

pub fn generateChunkMesh(world_mesh: *WorldMesh, gpa: std.mem.Allocator, world: *World, chunk_pos: Chunk.Pos) !void {
    const chunk = world.getChunk(chunk_pos);
    const neighbor_chunks = world.getNeighborChunks6(chunk_pos);

    if (chunk.num_of_air != Chunk.VOLUME) {
        try world_mesh.chunk_mesh_generator.generate(gpa, chunk, neighbor_chunks);

        for (&world_mesh.layers, &world_mesh.chunk_mesh_generator.layers) |*world_mesh_layer, *chunk_mesh_layer| {
            try world_mesh_layer.suballoc(gpa, chunk_mesh_layer, chunk_pos);

            for (&chunk_mesh_layer.faces) |*chunk_mesh_face| {
                chunk_mesh_face.clearRetainingCapacity();
            }
        }
    }
}

pub fn invalidateChunkMesh(world_mesh: *WorldMesh, chunk_pos: Chunk.Pos) void {
    for (&world_mesh.layers) |*world_mesh_layer| {
        world_mesh_layer.free(chunk_pos);
    }

    world_mesh.getChunkMesh(chunk_pos).light_texture.deinit();
}

pub fn generateVisibleChunkMeshes(world_mesh: *WorldMesh, gpa: std.mem.Allocator, world: World, camera: Camera) !void {
    world_mesh.visible_chunk_meshes.clearRetainingCapacity();
    debug.visible_chunk_mesh_positions.clearRetainingCapacity();

    const left_nrm = Vec3f.init(camera.plane_left[0], camera.plane_left[1], camera.plane_left[2]).normalize();
    const right_nrm = Vec3f.init(camera.plane_right[0], camera.plane_right[1], camera.plane_right[2]).normalize();
    const bottom_nrm = Vec3f.init(camera.plane_bottom[0], camera.plane_bottom[1], camera.plane_bottom[2]).normalize();
    const top_nrm = Vec3f.init(camera.plane_top[0], camera.plane_top[1], camera.plane_top[2]).normalize();

    const camera_chunk_pos = camera.position.toChunkPos();

    for (world.chunks.keys()) |chunk_pos| {
        const chunk_mesh_pos = chunk_pos.toVec3f();

        if (chunk_pos.equal(camera_chunk_pos)) {
            try world_mesh.visible_chunk_meshes.append(gpa, .{ .pos = chunk_pos, .visibility = .full });
            try debug.visible_chunk_mesh_positions.data.append(gpa, chunk_mesh_pos);
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

        const diff = camera_chunk_pos.subtract(chunk_pos);
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

        try world_mesh.visible_chunk_meshes.append(gpa, .{ .pos = chunk_pos, .visibility = visibility });
        try debug.visible_chunk_mesh_positions.data.append(gpa, chunk_mesh_pos);
    }

    debug.visible_chunk_mesh_positions.ssbo.upload(debug.visible_chunk_mesh_positions.data.items) catch |err| switch (err) {
        error.DataTooLarge => {
            debug.visible_chunk_mesh_positions.ssbo.resize(debug.visible_chunk_mesh_positions.data.items.len, WorldMeshLayer.COMMAND_INCREMENT_SIZE);
            debug.visible_chunk_mesh_positions.ssbo.upload(debug.visible_chunk_mesh_positions.data.items) catch unreachable;
        },
    };
}

pub fn uploadLightTexture(world_mesh: *WorldMesh, world: World, chunk_pos: Chunk.Pos) !void {
    const neighbor_chunks = world.getNeighborChunks27(chunk_pos);

    const neighbor_chunk_meshes = world_mesh.getNeighborChunkMeshes27(chunk_pos);
    const light_texture = neighbor_chunk_meshes.chunk_meshes.get(.middle).?.light_texture;

    light_texture.uploadMainVolume(neighbor_chunks.chunks.get(.middle).?);

    light_texture.uploadWestOverlap(neighbor_chunks.chunks.get(.west));
    light_texture.uploadBottomWestOverlap(neighbor_chunks.chunks.get(.bottom_west));
    light_texture.uploadTopWestOverlap(neighbor_chunks.chunks.get(.top_west));

    light_texture.uploadEastOverlap(neighbor_chunks.chunks.get(.east));
    light_texture.uploadBottomEastOverlap(neighbor_chunks.chunks.get(.bottom_east));
    light_texture.uploadTopEastOverlap(neighbor_chunks.chunks.get(.top_east));

    light_texture.uploadNorthOverlap(neighbor_chunks.chunks.get(.north));
    light_texture.uploadBottomNorthOverlap(neighbor_chunks.chunks.get(.bottom_north));
    light_texture.uploadTopNorthOverlap(neighbor_chunks.chunks.get(.top_north));

    light_texture.uploadSouthOverlap(neighbor_chunks.chunks.get(.south));
    light_texture.uploadBottomSouthOverlap(neighbor_chunks.chunks.get(.bottom_south));
    light_texture.uploadTopSouthOverlap(neighbor_chunks.chunks.get(.top_south));

    light_texture.uploadNorthWestOverlap(neighbor_chunks.chunks.get(.north_west));
    light_texture.uploadBottomNorthWestOverlap(neighbor_chunks.chunks.get(.bottom_north_west));
    light_texture.uploadTopNorthWestOverlap(neighbor_chunks.chunks.get(.top_north_west));

    light_texture.uploadNorthEastOverlap(neighbor_chunks.chunks.get(.north_east));
    light_texture.uploadBottomNorthEastOverlap(neighbor_chunks.chunks.get(.bottom_north_east));
    light_texture.uploadTopNorthEastOverlap(neighbor_chunks.chunks.get(.top_north_east));

    light_texture.uploadSouthWestOverlap(neighbor_chunks.chunks.get(.south_west));
    light_texture.uploadBottomSouthWestOverlap(neighbor_chunks.chunks.get(.bottom_south_west));
    light_texture.uploadTopSouthWestOverlap(neighbor_chunks.chunks.get(.top_south_west));

    light_texture.uploadSouthEastOverlap(neighbor_chunks.chunks.get(.south_east));
    light_texture.uploadBottomSouthEastOverlap(neighbor_chunks.chunks.get(.bottom_south_east));
    light_texture.uploadTopSouthEastOverlap(neighbor_chunks.chunks.get(.top_south_east));

    light_texture.uploadBottomOverlap(neighbor_chunks.chunks.get(.bottom));
    light_texture.uploadTopOverlap(neighbor_chunks.chunks.get(.top));
}

pub fn uploadLightTextureOverlaps(world_mesh: *WorldMesh, world: World, chunk_pos: Chunk.Pos) !void {
    const chunk = world.getChunk(chunk_pos);

    const neighbor_chunk_meshes = world_mesh.getNeighborChunkMeshes27(chunk_pos);
    if (neighbor_chunk_meshes.chunk_meshes.get(.west)) |chunk_mesh| {
        chunk_mesh.light_texture.uploadEastOverlap(chunk);
    }

    if (neighbor_chunk_meshes.chunk_meshes.get(.bottom_west)) |chunk_mesh| {
        chunk_mesh.light_texture.uploadTopEastOverlap(chunk);
    }

    if (neighbor_chunk_meshes.chunk_meshes.get(.top_west)) |chunk_mesh| {
        chunk_mesh.light_texture.uploadBottomEastOverlap(chunk);
    }

    if (neighbor_chunk_meshes.chunk_meshes.get(.east)) |chunk_mesh| {
        chunk_mesh.light_texture.uploadWestOverlap(chunk);
    }

    if (neighbor_chunk_meshes.chunk_meshes.get(.bottom_east)) |chunk_mesh| {
        chunk_mesh.light_texture.uploadTopWestOverlap(chunk);
    }

    if (neighbor_chunk_meshes.chunk_meshes.get(.top_east)) |chunk_mesh| {
        chunk_mesh.light_texture.uploadBottomWestOverlap(chunk);
    }

    if (neighbor_chunk_meshes.chunk_meshes.get(.north)) |chunk_mesh| {
        chunk_mesh.light_texture.uploadSouthOverlap(chunk);
    }

    if (neighbor_chunk_meshes.chunk_meshes.get(.bottom_north)) |chunk_mesh| {
        chunk_mesh.light_texture.uploadTopNorthOverlap(chunk);
    }

    if (neighbor_chunk_meshes.chunk_meshes.get(.top_north)) |chunk_mesh| {
        chunk_mesh.light_texture.uploadBottomSouthOverlap(chunk);
    }

    if (neighbor_chunk_meshes.chunk_meshes.get(.south)) |chunk_mesh| {
        chunk_mesh.light_texture.uploadNorthOverlap(chunk);
    }

    if (neighbor_chunk_meshes.chunk_meshes.get(.bottom_south)) |chunk_mesh| {
        chunk_mesh.light_texture.uploadTopNorthOverlap(chunk);
    }

    if (neighbor_chunk_meshes.chunk_meshes.get(.top_south)) |chunk_mesh| {
        chunk_mesh.light_texture.uploadBottomNorthOverlap(chunk);
    }

    if (neighbor_chunk_meshes.chunk_meshes.get(.north_west)) |chunk_mesh| {
        chunk_mesh.light_texture.uploadSouthEastOverlap(chunk);
    }

    if (neighbor_chunk_meshes.chunk_meshes.get(.bottom_north_west)) |chunk_mesh| {
        chunk_mesh.light_texture.uploadTopSouthEastOverlap(chunk);
    }

    if (neighbor_chunk_meshes.chunk_meshes.get(.top_north_west)) |chunk_mesh| {
        chunk_mesh.light_texture.uploadBottomSouthEastOverlap(chunk);
    }

    if (neighbor_chunk_meshes.chunk_meshes.get(.north_east)) |chunk_mesh| {
        chunk_mesh.light_texture.uploadSouthWestOverlap(chunk);
    }

    if (neighbor_chunk_meshes.chunk_meshes.get(.bottom_north_east)) |chunk_mesh| {
        chunk_mesh.light_texture.uploadTopSouthWestOverlap(chunk);
    }

    if (neighbor_chunk_meshes.chunk_meshes.get(.top_north_east)) |chunk_mesh| {
        chunk_mesh.light_texture.uploadBottomSouthWestOverlap(chunk);
    }

    if (neighbor_chunk_meshes.chunk_meshes.get(.south_west)) |chunk_mesh| {
        chunk_mesh.light_texture.uploadNorthEastOverlap(chunk);
    }

    if (neighbor_chunk_meshes.chunk_meshes.get(.bottom_south_west)) |chunk_mesh| {
        chunk_mesh.light_texture.uploadTopNorthEastOverlap(chunk);
    }

    if (neighbor_chunk_meshes.chunk_meshes.get(.top_south_west)) |chunk_mesh| {
        chunk_mesh.light_texture.uploadBottomNorthEastOverlap(chunk);
    }

    if (neighbor_chunk_meshes.chunk_meshes.get(.south_east)) |chunk_mesh| {
        chunk_mesh.light_texture.uploadNorthWestOverlap(chunk);
    }

    if (neighbor_chunk_meshes.chunk_meshes.get(.bottom_south_east)) |chunk_mesh| {
        chunk_mesh.light_texture.uploadTopNorthWestOverlap(chunk);
    }

    if (neighbor_chunk_meshes.chunk_meshes.get(.top_south_east)) |chunk_mesh| {
        chunk_mesh.light_texture.uploadBottomNorthWestOverlap(chunk);
    }

    if (neighbor_chunk_meshes.chunk_meshes.get(.bottom)) |chunk_mesh| {
        chunk_mesh.light_texture.uploadTopOverlap(chunk);
    }

    if (neighbor_chunk_meshes.chunk_meshes.get(.top)) |chunk_mesh| {
        chunk_mesh.light_texture.uploadBottomOverlap(chunk);
    }
}

pub fn generateCommands(world_mesh: *WorldMesh, gpa: std.mem.Allocator) !void {
    for (BlockLayer.values) |block_layer| {
        const world_mesh_layer = &world_mesh.layers[block_layer.idx()];
        world_mesh_layer.command.data.clearRetainingCapacity();

        for (world_mesh.visible_chunk_meshes.items) |visible_chunk_mesh| {
            const chunk_pos = visible_chunk_mesh.pos;
            const chunk_mesh_pos = chunk_pos.toVec3f();
            const visibility = visible_chunk_mesh.visibility;

            const chunk_mesh = world_mesh.chunk_meshes.get(chunk_pos) orelse unreachable;

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
                        .chunk_mesh_pos = chunk_mesh_pos,
                        .light_texture = chunk_mesh.light_texture.descriptor,
                    };

                    try world_mesh_layer.command.data.append(gpa, command);

                    starting_offset = 0;
                    total_size = 0;
                }

                offset += face_size;
            }

            if (total_size != 0) {
                const command: DrawArraysIndirectCommand = .{
                    .first_vertex = @intCast(starting_offset * 6),
                    .count = @intCast(total_size * 6),
                    .chunk_mesh_pos = chunk_mesh_pos,
                    .light_texture = chunk_mesh.light_texture.descriptor,
                };

                try world_mesh_layer.command.data.append(gpa, command);
            }
        }
    }
}

pub fn uploadMesh(world_mesh: *WorldMesh) void {
    for (&world_mesh.layers) |*world_mesh_layer| {
        world_mesh_layer.mesh.ssbo.upload(world_mesh_layer.mesh.data.items) catch |err| switch (err) {
            error.DataTooLarge => {
                world_mesh_layer.mesh.ssbo.resize(world_mesh_layer.mesh.data.items.len, WorldMesh.WorldMeshLayer.MESH_INCREMENT_SIZE);
                world_mesh_layer.mesh.ssbo.upload(world_mesh_layer.mesh.data.items) catch unreachable;
            },
            else => unreachable,
        };
    }
}

pub fn uploadCommands(world_mesh: *WorldMesh) void {
    for (&world_mesh.layers) |*world_mesh_layer| {
        world_mesh_layer.command.ssbo.upload(world_mesh_layer.command.data.items) catch |err| switch (err) {
            error.DataTooLarge => {
                world_mesh_layer.command.ssbo.resize(world_mesh_layer.command.data.items.len, WorldMesh.WorldMeshLayer.COMMAND_INCREMENT_SIZE);
                world_mesh_layer.command.ssbo.upload(world_mesh_layer.command.data.items) catch unreachable;
            },
            else => unreachable,
        };

        // for chunks_bb frag shader
        // world_mesh_layer.command.bind(6 + layer_idx);
    }
}
