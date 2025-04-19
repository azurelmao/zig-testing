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
const WorldMesh = @import("WorldMesh.zig");
const ShaderPrograms = @import("ShaderPrograms.zig");
const Textures = @import("Textures.zig");
const ShaderStorageBuffers = @import("ShaderStorageBuffers.zig");
const Framebuffer = @import("Framebuffer.zig");

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
    // uniform_buffers: UniformBuffers,
    shader_programs: ShaderPrograms,
    textures: Textures,
    shader_storage_buffers: ShaderStorageBuffers,
    offscreen_framebuffer: Framebuffer,
    world: World,
    world_mesh: WorldMesh,
    selected_block: World.RaycastResult,
    visible_chunk_meshes: usize,

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
        const offscreen_framebuffer = try Framebuffer.init(3, screen.window_width, screen.window_height);

        const world = try World.init(30);
        const selected_block = world.raycast(camera.position, camera.direction);

        const world_mesh = WorldMesh.init();

        return .{
            .settings = settings,
            .screen = screen,
            .camera = camera,
            .window = window,
            .callback_user_data = callback_user_data,
            .shader_programs = shader_programs,
            .textures = textures,
            .shader_storage_buffers = shader_storage_buffers,
            .offscreen_framebuffer = offscreen_framebuffer,
            .world = world,
            .world_mesh = world_mesh,
            .selected_block = selected_block,
            .visible_chunk_meshes = 0,
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

        gl.Enable(gl.DEPTH_TEST);
        gl.Enable(gl.CULL_FACE);
        gl.Enable(gl.BLEND);
        gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

        // Empty VAO because we use vertex pulling
        var vao_handle: gl.uint = undefined;
        gl.GenVertexArrays(1, @ptrCast(&vao_handle));
        gl.BindVertexArray(vao_handle);
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

    fn handleInput(self: *Game, delta_time: gl.float) !void {
        const mouse_speed = self.settings.mouse_speed * delta_time;
        const movement_speed = self.settings.movement_speed * delta_time;

        var calc_view_matrix = false;
        var calc_projection_matrix = false;

        if (self.window.getKey(glfw.Key.s) == .press) {
            self.camera.position.subtractInPlace(self.camera.horizontal_direction.multiplyScalar(movement_speed));
            calc_view_matrix = true;
        }

        if (self.window.getKey(glfw.Key.w) == .press) {
            self.camera.position.addInPlace(self.camera.horizontal_direction.multiplyScalar(movement_speed));
            calc_view_matrix = true;
        }

        if (self.window.getKey(glfw.Key.left_shift) == .press) {
            self.camera.position.subtractInPlace(Camera.up.multiplyScalar(movement_speed));
            calc_view_matrix = true;
        }

        if (self.window.getKey(glfw.Key.space) == .press) {
            self.camera.position.addInPlace(Camera.up.multiplyScalar(movement_speed));
            calc_view_matrix = true;
        }

        if (self.window.getKey(glfw.Key.a) == .press) {
            self.camera.position.subtractInPlace(self.camera.right.multiplyScalar(movement_speed));
            calc_view_matrix = true;
        }

        if (self.window.getKey(glfw.Key.d) == .press) {
            self.camera.position.addInPlace(self.camera.right.multiplyScalar(movement_speed));
            calc_view_matrix = true;
        }

        if (self.callback_user_data.new_window_size) |new_window_size| {
            self.screen.window_width = new_window_size.window_width;
            self.screen.window_height = new_window_size.window_height;
            self.screen.window_width_f = @floatFromInt(new_window_size.window_width);
            self.screen.window_height_f = @floatFromInt(new_window_size.window_height);

            self.screen.calcAspectRatio();
            self.shader_programs.crosshair.setUniform2f("uWindowSize", self.screen.window_width_f, self.screen.window_height_f);

            gl.Viewport(0, 0, self.screen.window_width, self.screen.window_height);

            try self.offscreen_framebuffer.resize(self.screen.window_width, self.screen.window_height);
            self.offscreen_framebuffer.bind(3);

            calc_projection_matrix = true;
        }

        if (self.callback_user_data.new_cursor_pos) |new_cursor_pos| {
            const offset_x = (new_cursor_pos.cursor_x - self.screen.prev_cursor_x) * mouse_speed;
            const offset_y = (self.screen.prev_cursor_y - new_cursor_pos.cursor_y) * mouse_speed;

            self.screen.prev_cursor_x = new_cursor_pos.cursor_x;
            self.screen.prev_cursor_y = new_cursor_pos.cursor_y;

            self.camera.yaw += offset_x;
            self.camera.pitch = std.math.clamp(self.camera.pitch + offset_y, -89.0, 89.0);

            self.camera.calcDirectionAndRight();

            calc_view_matrix = true;
        }

        if (calc_view_matrix) {
            self.camera.calcViewMatrix();

            self.shader_programs.chunks.setUniform3f("uCameraPosition", self.camera.position.x, self.camera.position.y, self.camera.position.z);
        }

        if (calc_projection_matrix) {
            self.camera.calcProjectionMatrix(self.screen.aspect_ratio);
        }

        const calc_view_projection_matrix = calc_view_matrix or calc_projection_matrix;
        if (calc_view_projection_matrix) {
            self.camera.calcViewProjectionMatrix();
            self.camera.calcFrustumPlanes();

            self.visible_chunk_meshes = self.world_mesh.cull(&self.camera);
            self.world_mesh.uploadCommandBuffers();

            self.selected_block = self.world.raycast(self.camera.position, self.camera.direction);

            const selected_pos = self.selected_block.pos.toVec3f();
            self.shader_programs.selected_block.setUniform3f("uBlockPosition", selected_pos.x, selected_pos.y, selected_pos.z);
            self.shader_programs.selected_side.setUniform3f("uBlockPosition", selected_pos.x, selected_pos.y, selected_pos.z);

            const side = self.selected_block.side;

            if (side != .out_of_bounds and side != .inside) {
                if (self.selected_block.block) |block| {
                    const model_idx = block.getModelIndices().faces[side.idx()];
                    self.shader_programs.selected_side.setUniform1ui("uModelIdx", model_idx);
                }
            }

            self.shader_programs.chunks.setUniformMatrix4f("uViewProjection", self.camera.view_projection_matrix);
            self.shader_programs.chunks_bb.setUniformMatrix4f("uViewProjection", self.camera.view_projection_matrix);
            self.shader_programs.chunks_debug.setUniformMatrix4f("uViewProjection", self.camera.view_projection_matrix);
            self.shader_programs.selected_block.setUniformMatrix4f("uViewProjection", self.camera.view_projection_matrix);
            self.shader_programs.selected_side.setUniformMatrix4f("uViewProjection", self.camera.view_projection_matrix);
        }
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

    try game.world.generate(allocator);
    try game.world.propagateLights(allocator);
    try game.world.propagateLights(allocator);

    game.selected_block = game.world.raycast(game.camera.position, game.camera.direction);
    {
        const selected_pos = game.selected_block.pos.toVec3f();
        game.shader_programs.selected_block.setUniform3f("uBlockPosition", selected_pos.x, selected_pos.y, selected_pos.z);
        game.shader_programs.selected_side.setUniform3f("uBlockPosition", selected_pos.x, selected_pos.y, selected_pos.z);

        const side = game.selected_block.side;

        if (side != .out_of_bounds and side != .inside) {
            if (game.selected_block.block) |block| {
                const model_idx = block.getModelIndices().faces[side.idx()];
                game.shader_programs.selected_side.setUniform1ui("uModelIdx", model_idx);
            }
        }
    }

    try game.world_mesh.generate(allocator, &game.world);

    game.visible_chunk_meshes = game.world_mesh.cull(&game.camera);
    game.world_mesh.pos.uploadAndOrResize();

    inline for (0..Block.Layer.len) |layer_idx| {
        const world_mesh_layer = &game.world_mesh.layers[layer_idx];

        if (world_mesh_layer.mesh.data.items.len > 0) {
            world_mesh_layer.mesh.uploadAndOrResize();
        }

        world_mesh_layer.command.uploadAndOrResize();
        world_mesh_layer.command.bind(6 + layer_idx);
    }

    var text_manager = ui.TextManager.init();

    var delta_time: gl.float = 1.0 / 60.0;
    var timer = try std.time.Timer.start();

    while (!game.window.shouldClose()) {
        try game.handleInput(delta_time);

        gl.ClearColor(0.47843137254901963, 0.6588235294117647, 0.9921568627450981, 1.0);
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

        game.shader_programs.chunks.bind();
        inline for (0..Block.Layer.len) |layer_idx| {
            const world_mesh_layer = &game.world_mesh.layers[layer_idx];

            if (world_mesh_layer.mesh.data.items.len > 0) {
                world_mesh_layer.mesh.bind(3);
                world_mesh_layer.command.bindAsIndirectBuffer();

                gl.MultiDrawArraysIndirect(gl.TRIANGLES, null, @intCast(world_mesh_layer.command.data.items.len), 0);
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
            gl.DrawArraysInstanced(gl.TRIANGLES, 0, 36, @intCast(game.world_mesh.pos.data.items.len));
            gl.MemoryBarrier(gl.SHADER_STORAGE_BARRIER_BIT);
        }

        gl.BlitNamedFramebuffer(0, game.offscreen_framebuffer.framebuffer_handle, 0, 0, game.screen.window_width, game.screen.window_height, 0, 0, game.screen.window_width, game.screen.window_height, gl.COLOR_BUFFER_BIT, gl.LINEAR);

        game.shader_programs.chunks_debug.bind();
        {
            gl.Enable(gl.POLYGON_OFFSET_LINE);
            defer gl.Disable(gl.POLYGON_OFFSET_LINE);

            gl.PolygonOffset(-1.0, 1.0);
            defer gl.PolygonOffset(0.0, 0.0);

            gl.Enable(gl.LINE_SMOOTH);
            defer gl.Disable(gl.LINE_SMOOTH);

            gl.DrawArraysInstanced(gl.LINES, 0, 36, @intCast(game.world_mesh.pos.data.items.len));
        }

        if (game.selected_block.side != .out_of_bounds and game.selected_block.side != .inside) {
            if (game.selected_block.block) |_| {
                game.shader_programs.selected_side.bind();
                {
                    gl.Enable(gl.POLYGON_OFFSET_FILL);
                    defer gl.Disable(gl.POLYGON_OFFSET_FILL);

                    gl.PolygonOffset(-1.0, 1.0);
                    defer gl.PolygonOffset(0.0, 0.0);

                    gl.DrawArrays(gl.TRIANGLES, 0, 6);
                }
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
            .text = try std.fmt.allocPrint(allocator, "visible: {}/{}", .{ game.visible_chunk_meshes, game.world_mesh.pos.data.items.len * 6 }),
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

        try onRaycast(allocator, &game.world, &text_manager, game.selected_block);

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
