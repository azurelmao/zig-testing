const std = @import("std");
const glfw = @import("glfw");
const gl = @import("gl");
const stbi = @import("zstbi");

const World = @import("World.zig");
const Chunk = @import("Chunk.zig");
const Block = @import("block.zig").Block;
const Side = @import("side.zig").Side;

const ShaderProgram = @import("ShaderProgram.zig");
const ShaderStorageBuffer = @import("buffer.zig").ShaderStorageBuffer;
const ShaderStorageBufferUnmanaged = @import("buffer.zig").ShaderStorageBufferUnmanaged;
const Vec3f = @import("vec3f.zig").Vec3f;
const Matrix4x4f = @import("Matrix4x4f.zig");
const Camera = @import("Camera.zig");
const Screen = @import("Screen.zig");
const TextureArray2D = @import("TextureArray2D.zig");
const Texture2D = @import("Texture2D.zig");
const ChunkMeshLayers = @import("ChunkMeshLayers.zig");
const ui = @import("ui.zig");
const chunk_bounding_box = @import("chunk_bounding_box.zig");

pub const std_options: std.Options = .{
    .log_level = .info,
};

var procs: gl.ProcTable = undefined;

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
    window.getUserPointer(WindowUserData).?.*.new_cursor_pos = .{
        .cursor_x = @floatCast(cursor_x),
        .cursor_y = @floatCast(cursor_y),
    };
}

