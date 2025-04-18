const std = @import("std");
const glfw = @import("glfw");
const gl = @import("gl");
const stbi = @import("zstbi");
const callback = @import("callback.zig");
const ui = @import("ui.zig");
const World = @import("World.zig");
const Chunk = @import("Chunk.zig");
const Block = @import("block.zig").Block;
const Camera = @import("Camera.zig");
const Screen = @import("Screen.zig");
const ChunkMeshLayers = @import("ChunkMeshLayers.zig");
const ShaderPrograms = @import("ShaderPrograms.zig");
const Textures = @import("Textures.zig");
const ShaderStorageBuffers = @import("ShaderStorageBuffers.zig");

pub const std_options: std.Options = .{
    .log_level = .info,
};

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
    ui_scale: gl.sizei = 2,
    mouse_speed: gl.float = 10.0,
    movement_speed: gl.float = 16.0,
};

const Game = struct {
    const DEBUG_CONTEXT = true;

    settings: Settings,
    screen: Screen,
    camera: Camera,
    window: glfw.Window,
    callback_user_data: callback.UserData,
    shader_programs: ShaderPrograms,
    textures: Textures,
    shader_storage_buffers: ShaderStorageBuffers,
    // uniform_buffers: UniformBuffers,
    world: World,

    fn init(allocator: std.mem.Allocator) !Game {
        const settings = Settings{};
        const screen = Screen{};
        const camera = Camera.init(.new(0, 0, 0), 0, 0, screen.aspect_ratio);

        try initGLFW();
        const window = try initWindow(&screen);
        const callback_user_data = callback.UserData{};

        try initGL();
        const shader_programs = try ShaderPrograms.init(allocator);

        stbi.init(allocator);
        const textures = try Textures.init();

        const shader_storage_buffers = try ShaderStorageBuffers.init();

        const world = try World.init(30);

        return .{
            .settings = settings,
            .screen = screen,
            .camera = camera,
            .window = window,
            .callback_user_data = callback_user_data,
            .shader_programs = shader_programs,
            .textures = textures,
            .shader_storage_buffers = shader_storage_buffers,
            .world = world,
        };
    }

    fn initGLFW() !void {
        glfw.setErrorCallback(callback.errorCallback);

        if (!glfw.init(.{})) {
            std.log.err("failed to initialize GLFW: {?s}", .{glfw.getErrorString()});
            return error.GLFWInitFailed;
        }
    }

    fn initGL() !void {
        // My laptop's iGPU (Intel UHD Graphics 620) says it supports GL 4.6, but glfw fails to init these functions:
        // - glGetnTexImage
        // - glGetnUniformdv
        // - glMultiDrawArraysIndirectCount
        // - glMultiDrawElementsIndirectCount
        const supports_gl46 = expr: {
            const glGetString: @FieldType(gl.ProcTable, "GetString") = @ptrCast(glfw.getProcAddress("glGetString").?);
            const version_str = glGetString(gl.VERSION).?;

            break :expr version_str[0] == '4' and version_str[2] == '6';
        };

        const getProcAddress = struct {
            fn getProcAddress(proc_name: [*:0]const u8) callconv(.C) ?glfw.GLProc {
                if (glfw.getProcAddress(proc_name)) |proc_address| return proc_address;
                std.log.err("failed to initialize proc: {?s}", .{proc_name});
                return null;
            }
        }.getProcAddress;

        if (!procs.init(getProcAddress) and !supports_gl46) return error.ProcInitFailed;

        gl.makeProcTableCurrent(&procs);

        var flags: gl.int = undefined;
        gl.GetIntegerv(gl.CONTEXT_FLAGS, @ptrCast(&flags));
        if (flags & gl.CONTEXT_FLAG_DEBUG_BIT > 0) {
            gl.Enable(gl.DEBUG_OUTPUT);
            gl.Enable(gl.DEBUG_OUTPUT_SYNCHRONOUS);
            gl.DebugMessageCallback(callback.debugCallback, null);
            gl.DebugMessageControl(gl.DONT_CARE, gl.DONT_CARE, gl.DONT_CARE, 0, null, gl.TRUE);
        } else if (DEBUG_CONTEXT) {
            std.log.err("failed to load OpenGL debug context", .{});
            return error.DebugContextFailed;
        }

        // Without this, texture data is aligned to vec4s even when specifying data format to be RED
        gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1);
    }

    fn initWindow(screen: *const Screen) !glfw.Window {
        const window = glfw.Window.create(@intCast(screen.window_width), @intCast(screen.window_height), "Natura ex Deus", null, null, .{
            .opengl_profile = .opengl_core_profile,
            .context_version_major = 4,
            .context_version_minor = 6,
            .context_debug = DEBUG_CONTEXT,
        }) orelse {
            std.log.err("failed to create GLFW window: {?s}", .{glfw.getErrorString()});
            return error.WindowCreationFailed;
        };

        glfw.makeContextCurrent(window);

        window.setInputModeCursor(.disabled);
        window.setCursorPos(screen.prev_cursor_x, screen.prev_cursor_y);
        window.setCursorPosCallback(callback.cursorCallback);
        window.setFramebufferSizeCallback(callback.framebufferSizeCallback);
        window.setKeyCallback(callback.keyCallback);

        return window;
    }

    fn setWindowUserPointer(self: *Game) void {
        self.window.setUserPointer(@ptrCast(&self.callback_user_data));
    }

    fn deinit(self: *Game) void {
        self.window.destroy();
        gl.makeProcTableCurrent(null);
        glfw.terminate();
        stbi.deinit();
    }
};

