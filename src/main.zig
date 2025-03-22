const std = @import("std");
const glfw = @import("glfw");
const gl = @import("gl");
const zstbi = @import("zstbi");
const print = std.debug.print;

const World = @import("World.zig");
const Chunk = @import("Chunk.zig");
const Block = @import("block.zig").Block;
const Side = @import("side.zig").Side;
const DedupQueue = @import("dedup_queue.zig").DedupQueue;

const SingleChunkMeshLayers = @import("SingleChunkMeshLayers.zig");
const ShaderProgram = @import("ShaderProgram.zig");
const Matrix4x4f = @import("Matrix4x4f.zig");
const Vec3f = @import("vec3f.zig").Vec3f;

const Texture2D = @import("Texture2D.zig");
const TextureArray2D = @import("TextureArray2D.zig");
const ui = @import("ui.zig");

pub const std_options: std.Options = .{
    .log_level = .info,
};

var procs: gl.ProcTable = undefined;

var chunks_shader_program: ShaderProgram = undefined;
var chunks_bb_shader_program: ShaderProgram = undefined;
var chunks_debug_shader_program: ShaderProgram = undefined;
var text_shader_program: ShaderProgram = undefined;

var view_matrix: Matrix4x4f = undefined;
var projection_matrix: Matrix4x4f = undefined;
var view_projection_matrix: Matrix4x4f = undefined;

var camera_pitch: gl.float = 0.0; // up and down
var camera_yaw: gl.float = 0.0; // left and right

var camera_position = Vec3f.new(0.0, 6.0, 0.0);
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
    chunks_shader_program.setUniformMatrix4f("uViewProjection", view_projection_matrix);
    chunks_bb_shader_program.setUniformMatrix4f("uViewProjection", view_projection_matrix);
    chunks_debug_shader_program.setUniformMatrix4f("uViewProjection", view_projection_matrix);

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

    const camera_chunk_pos = camera_position.toChunkPos();

    for (chunk_mesh_layers.pos.buffer.items, 0..) |chunk_mesh_pos, chunk_mesh_idx_| {
        const chunk_pos = chunk_mesh_pos.toChunkPos();
        const chunk_mesh_idx = chunk_mesh_idx_ * 6;

        if (chunk_pos.equal(camera_chunk_pos)) {
            inline for (0..Block.Layer.len) |layer_idx| {
                const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];

                inline for (0..6) |face_idx| {
                    if (chunk_mesh_layer.len.items[chunk_mesh_idx + face_idx] > 0) {
                        chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + face_idx].instance_count = 1;
                        chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + face_idx].base_instance = 1;
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
            (point.dot(top_nrm) < -Chunk.Radius) or
            (point.dot(camera_direction.negate()) < -(far + Chunk.Radius)))
        {
            inline for (0..Block.Layer.len) |layer_idx| {
                const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];

                inline for (0..6) |face_idx| {
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + face_idx].instance_count = 0;
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + face_idx].base_instance = 0;
                }
            }

            continue;
        }

        const diff = camera_chunk_pos.subtract(chunk_pos);

        if (diff.x < 0) {
            inline for (0..Block.Layer.len) |layer_idx| {
                const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];

                if (chunk_mesh_layer.len.items[chunk_mesh_idx] > 0) {
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx].instance_count = 1;
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx].base_instance = 1;
                }

                chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 1].instance_count = 0;
                chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 1].base_instance = 0;
            }
        } else if (diff.x != 0) {
            inline for (0..Block.Layer.len) |layer_idx| {
                const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];

                chunk_mesh_layer.command.buffer.items[chunk_mesh_idx].instance_count = 0;
                chunk_mesh_layer.command.buffer.items[chunk_mesh_idx].base_instance = 0;

                if (chunk_mesh_layer.len.items[chunk_mesh_idx + 1] > 0) {
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 1].instance_count = 1;
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 1].base_instance = 1;
                }
            }
        } else {
            inline for (0..Block.Layer.len) |layer_idx| {
                const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];

                if (chunk_mesh_layer.len.items[chunk_mesh_idx] > 0) {
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx].instance_count = 1;
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx].base_instance = 1;
                }

                if (chunk_mesh_layer.len.items[chunk_mesh_idx + 1] > 0) {
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 1].instance_count = 1;
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 1].base_instance = 1;
                }
            }
        }

        if (diff.y < 0) {
            inline for (0..Block.Layer.len) |layer_idx| {
                const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];

                if (chunk_mesh_layer.len.items[chunk_mesh_idx + 2] > 0) {
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 2].instance_count = 1;
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 2].base_instance = 1;
                }

                chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 3].instance_count = 0;
                chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 3].base_instance = 0;
            }
        } else if (diff.y != 0) {
            inline for (0..Block.Layer.len) |layer_idx| {
                const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];

                chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 2].instance_count = 0;
                chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 2].base_instance = 0;

                if (chunk_mesh_layer.len.items[chunk_mesh_idx + 3] > 0) {
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 3].instance_count = 1;
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 3].base_instance = 1;
                }
            }
        } else {
            inline for (0..Block.Layer.len) |layer_idx| {
                const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];

                if (chunk_mesh_layer.len.items[chunk_mesh_idx + 2] > 0) {
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 2].instance_count = 1;
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 2].base_instance = 1;
                }

                if (chunk_mesh_layer.len.items[chunk_mesh_idx + 3] > 0) {
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 3].instance_count = 1;
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 3].base_instance = 1;
                }
            }
        }

        if (diff.z < 0) {
            inline for (0..Block.Layer.len) |layer_idx| {
                const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];

                if (chunk_mesh_layer.len.items[chunk_mesh_idx + 4] > 0) {
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 4].instance_count = 1;
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 4].base_instance = 1;
                }

                chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 5].instance_count = 0;
                chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 5].base_instance = 0;
            }
        } else if (diff.z > 0) {
            inline for (0..Block.Layer.len) |layer_idx| {
                const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];

                chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 4].instance_count = 0;
                chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 4].base_instance = 0;

                if (chunk_mesh_layer.len.items[chunk_mesh_idx + 5] > 0) {
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 5].instance_count = 1;
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 5].base_instance = 1;
                }
            }
        } else {
            inline for (0..Block.Layer.len) |layer_idx| {
                const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];

                if (chunk_mesh_layer.len.items[chunk_mesh_idx + 4] > 0) {
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 4].instance_count = 1;
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 4].base_instance = 1;
                }

                if (chunk_mesh_layer.len.items[chunk_mesh_idx + 5] > 0) {
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 5].instance_count = 1;
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + 5].base_instance = 1;
                }
            }
        }
    }
}

