const std = @import("std");
const glfw = @import("mach-glfw");
const gl = @import("gl");
const zstbi = @import("zstbi");
const print = std.debug.print;

const Chunk = @import("Chunk.zig");
const Block = @import("block.zig").Block;

const mesh = @import("mesh.zig");
const ShaderProgram = @import("ShaderProgram.zig");
const Matrix4x4f = @import("Matrix4x4f.zig");
const Vec3f = @import("vec3f.zig").Vec3f;
const model = @import("model.zig");

const Texture2D = @import("Texture2D.zig");
const TextureArray2D = @import("TextureArray2D.zig");

pub const std_options: std.Options = .{
    .log_level = .info,
};

var shader_program: ShaderProgram = undefined;

var view_matrix: Matrix4x4f = undefined;
var projection_matrix: Matrix4x4f = undefined;
var view_projection_matrix: Matrix4x4f = undefined;

var camera_pitch: gl.float = 0.0; // up and down
var camera_yaw: gl.float = 0.0; // left and right

var camera_position = Vec3f.new(0.0, 0.0, 0.0);
var camera_direction: Vec3f = undefined;
var camera_horizontal_direction: Vec3f = undefined;
var camera_right: Vec3f = undefined;
const camera_up = Vec3f.new(0.0, 1.0, 0.0);

var camera_angles_changed = false;

const DEG_TO_RAD: gl.float = std.math.pi / 180.0;

fn cacheCameraDirectionAndRight() void {
    const yaw_rads = camera_yaw * DEG_TO_RAD;
    const pitch_rads = camera_pitch * DEG_TO_RAD;

    const xz_len = std.math.cos(pitch_rads);
    const x = xz_len * std.math.cos(yaw_rads);
    const y = std.math.sin(pitch_rads);
    const z = xz_len * std.math.sin(yaw_rads);

    camera_direction = Vec3f.new(x, y, z);
    camera_direction.normalizeInPlace();

    camera_horizontal_direction = Vec3f.new(x, 0, z);
    camera_horizontal_direction.normalizeInPlace();

    camera_right = camera_horizontal_direction.cross(camera_up);
    camera_right.normalizeInPlace();
}

fn cacheViewMatrix() void {
    view_matrix.lookTowardInPlace(camera_position, camera_direction, camera_up);
}

const INITIAL_WINDOW_WIDTH = 640;
const INITIAL_WINDOW_HEIGHT = 480;

var prev_cursor_x: gl.float = INITIAL_WINDOW_WIDTH / 2;
var prev_cursor_y: gl.float = INITIAL_WINDOW_HEIGHT / 2;
var mouse_speed: gl.float = 10.0;

var delta_time: gl.float = 1.0 / 60.0;

var window_width: gl.sizei = INITIAL_WINDOW_WIDTH;
var window_height: gl.sizei = INITIAL_WINDOW_HEIGHT;

var fov_x: gl.float = 90.0;
var aspect_ratio: gl.float = @as(gl.float, INITIAL_WINDOW_WIDTH) / @as(gl.float, INITIAL_WINDOW_HEIGHT);
var near: gl.float = 0.1;
var far: gl.float = 32 * Chunk.Size * std.math.sqrt(3.0);

fn cacheAspectRatio() void {
    aspect_ratio = @as(gl.float, @floatFromInt(window_width)) / @as(gl.float, @floatFromInt(window_height));
}

fn cacheProjectionMatrix() void {
    projection_matrix.perspectiveInPlace(fov_x, aspect_ratio, near, far);
}

fn cacheViewProjectionMatrix() void {
    view_projection_matrix = view_matrix.multiply(projection_matrix);
}

fn errorCallback(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    std.log.err("glfw: {}: {s}\n", .{ error_code, description });
}

fn keyCallback(window: glfw.Window, key: glfw.Key, scancode: i32, action: glfw.Action, mods: glfw.Mods) void {
    _ = scancode;
    _ = mods;

    switch (key) {
        .escape => if (action == .press) {
            window.setShouldClose(true);
        },
        else => {},
    }
}

fn cursorCallback(window: glfw.Window, cursor_x: f64, cursor_y: f64) void {
    _ = window;

    const sensitivity = mouse_speed * delta_time;

    const offset_x = (@as(gl.float, @floatCast(cursor_x)) - prev_cursor_x) * sensitivity;
    const offset_y = (prev_cursor_y - @as(gl.float, @floatCast(cursor_y))) * sensitivity;

    prev_cursor_x = @floatCast(cursor_x);
    prev_cursor_y = @floatCast(cursor_y);

    camera_yaw += offset_x;
    camera_pitch = std.math.clamp(camera_pitch + offset_y, -89.0, 89.0);

    camera_angles_changed = true;
}

