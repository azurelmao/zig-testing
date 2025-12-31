const std = @import("std");
const glfw = @import("glfw");
const gl = @import("gl");
const stbi = @import("zstbi");
const debug = @import("debug.zig");
const callback = @import("callback.zig");
const Input = @import("Input.zig");
const World = @import("World.zig");
const Chunk = @import("Chunk.zig");
const Block = @import("block.zig").Block;
const BlockLayer = @import("block.zig").BlockLayer;
const BlockModel = @import("block.zig").BlockModel;
const BlockVolumeScheme = @import("block.zig").BlockVolumeScheme;
const Camera = @import("Camera.zig");
const Window = @import("Window.zig");
const WorldMesh = @import("WorldMesh.zig");
const UniformBuffer = @import("UniformBuffer.zig");
const ShaderPrograms = @import("ShaderPrograms.zig");
const Textures = @import("Textures.zig");
const ShaderStorageBuffers = @import("ShaderStorageBuffers.zig");
const Framebuffer = @import("Framebuffer.zig");
const TextManager = @import("TextManager.zig");
const Dir = @import("dir.zig").Dir;
const Light = @import("light.zig").Light;
const ShaderStorageBufferWithArrayList = @import("shader_storage_buffer.zig").ShaderStorageBufferWithArrayList;
const Vec3f = @import("vec3f.zig").Vec3f;
const LightTexture = @import("LightTexture.zig");
const HashArrayList = @import("hash_arraylist.zig").HashArrayList;

pub const std_options: std.Options = .{
    .log_level = .debug,
};

const Settings = struct {
    ui_scale: gl.sizei = 3,
    mouse_speed: gl.float = 10.0,
    movement_speed: gl.float = 16.0,
    chunk_borders: bool = true,
    light_addition_nodes: bool = true,
    light_removal_nodes: bool = true,
    relative_selector: bool = false,
};