fn uploadCommandBuffers(chunk_mesh_layers: *const ChunkMeshLayers) void {
    inline for (0..Block.Layer.len) |layer_idx| {
        const chunk_mesh_layer = chunk_mesh_layers.layers[layer_idx];

        gl.NamedBufferSubData(
            chunk_mesh_layer.command.handle,
            0,
            @intCast(@sizeOf(DrawArraysIndirectCommand) * chunk_mesh_layer.command.buffer.items.len),
            @ptrCast(chunk_mesh_layer.command.buffer.items.ptr),
        );
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

    len: std.ArrayList(usize),
    mesh: ShaderStorageBuffer(SingleChunkMeshLayers.LocalPosAndModelIdx),
    command: ShaderStorageBuffer(DrawArraysIndirectCommand),

    pub fn new(allocator: std.mem.Allocator) Self {
        return .{
            .len = std.ArrayList(usize).init(allocator),
            .mesh = ShaderStorageBuffer(SingleChunkMeshLayers.LocalPosAndModelIdx).new(allocator),
            .command = ShaderStorageBuffer(DrawArraysIndirectCommand).new(allocator),
        };
    }
};

pub const ChunkMeshLayers = struct {
    layers: [Block.Layer.len]ChunkMeshBuffers,
    pos: ShaderStorageBuffer(Vec3f),

    pub fn new(allocator: std.mem.Allocator) @This() {
        var layers: [Block.Layer.len]ChunkMeshBuffers = undefined;

        inline for (0..Block.Layer.len) |i| {
            layers[i] = ChunkMeshBuffers.new(allocator);
        }

        return .{
            .layers = layers,
            .pos = ShaderStorageBuffer(Vec3f).new(allocator),
        };
    }
};

pub const ChunkBoundingBox = struct {
    const vertices = west ++ east ++ bottom ++ top ++ north ++ south;

    const west = [6]Vec3f{
        .{ .x = 0, .y = Chunk.Size, .z = Chunk.Size },
        .{ .x = 0, .y = Chunk.Size, .z = 0 },
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 0, .y = 0, .z = Chunk.Size },
        .{ .x = 0, .y = Chunk.Size, .z = Chunk.Size },
    };

    const east = [6]Vec3f{
        .{ .x = Chunk.Size, .y = 0, .z = 0 },
        .{ .x = Chunk.Size, .y = Chunk.Size, .z = 0 },
        .{ .x = Chunk.Size, .y = Chunk.Size, .z = Chunk.Size },
        .{ .x = Chunk.Size, .y = Chunk.Size, .z = Chunk.Size },
        .{ .x = Chunk.Size, .y = 0, .z = Chunk.Size },
        .{ .x = Chunk.Size, .y = 0, .z = 0 },
    };

    const bottom = [6]Vec3f{
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = Chunk.Size, .y = 0, .z = 0 },
        .{ .x = Chunk.Size, .y = 0, .z = Chunk.Size },
        .{ .x = Chunk.Size, .y = 0, .z = Chunk.Size },
        .{ .x = 0, .y = 0, .z = Chunk.Size },
        .{ .x = 0, .y = 0, .z = 0 },
    };

    const top = [6]Vec3f{
        .{ .x = Chunk.Size, .y = Chunk.Size, .z = Chunk.Size },
        .{ .x = Chunk.Size, .y = Chunk.Size, .z = 0 },
        .{ .x = 0, .y = Chunk.Size, .z = 0 },
        .{ .x = 0, .y = Chunk.Size, .z = 0 },
        .{ .x = 0, .y = Chunk.Size, .z = Chunk.Size },
        .{ .x = Chunk.Size, .y = Chunk.Size, .z = Chunk.Size },
    };

    const north = [6]Vec3f{
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 0, .y = Chunk.Size, .z = 0 },
        .{ .x = Chunk.Size, .y = Chunk.Size, .z = 0 },
        .{ .x = Chunk.Size, .y = Chunk.Size, .z = 0 },
        .{ .x = Chunk.Size, .y = 0, .z = 0 },
        .{ .x = 0, .y = 0, .z = 0 },
    };

    const south = [6]Vec3f{
        .{ .x = Chunk.Size, .y = Chunk.Size, .z = Chunk.Size },
        .{ .x = 0, .y = Chunk.Size, .z = Chunk.Size },
        .{ .x = 0, .y = 0, .z = Chunk.Size },
        .{ .x = 0, .y = 0, .z = Chunk.Size },
        .{ .x = Chunk.Size, .y = 0, .z = Chunk.Size },
        .{ .x = Chunk.Size, .y = Chunk.Size, .z = Chunk.Size },
    };
};