fn framebufferSizeCallback(window: glfw.Window, width: u32, height: u32) void {
    _ = window;

    window_width = @intCast(width);
    window_height = @intCast(height);
    cacheAspectRatio();
    cacheProjectionMatrix();
    cacheViewProjectionMatrix();
    shader_program.setUniformMatrix4f("uViewProjection", view_projection_matrix);

    gl.Viewport(0, 0, window_width, window_height);
}

fn debugCallback(source: gl.@"enum", @"type": gl.@"enum", id: gl.uint, severity: gl.@"enum", length: gl.sizei, message: [*:0]const u8, user_params: ?*const anyopaque) callconv(gl.APIENTRY) void {
    _ = user_params;
    _ = length;

    const source_str = switch (source) {
        gl.DEBUG_SOURCE_API => "api",
        gl.DEBUG_SOURCE_APPLICATION => "application",
        gl.DEBUG_SOURCE_THIRD_PARTY => "third party",
        gl.DEBUG_SOURCE_WINDOW_SYSTEM => "window system",
        gl.DEBUG_SOURCE_SHADER_COMPILER => "shader compiler",
        else => "other",
    };

    const type_str = switch (@"type") {
        gl.DEBUG_TYPE_DEPRECATED_BEHAVIOR => "deprecated behavior",
        gl.DEBUG_TYPE_MARKER => "marker",
        gl.DEBUG_TYPE_UNDEFINED_BEHAVIOR => "undefined behavior",
        gl.DEBUG_TYPE_POP_GROUP => "pop group",
        gl.DEBUG_TYPE_PORTABILITY => "portability",
        gl.DEBUG_TYPE_PUSH_GROUP => "push group",
        gl.DEBUG_TYPE_ERROR => "error",
        gl.DEBUG_TYPE_PERFORMANCE => "performance",
        else => "other",
    };

    switch (severity) {
        gl.DEBUG_SEVERITY_HIGH => std.log.err("OpenGL Debug Message [id: {}]  Source: {s}  Type: {s}\n{s}", .{ id, source_str, type_str, message }),
        gl.DEBUG_SEVERITY_MEDIUM => std.log.warn("OpenGL Debug Message [id: {}]  Source: {s}  Type: {s}\n{s}", .{ id, source_str, type_str, message }),
        else => std.log.info("OpenGL Debug Message [id: {}]  Source: {s}  Type: {s}\n{s}", .{ id, source_str, type_str, message }),
    }
}

const CHUNK_DISTANCE = 32;

fn generateChunk(allocator: std.mem.Allocator, rand: std.Random, chunk_x_: usize, chunk_z_: usize) !Chunk {
    const chunk_x = @as(i16, @intCast(chunk_x_)) - CHUNK_DISTANCE;
    const chunk_z = @as(i16, @intCast(chunk_z_)) - CHUNK_DISTANCE;

    var additional_height: u5 = 0;
    if (chunk_x_ == (CHUNK_DISTANCE * 2 - 1) or chunk_z_ == (CHUNK_DISTANCE * 2 - 1)) {
        additional_height = 16;
    } else if (chunk_x_ == 0 or chunk_z_ == 0) {
        additional_height = 24;
    }

    const chunk = try Chunk.new(allocator, .{ .x = chunk_x, .y = 0, .z = chunk_z }, .air);

    for (0..Chunk.Size) |x_| {
        for (0..Chunk.Size) |z_| {
            const x: u5 = @intCast(x_);
            const z: u5 = @intCast(z_);

            const height = rand.intRangeAtMost(u5, 1, 7) + additional_height;

            for (0..height) |y_| {
                const y: u5 = @intCast(y_);

                const block: Block = if (y == height - 1) .grass else .stone;
                chunk.setBlock(.{ .x = x, .y = y, .z = z }, block);
            }

            if (height < 5) {
                for (1..5) |y_| {
                    const y: u5 = @intCast(y_);

                    if (chunk.getBlock(.{ .x = x, .y = y, .z = z }) == .air) {
                        chunk.setBlock(.{ .x = x, .y = y, .z = z }, .water);
                    }
                }
            }
        }
    }

    return chunk;
}

fn generateChunks(allocator: std.mem.Allocator, rand: std.Random, chunks: *std.AutoHashMap(Chunk.Pos, Chunk)) !void {
    for (0..CHUNK_DISTANCE * 2) |chunk_x_| {
        for (0..CHUNK_DISTANCE * 2) |chunk_z_| {
            const chunk = try generateChunk(allocator, rand, chunk_x_, chunk_z_);
            try chunks.put(chunk.pos, chunk);
        }
    }
}