const Game = struct {
    const TITLE = "PolyCosm";
    const DEBUG_CONTEXT = true;

    paused: bool,
    settings: Settings,
    window: Window,
    camera: Camera,
    input: *Input,
    callback_data: *callback.CallbackData,
    uniform_buffer: UniformBuffer,
    shader_programs: ShaderPrograms,
    textures: Textures,
    shader_storage_buffers: ShaderStorageBuffers,
    offscreen_framebuffer: Framebuffer,
    text_manager: TextManager,

    chunk_volume: HashArrayList(Chunk.Pos),
    world: World,
    world_mesh: WorldMesh,

    selected_block: World.RaycastResult,
    relative_selector_world_pos: World.Pos,
    inventory: []const Block,
    selected_slot: usize,

    fn init(gpa: std.mem.Allocator) !Game {
        const settings: Settings = .{};

        try initGLFW();
        const window: Window = try .init(Window.INITIAL_WIDTH, Window.INITIAL_HEIGHT, TITLE, DEBUG_CONTEXT);

        const input = try gpa.create(Input);
        input.* = try .init(gpa);

        const callback_data = try gpa.create(callback.CallbackData);
        callback_data.* = .init(input);

        window.handle.setUserPointer(@ptrCast(callback_data));

        const camera: Camera = .init(.init(0, 0, 0), 0, 0, window.aspect_ratio);

        const world: World = try .init(gpa, 30);
        const selected_block = world.raycast(camera.position, camera.direction);

        try initGL();
        var uniform_buffer: UniformBuffer = .init(0);
        uniform_buffer.uploadSelectedBlockPos(selected_block.world_pos.toVec3f());
        uniform_buffer.uploadViewProjectionMatrix(camera.view_projection_matrix);

        const shader_programs: ShaderPrograms = try .init(gpa, selected_block, window);

        stbi.init(gpa);
        const textures: Textures = try .init();
        const shader_storage_buffers: ShaderStorageBuffers = try .init();
        const offscreen_framebuffer: Framebuffer = try .init(3, window.width, window.height);
        const text_manager: TextManager = try .init(gpa);

        const world_mesh: WorldMesh = try .init(gpa);

        const inventory = try initInventory(gpa);

        return .{
            .paused = false,
            .settings = settings,
            .window = window,
            .camera = camera,
            .input = input,
            .callback_data = callback_data,
            .uniform_buffer = uniform_buffer,
            .shader_programs = shader_programs,
            .textures = textures,
            .shader_storage_buffers = shader_storage_buffers,
            .offscreen_framebuffer = offscreen_framebuffer,
            .text_manager = text_manager,

            .chunk_volume = .empty,
            .world = world,
            .world_mesh = world_mesh,

            .selected_block = selected_block,
            .relative_selector_world_pos = .{ .x = 0, .y = 0, .z = 0 },
            .inventory = inventory,
            .selected_slot = 0,
        };
    }

    fn deinit(game: *Game, gpa: std.mem.Allocator) void {
        gpa.destroy(game.callback_data);
        gpa.destroy(game.input);
        game.window.handle.destroy();
        gl.makeProcTableCurrent(null);
        glfw.terminate();
        stbi.deinit();
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
                std.log.warn("failed to initialize proc: {?s}", .{proc_name});
                return null;
            }
        }.getProcAddress;

        if (!procs.init(getProcAddress) and !supports_gl46) return error.ProcInitFailed;

        gl.makeProcTableCurrent(&procs);

        var flags: gl.int = undefined;
        gl.GetIntegerv(gl.CONTEXT_FLAGS, @ptrCast(&flags));
        if (flags & gl.CONTEXT_FLAG_DEBUG_BIT != 0) {
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

    fn initInventory(gpa: std.mem.Allocator) ![]const Block {
        var inventory: std.ArrayListUnmanaged(Block) = .empty;

        // Lamp lights
        for ([_]Light{
            .{
                .red = 15,
                .green = 0,
                .blue = 0,
                .indirect = 0,
            },
            .{
                .red = 0,
                .green = 15,
                .blue = 0,
                .indirect = 0,
            },
            .{
                .red = 0,
                .green = 0,
                .blue = 15,
                .indirect = 0,
            },
            .{
                .red = 15,
                .green = 15,
                .blue = 0,
                .indirect = 0,
            },
            .{
                .red = 15,
                .green = 0,
                .blue = 15,
                .indirect = 0,
            },
            .{
                .red = 0,
                .green = 15,
                .blue = 15,
                .indirect = 0,
            },
            .{
                .red = 15,
                .green = 15,
                .blue = 15,
                .indirect = 0,
            },
        }) |light| {
            try inventory.append(gpa, .init(.lamp, .{ .lamp = .{ .light = light } }));
        }

        try inventory.append(gpa, .initNone(.stone));
        try inventory.append(gpa, .initNone(.glass));
        try inventory.append(gpa, .initNone(.ice));
        try inventory.append(gpa, .initNone(.glass_tinted));

        try inventory.append(gpa, .initNone(.torch));

        return inventory.items;
    }

    fn generateChunkVolume(game: *Game, gpa: std.mem.Allocator, camera: Camera) !void {
        const prev_camera_chunk_pos = camera.prev_position.toChunkPos();
        const camera_chunk_pos = camera.position.toChunkPos();

        if (game.chunk_volume.count() != 0 and prev_camera_chunk_pos.equal(camera_chunk_pos)) return;

        game.chunk_volume.clearRetainingCapacity();

        const render_distance_usize: usize = 2;
        const render_distance: i11 = @intCast(render_distance_usize);

        for (0..render_distance_usize * 2) |x_usize| {
            const x = @as(i11, @intCast(x_usize)) - render_distance;

            for (0..render_distance_usize * 2) |z_usize| {
                const z = @as(i11, @intCast(z_usize)) - render_distance;

                for (0..render_distance_usize * 2) |y_usize| {
                    const y = @as(i11, @intCast(y_usize)) - render_distance;
                    const chunk_pos: Chunk.Pos = camera_chunk_pos.add(.{ .x = x, .y = y, .z = z });

                    try game.chunk_volume.append(gpa, chunk_pos);
                }
            }
        }
    }

    fn appendRaycastText(game: *Game, gpa: std.mem.Allocator, original_line: i32) !i32 {
        const world_pos = game.selected_block.world_pos;
        const raycast_dir = game.selected_block.dir;

        var line = original_line;

        switch (raycast_dir) {
            else => {
                try game.text_manager.append(gpa, .{
                    .pixel_x = 0,
                    .pixel_y = line * 6,
                    .text = try std.fmt.allocPrint(gpa, "looking at: [x: {d} y: {d} z: {d}] on dir: {s}", .{
                        world_pos.x,
                        world_pos.y,
                        world_pos.z,
                        @tagName(raycast_dir),
                    }),
                });
                line += 1;

                try game.text_manager.append(gpa, .{
                    .pixel_x = 0,
                    .pixel_y = line * 6,
                    .text = try std.fmt.allocPrint(gpa, "block: {s}", .{
                        if (game.selected_block.block) |block| @tagName(block.kind) else "null",
                    }),
                });
                line += 1;

                if (game.world.getLightOrNull(world_pos.add(.getOffset(raycast_dir.toDir())))) |light| {
                    try game.text_manager.append(gpa, .{
                        .pixel_x = 0,
                        .pixel_y = line * 6,
                        .text = try std.fmt.allocPrint(gpa, "light: [r: {} g: {} b: {} i: {}]", .{
                            light.red,
                            light.green,
                            light.blue,
                            light.indirect,
                        }),
                    });
                    line += 1;
                } else {
                    try game.text_manager.append(gpa, .{
                        .pixel_x = 0,
                        .pixel_y = line * 6,
                        .text = try std.fmt.allocPrint(gpa, "light: out_of_bounds", .{}),
                    });
                    line += 1;
                }
            },

            .inside => {
                const light = try game.world.getLight(world_pos);

                try game.text_manager.append(gpa, .{
                    .pixel_x = 0,
                    .pixel_y = line * 6,
                    .text = try std.fmt.allocPrint(gpa, "looking at: [x: {d} y: {d} z: {d}] on dir: {s}", .{
                        world_pos.x,
                        world_pos.y,
                        world_pos.z,
                        @tagName(raycast_dir),
                    }),
                });
                line += 1;

                try game.text_manager.append(gpa, .{
                    .pixel_x = 0,
                    .pixel_y = line * 6,
                    .text = try std.fmt.allocPrint(gpa, "block: {s}", .{@tagName(game.selected_block.block.?.kind)}),
                });
                line += 1;

                try game.text_manager.append(gpa, .{
                    .pixel_x = 0,
                    .pixel_y = line * 6,
                    .text = try std.fmt.allocPrint(gpa, "light: [r: {} g: {} b: {} i: {}]", .{
                        light.red,
                        light.green,
                        light.blue,
                        light.indirect,
                    }),
                });
                line += 1;
            },

            .out_of_bounds => {
                try game.text_manager.append(gpa, .{
                    .pixel_x = 0,
                    .pixel_y = line * 6,
                    .text = try std.fmt.allocPrint(gpa, "looking at: [x: {d} y: {d} z: {d}] on dir: {s}", .{
                        world_pos.x,
                        world_pos.y,
                        world_pos.z,
                        @tagName(raycast_dir),
                    }),
                });
                line += 1;
            },
        }

        return line;
    }

    fn appendRelativeSelectorText(game: *Game, gpa: std.mem.Allocator, original_line: i32) !i32 {
        const world_pos = game.selected_block.world_pos.add(game.relative_selector_world_pos);
        var line = original_line;

        const block_or_null = game.world.getBlockOrNull(world_pos);
        const light_or_null = game.world.getLightOrNull(world_pos);

        try game.text_manager.append(gpa, .{
            .pixel_x = 0,
            .pixel_y = line * 6,
            .text = try std.fmt.allocPrint(gpa, "selector at: [x: {d} y: {d} z: {d}]", .{
                world_pos.x,
                world_pos.y,
                world_pos.z,
            }),
        });
        line += 1;

        if (block_or_null) |block| {
            try game.text_manager.append(gpa, .{
                .pixel_x = 0,
                .pixel_y = line * 6,
                .text = try std.fmt.allocPrint(gpa, "block: {s}", .{@tagName(block.kind)}),
            });
            line += 1;
        }

        if (light_or_null) |light| {
            try game.text_manager.append(gpa, .{
                .pixel_x = 0,
                .pixel_y = line * 6,
                .text = try std.fmt.allocPrint(gpa, "light: [r: {} g: {} b: {} i: {}]", .{
                    light.red,
                    light.green,
                    light.blue,
                    light.indirect,
                }),
            });
            line += 1;
        }

        return line;
    }

    fn appendText(game: *Game, gpa: std.mem.Allocator) !void {
        game.text_manager.clear();

        var line: i32 = 0;

        try game.text_manager.append(gpa, .{
            .pixel_x = 0,
            .pixel_y = line * 6,
            .text = TITLE,
        });
        line += 1;

        try game.text_manager.append(gpa, .{
            .pixel_x = 0,
            .pixel_y = line * 6,
            .text = try std.fmt.allocPrint(gpa, "visible: {}", .{game.world_mesh.visible_chunk_meshes.items.len}),
        });
        line += 1;

        const camera_world_pos = game.camera.position.toWorldPos();
        const camera_local_pos = camera_world_pos.toLocalPos();
        const camera_chunk_pos = camera_world_pos.toChunkPos();

        try game.text_manager.append(gpa, .{
            .pixel_x = 0,
            .pixel_y = line * 6,
            .text = try std.fmt.allocPrint(gpa, "chunk: [x: {} y: {} z: {}]", .{ camera_chunk_pos.x, camera_chunk_pos.y, camera_chunk_pos.z }),
        });
        line += 1;

        try game.text_manager.append(gpa, .{
            .pixel_x = 0,
            .pixel_y = line * 6,
            .text = try std.fmt.allocPrint(gpa, "local: [x: {} y: {} z: {}]", .{ camera_local_pos.x, camera_local_pos.y, camera_local_pos.z }),
        });
        line += 1;

        try game.text_manager.append(gpa, .{
            .pixel_x = 0,
            .pixel_y = line * 6,
            .text = try std.fmt.allocPrint(gpa, "world: [x: {} y: {} z: {}]", .{ camera_world_pos.x, camera_world_pos.y, camera_world_pos.z }),
        });
        line += 1;

        try game.text_manager.append(gpa, .{
            .pixel_x = 0,
            .pixel_y = line * 6,
            .text = try std.fmt.allocPrint(gpa, "camera: [x: {d:.6} y: {d:.6} z: {d:.6}]", .{ game.camera.position.x, game.camera.position.y, game.camera.position.z }),
        });
        line += 1;

        try game.text_manager.append(gpa, .{
            .pixel_x = 0,
            .pixel_y = line * 6,
            .text = try std.fmt.allocPrint(gpa, "yaw: {d:.2} pitch: {d:.2}", .{ @mod(game.camera.yaw, 360.0), game.camera.pitch }),
        });
        line += 1;

        // make some space between raycast info
        line += 1;

        line = try game.appendRaycastText(gpa, line);

        if (game.settings.relative_selector) {
            // make some space between relative selector info
            line += 1;

            line = try game.appendRelativeSelectorText(gpa, line);
        }

        try game.text_manager.build(gpa, game.window.width, game.window.height, game.settings.ui_scale);
    }

    pub const SharedFlags = packed struct {
        calc_projection_matrix: bool,
        calc_view_matrix: bool,
        selector_changed: bool,
        action: enum(u2) { none, primary, secondary },
    };

    fn processWindowEvents(game: *Game, delta_time: gl.float, shared_flags: *SharedFlags) !void {
        if (game.callback_data.new_window_size) |new_window_size| {
            game.window.width = new_window_size.width;
            game.window.height = new_window_size.height;
            game.window.width_f = @floatFromInt(new_window_size.width);
            game.window.height_f = @floatFromInt(new_window_size.height);

            game.window.calcAspectRatio();
            game.shader_programs.crosshair.setUniform2f("uWindowSize", game.window.width_f, game.window.height_f);

            gl.Viewport(0, 0, game.window.width, game.window.height);

            try game.offscreen_framebuffer.resizeAndBind(game.window.width, game.window.height, 3);

            shared_flags.calc_projection_matrix = true;
            game.callback_data.new_window_size = null;
        }

        if (game.callback_data.new_cursor_pos) |new_cursor_pos| {
            if (!game.paused) {
                const mouse_speed = game.settings.mouse_speed * delta_time;

                const offset_x = (new_cursor_pos.cursor_x - game.window.prev_cursor_x) * mouse_speed;
                const offset_y = (game.window.prev_cursor_y - new_cursor_pos.cursor_y) * mouse_speed;

                game.window.prev_cursor_x = new_cursor_pos.cursor_x;
                game.window.prev_cursor_y = new_cursor_pos.cursor_y;

                game.camera.yaw += offset_x;
                game.camera.pitch = std.math.clamp(game.camera.pitch + offset_y, -89.0, 89.0);

                game.camera.calcDirectionAndRight();

                shared_flags.calc_view_matrix = true;
            }

            game.callback_data.new_cursor_pos = null;
        }
    }

    fn processInput(game: *Game, delta_time: gl.float, shared_flags: *SharedFlags) void {
        if (game.input.getUncached(.close_window) == .press) {
            game.window.handle.setShouldClose(true);
        }

        if (game.input.getUncached(.pause) == .press) {
            game.paused = !game.paused;

            const cursor_mode: glfw.Window.InputModeCursor = if (game.paused) .normal else .disabled;
            game.window.handle.setInputModeCursor(cursor_mode);
        }

        if (game.paused) return;

        if (game.input.getUncached(.toggle_chunk_borders) == .press) {
            game.settings.chunk_borders = !game.settings.chunk_borders;
        }

        if (game.input.getUncached(.toggle_light_removal_nodes) == .press) {
            game.settings.light_removal_nodes = !game.settings.light_removal_nodes;
        }

        if (game.input.getUncached(.toggle_light_addition_nodes) == .press) {
            game.settings.light_addition_nodes = !game.settings.light_addition_nodes;
        }

        if (game.input.getUncached(.toggle_relative_selector) == .press) {
            game.settings.relative_selector = !game.settings.relative_selector;
        }

        if (game.input.getUncached(.slot_1) == .press) {
            game.selected_slot -|= 1;
        }

        if (game.input.getUncached(.slot_2) == .press) {
            if (game.selected_slot +| 1 < game.inventory.len) game.selected_slot += 1;
        }

        // if (game.input.getUncached(.slot_3) == .press) {
        //     game.selected_slot = 2;
        // }

        // if (game.input.getUncached(.slot_4) == .press) {
        //     game.selected_slot = 3;
        // }

        // if (game.input.getUncached(.slot_5) == .press) {
        //     game.selected_slot = 4;
        // }

        // if (game.input.getUncached(.slot_6) == .press) {
        //     game.selected_slot = 5;
        // }

        // if (game.input.getUncached(.slot_7) == .press) {
        //     game.selected_slot = 6;
        // }

        if (game.input.getUncached(.move_selector_east) == .press) {
            game.relative_selector_world_pos.x -|= 1;
            shared_flags.selector_changed = true;
        }

        if (game.input.getUncached(.move_selector_west) == .press) {
            game.relative_selector_world_pos.x +|= 1;
            shared_flags.selector_changed = true;
        }

        if (game.input.getUncached(.move_selector_down) == .press) {
            game.relative_selector_world_pos.y -|= 1;
            shared_flags.selector_changed = true;
        }

        if (game.input.getUncached(.move_selector_up) == .press) {
            game.relative_selector_world_pos.y +|= 1;
            shared_flags.selector_changed = true;
        }

        if (game.input.getUncached(.move_selector_north) == .press) {
            game.relative_selector_world_pos.z -|= 1;
            shared_flags.selector_changed = true;
        }

        if (game.input.getUncached(.move_selector_south) == .press) {
            game.relative_selector_world_pos.z +|= 1;
            shared_flags.selector_changed = true;
        }

        const movement_speed = game.settings.movement_speed * delta_time;

        if (game.input.getCached(.move_camera_left)) {
            game.camera.position.subtractInPlace(game.camera.right.multiplyScalar(movement_speed));
            shared_flags.calc_view_matrix = true;
        }

        if (game.input.getCached(.move_camera_right)) {
            game.camera.position.addInPlace(game.camera.right.multiplyScalar(movement_speed));
            shared_flags.calc_view_matrix = true;
        }

        if (game.input.getCached(.move_camera_down)) {
            game.camera.position.subtractInPlace(Camera.up.multiplyScalar(movement_speed));
            shared_flags.calc_view_matrix = true;
        }

        if (game.input.getCached(.move_camera_up)) {
            game.camera.position.addInPlace(Camera.up.multiplyScalar(movement_speed));
            shared_flags.calc_view_matrix = true;
        }

        if (game.input.getCached(.move_camera_backward)) {
            game.camera.position.subtractInPlace(game.camera.horizontal_direction.multiplyScalar(movement_speed));
            shared_flags.calc_view_matrix = true;
        }

        if (game.input.getCached(.move_camera_forward)) {
            game.camera.position.addInPlace(game.camera.horizontal_direction.multiplyScalar(movement_speed));
            shared_flags.calc_view_matrix = true;
        }

        if (game.input.getUncached(.primary_action) == .press) {
            shared_flags.action = .primary;
        }

        if (game.input.getUncached(.secondary_action) == .press) {
            shared_flags.action = .secondary;
        }
    }

    fn processSharedFlags(game: *Game, gpa: std.mem.Allocator, shared_flags: SharedFlags) !void {
        if (shared_flags.calc_view_matrix and !game.paused) {
            game.camera.calcViewMatrix();

            game.shader_programs.chunks.setUniform3f("uCameraPosition", game.camera.position.x, game.camera.position.y, game.camera.position.z);
        }

        if (shared_flags.calc_projection_matrix) {
            game.camera.calcProjectionMatrix(game.window.aspect_ratio);
        }

        const calc_view_projection_matrix = shared_flags.calc_view_matrix or shared_flags.calc_projection_matrix;
        if (calc_view_projection_matrix) {
            game.camera.calcViewProjectionMatrix();
            game.camera.calcFrustumPlanes();
            game.uniform_buffer.uploadViewProjectionMatrix(game.camera.view_projection_matrix);
        }

        if (game.paused) return;

        if (calc_view_projection_matrix or shared_flags.action != .none) {
            game.selected_block = game.world.raycast(game.camera.position, game.camera.direction);

            var raycast_again = false;

            if (shared_flags.action == .primary) skip: {
                const block = game.selected_block.block orelse break :skip;

                if (block.kind == .air) break :skip;

                const world_pos = game.selected_block.world_pos;
                try game.world.breakBlock(gpa, world_pos, block);

                raycast_again = true;
            }

            if (shared_flags.action == .secondary) skip: {
                const selected_dir = game.selected_block.dir;
                if (selected_dir == .out_of_bounds or selected_dir == .inside) break :skip;

                const world_pos = game.selected_block.world_pos.add(.getOffset(selected_dir.toDir()));
                if (game.world.getChunkOrNull(world_pos.toChunkPos()) == null) break :skip;

                const block = game.inventory[game.selected_slot];
                try game.world.placeBlock(gpa, world_pos, block);

                raycast_again = true;
            }

            if (raycast_again) {
                game.selected_block = game.world.raycast(game.camera.position, game.camera.direction);
            }

            const selected_block_pos = game.selected_block.world_pos.toVec3f();
            game.uniform_buffer.uploadSelectedBlockPos(selected_block_pos);

            const selected_dir = game.selected_block.dir;

            if (selected_dir != .out_of_bounds and selected_dir != .inside) {
                if (game.selected_block.block) |block| {
                    const block_model_face_indices = block.kind.getModel().faces.get(selected_dir.toDir());
                    game.shader_programs.selected_side.setUniform1ui("uFaceIdx", @intCast(block_model_face_indices[0]));
                }
            }
        }

        if (shared_flags.selector_changed) {
            const selector_pos = game.selected_block.world_pos.add(game.relative_selector_world_pos).toVec3f();
            game.uniform_buffer.uploadSelectorPos(selector_pos);
        }
    }

    fn processChanges(game: *Game, gpa: std.mem.Allocator, shared_flags: SharedFlags) !void {
        if (debug.upload_nodes) {
            debug.addition_nodes.ssbo.upload(debug.addition_nodes.data.items) catch |err| switch (err) {
                error.DataTooLarge => {
                    debug.addition_nodes.ssbo.resize(debug.addition_nodes.data.items.len, 0);
                    debug.addition_nodes.ssbo.upload(debug.addition_nodes.data.items) catch unreachable;
                },
                else => unreachable,
            };

            debug.removal_nodes.ssbo.upload(debug.removal_nodes.data.items) catch |err| switch (err) {
                error.DataTooLarge => {
                    debug.removal_nodes.ssbo.resize(debug.removal_nodes.data.items.len, 0);
                    debug.removal_nodes.ssbo.upload(debug.removal_nodes.data.items) catch unreachable;
                },
                else => unreachable,
            };

            debug.upload_nodes = false;
        }

        try game.generateChunkVolume(gpa, game.camera);

        try game.world.generateChunks(gpa, game.chunk_volume);

        var upload_mesh = false;

        for (game.world.chunks_to_be_loaded.items()) |chunk_pos| {
            std.debug.assert(game.world.hasChunk(chunk_pos));

            if (game.world_mesh.hasChunkMesh(chunk_pos)) {
                game.world_mesh.invalidateChunkMesh(chunk_pos);
            } else {
                try game.world_mesh.putChunkMesh(gpa, chunk_pos, .{ .light_texture = .init() });
            }

            try game.world_mesh.generateChunkMesh(gpa, &game.world, chunk_pos);
            upload_mesh = true;
        }

        // for (game.world.chunks_to_be_unloaded.items()) |chunk_pos| {
        //     game.world_mesh.invalidateChunkMesh(chunk_pos);
        // }

        if (upload_mesh) {
            try game.world.propagateLightRemoval(gpa);
            try game.world.propagateLightAddition(gpa);
        }

        for (game.world.chunks_to_be_loaded.items()) |chunk_pos| {
            for (0..3) |x_usize| {
                const x = @as(i11, @intCast(x_usize)) - 1;

                for (0..3) |y_usize| {
                    const y = @as(i11, @intCast(y_usize)) - 1;

                    for (0..3) |z_usize| {
                        const z = @as(i11, @intCast(z_usize)) - 1;

                        const neighbor_chunk_pos = chunk_pos.add(.{ .x = x, .y = y, .z = z });

                        if (game.world.chunks_to_be_loaded.contains(neighbor_chunk_pos)) continue;
                        if (!game.world.hasChunk(neighbor_chunk_pos)) continue;

                        try game.world_mesh.chunk_meshes_which_need_to_upload_light_texture_overlaps.append(gpa, neighbor_chunk_pos);
                    }
                }
            }

            try game.world_mesh.uploadLightTexture(game.world, chunk_pos);
        }

        for (game.world_mesh.chunk_meshes_which_need_to_upload_light_texture_overlaps.items()) |chunk_pos| {
            try game.world_mesh.uploadLightTextureOverlaps(game.world, chunk_pos);
        }

        game.world.chunks_to_be_loaded.clearRetainingCapacity();
        game.world.chunks_to_be_unloaded.clearRetainingCapacity();
        game.world_mesh.chunk_meshes_which_need_to_upload_light_texture_overlaps.clearRetainingCapacity();

        if (shared_flags.calc_projection_matrix or shared_flags.calc_view_matrix or shared_flags.action != .none) {
            try game.world_mesh.generateVisibleChunkMeshes(gpa, game.world, game.camera);
            try game.world_mesh.generateCommands(gpa);
            game.world_mesh.uploadCommands();
        }

        if (upload_mesh) {
            game.world_mesh.uploadMesh();
        }
    }

    fn render(game: *Game) void {
        gl.ClearColor(0.47843137254901963, 0.6588235294117647, 0.9921568627450981, 1.0);
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

        game.shader_programs.chunks.bind();
        inline for (BlockLayer.values) |block_layer| skip: {
            if (block_layer == .water) gl.Disable(gl.CULL_FACE);
            defer if (block_layer == .water) gl.Enable(gl.CULL_FACE);

            const world_mesh_layer = &game.world_mesh.layers[block_layer.idx()];
            if (world_mesh_layer.command.data.items.len == 0) break :skip;

            world_mesh_layer.mesh.ssbo.bind(1);
            world_mesh_layer.command.ssbo.bind(2);
            world_mesh_layer.command.ssbo.bindAsIndirectBuffer();

            gl.MultiDrawArraysIndirect(
                gl.TRIANGLES,
                null,
                @intCast(world_mesh_layer.command.data.items.len),
                world_mesh_layer.command.ssbo.stride,
            );
        }

        // game.shader_programs.chunks_bb.bind();
        // {
        //     gl.Enable(gl.POLYGON_OFFSET_FILL);
        //     defer gl.Disable(gl.POLYGON_OFFSET_FILL);

        //     gl.PolygonOffset(1.0, 1.0);
        //     defer gl.PolygonOffset(0.0, 0.0);

        //     gl.DepthMask(gl.FALSE);
        //     defer gl.DepthMask(gl.TRUE);

        //     gl.ColorMask(gl.FALSE, gl.FALSE, gl.FALSE, gl.FALSE);
        //     defer gl.ColorMask(gl.TRUE, gl.TRUE, gl.TRUE, gl.TRUE);

        //     gl.MemoryBarrier(gl.SHADER_STORAGE_BARRIER_BIT);
        //     gl.DrawArraysInstanced(gl.TRIANGLES, 0, 36, @intCast(game.world_mesh.pos.data.items.len));
        //     gl.MemoryBarrier(gl.SHADER_STORAGE_BARRIER_BIT);
        // }

        gl.BlitNamedFramebuffer(0, game.offscreen_framebuffer.framebuffer_handle, 0, 0, game.window.width, game.window.height, 0, 0, game.window.width, game.window.height, gl.COLOR_BUFFER_BIT, gl.LINEAR);

        if (game.settings.chunk_borders) {
            game.shader_programs.chunk_borders.bind();
            {
                gl.Enable(gl.POLYGON_OFFSET_LINE);
                defer gl.Disable(gl.POLYGON_OFFSET_LINE);

                gl.PolygonOffset(-1.0, 1.0);
                defer gl.PolygonOffset(0.0, 0.0);

                gl.Enable(gl.LINE_SMOOTH);
                defer gl.Disable(gl.LINE_SMOOTH);

                game.shader_storage_buffers.chunk_bounding_box_lines.bind(1);
                debug.visible_chunk_mesh_positions.ssbo.bind(2);

                gl.DrawArraysInstanced(gl.LINES, 0, 36, @intCast(debug.visible_chunk_mesh_positions.data.items.len));
            }
        }

        if (game.selected_block.dir != .out_of_bounds and game.selected_block.dir != .inside) {
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

        // if (game.settings.light_removal_nodes or game.settings.light_addition_nodes) {
        //     game.shader_programs.debug_nodes.bind();
        //     {
        //         gl.Enable(gl.POLYGON_OFFSET_LINE);
        //         defer gl.Disable(gl.POLYGON_OFFSET_LINE);

        //         gl.PolygonOffset(-2.0, 1.0);
        //         defer gl.PolygonOffset(0.0, 0.0);

        //         gl.Enable(gl.LINE_SMOOTH);
        //         defer gl.Disable(gl.LINE_SMOOTH);

        //         gl.DepthFunc(gl.LEQUAL);
        //         defer gl.DepthFunc(gl.LESS);

        //         if (game.settings.light_removal_nodes) {
        //             game.shader_programs.debug_nodes.setUniform3f("uColor", 1, 0, 0);
        //             debug.removal_nodes.ssbo.bind(15);
        //             gl.DrawArraysInstanced(gl.LINES, 0, BlockVolumeScheme.FULL_LEN, @intCast(debug.removal_nodes.data.items.len));
        //         }

        //         if (game.settings.light_addition_nodes) {
        //             game.shader_programs.debug_nodes.setUniform3f("uColor", 0, 0, 1);
        //             debug.addition_nodes.ssbo.bind(15);
        //             gl.DrawArraysInstanced(gl.LINES, 0, BlockVolumeScheme.FULL_LEN, @intCast(debug.addition_nodes.data.items.len));
        //         }
        //     }
        // }

        if (game.selected_block.block) |block| {
            game.shader_programs.selected_block.bind();

            gl.Enable(gl.POLYGON_OFFSET_LINE);
            defer gl.Disable(gl.POLYGON_OFFSET_LINE);

            gl.PolygonOffset(-2.0, 1.0);
            defer gl.PolygonOffset(0.0, 0.0);

            gl.Enable(gl.LINE_SMOOTH);
            defer gl.Disable(gl.LINE_SMOOTH);

            gl.DepthFunc(gl.LEQUAL);
            defer gl.DepthFunc(gl.LESS);

            const index_and_len = block.kind.getVolumeIndexAndLen();

            gl.DrawArrays(gl.LINES, @intCast(index_and_len.index), @intCast(index_and_len.len));
        }

        // if (game.settings.relative_selector) {
        //     game.shader_programs.relative_selector.bind();

        //     gl.Enable(gl.POLYGON_OFFSET_LINE);
        //     defer gl.Disable(gl.POLYGON_OFFSET_LINE);

        //     gl.PolygonOffset(-2.0, 1.0);
        //     defer gl.PolygonOffset(0.0, 0.0);

        //     gl.Enable(gl.LINE_SMOOTH);
        //     defer gl.Disable(gl.LINE_SMOOTH);

        //     gl.DepthFunc(gl.LEQUAL);
        //     defer gl.DepthFunc(gl.LESS);

        //     gl.DrawArrays(gl.LINES, 0, BlockVolumeScheme.FULL_LEN);
        // }

        game.shader_programs.crosshair.bind();
        gl.DrawArrays(gl.TRIANGLES, 0, 6);

        game.shader_programs.text.bind();
        gl.DrawArrays(gl.TRIANGLES, 0, @intCast(game.text_manager.vertices.data.items.len));
    }
};

var procs: gl.ProcTable = undefined;

pub fn main() !void {
    // var arena_state: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    // defer arena_state.deinit();
    // const arena = arena_state.allocator();

    const gpa = std.heap.smp_allocator;

    var game: Game = try .init(gpa);
    defer game.deinit(gpa);

    try debug.init(gpa);

    // for (0..8) |x| {
    //     for (0..8) |z| {
    //         try game.world.placeBlock(
    //             gpa,
    //             .{ .x = @intCast(x + 5), .y = 6, .z = @intCast(z + 5) },
    //             .initNone(.stone),
    //         );
    //     }
    // }

    // for (0..4) |x| {
    //     for (0..4) |z| {
    //         try game.world.placeBlock(
    //             gpa,
    //             .{ .x = @intCast(x + 7), .y = 7, .z = @intCast(z + 7) },
    //             .initNone(.stone),
    //         );
    //     }
    // }

    // for (0..8) |x| {
    //     for (0..8) |z| {
    //         try game.world.placeBlock(
    //             gpa,
    //             .{ .x = @intCast(x + 5), .y = 11, .z = @intCast(z + 5) },
    //             .initNone(.stone),
    //         );
    //     }
    // }

    // for (0..4) |x| {
    //     for (0..4) |z| {
    //         try game.world.placeBlock(
    //             gpa,
    //             .{ .x = @intCast(x + 7), .y = 10, .z = @intCast(z + 7) },
    //             .initNone(.stone),
    //         );
    //     }
    // }

    // try game.world.propagateLights(gpa, &game.debug);
    // try game.world.propagateLightAddition(gpa);
    // game.debug.removal_nodes.data.clearRetainingCapacity();
    // game.debug.addition_nodes.data.clearRetainingCapacity();

    // try game.world_mesh.generateMesh(gpa, &game.world);
    // try game.world_mesh.generateVisibleChunkMeshes(gpa, &game.world, &game.camera);
    // try game.world_mesh.generateLightTextures(gpa, &game.world);
    // try game.world_mesh.generateCommands(gpa);

    // game.world_mesh.uploadMesh();
    // game.world_mesh.uploadCommands();

    var delta_time: gl.float = 1.0 / 60.0;
    var timer: std.time.Timer = try .start();

    while (!game.window.handle.shouldClose()) {
        glfw.pollEvents();

        var shared_flags: Game.SharedFlags = .{
            .calc_projection_matrix = false,
            .calc_view_matrix = false,
            .selector_changed = false,
            .action = .none,
        };

        game.camera.prev_position = game.camera.position;

        try game.processWindowEvents(delta_time, &shared_flags);
        game.processInput(delta_time, &shared_flags);

        try game.processSharedFlags(gpa, shared_flags);
        try game.appendText(gpa);

        if (!game.paused)
            try game.processChanges(gpa, shared_flags);

        game.render();

        game.input.resetUncachedKeys();

        delta_time = @floatCast(@as(f64, @floatFromInt(timer.lap())) / 1_000_000_000.0);
        game.window.handle.swapBuffers();
    }
}