fn framebufferSizeCallback(window: glfw.Window, window_width: u32, window_height: u32) void {
    window.getUserPointer(WindowUserData).?.*.new_window_size = .{
        .window_width = @intCast(window_width),
        .window_height = @intCast(window_height),
    };
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

fn onRaycast(allocator: std.mem.Allocator, world: *World, text_manager: *ui.TextManager, result: World.RaycastResult) !void {
    const world_pos = result.pos;
    const side = result.side;

    switch (side) {
        else => {
            try text_manager.append(allocator, .{
                .pixel_x = 0,
                .pixel_y = 48,
                .text = try std.fmt.allocPrint(allocator, "looking at: [x: {d} y: {d} z: {d}] on side: {s}", .{
                    world_pos.x,
                    world_pos.y,
                    world_pos.z,
                    @tagName(side),
                }),
            });

            try text_manager.append(allocator, .{
                .pixel_x = 0,
                .pixel_y = 54,
                .text = try std.fmt.allocPrint(allocator, "block: {s}", .{
                    if (result.block) |block| @tagName(block) else "null",
                }),
            });

            if (world.getLight(world_pos.add(World.Pos.Offsets[@intFromEnum(side)]))) |light| {
                try text_manager.append(allocator, .{
                    .pixel_x = 0,
                    .pixel_y = 60,
                    .text = try std.fmt.allocPrint(allocator, "light: [r: {} g: {} b: {} i: {}]", .{
                        light.red,
                        light.green,
                        light.blue,
                        light.indirect,
                    }),
                });
            } else |_| {
                try text_manager.append(allocator, .{
                    .pixel_x = 0,
                    .pixel_y = 60,
                    .text = try std.fmt.allocPrint(allocator, "light: out_of_bounds", .{}),
                });
            }
        },

        .inside => {
            const light = try world.getLight(world_pos);

            try text_manager.append(allocator, .{
                .pixel_x = 0,
                .pixel_y = 48,
                .text = try std.fmt.allocPrint(allocator, "looking at: [x: {d} y: {d} z: {d}] on side: {s}", .{
                    world_pos.x,
                    world_pos.y,
                    world_pos.z,
                    @tagName(side),
                }),
            });

            try text_manager.append(allocator, .{
                .pixel_x = 0,
                .pixel_y = 54,
                .text = try std.fmt.allocPrint(allocator, "block: {s}", .{
                    if (result.block) |block| @tagName(block) else "null",
                }),
            });

            try text_manager.append(allocator, .{
                .pixel_x = 0,
                .pixel_y = 60,
                .text = try std.fmt.allocPrint(allocator, "light: [r: {} g: {} b: {} i: {}]", .{
                    light.red,
                    light.green,
                    light.blue,
                    light.indirect,
                }),
            });
        },

        .out_of_bounds => {
            try text_manager.append(allocator, .{
                .pixel_x = 0,
                .pixel_y = 48,
                .text = try std.fmt.allocPrint(allocator, "looking at: [x: {d} y: {d} z: {d}] on side: {s}", .{
                    world_pos.x,
                    world_pos.y,
                    world_pos.z,
                    @tagName(side),
                }),
            });
        },
    }
}

const Settings = struct {
    ui_scale: gl.sizei = 3,
    mouse_speed: gl.float = 10.0,
    movement_speed: gl.float = 16.0,
};

const NewWindowSize = struct {
    window_width: gl.sizei,
    window_height: gl.sizei,
};

const NewCursorPos = struct {
    cursor_x: gl.float,
    cursor_y: gl.float,
};

const WindowUserData = struct {
    new_window_size: ?NewWindowSize = null,
    new_cursor_pos: ?NewCursorPos = null,
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    stbi.init(allocator);

    glfw.setErrorCallback(errorCallback);
    if (!glfw.init(.{})) {
        std.log.err("failed to initialize GLFW: {?s}", .{glfw.getErrorString()});
        return error.GLFWInitFailed;
    }
    defer glfw.terminate();

    const settings = Settings{};
    var screen = Screen{};
    var camera = Camera.init(.new(0, 0, 0), 0, 0, screen.aspect_ratio);

    const debug_context = true;

    const window = glfw.Window.create(@intCast(screen.window_width), @intCast(screen.window_height), "Natura ex Deus", null, null, .{
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

    var window_user_data = WindowUserData{};

    window.setUserPointer(@ptrCast(&window_user_data));

    window.setInputModeCursor(.disabled);
    window.setCursorPos(screen.prev_cursor_x, screen.prev_cursor_y);
    window.setCursorPosCallback(cursorCallback);
    window.setFramebufferSizeCallback(framebufferSizeCallback);
    window.setKeyCallback(keyCallback);

    var chunks_shader_program = try ShaderProgram.new(allocator, "assets/shaders/chunks_vs.glsl", "assets/shaders/chunks_fs.glsl");
    chunks_shader_program.setUniformMatrix4f("uViewProjection", camera.view_projection_matrix);

    var chunks_bb_shader_program = try ShaderProgram.new(allocator, "assets/shaders/chunks_bb_vs.glsl", "assets/shaders/chunks_bb_fs.glsl");
    chunks_bb_shader_program.setUniformMatrix4f("uViewProjection", camera.view_projection_matrix);

    var chunks_debug_shader_program = try ShaderProgram.new(allocator, "assets/shaders/chunks_debug_vs.glsl", "assets/shaders/chunks_debug_fs.glsl");
    chunks_debug_shader_program.setUniformMatrix4f("uViewProjection", camera.view_projection_matrix);
    chunks_debug_shader_program.setUniform2ui("uWindowSize", @intCast(screen.window_width), @intCast(screen.window_height));

    var text_shader_program = try ShaderProgram.new(allocator, "assets/shaders/text_vs.glsl", "assets/shaders/text_fs.glsl");

    gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1);

    var block_images = std.ArrayList(stbi.Image).init(allocator);

    for (Block.Texture.TEXTURES) |texture| {
        const image = try stbi.Image.loadFromFile(texture.getPath(), 0);
        try block_images.append(image);
    }

    const block_textures = try TextureArray2D.init(block_images.items, 16, 16, .{
        .texture_format = .rgba8,
        .data_format = .rgba,
    });
    block_textures.bind(0);

    var font_image = try stbi.Image.loadFromFile("assets/textures/font.png", 0);
    var glyph_images = try allocator.alloc(stbi.Image, ui.Glyph.len);

    for (0..ui.Glyph.len) |glyph_idx| {
        const base_x = glyph_idx * 6;

        var glyph_image = try stbi.Image.createEmpty(6, 6, 1, .{});

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

    const font_texture = try TextureArray2D.init(glyph_images, 6, 6, .{
        .texture_format = .r8,
        .data_format = .r,
    });
    font_texture.bind(1);

    var indirect_light_image = try stbi.Image.loadFromFile("assets/textures/indirect_light.png", 0);
    var indirect_light_data: [16]Vec3f = undefined;
    for (0..(indirect_light_image.data.len / 4)) |idx| {
        const vec3 = Vec3f{
            .x = @as(gl.float, @floatFromInt(indirect_light_image.data[idx * 4])) / 255.0,
            .y = @as(gl.float, @floatFromInt(indirect_light_image.data[idx * 4 + 1])) / 255.0,
            .z = @as(gl.float, @floatFromInt(indirect_light_image.data[idx * 4 + 2])) / 255.0,
        };

        indirect_light_data[idx] = vec3;
    }

    var indirect_light_buffer = ShaderStorageBufferUnmanaged(Vec3f).init(gl.DYNAMIC_STORAGE_BIT);
    indirect_light_buffer.initBufferAndBind(&indirect_light_data, 4);

    var debug_timer = try std.time.Timer.start();

    debug_timer.reset();
    var world = try World.init(30);
    try world.generate(allocator);

    var debug_time = @as(f64, @floatFromInt(debug_timer.lap())) / 1_000_000_000.0;
    std.log.info("Generating world done. {d} s", .{debug_time});

    debug_timer.reset();
    try world.propagateLights(allocator);

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
    try world.propagateLights(allocator);

    debug_time = @as(f64, @floatFromInt(debug_timer.lap())) / 1_000_000_000.0;
    std.log.info("Light propagation done. {d} s", .{debug_time});

    var chunk_mesh_layers = ChunkMeshLayers.init();

    debug_timer.reset();
    try chunk_mesh_layers.generate(allocator, &world);

    debug_time = @as(f64, @floatFromInt(debug_timer.lap())) / 1_000_000_000.0;
    std.log.info("Chunk mesh buffers done. {d} s", .{debug_time});

    debug_timer.reset();
    _ = chunk_mesh_layers.cull(&camera);

    debug_time = @as(f64, @floatFromInt(debug_timer.lap())) / 1_000_000_000.0;
    std.log.info("Culling done. {d} s", .{debug_time});

    var block_vertex_buffer = ShaderStorageBufferUnmanaged(Block.Vertex).init(gl.DYNAMIC_STORAGE_BIT);
    block_vertex_buffer.initBufferAndBind(Block.VERTEX_BUFFER, 0);

    var block_face_buffer = ShaderStorageBufferUnmanaged(Block.FaceVertex).init(gl.DYNAMIC_STORAGE_BIT);
    block_face_buffer.initBufferAndBind(Block.VERTEX_IDX_AND_TEXTURE_IDX_BUFFER, 1);

    chunk_mesh_layers.pos.initBufferAndBind(2);

    inline for (0..Block.Layer.len) |layer_idx| {
        const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];

        if (chunk_mesh_layer.mesh.buffer.items.len > 0) {
            chunk_mesh_layer.mesh.initBuffer();
        }

        chunk_mesh_layer.command.initBufferAndBind(6 + layer_idx);
    }

    var bounding_box_buffer = ShaderStorageBufferUnmanaged(Vec3f).init(gl.DYNAMIC_STORAGE_BIT);
    bounding_box_buffer.initBufferAndBind(chunk_bounding_box.vertices, 5);

    var bounding_box_lines_buffer = ShaderStorageBufferUnmanaged(Vec3f).init(gl.DYNAMIC_STORAGE_BIT);
    bounding_box_lines_buffer.initBufferAndBind(chunk_bounding_box.lines, 11);

    var text_manager = ui.TextManager.init();

    var vao_handle: gl.uint = undefined;
    gl.GenVertexArrays(1, @ptrCast(&vao_handle));
    gl.BindVertexArray(vao_handle);

    var offscreen_texture_handle: gl.uint = undefined;
    gl.CreateTextures(gl.TEXTURE_2D, 1, @ptrCast(&offscreen_texture_handle));
    gl.TextureStorage2D(offscreen_texture_handle, 1, gl.RGBA8, screen.window_width, screen.window_height);
    gl.BindTextureUnit(2, offscreen_texture_handle);

    var offscreen_framebuffer_handle: gl.uint = undefined;
    gl.CreateFramebuffers(1, @ptrCast(&offscreen_framebuffer_handle));
    gl.NamedFramebufferTexture(offscreen_framebuffer_handle, gl.COLOR_ATTACHMENT0, offscreen_texture_handle, 0);

    gl.Enable(gl.DEPTH_TEST);
    gl.Enable(gl.CULL_FACE);
    gl.Enable(gl.BLEND);
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

    var delta_time: gl.float = 1.0 / 60.0;
    var timer = try std.time.Timer.start();

    while (!window.shouldClose()) {
        var calc_view_matrix = false;
        var calc_projection_matrix = false;

        if (window.getKey(glfw.Key.s) == .press) {
            camera.position.subtractInPlace(camera.horizontal_direction.multiplyScalar(settings.movement_speed * delta_time));
            calc_view_matrix = true;
        }

        if (window.getKey(glfw.Key.w) == .press) {
            camera.position.addInPlace(camera.horizontal_direction.multiplyScalar(settings.movement_speed * delta_time));
            calc_view_matrix = true;
        }

        if (window.getKey(glfw.Key.left_shift) == .press) {
            camera.position.subtractInPlace(Camera.up.multiplyScalar(settings.movement_speed * delta_time));
            calc_view_matrix = true;
        }

        if (window.getKey(glfw.Key.space) == .press) {
            camera.position.addInPlace(Camera.up.multiplyScalar(settings.movement_speed * delta_time));
            calc_view_matrix = true;
        }

        if (window.getKey(glfw.Key.a) == .press) {
            camera.position.subtractInPlace(camera.right.multiplyScalar(settings.movement_speed * delta_time));
            calc_view_matrix = true;
        }

        if (window.getKey(glfw.Key.d) == .press) {
            camera.position.addInPlace(camera.right.multiplyScalar(settings.movement_speed * delta_time));
            calc_view_matrix = true;
        }

        if (window_user_data.new_cursor_pos) |new_cursor_pos| {
            const sensitivity = settings.mouse_speed * delta_time;

            const offset_x = (new_cursor_pos.cursor_x - screen.prev_cursor_x) * sensitivity;
            const offset_y = (screen.prev_cursor_y - new_cursor_pos.cursor_y) * sensitivity;

            screen.prev_cursor_x = new_cursor_pos.cursor_x;
            screen.prev_cursor_y = new_cursor_pos.cursor_y;

            camera.yaw += offset_x;
            camera.pitch = std.math.clamp(camera.pitch + offset_y, -89.0, 89.0);

            camera.calcDirectionAndRight();

            calc_view_matrix = true;
        }

        if (window_user_data.new_window_size) |new_window_size| {
            screen.window_width = new_window_size.window_width;
            screen.window_height = new_window_size.window_height;
            screen.window_width_f = @floatFromInt(screen.window_width);
            screen.window_height_f = @floatFromInt(screen.window_height);

            gl.Viewport(0, 0, screen.window_width, screen.window_height);

            gl.DeleteTextures(1, @ptrCast(&offscreen_texture_handle));
            gl.CreateTextures(gl.TEXTURE_2D, 1, @ptrCast(&offscreen_texture_handle));
            gl.TextureStorage2D(offscreen_texture_handle, 1, gl.RGBA8, screen.window_width, screen.window_height);
            gl.BindTextureUnit(2, offscreen_texture_handle);

            gl.DeleteFramebuffers(1, @ptrCast(&offscreen_framebuffer_handle));
            gl.CreateFramebuffers(1, @ptrCast(&offscreen_framebuffer_handle));
            gl.NamedFramebufferTexture(offscreen_framebuffer_handle, gl.COLOR_ATTACHMENT0, offscreen_texture_handle, 0);

            screen.calcAspectRatio();
            chunks_debug_shader_program.setUniform2ui("uWindowSize", @intCast(screen.window_width), @intCast(screen.window_height));

            calc_projection_matrix = true;
        }

        if (calc_view_matrix) {
            camera.calcViewMatrix();

            chunks_shader_program.setUniform3f("uCameraPosition", camera.position.x, camera.position.y, camera.position.z);
        }

        if (calc_projection_matrix) {
            camera.calcProjectionMatrix(screen.aspect_ratio);
        }

        const calc_view_projection_matrix = calc_view_matrix or calc_projection_matrix;
        if (calc_view_projection_matrix) {
            camera.calcViewProjectionMatrix();
            camera.calcFrustumPlanes();

            chunks_shader_program.setUniformMatrix4f("uViewProjection", camera.view_projection_matrix);
            chunks_bb_shader_program.setUniformMatrix4f("uViewProjection", camera.view_projection_matrix);
            chunks_debug_shader_program.setUniformMatrix4f("uViewProjection", camera.view_projection_matrix);
        }

        const visible_num = chunk_mesh_layers.cull(&camera);
        chunk_mesh_layers.uploadCommandBuffers();

        gl.ClearColor(0.47843137254901963, 0.6588235294117647, 0.9921568627450981, 1.0);
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

        chunks_shader_program.bind();
        chunk_mesh_layers.draw();

        for (0..chunk_mesh_layers.pos.buffer.items.len) |chunk_mesh_idx_| {
            const chunk_mesh_idx = chunk_mesh_idx_ * 6;

            inline for (0..Block.Layer.len) |layer_idx| {
                const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];

                inline for (0..6) |face_idx| {
                    chunk_mesh_layer.command.buffer.items[chunk_mesh_idx + face_idx].instance_count = 0;
                }
            }
        }
        chunk_mesh_layers.uploadCommandBuffers();

        chunks_bb_shader_program.bind();
        {
            gl.Enable(gl.POLYGON_OFFSET_FILL);
            defer gl.Disable(gl.POLYGON_OFFSET_FILL);

            gl.PolygonOffset(1.0, 1.0);
            defer gl.PolygonOffset(0.0, 0.0);

            gl.DepthMask(gl.FALSE);
            defer gl.DepthMask(gl.TRUE);

            gl.ColorMask(gl.FALSE, gl.FALSE, gl.FALSE, gl.FALSE);
            defer gl.ColorMask(gl.TRUE, gl.TRUE, gl.TRUE, gl.TRUE);

            gl.MemoryBarrier(gl.SHADER_STORAGE_BARRIER_BIT);
            gl.DrawArraysInstanced(gl.TRIANGLES, 0, 36, @intCast(chunk_mesh_layers.pos.buffer.items.len));
            gl.MemoryBarrier(gl.SHADER_STORAGE_BARRIER_BIT);
        }

        gl.BlitNamedFramebuffer(0, offscreen_framebuffer_handle, 0, 0, screen.window_width, screen.window_height, 0, 0, screen.window_width, screen.window_height, gl.COLOR_BUFFER_BIT, gl.LINEAR);

        chunks_debug_shader_program.bind();
        {
            gl.Enable(gl.POLYGON_OFFSET_LINE);
            defer gl.Disable(gl.POLYGON_OFFSET_LINE);

            gl.PolygonOffset(-1.0, 1.0);
            defer gl.PolygonOffset(0.0, 0.0);

            gl.Enable(gl.LINE_SMOOTH);
            defer gl.Disable(gl.LINE_SMOOTH);

            gl.DrawArraysInstanced(gl.LINES, 0, 36, @intCast(chunk_mesh_layers.pos.buffer.items.len));
        }

        text_manager.clear();

        try text_manager.append(allocator, .{
            .pixel_x = 0,
            .pixel_y = 0,
            .text = "Natura ex Deus",
        });

        try text_manager.append(allocator, .{
            .pixel_x = 0,
            .pixel_y = 6,
            .text = try std.fmt.allocPrint(allocator, "visible: {}/{}", .{ visible_num, chunk_mesh_layers.pos.buffer.items.len * 6 }),
        });

        const camera_chunk_pos = camera.position.toChunkPos();
        try text_manager.append(allocator, .{
            .pixel_x = 0,
            .pixel_y = 12,
            .text = try std.fmt.allocPrint(allocator, "chunk: [x: {} y: {} z: {}]", .{ camera_chunk_pos.x, camera_chunk_pos.y, camera_chunk_pos.z }),
        });

        const camera_world_pos = camera.position.toWorldPos();
        const camera_local_pos = camera_world_pos.toLocalPos();
        try text_manager.append(allocator, .{
            .pixel_x = 0,
            .pixel_y = 18,
            .text = try std.fmt.allocPrint(allocator, "local: [x: {} y: {} z: {}]", .{ camera_local_pos.x, camera_local_pos.y, camera_local_pos.z }),
        });

        try text_manager.append(allocator, .{
            .pixel_x = 0,
            .pixel_y = 24,
            .text = try std.fmt.allocPrint(allocator, "world: [x: {} y: {} z: {}]", .{ camera_world_pos.x, camera_world_pos.y, camera_world_pos.z }),
        });

        try text_manager.append(allocator, .{
            .pixel_x = 0,
            .pixel_y = 30,
            .text = try std.fmt.allocPrint(allocator, "camera: [x: {d:.6} y: {d:.6} z: {d:.6}]", .{ camera.position.x, camera.position.y, camera.position.z }),
        });

        try text_manager.append(allocator, .{
            .pixel_x = 0,
            .pixel_y = 36,
            .text = try std.fmt.allocPrint(allocator, "yaw: {d:.2} pitch: {d:.2}", .{ @mod(camera.yaw, 360.0) - 180.0, camera.pitch }),
        });

        const result = world.raycast(camera.position, camera.direction);
        try onRaycast(allocator, &world, &text_manager, result);

        try text_manager.buildVertices(allocator, screen.window_width, screen.window_height, settings.ui_scale);
        text_manager.text_vertices.resizeBufferAndBind(12);

        text_shader_program.bind();
        gl.DrawArrays(gl.TRIANGLES, 0, @intCast(text_manager.text_vertices.buffer.items.len));

        delta_time = @floatCast(@as(f64, @floatFromInt(timer.lap())) / 1_000_000_000.0);

        window.swapBuffers();
        glfw.pollEvents();
    }

    for (block_images.items) |*image| {
        image.deinit();
    }

    for (glyph_images) |*image| {
        image.deinit();
    }

    indirect_light_image.deinit();
    font_image.deinit();

    stbi.deinit();
}