const DrawArraysIndirectCommand = packed struct {
    count: gl.uint,
    instance_count: gl.uint,
    first_vertex: gl.uint,
    base_instance: gl.uint,
};

fn extractPlanesFromViewProjection(matrix: Matrix4x4f, left: *[4]gl.float, right: *[4]gl.float, bottom: *[4]gl.float, top: *[4]gl.float) void {
    for (0..4) |i| {
        left[i] = matrix.data[i * 4 + 3] + matrix.data[i * 4 + 0];
        right[i] = matrix.data[i * 4 + 3] - matrix.data[i * 4 + 0];
        bottom[i] = matrix.data[i * 4 + 3] + matrix.data[i * 4 + 1];
        top[i] = matrix.data[i * 4 + 3] - matrix.data[i * 4 + 1];
    }
}

fn cullChunkFacesAndFrustum(chunk_mesh_layers: *ChunkMeshLayers) void {
    var left: [4]gl.float = @splat(0);
    var right: [4]gl.float = @splat(0);
    var bottom: [4]gl.float = @splat(0);
    var top: [4]gl.float = @splat(0);

    extractPlanesFromViewProjection(view_projection_matrix, &left, &right, &bottom, &top);

    var left_nrm = Vec3f.new(left[0], left[1], left[2]);
    left_nrm.normalizeInPlace();

    var right_nrm = Vec3f.new(right[0], right[1], right[2]);
    right_nrm.normalizeInPlace();

    var bottom_nrm = Vec3f.new(bottom[0], bottom[1], bottom[2]);
    bottom_nrm.normalizeInPlace();

    var top_nrm = Vec3f.new(top[0], top[1], top[2]);
    top_nrm.normalizeInPlace();

    const camera_pos = camera_position.toChunkPos();

    for (chunk_mesh_layers.pos.buffer.items, 0..) |chunk_mesh_pos, chunk_mesh_idx_| {
        const chunk_pos = chunk_mesh_pos.toChunkPos();
        const chunk_mesh_idx = chunk_mesh_idx_ * 6;

        if (chunk_pos.equal(camera_pos)) {
            inline for (0..2) |layer_idx| {
                const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];

                inline for (0..6) |face_idx| {
                    if (chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + face_idx].base_instance > 0) {
                        chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + face_idx].instance_count = 1;
                    }
                }
            }

            continue;
        }

        const point = chunk_mesh_pos.addScalar(Chunk.Center).subtract(camera_position);
        if ((point.dot(camera_direction) < -Chunk.Radius) or
            (point.dot(left_nrm) < -Chunk.Radius) or
            (point.dot(right_nrm) < -Chunk.Radius) or
            (point.dot(bottom_nrm) < -Chunk.Radius) or
            (point.dot(top_nrm) < -Chunk.Radius))
        {
            inline for (0..2) |layer_idx| {
                const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];

                inline for (0..6) |face_idx| {
                    if (chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + face_idx].base_instance > 0) {
                        chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + face_idx].instance_count = 0;
                    }
                }
            }

            continue;
        }

        const diff = camera_pos.subtract(chunk_pos);

        if (diff.x < 0) {
            inline for (0..2) |layer_idx| {
                const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];

                if (chunk_mesh_layer.command.buffer.items[chunk_mesh_idx].base_instance > 0) {
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx].instance_count = 1;
                }

                chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 1].instance_count = 0;
            }
        } else if (diff.x > 0) {
            inline for (0..2) |layer_idx| {
                const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];

                chunk_mesh_layer.command.buffer.items[chunk_mesh_idx].instance_count = 0;

                if (chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 1].base_instance > 0) {
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 1].instance_count = 1;
                }
            }
        } else {
            inline for (0..2) |layer_idx| {
                const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];

                if (chunk_mesh_layer.command.buffer.items[chunk_mesh_idx].base_instance > 0) {
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx].instance_count = 1;
                }

                if (chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 1].base_instance > 0) {
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 1].instance_count = 1;
                }
            }
        }

        if (diff.y < 0) {
            inline for (0..2) |layer_idx| {
                const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];

                if (chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 2].base_instance > 0) {
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 2].instance_count = 1;
                }

                chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 3].instance_count = 0;
            }
        } else if (diff.y > 0) {
            inline for (0..2) |layer_idx| {
                const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];

                chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 2].instance_count = 0;

                if (chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 3].base_instance > 0) {
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 3].instance_count = 1;
                }
            }
        } else {
            inline for (0..2) |layer_idx| {
                const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];

                if (chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 2].base_instance > 0) {
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 2].instance_count = 1;
                }

                if (chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 3].base_instance > 0) {
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 3].instance_count = 1;
                }
            }
        }

        if (diff.z < 0) {
            inline for (0..2) |layer_idx| {
                const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];

                if (chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 4].base_instance > 0) {
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 4].instance_count = 1;
                }

                chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 5].instance_count = 0;
            }
        } else if (diff.z > 0) {
            inline for (0..2) |layer_idx| {
                const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];

                chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 4].instance_count = 0;

                if (chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 5].base_instance > 0) {
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 5].instance_count = 1;
                }
            }
        } else {
            inline for (0..2) |layer_idx| {
                const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];

                if (chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 4].base_instance > 0) {
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 4].instance_count = 1;
                }

                if (chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 5].base_instance > 0) {
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 5].instance_count = 1;
                }
            }
        }
    }
}