var procs: gl.ProcTable = undefined;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var game = try Game.init(allocator);
    defer game.deinit();

    // Has to be outside init to not create a dangling ptr
    game.setWindowUserPointer();

    game.shader_programs.chunks.setUniformMatrix4f("uViewProjection", game.camera.view_projection_matrix);
    game.shader_programs.chunks_bb.setUniformMatrix4f("uViewProjection", game.camera.view_projection_matrix);
    game.shader_programs.chunks_debug.setUniformMatrix4f("uViewProjection", game.camera.view_projection_matrix);
    game.shader_programs.selected_block.setUniformMatrix4f("uViewProjection", game.camera.view_projection_matrix);
    game.shader_programs.selected_side.setUniformMatrix4f("uViewProjection", game.camera.view_projection_matrix);
    game.shader_programs.crosshair.setUniform2f("uWindowSize", game.screen.window_width_f, game.screen.window_height_f);

    var debug_timer = try std.time.Timer.start();

    debug_timer.reset();
    try game.world.generate(allocator);

    var debug_time = @as(f64, @floatFromInt(debug_timer.lap())) / 1_000_000_000.0;
    std.log.info("Generating world done. {d} s", .{debug_time});

    debug_timer.reset();
    try game.world.propagateLights(allocator);

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

    for (0..15) |x_| {
        const x: i16 = @intCast(x_);

        for (0..15) |z_| {
            const z: i16 = @intCast(z_);

            try game.world.setBlockAndAffectLight(allocator, .{ .x = x, .y = 20, .z = z }, .bricks);
        }
    }

    debug_timer.reset();
    try game.world.propagateLights(allocator);

    debug_time = @as(f64, @floatFromInt(debug_timer.lap())) / 1_000_000_000.0;
    std.log.info("Light propagation done. {d} s", .{debug_time});

    var result = game.world.raycast(game.camera.position, game.camera.direction);
    var draw_selected_side = false;
    {
        const selected_pos = result.pos.toVec3f();
        game.shader_programs.selected_block.setUniform3f("uBlockPosition", selected_pos.x, selected_pos.y, selected_pos.z);
        game.shader_programs.selected_side.setUniform3f("uBlockPosition", selected_pos.x, selected_pos.y, selected_pos.z);

        const side = result.side;

        if (side != .out_of_bounds and side != .inside) {
            if (result.block) |block| {
                const model_idx = block.getModelIndices().faces[side.idx()];
                game.shader_programs.selected_side.setUniform1ui("uModelIdx", model_idx);

                draw_selected_side = true;
            } else {
                draw_selected_side = false;
            }
        } else {
            draw_selected_side = false;
        }
    }

    var chunk_mesh_layers = ChunkMeshLayers.init();

    debug_timer.reset();
    try chunk_mesh_layers.generate(allocator, &game.world);

    debug_time = @as(f64, @floatFromInt(debug_timer.lap())) / 1_000_000_000.0;
    std.log.info("Chunk mesh buffers done. {d} s", .{debug_time});

    debug_timer.reset();
    var visible_num = chunk_mesh_layers.cull(&game.camera);

    debug_time = @as(f64, @floatFromInt(debug_timer.lap())) / 1_000_000_000.0;
    std.log.info("Culling done. {d} s", .{debug_time});

    chunk_mesh_layers.pos.uploadAndOrResize();

    inline for (0..Block.Layer.len) |layer_idx| {
        const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];

        if (chunk_mesh_layer.mesh.data.items.len > 0) {
            chunk_mesh_layer.mesh.uploadAndOrResize();
        }

        chunk_mesh_layer.command.uploadAndOrResize();
        chunk_mesh_layer.command.bind(6 + layer_idx);
    }

    var text_manager = ui.TextManager.init();

    var vao_handle: gl.uint = undefined;
    gl.GenVertexArrays(1, @ptrCast(&vao_handle));
    gl.BindVertexArray(vao_handle);

    var offscreen_texture_handle: gl.uint = undefined;
    gl.CreateTextures(gl.TEXTURE_2D, 1, @ptrCast(&offscreen_texture_handle));
    gl.TextureStorage2D(offscreen_texture_handle, 1, gl.RGBA8, game.screen.window_width, game.screen.window_height);
    gl.BindTextureUnit(3, offscreen_texture_handle);

    var offscreen_framebuffer_handle: gl.uint = undefined;
    gl.CreateFramebuffers(1, @ptrCast(&offscreen_framebuffer_handle));
    gl.NamedFramebufferTexture(offscreen_framebuffer_handle, gl.COLOR_ATTACHMENT0, offscreen_texture_handle, 0);

    if (gl.CheckNamedFramebufferStatus(offscreen_framebuffer_handle, gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE) {
        std.debug.panic("Incomplete offscreen framebuffer status", .{});
    }

    gl.Enable(gl.DEPTH_TEST);
    gl.Enable(gl.CULL_FACE);
    gl.Enable(gl.BLEND);
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

    var delta_time: gl.float = 1.0 / 60.0;
    var timer = try std.time.Timer.start();

    while (!game.window.shouldClose()) {
        const mouse_speed = game.settings.mouse_speed * delta_time;
        const movement_speed = game.settings.movement_speed * delta_time;

        var calc_view_matrix = false;
        var calc_projection_matrix = false;

        if (game.window.getKey(glfw.Key.s) == .press) {
            game.camera.position.subtractInPlace(game.camera.horizontal_direction.multiplyScalar(movement_speed));
            calc_view_matrix = true;
        }

        if (game.window.getKey(glfw.Key.w) == .press) {
            game.camera.position.addInPlace(game.camera.horizontal_direction.multiplyScalar(movement_speed));
            calc_view_matrix = true;
        }

        if (game.window.getKey(glfw.Key.left_shift) == .press) {
            game.camera.position.subtractInPlace(Camera.up.multiplyScalar(movement_speed));
            calc_view_matrix = true;
        }

        if (game.window.getKey(glfw.Key.space) == .press) {
            game.camera.position.addInPlace(Camera.up.multiplyScalar(movement_speed));
            calc_view_matrix = true;
        }

        if (game.window.getKey(glfw.Key.a) == .press) {
            game.camera.position.subtractInPlace(game.camera.right.multiplyScalar(movement_speed));
            calc_view_matrix = true;
        }

        if (game.window.getKey(glfw.Key.d) == .press) {
            game.camera.position.addInPlace(game.camera.right.multiplyScalar(movement_speed));
            calc_view_matrix = true;
        }

        if (game.callback_user_data.new_window_size) |new_window_size| {
            game.screen.window_width = new_window_size.window_width;
            game.screen.window_height = new_window_size.window_height;
            game.screen.window_width_f = @floatFromInt(new_window_size.window_width);
            game.screen.window_height_f = @floatFromInt(new_window_size.window_height);

            game.screen.calcAspectRatio();
            game.shader_programs.crosshair.setUniform2f("uWindowSize", game.screen.window_width_f, game.screen.window_height_f);

            gl.Viewport(0, 0, game.screen.window_width, game.screen.window_height);

            gl.DeleteTextures(1, @ptrCast(&offscreen_texture_handle));
            gl.CreateTextures(gl.TEXTURE_2D, 1, @ptrCast(&offscreen_texture_handle));
            gl.TextureStorage2D(offscreen_texture_handle, 1, gl.RGBA8, game.screen.window_width, game.screen.window_height);
            gl.BindTextureUnit(3, offscreen_texture_handle);

            gl.DeleteFramebuffers(1, @ptrCast(&offscreen_framebuffer_handle));
            gl.CreateFramebuffers(1, @ptrCast(&offscreen_framebuffer_handle));
            gl.NamedFramebufferTexture(offscreen_framebuffer_handle, gl.COLOR_ATTACHMENT0, offscreen_texture_handle, 0);

            calc_projection_matrix = true;
        }

        if (game.callback_user_data.new_cursor_pos) |new_cursor_pos| {
            const offset_x = (new_cursor_pos.cursor_x - game.screen.prev_cursor_x) * mouse_speed;
            const offset_y = (game.screen.prev_cursor_y - new_cursor_pos.cursor_y) * mouse_speed;

            game.screen.prev_cursor_x = new_cursor_pos.cursor_x;
            game.screen.prev_cursor_y = new_cursor_pos.cursor_y;

            game.camera.yaw += offset_x;
            game.camera.pitch = std.math.clamp(game.camera.pitch + offset_y, -89.0, 89.0);

            game.camera.calcDirectionAndRight();

            calc_view_matrix = true;
        }

        if (calc_view_matrix) {
            game.camera.calcViewMatrix();

            game.shader_programs.chunks.setUniform3f("uCameraPosition", game.camera.position.x, game.camera.position.y, game.camera.position.z);
        }

        if (calc_projection_matrix) {
            game.camera.calcProjectionMatrix(game.screen.aspect_ratio);
        }

        const calc_view_projection_matrix = calc_view_matrix or calc_projection_matrix;
        if (calc_view_projection_matrix) {
            game.camera.calcViewProjectionMatrix();
            game.camera.calcFrustumPlanes();

            result = game.world.raycast(game.camera.position, game.camera.direction);

            const selected_pos = result.pos.toVec3f();
            game.shader_programs.selected_block.setUniform3f("uBlockPosition", selected_pos.x, selected_pos.y, selected_pos.z);
            game.shader_programs.selected_side.setUniform3f("uBlockPosition", selected_pos.x, selected_pos.y, selected_pos.z);

            const side = result.side;

            if (side != .out_of_bounds and side != .inside) {
                if (result.block) |block| {
                    const model_idx = block.getModelIndices().faces[side.idx()];
                    game.shader_programs.selected_side.setUniform1ui("uModelIdx", model_idx);

                    draw_selected_side = true;
                } else {
                    draw_selected_side = false;
                }
            } else {
                draw_selected_side = false;
            }

            game.shader_programs.chunks.setUniformMatrix4f("uViewProjection", game.camera.view_projection_matrix);
            game.shader_programs.chunks_bb.setUniformMatrix4f("uViewProjection", game.camera.view_projection_matrix);
            game.shader_programs.chunks_debug.setUniformMatrix4f("uViewProjection", game.camera.view_projection_matrix);
            game.shader_programs.selected_block.setUniformMatrix4f("uViewProjection", game.camera.view_projection_matrix);
            game.shader_programs.selected_side.setUniformMatrix4f("uViewProjection", game.camera.view_projection_matrix);
        }

        if (calc_view_projection_matrix) {
            visible_num = chunk_mesh_layers.cull(&game.camera);
            chunk_mesh_layers.uploadCommandBuffers();
        }

        gl.ClearColor(0.47843137254901963, 0.6588235294117647, 0.9921568627450981, 1.0);
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

        game.shader_programs.chunks.bind();
        inline for (0..Block.Layer.len) |layer_idx| {
            const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];

            if (chunk_mesh_layer.mesh.data.items.len > 0) {
                chunk_mesh_layer.mesh.bind(3);
                chunk_mesh_layer.command.bindAsIndirectBuffer();

                gl.MultiDrawArraysIndirect(gl.TRIANGLES, null, @intCast(chunk_mesh_layer.command.data.items.len), 0);
            }
        }

        game.shader_programs.chunks_bb.bind();
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
            gl.DrawArraysInstanced(gl.TRIANGLES, 0, 36, @intCast(chunk_mesh_layers.pos.data.items.len));
            gl.MemoryBarrier(gl.SHADER_STORAGE_BARRIER_BIT);
        }

        gl.BlitNamedFramebuffer(0, offscreen_framebuffer_handle, 0, 0, game.screen.window_width, game.screen.window_height, 0, 0, game.screen.window_width, game.screen.window_height, gl.COLOR_BUFFER_BIT, gl.LINEAR);

        game.shader_programs.chunks_debug.bind();
        {
            gl.Enable(gl.POLYGON_OFFSET_LINE);
            defer gl.Disable(gl.POLYGON_OFFSET_LINE);

            gl.PolygonOffset(-1.0, 1.0);
            defer gl.PolygonOffset(0.0, 0.0);

            gl.Enable(gl.LINE_SMOOTH);
            defer gl.Disable(gl.LINE_SMOOTH);

            gl.DrawArraysInstanced(gl.LINES, 0, 36, @intCast(chunk_mesh_layers.pos.data.items.len));
        }

        if (draw_selected_side) {
            game.shader_programs.selected_side.bind();
            {
                gl.Enable(gl.POLYGON_OFFSET_FILL);
                defer gl.Disable(gl.POLYGON_OFFSET_FILL);

                gl.PolygonOffset(-1.0, 1.0);
                defer gl.PolygonOffset(0.0, 0.0);

                gl.DrawArrays(gl.TRIANGLES, 0, 6);
            }
        }

        game.shader_programs.selected_block.bind();
        {
            gl.Enable(gl.POLYGON_OFFSET_LINE);
            defer gl.Disable(gl.POLYGON_OFFSET_LINE);

            gl.PolygonOffset(-2.0, 1.0);
            defer gl.PolygonOffset(0.0, 0.0);

            gl.Enable(gl.LINE_SMOOTH);
            defer gl.Disable(gl.LINE_SMOOTH);

            gl.DepthFunc(gl.LEQUAL);
            defer gl.DepthFunc(gl.LESS);

            gl.DrawArrays(gl.LINES, 0, Block.BOUNDING_BOX_LINES_BUFFER.len);
        }

        game.shader_programs.crosshair.bind();
        gl.DrawArrays(gl.TRIANGLES, 0, 6);

        text_manager.clear();

        try text_manager.append(allocator, .{
            .pixel_x = 0,
            .pixel_y = 0,
            .text = "Natura ex Deus",
        });

        try text_manager.append(allocator, .{
            .pixel_x = 0,
            .pixel_y = 6,
            .text = try std.fmt.allocPrint(allocator, "visible: {}/{}", .{ visible_num, chunk_mesh_layers.pos.data.items.len * 6 }),
        });

        const camera_chunk_pos = game.camera.position.toChunkPos();
        try text_manager.append(allocator, .{
            .pixel_x = 0,
            .pixel_y = 12,
            .text = try std.fmt.allocPrint(allocator, "chunk: [x: {} y: {} z: {}]", .{ camera_chunk_pos.x, camera_chunk_pos.y, camera_chunk_pos.z }),
        });

        const camera_world_pos = game.camera.position.toWorldPos();
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
            .text = try std.fmt.allocPrint(allocator, "camera: [x: {d:.6} y: {d:.6} z: {d:.6}]", .{ game.camera.position.x, game.camera.position.y, game.camera.position.z }),
        });

        try text_manager.append(allocator, .{
            .pixel_x = 0,
            .pixel_y = 36,
            .text = try std.fmt.allocPrint(allocator, "yaw: {d:.2} pitch: {d:.2}", .{ @mod(game.camera.yaw, 360.0) - 180.0, game.camera.pitch }),
        });

        try onRaycast(allocator, &game.world, &text_manager, result);

        try text_manager.buildVertices(allocator, game.screen.window_width, game.screen.window_height, game.settings.ui_scale);
        text_manager.text_vertices.uploadAndOrResize();
        text_manager.text_vertices.bind(12);

        game.shader_programs.text.bind();
        gl.DrawArrays(gl.TRIANGLES, 0, @intCast(text_manager.text_vertices.data.items.len));

        delta_time = @floatCast(@as(f64, @floatFromInt(timer.lap())) / 1_000_000_000.0);

        game.window.swapBuffers();
        glfw.pollEvents();
    }
}