fn populateChunkMeshLayers(allocator: std.mem.Allocator, world: *World, chunk_mesh_layers: *ChunkMeshLayers) !void {
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

        try chunk_mesh_layers.pos.buffer.append(chunk_pos.toVec3f());

        if (chunk.num_of_air != 0 and chunk.num_of_air != Chunk.Volume) {
            try single_chunk_mesh_layers.generate(chunk, &neighbor_chunks);

            inline for (0..Block.Layer.len) |layer_idx| {
                const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];
                const single_chunk_mesh_layer = &single_chunk_mesh_layers.layers[layer_idx];

                inline for (0..6) |face_idx| {
                    const single_chunk_mesh_face = &single_chunk_mesh_layer.faces[face_idx];
                    const len: gl.uint = @intCast(single_chunk_mesh_face.items.len);

                    try chunk_mesh_layer.len.append(len);

                    const command = DrawArraysIndirectCommand{
                        .first_vertex = @intCast(chunk_mesh_layer.mesh.buffer.items.len * 6),
                        .count = @intCast(len * 6),
                        .instance_count = if (len > 0) 1 else 0,
                        .base_instance = 0,
                    };

                    try chunk_mesh_layer.command.buffer.append(command);
                    try chunk_mesh_layer.mesh.buffer.appendSlice(single_chunk_mesh_face.items);
                    single_chunk_mesh_face.clearRetainingCapacity();
                }
            }
        } else {
            inline for (0..Block.Layer.len) |layer_idx| {
                const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];

                try chunk_mesh_layer.len.appendNTimes(0, 6);

                inline for (0..6) |_| {
                    const command = DrawArraysIndirectCommand{
                        .first_vertex = @intCast(chunk_mesh_layer.mesh.buffer.items.len * 6),
                        .count = 0,
                        .instance_count = 0,
                        .base_instance = 0,
                    };

                    try chunk_mesh_layer.command.buffer.append(command);
                }
            }
        }
    }
}