fn uploadCommandBuffers(chunk_mesh_layers: ChunkMeshLayers) void {
    inline for (0..2) |layer_idx| {
        const chunk_mesh_layer = chunk_mesh_layers.layers[layer_idx];

        gl.NamedBufferSubData(
            chunk_mesh_layer.command.handle,
            0,
            @intCast(@sizeOf(DrawArraysIndirectCommand) * chunk_mesh_layer.command.buffer.items.len),
            @ptrCast(chunk_mesh_layer.command.buffer.items.ptr),
        );
    }
}

const VertexIndices = struct {
    west: u32,
    east: u32,
    bottom: u32,
    top: u32,
    north: u32,
    south: u32,
};

fn populateVertexBuffer(vertex_buffer: *std.ArrayList(model.Vertex), model_id_to_vertex_indices: *std.AutoHashMap(model.ModelId, VertexIndices)) !void {
    // for all models
    inline for (.{model.SQUARE}) |block_model| {
        var vertex_indices: VertexIndices = undefined;

        vertex_indices.west = @intCast(vertex_buffer.items.len);
        try vertex_buffer.appendSlice(block_model.west);

        vertex_indices.east = @intCast(vertex_buffer.items.len);
        try vertex_buffer.appendSlice(block_model.east);

        vertex_indices.bottom = @intCast(vertex_buffer.items.len);
        try vertex_buffer.appendSlice(block_model.bottom);

        vertex_indices.top = @intCast(vertex_buffer.items.len);
        try vertex_buffer.appendSlice(block_model.top);

        vertex_indices.north = @intCast(vertex_buffer.items.len);
        try vertex_buffer.appendSlice(block_model.north);

        vertex_indices.south = @intCast(vertex_buffer.items.len);
        try vertex_buffer.appendSlice(block_model.south);

        try model_id_to_vertex_indices.put(block_model.id, vertex_indices);
    }
}

fn populateVertexIdxAndTextureIdxBuffer(model_id_to_vertex_indices: std.AutoHashMap(model.ModelId, VertexIndices), vertex_idx_and_texture_idx_buffer: *std.ArrayList(model.VertexIdxAndTextureIdx), block_to_face_indices: *std.AutoHashMap(Block, mesh.FaceIndices)) !void {
    var face_idx: u17 = 0;
    inline for (Block.blocks_with_a_model) |block| {
        const block_model = block.getModel();
        const texture_idx = block.getTextureIdx();
        const vertex_indices = model_id_to_vertex_indices.get(block_model.id) orelse std.debug.panic("Should be impossible", .{});
        var face_indices: mesh.FaceIndices = undefined;

        {
            face_indices.west = face_idx;
            face_idx += 1;
            const vertex_idx_and_texture_idx = model.VertexIdxAndTextureIdx{
                .vertex_idx = vertex_indices.west,
                .texture_idx = texture_idx,
            };
            try vertex_idx_and_texture_idx_buffer.append(vertex_idx_and_texture_idx);
        }

        {
            face_indices.east = face_idx;
            face_idx += 1;
            const vertex_idx_and_texture_idx = model.VertexIdxAndTextureIdx{
                .vertex_idx = vertex_indices.east,
                .texture_idx = texture_idx,
            };
            try vertex_idx_and_texture_idx_buffer.append(vertex_idx_and_texture_idx);
        }

        {
            face_indices.bottom = face_idx;
            face_idx += 1;
            const vertex_idx_and_texture_idx = model.VertexIdxAndTextureIdx{
                .vertex_idx = vertex_indices.bottom,
                .texture_idx = texture_idx,
            };
            try vertex_idx_and_texture_idx_buffer.append(vertex_idx_and_texture_idx);
        }

        {
            face_indices.top = face_idx;
            face_idx += 1;
            const vertex_idx_and_texture_idx = model.VertexIdxAndTextureIdx{
                .vertex_idx = vertex_indices.top,
                .texture_idx = texture_idx,
            };
            try vertex_idx_and_texture_idx_buffer.append(vertex_idx_and_texture_idx);
        }

        {
            face_indices.north = face_idx;
            face_idx += 1;
            const vertex_idx_and_texture_idx = model.VertexIdxAndTextureIdx{
                .vertex_idx = vertex_indices.north,
                .texture_idx = texture_idx,
            };
            try vertex_idx_and_texture_idx_buffer.append(vertex_idx_and_texture_idx);
        }

        {
            face_indices.south = face_idx;
            face_idx += 1;
            const vertex_idx_and_texture_idx = model.VertexIdxAndTextureIdx{
                .vertex_idx = vertex_indices.south,
                .texture_idx = texture_idx,
            };
            try vertex_idx_and_texture_idx_buffer.append(vertex_idx_and_texture_idx);
        }

        try block_to_face_indices.put(block, face_indices);
    }
}

fn ShaderStorageBuffer(comptime T: type) type {
    return struct {
        buffer: std.ArrayList(T),
        handle: gl.uint,

        pub fn new(allocator: std.mem.Allocator) @This() {
            return .{
                .buffer = std.ArrayList(T).init(allocator),
                .handle = 0,
            };
        }
    };
}

pub const ChunkMeshBuffers = struct {
    const Self = @This();

    len: std.ArrayList(gl.uint),
    mesh: ShaderStorageBuffer(mesh.LocalPosAndFaceIdx),
    command: ShaderStorageBuffer(DrawArraysIndirectCommand),

    pub fn new(allocator: std.mem.Allocator) Self {
        return .{
            .len = std.ArrayList(gl.uint).init(allocator),
            .mesh = ShaderStorageBuffer(mesh.LocalPosAndFaceIdx).new(allocator),
            .command = ShaderStorageBuffer(DrawArraysIndirectCommand).new(allocator),
        };
    }
};

pub const ChunkMeshLayers = struct {
    layers: [2]ChunkMeshBuffers,
    pos: ShaderStorageBuffer(Vec3f),

    pub fn new(allocator: std.mem.Allocator) @This() {
        var layers: [2]ChunkMeshBuffers = undefined;

        inline for (0..2) |i| {
            layers[i] = ChunkMeshBuffers.new(allocator);
        }

        return .{
            .layers = layers,
            .pos = ShaderStorageBuffer(Vec3f).new(allocator),
        };
    }
};

pub const SingleChunkMeshFaces = struct {
    const Self = @This();

    faces: [6]std.ArrayList(mesh.LocalPosAndFaceIdx),

    pub fn new(allocator: std.mem.Allocator) Self {
        var faces: [6]std.ArrayList(mesh.LocalPosAndFaceIdx) = undefined;

        for (0..6) |face_idx| {
            faces[face_idx] = std.ArrayList(mesh.LocalPosAndFaceIdx).init(allocator);
        }

        return .{ .faces = faces };
    }
};

pub const SingleChunkMeshLayers = struct {
    const Self = @This();

    layers: [2]SingleChunkMeshFaces,

    pub fn new(allocator: std.mem.Allocator) Self {
        var layers: [2]SingleChunkMeshFaces = undefined;

        for (0..2) |layer_idx| {
            layers[layer_idx] = SingleChunkMeshFaces.new(allocator);
        }

        return .{ .layers = layers };
    }
};