pub const RaycastSide = enum {
    west,
    east,
    bottom,
    top,
    north,
    south,
    inside,
    out_of_bounds,
};

pub const RaycastResult = struct {
    pos: World.Pos,
    side: RaycastSide,
    block: ?Block,
};

pub fn raycast(world: *World, origin: Vec3f, direction: Vec3f) RaycastResult {
    var moving_position = origin.floor();

    const step = Vec3f.new(std.math.sign(direction.x), std.math.sign(direction.y), std.math.sign(direction.z));
    const delta_distance = Vec3f.fromScalar(direction.magnitude()).divide(direction).abs();
    var side_distance = step.multiply(moving_position.subtract(origin)).add(step.multiplyScalar(0.5).addScalar(0.5)).multiply(delta_distance);

    var mask = packed struct {
        x: bool,
        y: bool,
        z: bool,
    }{
        .x = false,
        .y = false,
        .z = false,
    };

    for (0..120) |_| {
        const block_world_pos = moving_position.toWorldPos();
        const block_or_null = world.getBlockOrNull(block_world_pos);

        if (block_or_null) |block| {
            if (block.isInteractable()) {
                const side: RaycastSide = expr: {
                    if (mask.x) {
                        if (step.x > 0) {
                            break :expr .west;
                        } else if (step.x < 0) {
                            break :expr .east;
                        }
                    } else if (mask.y) {
                        if (step.y > 0) {
                            break :expr .bottom;
                        } else if (step.y < 0) {
                            break :expr .top;
                        }
                    } else if (mask.z) {
                        if (step.z > 0) {
                            break :expr .north;
                        } else if (step.z < 0) {
                            break :expr .south;
                        }
                    }

                    break :expr .inside;
                };

                return .{
                    .pos = block_world_pos,
                    .side = side,
                    .block = block,
                };
            }
        }

        if (side_distance.x < side_distance.y) {
            if (side_distance.x < side_distance.z) {
                side_distance.x += delta_distance.x;
                moving_position.x += step.x;
                mask = .{ .x = true, .y = false, .z = false };
            } else {
                side_distance.z += delta_distance.z;
                moving_position.z += step.z;
                mask = .{ .x = false, .y = false, .z = true };
            }
        } else {
            if (side_distance.y < side_distance.z) {
                side_distance.y += delta_distance.y;
                moving_position.y += step.y;
                mask = .{ .x = false, .y = true, .z = false };
            } else {
                side_distance.z += delta_distance.z;
                moving_position.z += step.z;
                mask = .{ .x = false, .y = false, .z = true };
            }
        }
    }

    return .{
        .pos = moving_position.toWorldPos(),
        .side = .out_of_bounds,
        .block = null,
    };
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    zstbi.init(allocator);

    glfw.setErrorCallback(errorCallback);
    if (!glfw.init(.{})) {
        std.log.err("failed to initialize GLFW: {?s}", .{glfw.getErrorString()});
        return error.GLFWInitFailed;
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
        return error.WindowCreationFailed;
    };
    defer window.destroy();

    glfw.makeContextCurrent(window);

    // My iGPU (Intel UHD Graphics 620) says it supports GL 4.6, but glfw fails to init these functions:
    // - glGetnTexImage
    // - glGetnUniformdv
    // - glMultiDrawArraysIndirectCount
    // - glMultiDrawElementsIndirectCount
    const supports_gl46 = expr: {
        const glGetString: @FieldType(gl.ProcTable, "GetString") = @ptrCast(glfw.getProcAddress("glGetString").?);
        const version_str = glGetString(gl.VERSION).?;

        break :expr version_str[0] == '4' and version_str[2] == '6';
    };

    if (!procs.init(glfw.getProcAddress) and !supports_gl46) return error.ProcInitFailed;

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

    chunks_shader_program = try ShaderProgram.new(allocator, "assets/shaders/chunks_vs.glsl", "assets/shaders/chunks_fs.glsl");
    chunks_shader_program.setUniformMatrix4f("uViewProjection", view_projection_matrix);

    chunks_bb_shader_program = try ShaderProgram.new(allocator, "assets/shaders/chunks_bb_vs.glsl", "assets/shaders/chunks_bb_fs.glsl");
    chunks_bb_shader_program.setUniformMatrix4f("uViewProjection", view_projection_matrix);

    chunks_debug_shader_program = try ShaderProgram.new(allocator, "assets/shaders/chunks_debug_vs.glsl", "assets/shaders/chunks_debug_fs.glsl");
    chunks_debug_shader_program.setUniformMatrix4f("uViewProjection", view_projection_matrix);

    text_shader_program = try ShaderProgram.new(allocator, "assets/shaders/text_vs.glsl", "assets/shaders/text_fs.glsl");

    window.setInputModeCursor(.disabled);
    window.setCursorPos(prev_cursor_x, prev_cursor_y);
    window.setCursorPosCallback(cursorCallback);
    window.setFramebufferSizeCallback(framebufferSizeCallback);
    window.setKeyCallback(keyCallback);

    gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1);

    var block_images = std.ArrayList(zstbi.Image).init(allocator);

    for (Block.Texture.TEXTURES) |texture| {
        const image = try zstbi.Image.loadFromFile(texture.getPath(), 0);
        try block_images.append(image);
    }

    const block_textures = try TextureArray2D.initFromImages(block_images.items, 16, 16, .{
        .texture_format = .rgba8,
        .data_format = .rgba,
    });
    block_textures.bind(0);

    var font_image = try zstbi.Image.loadFromFile("assets/textures/font.png", 0);
    var glyph_images = try allocator.alloc(zstbi.Image, ui.Glyph.len);

    for (0..ui.Glyph.len) |glyph_idx| {
        const base_x = glyph_idx * 6;

        var glyph_image = try zstbi.Image.createEmpty(6, 6, 1, .{});

        var data_idx: usize = 0;
        for (0..6) |y| {
            for (0..6) |x_| {
                const x = base_x + x_;
                const image_idx = y * font_image.width + x;

                glyph_image.data[data_idx] = font_image.data[image_idx];
                data_idx += 1;
            }
        }

        glyph_images[glyph_idx] = glyph_image;
    }

    const font_texture = try TextureArray2D.initFromImages(glyph_images, 6, 6, .{
        .texture_format = .r8,
        .data_format = .r,
    });
    font_texture.bind(1);

    var indirect_light_image = try zstbi.Image.loadFromFile("assets/textures/indirect_light.png", 0);
    var indirect_light_data: [16]Vec3f = undefined;
    for (0..(indirect_light_image.data.len / 4)) |idx| {
        const vec3 = Vec3f{
            .x = @as(gl.float, @floatFromInt(indirect_light_image.data[idx * 4])) / 255.0,
            .y = @as(gl.float, @floatFromInt(indirect_light_image.data[idx * 4 + 1])) / 255.0,
            .z = @as(gl.float, @floatFromInt(indirect_light_image.data[idx * 4 + 2])) / 255.0,
        };

        indirect_light_data[idx] = vec3;
    }

    var indirect_light_buffer_handle: gl.uint = undefined;
    gl.CreateBuffers(1, @ptrCast(&indirect_light_buffer_handle));
    gl.NamedBufferStorage(
        indirect_light_buffer_handle,
        @intCast((@sizeOf(Vec3f)) * 16),
        @ptrCast(&indirect_light_data),
        gl.DYNAMIC_STORAGE_BIT,
    );
    gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 4, indirect_light_buffer_handle);

    var debug_timer = try std.time.Timer.start();

    debug_timer.reset();
    var world = try World.new(allocator);
    try world.generateWorld();

    var debug_time = @as(f64, @floatFromInt(debug_timer.lap())) / 1_000_000_000.0;
    std.log.info("Generating world done. {d} s", .{debug_time});

    debug_timer.reset();
    try world.propagateLights();

    debug_time = @as(f64, @floatFromInt(debug_timer.lap())) / 1_000_000_000.0;
    std.log.info("Indirect light propagation done. {d} s", .{debug_time});

    // const pyramid_pos = World.Pos{ .x = 0, .y = 22, .z = 0 };
    // const pyramid_height = 16;
    // var pyramid_size: usize = 33;
    // var offset: i16 = 0;

    // for (0..pyramid_height) |y_| {
    //     for (0..pyramid_size) |x_| {
    //         for (0..pyramid_size) |z_| {
    //             const x: i16 = @intCast(x_);
    //             const y: i16 = @intCast(y_);
    //             const z: i16 = @intCast(z_);

    //             var block = Block.air;
    //             if (x == pyramid_size - 1 or z == pyramid_size - 1 or
    //                 x == 0 or z == 0 or y == 0)
    //             {
    //                 block = Block.bricks;
    //             }

    //             const pos = pyramid_pos.add(.{ .x = x + offset, .y = y, .z = z + offset });
    //             try world.setBlockAndAffectLight(pos, block);
    //         }
    //     }

    //     pyramid_size -= 2;
    //     offset += 1;
    // }

    // try world.setBlockAndAffectLight(.{ .x = 16, .y = 37, .z = 16 }, .glass_tinted);

    debug_timer.reset();
    try world.propagateLights();

    debug_time = @as(f64, @floatFromInt(debug_timer.lap())) / 1_000_000_000.0;
    std.log.info("Light propagation done. {d} s", .{debug_time});

    var chunk_mesh_layers = ChunkMeshLayers.new(allocator);

    debug_timer.reset();
    try populateChunkMeshLayers(allocator, &world, &chunk_mesh_layers);

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
        @intCast((@sizeOf(Block.Vertex)) * Block.VERTEX_BUFFER.len),
        @ptrCast(Block.VERTEX_BUFFER.ptr),
        gl.DYNAMIC_STORAGE_BIT,
    );
    gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 0, vertex_buffer_handle);

    var vertex_idx_and_texture_idx_buffer_handle: gl.uint = undefined;
    gl.CreateBuffers(1, @ptrCast(&vertex_idx_and_texture_idx_buffer_handle));
    gl.NamedBufferStorage(
        vertex_idx_and_texture_idx_buffer_handle,
        @intCast((@sizeOf(Block.VertexIdxAndTextureIdx)) * Block.VERTEX_IDX_AND_TEXTURE_IDX_BUFFER.len),
        @ptrCast(Block.VERTEX_IDX_AND_TEXTURE_IDX_BUFFER.ptr),
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

    inline for (0..Block.Layer.len) |layer_idx| {
        const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];

        if (chunk_mesh_layer.mesh.buffer.items.len > 0) {
            gl.CreateBuffers(1, @ptrCast(&chunk_mesh_layer.mesh.handle));
            gl.NamedBufferStorage(
                chunk_mesh_layer.mesh.handle,
                @intCast((@sizeOf(SingleChunkMeshLayers.LocalPosAndModelIdx)) * chunk_mesh_layer.mesh.buffer.items.len),
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
        gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 6 + layer_idx, chunk_mesh_layer.command.handle);
    }

    var bounding_box_buffer_handle: gl.uint = undefined;
    gl.CreateBuffers(1, @ptrCast(&bounding_box_buffer_handle));
    gl.NamedBufferStorage(
        bounding_box_buffer_handle,
        @intCast(@sizeOf(Vec3f) * ChunkBoundingBox.vertices.len),
        @ptrCast(&ChunkBoundingBox.vertices),
        gl.DYNAMIC_STORAGE_BIT,
    );
    gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 5, bounding_box_buffer_handle);

    var text_list = std.ArrayList(ui.Text).init(allocator);

    try text_list.append(.{
        .pixel_x = 0,
        .pixel_y = 0,
        .text = "The quick brown fox jumps over the lazy dog",
    });

    try text_list.append(.{
        .pixel_x = 0,
        .pixel_y = 6,
        .text = "Lorem ipsum dolor sit amet",
    });

    var text_vertices = std.ArrayList(ui.Text.Vertex).init(allocator);
    const quarter_window_width = @divTrunc(window_width, 4);
    const quarter_window_height = @divTrunc(window_height, 4);
    const half_window_width_f = @as(gl.float, @floatFromInt(window_width)) / 2.0;
    const half_window_height_f = @as(gl.float, @floatFromInt(window_height)) / 2.0;
    const ui_scale = 2;
    const pixel_height = 6;
    const max_pixel_width = 6;
    const max_width: gl.float = @floatFromInt(max_pixel_width);

    for (text_list.items) |text| {
        var pixel_x = text.pixel_x - quarter_window_width;
        const pixel_y = quarter_window_height - text.pixel_y - pixel_height;

        const pixel_min_y = pixel_y;
        const pixel_max_y = pixel_y + pixel_height;

        const min_y = @as(gl.float, @floatFromInt(pixel_min_y * ui_scale)) / half_window_height_f;
        const max_y = @as(gl.float, @floatFromInt(pixel_max_y * ui_scale)) / half_window_height_f;

        for (text.text) |char| {
            const glyph = ui.Glyph.fromChar(char);
            const pixel_width: i32 = @intCast(glyph.getWidth());
            const idx: gl.uint = @intCast(glyph.idx());

            const pixel_min_x = pixel_x;
            const pixel_max_x = pixel_x + pixel_width;

            const min_x = @as(gl.float, @floatFromInt(pixel_min_x * ui_scale)) / half_window_width_f;
            const max_x = @as(gl.float, @floatFromInt(pixel_max_x * ui_scale)) / half_window_width_f;

            const width: gl.float = @floatFromInt(pixel_width);
            const max_u = width / max_width;

            try text_vertices.appendSlice(&.{
                .{ .x = max_x, .y = max_y, .u = max_u, .v = 0, .idx = idx },
                .{ .x = min_x, .y = max_y, .u = 0, .v = 0, .idx = idx },
                .{ .x = min_x, .y = min_y, .u = 0, .v = 1, .idx = idx },
                .{ .x = min_x, .y = min_y, .u = 0, .v = 1, .idx = idx },
                .{ .x = max_x, .y = min_y, .u = max_u, .v = 1, .idx = idx },
                .{ .x = max_x, .y = max_y, .u = max_u, .v = 0, .idx = idx },
            });

            pixel_x += pixel_width + 1;
        }
    }

    var text_buffer_handle: gl.uint = undefined;
    gl.CreateBuffers(1, @ptrCast(&text_buffer_handle));
    gl.NamedBufferStorage(
        text_buffer_handle,
        @intCast(@sizeOf(ui.Text.Vertex) * text_vertices.items.len),
        @ptrCast(text_vertices.items.ptr),
        gl.DYNAMIC_STORAGE_BIT,
    );
    gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 11, text_buffer_handle);

    var vao_handle: gl.uint = undefined;
    gl.GenVertexArrays(1, @ptrCast(&vao_handle));
    gl.BindVertexArray(vao_handle);

    gl.Enable(gl.DEPTH_TEST);
    gl.Enable(gl.CULL_FACE);
    gl.Enable(gl.BLEND);
    gl.PolygonOffset(1.0, 1.0);
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

    const movement_speed: gl.float = 16.0;
    var timer = try std.time.Timer.start();

    while (!window.shouldClose()) {
        gl.ClearColor(0.47843137254901963, 0.6588235294117647, 0.9921568627450981, 1.0);
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

        if (window.getKey(glfw.Key.h) == .press) {
            const result = raycast(&world, camera_position, camera_direction);
            const world_pos = result.pos;
            const chunk_pos = world_pos.toChunkPos();
            const local_pos = world_pos.toLocalPos();
            const side = result.side;

            switch (side) {
                else => {
                    const light = try world.getLight(world_pos.add(World.Pos.Offsets[@intFromEnum(side)]));

                    std.log.info("at w[{} {} {}], c[{} {} {}], l[{} {} {}]:\n - block: {s}\n - light on {s} side: [{} {} {} {}]", .{
                        world_pos.x,
                        world_pos.y,
                        world_pos.z,
                        chunk_pos.x,
                        chunk_pos.y,
                        chunk_pos.z,
                        local_pos.x,
                        local_pos.y,
                        local_pos.z,
                        if (result.block) |block| @tagName(block) else "null",
                        @tagName(side),
                        light.red,
                        light.green,
                        light.blue,
                        light.indirect,
                    });
                },

                .inside => {
                    const light = try world.getLight(world_pos);

                    std.log.info("at [{} {} {}]:\n - block: {s}\n - light inside: [{} {} {} {}]", .{
                        world_pos.x,
                        world_pos.y,
                        world_pos.z,
                        if (result.block) |block| @tagName(block) else "null",
                        light.red,
                        light.green,
                        light.blue,
                        light.indirect,
                    });
                },

                .out_of_bounds => {
                    std.log.info("at [{} {} {}]:\n - block: {s}", .{
                        world_pos.x,
                        world_pos.y,
                        world_pos.z,
                        if (result.block) |block| @tagName(block) else "null",
                    });
                },
            }
        }

        if (camera_angles_changed or camera_moved) {
            if (camera_angles_changed) {
                camera_angles_changed = false;
                cacheCameraDirectionAndRight();
            }

            cacheViewMatrix();
            cacheViewProjectionMatrix();
            chunks_shader_program.setUniformMatrix4f("uViewProjection", view_projection_matrix);
            chunks_shader_program.setUniform3f("uCameraPosition", camera_position.x, camera_position.y, camera_position.z);

            chunks_bb_shader_program.setUniformMatrix4f("uViewProjection", view_projection_matrix);
            chunks_debug_shader_program.setUniformMatrix4f("uViewProjection", view_projection_matrix);
        }

        cullChunkFacesAndFrustum(&chunk_mesh_layers);
        uploadCommandBuffers(&chunk_mesh_layers);

        chunks_shader_program.bind();
        inline for (0..Block.Layer.len) |layer_idx| {
            const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];

            if (chunk_mesh_layer.mesh.buffer.items.len > 0) {
                gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 3, chunk_mesh_layer.mesh.handle);
                gl.BindBuffer(gl.DRAW_INDIRECT_BUFFER, chunk_mesh_layer.command.handle);

                gl.MemoryBarrier(gl.SHADER_STORAGE_BARRIER_BIT);
                gl.MultiDrawArraysIndirect(gl.TRIANGLES, null, @intCast(chunk_mesh_layer.command.buffer.items.len), 0);
                gl.MemoryBarrier(gl.SHADER_STORAGE_BARRIER_BIT);
            }
        }

        for (0..chunk_mesh_layers.pos.buffer.items.len) |chunk_mesh_idx_| {
            const chunk_mesh_idx = chunk_mesh_idx_ * 6;

            inline for (0..Block.Layer.len) |layer_idx| {
                const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];

                inline for (0..6) |face_idx| {
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + face_idx].instance_count = 0;
                }
            }
        }
        uploadCommandBuffers(&chunk_mesh_layers);

        chunks_bb_shader_program.bind();
        gl.Enable(gl.POLYGON_OFFSET_FILL);
        gl.DepthMask(gl.FALSE);
        gl.ColorMask(gl.FALSE, gl.FALSE, gl.FALSE, gl.FALSE);

        gl.MemoryBarrier(gl.SHADER_STORAGE_BARRIER_BIT);
        gl.DrawArraysInstanced(gl.TRIANGLES, 0, 36, @intCast(chunk_mesh_layers.pos.buffer.items.len));
        gl.MemoryBarrier(gl.SHADER_STORAGE_BARRIER_BIT);

        gl.DepthMask(gl.TRUE);
        gl.ColorMask(gl.TRUE, gl.TRUE, gl.TRUE, gl.TRUE);
        gl.Disable(gl.POLYGON_OFFSET_FILL);

        chunks_debug_shader_program.bind();
        gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE);
        gl.DrawArraysInstanced(gl.TRIANGLES, 0, 36, @intCast(chunk_mesh_layers.pos.buffer.items.len));
        gl.PolygonMode(gl.FRONT_AND_BACK, gl.FILL);

        text_shader_program.bind();
        gl.DrawArrays(gl.TRIANGLES, 0, @intCast(text_vertices.items.len));

        delta_time = @floatCast(@as(f64, @floatFromInt(timer.lap())) / 1_000_000_000.0);

        window.swapBuffers();
        glfw.pollEvents();
    }

    for (block_images.items) |image_| {
        var image = image_;
        image.deinit();
    }

    for (glyph_images) |image_| {
        var image = image_;
        image.deinit();
    }

    indirect_light_image.deinit();
    font_image.deinit();

    zstbi.deinit();
}