fn populateChunkMeshLayers(allocator: std.mem.Allocator, chunks: std.AutoHashMap(Chunk.Pos, Chunk), block_to_face_indices: std.AutoHashMap(Block, mesh.FaceIndices), chunk_mesh_layers: *ChunkMeshLayers) !void {
    var single_chunk_mesh_layers = SingleChunkMeshLayers.new(allocator);

    var chunk_iter = chunks.valueIterator();
    while (chunk_iter.next()) |chunk| {
        const pos = chunk.pos;
        const west_pos = Chunk.Pos{ .x = pos.x - 1, .y = pos.y, .z = pos.z };
        const east_pos = Chunk.Pos{ .x = pos.x + 1, .y = pos.y, .z = pos.z };
        const north_pos = Chunk.Pos{ .x = pos.x, .y = pos.y, .z = pos.z - 1 };
        const south_pos = Chunk.Pos{ .x = pos.x, .y = pos.y, .z = pos.z + 1 };

        const neighbors = mesh.NeighborChunks{
            .west = chunks.get(west_pos),
            .east = chunks.get(east_pos),
            .north = chunks.get(north_pos),
            .south = chunks.get(south_pos),
        };

        try chunk_mesh_layers.pos.buffer.append(pos.toVec3f());

        try mesh.generate(&single_chunk_mesh_layers, block_to_face_indices, chunk.*, &neighbors);

        inline for (0..2) |layer_idx| {
            const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];
            const single_chunk_mesh_layer = &single_chunk_mesh_layers.layers[layer_idx];

            inline for (0..6) |face_idx| {
                const single_chunk_mesh_face = &single_chunk_mesh_layer.faces[face_idx];
                const len: gl.uint = @intCast(single_chunk_mesh_face.items.len);

                try chunk_mesh_layer.len.append(len);

                const draw_count: gl.uint = @intCast(len * 6);
                const command = DrawArraysIndirectCommand{
                    .count = draw_count,
                    .instance_count = if (len > 0) 1 else 0,
                    .first_vertex = @intCast(chunk_mesh_layer.mesh.buffer.items.len * 6),
                    .base_instance = if (len > 0) 1 else 0,
                };

                try chunk_mesh_layer.command.buffer.append(command);
                try chunk_mesh_layer.mesh.buffer.appendSlice(single_chunk_mesh_face.items);
                single_chunk_mesh_face.clearRetainingCapacity();
            }
        }
    }
}

var procs: gl.ProcTable = undefined;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    zstbi.init(allocator);
    defer zstbi.deinit();

    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rand = prng.random();

    glfw.setErrorCallback(errorCallback);
    if (!glfw.init(.{})) {
        std.log.err("failed to initialize GLFW: {?s}", .{glfw.getErrorString()});
        std.process.exit(1);
    }
    defer glfw.terminate();

    const debug_context = true;

    const window = glfw.Window.create(@intCast(window_width), @intCast(window_height), "Hello, mach-glfw!", null, null, .{
        .opengl_profile = .opengl_core_profile,
        .context_version_major = 4,
        .context_version_minor = 6,
        .context_debug = debug_context,
    }) orelse {
        std.log.err("failed to create GLFW window: {?s}", .{glfw.getErrorString()});
        std.process.exit(1);
    };
    defer window.destroy();

    glfw.makeContextCurrent(window);

    if (!procs.init(glfw.getProcAddress)) return error.InitFailed;

    gl.makeProcTableCurrent(&procs);
    defer gl.makeProcTableCurrent(null);

    var flags: gl.int = undefined;
    gl.GetIntegerv(gl.CONTEXT_FLAGS, @ptrCast(&flags));
    if (flags & gl.CONTEXT_FLAG_DEBUG_BIT > 0) {
        gl.Enable(gl.DEBUG_OUTPUT);
        gl.Enable(gl.DEBUG_OUTPUT_SYNCHRONOUS);
        gl.DebugMessageCallback(debugCallback, null);
        gl.DebugMessageControl(gl.DONT_CARE, gl.DONT_CARE, gl.DONT_CARE, 0, null, gl.TRUE);
    } else if (debug_context) {
        std.log.err("Failed to load OpenGL debug context", .{});
    }

    cacheCameraDirectionAndRight();
    view_matrix = Matrix4x4f.lookToward(camera_position, camera_direction, camera_up);
    projection_matrix = Matrix4x4f.perspective(fov_x, aspect_ratio, near, far);
    cacheViewProjectionMatrix();

    shader_program = try ShaderProgram.new(allocator, "assets/shaders/vs.glsl", "assets/shaders/fs.glsl");
    shader_program.bind();
    shader_program.setUniformMatrix4f("uViewProjection", view_projection_matrix);

    window.setInputModeCursor(.disabled);
    window.setCursorPos(prev_cursor_x, prev_cursor_y);
    window.setCursorPosCallback(cursorCallback);
    window.setFramebufferSizeCallback(framebufferSizeCallback);
    window.setKeyCallback(keyCallback);

    var cobble_image = try zstbi.Image.loadFromFile("assets/textures/cobble.png", 0);
    defer cobble_image.deinit();

    var grass_image = try zstbi.Image.loadFromFile("assets/textures/grass.png", 0);
    defer grass_image.deinit();

    var bricks_image = try zstbi.Image.loadFromFile("assets/textures/bricks.png", 0);
    defer bricks_image.deinit();

    var water_image = try zstbi.Image.loadFromFile("assets/textures/water.png", 0);
    defer water_image.deinit();

    var ice_image = try zstbi.Image.loadFromFile("assets/textures/ice.png", 0);
    defer ice_image.deinit();

    var glass_image = try zstbi.Image.loadFromFile("assets/textures/glass.png", 0);
    defer glass_image.deinit();

    var images = std.ArrayList(zstbi.Image).init(allocator);
    try images.append(cobble_image);
    try images.append(grass_image);
    try images.append(bricks_image);
    try images.append(water_image);
    try images.append(ice_image);
    try images.append(glass_image);

    const texture_array = try TextureArray2D.new(images.items, 16, 16, .{
        .wrap_s = .clamp_to_edge,
        .wrap_t = .clamp_to_edge,
        .min_filter = .nearest,
        .mag_filter = .nearest,
    });
    texture_array.bind(0);

    var vertex_buffer = std.ArrayList(model.Vertex).init(allocator);
    var model_id_to_vertex_indices = std.AutoHashMap(model.ModelId, VertexIndices).init(allocator);

    var debug_timer = try std.time.Timer.start();
    try populateVertexBuffer(&vertex_buffer, &model_id_to_vertex_indices);

    var debug_time = @as(f64, @floatFromInt(debug_timer.lap())) / 1_000_000_000.0;
    std.log.info("Vertex buffer done. {d} s", .{debug_time});

    var vertex_idx_and_texture_idx_buffer = std.ArrayList(model.VertexIdxAndTextureIdx).init(allocator);
    var block_to_face_indices = std.AutoHashMap(Block, mesh.FaceIndices).init(allocator);

    debug_timer.reset();
    try populateVertexIdxAndTextureIdxBuffer(model_id_to_vertex_indices, &vertex_idx_and_texture_idx_buffer, &block_to_face_indices);

    debug_time = @as(f64, @floatFromInt(debug_timer.lap())) / 1_000_000_000.0;
    std.log.info("Vertex idx buffer done. {d} s", .{debug_time});

    var chunks = std.AutoHashMap(Chunk.Pos, Chunk).init(allocator);

    debug_timer.reset();
    try generateChunks(allocator, rand, &chunks);

    debug_time = @as(f64, @floatFromInt(debug_timer.lap())) / 1_000_000_000.0;
    std.log.info("Generating chunks done. {d} s", .{debug_time});

    var chunk_mesh_layers = ChunkMeshLayers.new(allocator);

    debug_timer.reset();
    try populateChunkMeshLayers(allocator, chunks, block_to_face_indices, &chunk_mesh_layers);

    debug_time = @as(f64, @floatFromInt(debug_timer.lap())) / 1_000_000_000.0;
    std.log.info("Chunk mesh buffers done. {d} s", .{debug_time});

    debug_timer.reset();
    cullChunkFacesAndFrustum(&chunk_mesh_layers);

    debug_time = @as(f64, @floatFromInt(debug_timer.lap())) / 1_000_000_000.0;
    std.log.info("Culling done. {d} s", .{debug_time});

    var vertex_buffer_handle: gl.uint = undefined;
    gl.CreateBuffers(1, @ptrCast(&vertex_buffer_handle));
    gl.NamedBufferStorage(
        vertex_buffer_handle,
        @intCast((@sizeOf(model.Vertex)) * vertex_buffer.items.len),
        @ptrCast(vertex_buffer.items.ptr),
        gl.DYNAMIC_STORAGE_BIT,
    );
    gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 0, vertex_buffer_handle);

    var vertex_idx_and_texture_idx_buffer_handle: gl.uint = undefined;
    gl.CreateBuffers(1, @ptrCast(&vertex_idx_and_texture_idx_buffer_handle));
    gl.NamedBufferStorage(
        vertex_idx_and_texture_idx_buffer_handle,
        @intCast((@sizeOf(model.VertexIdxAndTextureIdx)) * vertex_idx_and_texture_idx_buffer.items.len),
        @ptrCast(vertex_idx_and_texture_idx_buffer.items.ptr),
        gl.DYNAMIC_STORAGE_BIT,
    );
    gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 1, vertex_idx_and_texture_idx_buffer_handle);

    gl.CreateBuffers(1, @ptrCast(&chunk_mesh_layers.pos.handle));
    gl.NamedBufferStorage(
        chunk_mesh_layers.pos.handle,
        @intCast(@sizeOf(Vec3f) * chunk_mesh_layers.pos.buffer.items.len),
        @ptrCast(chunk_mesh_layers.pos.buffer.items.ptr),
        gl.DYNAMIC_STORAGE_BIT,
    );
    gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 2, chunk_mesh_layers.pos.handle);

    inline for (0..2) |layer_idx| {
        const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];

        if (chunk_mesh_layer.mesh.buffer.items.len > 0) {
            gl.CreateBuffers(1, @ptrCast(&chunk_mesh_layer.mesh.handle));
            gl.NamedBufferStorage(
                chunk_mesh_layer.mesh.handle,
                @intCast((@sizeOf(mesh.LocalPosAndFaceIdx)) * chunk_mesh_layer.mesh.buffer.items.len),
                @ptrCast(chunk_mesh_layer.mesh.buffer.items.ptr),
                gl.DYNAMIC_STORAGE_BIT,
            );
        }

        gl.CreateBuffers(1, @ptrCast(&chunk_mesh_layer.command.handle));
        gl.NamedBufferStorage(
            chunk_mesh_layer.command.handle,
            @intCast(@sizeOf(DrawArraysIndirectCommand) * chunk_mesh_layer.command.buffer.items.len),
            @ptrCast(chunk_mesh_layer.command.buffer.items.ptr),
            gl.DYNAMIC_STORAGE_BIT | gl.MAP_READ_BIT | gl.MAP_WRITE_BIT,
        );
    }

    if (chunk_mesh_layers.layers[0].command.buffer.items.len != chunk_mesh_layers.layers[1].command.buffer.items.len) std.debug.panic("layers dont have the same amount of draw commands", .{});

    // var texture_handle_buffer_handle: gl.uint = undefined;
    // gl.CreateBuffers(1, @ptrCast(&texture_handle_buffer_handle));
    // gl.NamedBufferStorage(texture_handle_buffer_handle, @intCast(@sizeOf(gl.uint64) * texture_handle_buffer.items.len), @ptrCast(texture_handle_buffer.items.ptr), gl.DYNAMIC_STORAGE_BIT);
    // gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 4, texture_handle_buffer_handle);

    var vao_handle: gl.uint = undefined;
    gl.GenVertexArrays(1, @ptrCast(&vao_handle));
    gl.BindVertexArray(vao_handle);

    gl.Enable(gl.DEPTH_TEST);
    gl.Enable(gl.CULL_FACE);
    gl.Enable(gl.BLEND);
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

    const movement_speed: gl.float = 128.0;
    var timer = try std.time.Timer.start();

    while (!window.shouldClose()) {
        gl.ClearColor(0.1, 0.1, 0.2, 1.0);
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

        var camera_moved = false;

        if (window.getKey(glfw.Key.s) == .press) {
            camera_position.subtractInPlace(camera_horizontal_direction.multiplyScalar(movement_speed * delta_time));
            camera_moved = true;
        }
        if (window.getKey(glfw.Key.w) == .press) {
            camera_position.addInPlace(camera_horizontal_direction.multiplyScalar(movement_speed * delta_time));
            camera_moved = true;
        }
        if (window.getKey(glfw.Key.left_shift) == .press) {
            camera_position.subtractInPlace(camera_up.multiplyScalar(movement_speed * delta_time));
            camera_moved = true;
        }
        if (window.getKey(glfw.Key.space) == .press) {
            camera_position.addInPlace(camera_up.multiplyScalar(movement_speed * delta_time));
            camera_moved = true;
        }
        if (window.getKey(glfw.Key.a) == .press) {
            camera_position.subtractInPlace(camera_right.multiplyScalar(movement_speed * delta_time));
            camera_moved = true;
        }
        if (window.getKey(glfw.Key.d) == .press) {
            camera_position.addInPlace(camera_right.multiplyScalar(movement_speed * delta_time));
            camera_moved = true;
        }

        if (camera_angles_changed or camera_moved) {
            if (camera_angles_changed) {
                camera_angles_changed = false;
                cacheCameraDirectionAndRight();
            }

            cacheViewMatrix();
            cacheViewProjectionMatrix();
            shader_program.setUniformMatrix4f("uViewProjection", view_projection_matrix);

            cullChunkFacesAndFrustum(&chunk_mesh_layers);
            uploadCommandBuffers(chunk_mesh_layers);
        }

        inline for (0..2) |layer_idx| {
            const chunk_mesh_layer = chunk_mesh_layers.layers[layer_idx];

            if (chunk_mesh_layer.mesh.buffer.items.len > 0) {
                gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 3, chunk_mesh_layer.mesh.handle);
                gl.BindBuffer(gl.DRAW_INDIRECT_BUFFER, chunk_mesh_layer.command.handle);
                gl.MultiDrawArraysIndirect(gl.TRIANGLES, null, @intCast(chunk_mesh_layer.command.buffer.items.len), 0);
            }
        }

        delta_time = @floatCast(@as(f64, @floatFromInt(timer.lap())) / 1_000_000_000.0);

        window.swapBuffers();
        glfw.pollEvents();
    }
}
