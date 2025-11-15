const std = @import("std");
const glfw = @import("glfw");
const gl = @import("gl");
const stbi = @import("zstbi");
const callback = @import("callback.zig");
const World = @import("World.zig");
const Chunk = @import("Chunk.zig");
const Block = @import("block.zig").Block;
const BlockLayer = @import("block.zig").BlockLayer;
const BlockModel = @import("block.zig").BlockModel;
const Camera = @import("Camera.zig");
const Screen = @import("Screen.zig");
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

const c = @import("vma");

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

pub const Debug = struct {
    addition_nodes: ShaderStorageBufferWithArrayList(Vec3f),
    removal_nodes: ShaderStorageBufferWithArrayList(Vec3f),
};

const Game = struct {
    const TITLE = "PolyCosm";
    const DEBUG_CONTEXT = true;

    settings: Settings,
    screen: Screen,
    camera: Camera,
    window: glfw.Window,
    callback_user_data: *callback.UserData,
    uniform_buffer: UniformBuffer,
    shader_programs: ShaderPrograms,
    textures: Textures,
    shader_storage_buffers: ShaderStorageBuffers,
    offscreen_framebuffer: Framebuffer,
    text_manager: TextManager,
    world: World,
    world_mesh: WorldMesh,
    selected_block: World.RaycastResult,
    relative_selector_world_pos: World.Pos,
    inventory: [7]Block,
    selected_slot: u3,
    debug: Debug,

    fn init(gpa: std.mem.Allocator) !Game {
        const settings: Settings = .{};
        const screen: Screen = .{};
        const camera: Camera = .init(.new(0, 0, 0), 0, 0, screen.aspect_ratio);

        const world: World = try .init(gpa, 30);
        const selected_block = world.raycast(camera.position, camera.direction);

        try initGLFW();
        const window = try initWindow(&screen);

        const callback_user_data = try gpa.create(callback.UserData);
        callback_user_data.* = .default;
        window.setUserPointer(@ptrCast(callback_user_data));

        try initGL();
        var uniform_buffer: UniformBuffer = .init(0);
        uniform_buffer.uploadSelectedBlockPos(selected_block.world_pos.toVec3f());
        uniform_buffer.uploadViewProjectionMatrix(camera.view_projection_matrix);

        const shader_programs: ShaderPrograms = try .init(gpa, selected_block, screen);

        stbi.init(gpa);
        const textures: Textures = try .init();
        const shader_storage_buffers: ShaderStorageBuffers = try .init();
        const offscreen_framebuffer: Framebuffer = try .init(3, screen.window_width, screen.window_height);
        const text_manager: TextManager = try .init(gpa);

        const world_mesh: WorldMesh = try .init(gpa);

        var inventory: [7]Block = undefined;
        for (0..inventory.len) |idx| {
            const light_idx: u4 = @intCast(idx + 1);
            const light: Light = .{
                .red = (light_idx & 0b1) * 15,
                .green = ((light_idx >> 1) & 0b1) * 15,
                .blue = ((light_idx >> 2) & 0b1) * 15,
                .indirect = 0,
            };

            inventory[idx] = .init(.lamp, .{ .lamp = .{ .light = light } });
        }

        return .{
            .settings = settings,
            .screen = screen,
            .camera = camera,
            .window = window,
            .callback_user_data = callback_user_data,
            .uniform_buffer = uniform_buffer,
            .shader_programs = shader_programs,
            .textures = textures,
            .shader_storage_buffers = shader_storage_buffers,
            .offscreen_framebuffer = offscreen_framebuffer,
            .text_manager = text_manager,
            .world = world,
            .world_mesh = world_mesh,
            .selected_block = selected_block,
            .relative_selector_world_pos = .{ .x = 0, .y = 0, .z = 0 },
            .inventory = inventory,
            .selected_slot = 0,
            .debug = .{
                .addition_nodes = try .init(gpa, 10_000, gl.DYNAMIC_STORAGE_BIT),
                .removal_nodes = try .init(gpa, 10_000, gl.DYNAMIC_STORAGE_BIT),
            },
        };
    }

    fn deinit(self: *Game, gpa: std.mem.Allocator) void {
        gpa.destroy(self.callback_user_data);
        self.window.destroy();
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
        const window = glfw.Window.create(@intCast(screen.window_width), @intCast(screen.window_height), TITLE, null, null, .{
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
        window.setMouseButtonCallback(callback.buttonCallback);

        return window;
    }

    fn handleInput(self: *Game, gpa: std.mem.Allocator, delta_time: gl.float) !void {
        const mouse_speed = self.settings.mouse_speed * delta_time;
        const movement_speed = self.settings.movement_speed * delta_time;

        var calc_view_matrix = false;
        var calc_projection_matrix = false;
        var selector_changed = false;

        if (self.callback_user_data.new_key_action) |new_key_action| {
            if (new_key_action.action == .press) switch (new_key_action.key) {
                .escape => self.window.setShouldClose(true),

                .F4 => self.settings.chunk_borders = !self.settings.chunk_borders,
                .F3 => self.settings.light_removal_nodes = !self.settings.light_removal_nodes,
                .F2 => self.settings.light_addition_nodes = !self.settings.light_addition_nodes,
                .F1 => self.settings.relative_selector = !self.settings.relative_selector,

                .one => self.selected_slot = 0,
                .two => self.selected_slot = 1,
                .three => self.selected_slot = 2,
                .four => self.selected_slot = 3,
                .five => self.selected_slot = 4,
                .six => self.selected_slot = 5,
                .seven => self.selected_slot = 6,

                .kp_8 => {
                    self.relative_selector_world_pos.x +|= 1;
                    selector_changed = true;
                },
                .kp_2 => {
                    self.relative_selector_world_pos.x -|= 1;
                    selector_changed = true;
                },
                .kp_6 => {
                    self.relative_selector_world_pos.z +|= 1;
                    selector_changed = true;
                },
                .kp_4 => {
                    self.relative_selector_world_pos.z -|= 1;
                    selector_changed = true;
                },
                .kp_9 => {
                    self.relative_selector_world_pos.y +|= 1;
                    selector_changed = true;
                },
                .kp_3 => {
                    self.relative_selector_world_pos.y -|= 1;
                    selector_changed = true;
                },

                else => {},
            };

            self.callback_user_data.new_key_action = null;
        }

        var action: enum { none, destroy, place } = .none;

        if (self.callback_user_data.new_button_action) |new_button_action| {
            if (new_button_action.action == .press) switch (new_button_action.button) {
                .left => action = .destroy,
                .right => action = .place,
                else => {},
            };

            self.callback_user_data.new_button_action = null;
        }

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

            try self.offscreen_framebuffer.resizeAndBind(self.screen.window_width, self.screen.window_height, 3);

            calc_projection_matrix = true;
            self.callback_user_data.new_window_size = null;
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
            self.callback_user_data.new_cursor_pos = null;
        }

        if (calc_view_matrix) {
            self.camera.calcViewMatrix();

            self.shader_programs.chunks.setUniform3f("uCameraPosition", self.camera.position.x, self.camera.position.y, self.camera.position.z);
        }

        if (calc_projection_matrix) {
            self.camera.calcProjectionMatrix(self.screen.aspect_ratio);
        }

        const calc_view_projection_matrix = calc_view_matrix or calc_projection_matrix or action != .none;
        if (calc_view_projection_matrix) {
            self.camera.calcViewProjectionMatrix();
            self.camera.calcFrustumPlanes();
            self.uniform_buffer.uploadViewProjectionMatrix(self.camera.view_projection_matrix);

            self.selected_block = self.world.raycast(self.camera.position, self.camera.direction);

            switch (action) {
                .destroy => if (self.selected_block.block) |block| {
                    if (block.kind != .air) {
                        const world_pos = self.selected_block.world_pos;

                        try self.world.breakBlock(gpa, world_pos, block);
                    }
                },
                .place => skip: {
                    const selected_dir = self.selected_block.dir;

                    if (selected_dir == .out_of_bounds or selected_dir == .inside) break :skip;

                    const world_pos = self.selected_block.world_pos.add(World.Pos.OFFSETS[selected_dir.idx()]);
                    if (self.world.getChunkOrNull(world_pos.toChunkPos()) == null) break :skip;

                    const block = self.inventory[self.selected_slot];
                    try self.world.placeBlock(gpa, world_pos, block);
                },
                else => {},
            }

            if (action != .none) {
                self.selected_block = self.world.raycast(self.camera.position, self.camera.direction);
            }

            const selected_block_pos = self.selected_block.world_pos.toVec3f();
            self.uniform_buffer.uploadSelectedBlockPos(selected_block_pos);

            const selected_dir = self.selected_block.dir;

            if (selected_dir != .out_of_bounds and selected_dir != .inside) {
                if (self.selected_block.block) |block| {
                    const dir_idx = (block.kind.getModelIdx() * 36) + (selected_dir.idx() * 6);
                    self.shader_programs.selected_side.setUniform1ui("uFaceIdx", @intCast(dir_idx));
                }
            }

            self.camera.changed = true;
        }

        // if (selector_changed) {
        const selector_pos = self.selected_block.world_pos.add(self.relative_selector_world_pos).toVec3f();
        self.uniform_buffer.uploadSelectorPos(selector_pos);
        // }
    }

    fn appendRaycastText(self: *Game, gpa: std.mem.Allocator, original_line: i32) !i32 {
        const world_pos = self.selected_block.world_pos;
        const dir = self.selected_block.dir;

        var line = original_line;

        switch (dir) {
            else => {
                try self.text_manager.append(gpa, .{
                    .pixel_x = 0,
                    .pixel_y = line * 6,
                    .text = try std.fmt.allocPrint(gpa, "looking at: [x: {d} y: {d} z: {d}] on dir: {s}", .{
                        world_pos.x,
                        world_pos.y,
                        world_pos.z,
                        @tagName(dir),
                    }),
                });
                line += 1;

                try self.text_manager.append(gpa, .{
                    .pixel_x = 0,
                    .pixel_y = line * 6,
                    .text = try std.fmt.allocPrint(gpa, "block: {s}", .{
                        if (self.selected_block.block) |block| @tagName(block.kind) else "null",
                    }),
                });
                line += 1;

                if (self.world.getLight(world_pos.add(World.Pos.OFFSETS[dir.idx()]))) |light| {
                    try self.text_manager.append(gpa, .{
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
                } else |_| {
                    try self.text_manager.append(gpa, .{
                        .pixel_x = 0,
                        .pixel_y = line * 6,
                        .text = try std.fmt.allocPrint(gpa, "light: out_of_bounds", .{}),
                    });
                    line += 1;
                }
            },

            .inside => {
                const light = try self.world.getLight(world_pos);

                try self.text_manager.append(gpa, .{
                    .pixel_x = 0,
                    .pixel_y = line * 6,
                    .text = try std.fmt.allocPrint(gpa, "looking at: [x: {d} y: {d} z: {d}] on dir: {s}", .{
                        world_pos.x,
                        world_pos.y,
                        world_pos.z,
                        @tagName(dir),
                    }),
                });
                line += 1;

                try self.text_manager.append(gpa, .{
                    .pixel_x = 0,
                    .pixel_y = line * 6,
                    .text = try std.fmt.allocPrint(gpa, "block: {s}", .{@tagName(self.selected_block.block.?.kind)}),
                });
                line += 1;

                try self.text_manager.append(gpa, .{
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
                try self.text_manager.append(gpa, .{
                    .pixel_x = 0,
                    .pixel_y = line * 6,
                    .text = try std.fmt.allocPrint(gpa, "looking at: [x: {d} y: {d} z: {d}] on dir: {s}", .{
                        world_pos.x,
                        world_pos.y,
                        world_pos.z,
                        @tagName(dir),
                    }),
                });
                line += 1;
            },
        }

        return line;
    }

    fn appendRelativeSelectorText(self: *Game, gpa: std.mem.Allocator, original_line: i32) !i32 {
        const world_pos = self.selected_block.world_pos.add(self.relative_selector_world_pos);
        var line = original_line;

        const block_or_null = self.world.getBlockOrNull(world_pos);
        const light_or_null = self.world.getLightOrNull(world_pos);

        try self.text_manager.append(gpa, .{
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
            try self.text_manager.append(gpa, .{
                .pixel_x = 0,
                .pixel_y = line * 6,
                .text = try std.fmt.allocPrint(gpa, "block: {s}", .{@tagName(block.kind)}),
            });
            line += 1;
        }

        if (light_or_null) |light| {
            try self.text_manager.append(gpa, .{
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

    fn appendText(self: *Game, gpa: std.mem.Allocator) !void {
        self.text_manager.clear();

        var line: i32 = 0;

        try self.text_manager.append(gpa, .{
            .pixel_x = 0,
            .pixel_y = line * 6,
            .text = TITLE,
        });
        line += 1;

        try self.text_manager.append(gpa, .{
            .pixel_x = 0,
            .pixel_y = line * 6,
            .text = try std.fmt.allocPrint(gpa, "visible: {}", .{self.world_mesh.visible_chunk_meshes.items.len}),
        });
        line += 1;

        const camera_world_pos = self.camera.position.toWorldPos();
        const camera_local_pos = camera_world_pos.toLocalPos();
        const camera_chunk_pos = camera_world_pos.toChunkPos();

        try self.text_manager.append(gpa, .{
            .pixel_x = 0,
            .pixel_y = line * 6,
            .text = try std.fmt.allocPrint(gpa, "chunk: [x: {} y: {} z: {}]", .{ camera_chunk_pos.x, camera_chunk_pos.y, camera_chunk_pos.z }),
        });
        line += 1;

        try self.text_manager.append(gpa, .{
            .pixel_x = 0,
            .pixel_y = line * 6,
            .text = try std.fmt.allocPrint(gpa, "local: [x: {} y: {} z: {}]", .{ camera_local_pos.x, camera_local_pos.y, camera_local_pos.z }),
        });
        line += 1;

        try self.text_manager.append(gpa, .{
            .pixel_x = 0,
            .pixel_y = line * 6,
            .text = try std.fmt.allocPrint(gpa, "world: [x: {} y: {} z: {}]", .{ camera_world_pos.x, camera_world_pos.y, camera_world_pos.z }),
        });
        line += 1;

        try self.text_manager.append(gpa, .{
            .pixel_x = 0,
            .pixel_y = line * 6,
            .text = try std.fmt.allocPrint(gpa, "camera: [x: {d:.6} y: {d:.6} z: {d:.6}]", .{ self.camera.position.x, self.camera.position.y, self.camera.position.z }),
        });
        line += 1;

        try self.text_manager.append(gpa, .{
            .pixel_x = 0,
            .pixel_y = line * 6,
            .text = try std.fmt.allocPrint(gpa, "yaw: {d:.2} pitch: {d:.2}", .{ @mod(self.camera.yaw, 360.0), self.camera.pitch }),
        });
        line += 1;

        // make some space between raycast info
        line += 1;

        line = try self.appendRaycastText(gpa, line);

        if (self.settings.relative_selector) {
            // make some space between relative selector info
            line += 1;

            line = try self.appendRelativeSelectorText(gpa, line);
        }

        try self.text_manager.build(gpa, self.screen.window_width, self.screen.window_height, self.settings.ui_scale);
    }

    fn processChanges(self: *Game, gpa: std.mem.Allocator) !void {
        const upload_nodes = self.world.light_source_removal_queue.readableLength() > 0;

        if (upload_nodes) {
            self.debug.addition_nodes.data.clearRetainingCapacity();
            self.debug.removal_nodes.data.clearRetainingCapacity();
        }

        try self.world.propagateLights(gpa, &self.debug);

        if (upload_nodes) {
            self.debug.addition_nodes.ssbo.upload(self.debug.addition_nodes.data.items) catch |err| switch (err) {
                error.DataTooLarge => {
                    self.debug.addition_nodes.ssbo.resize(self.debug.addition_nodes.data.items.len, 0);
                    self.debug.addition_nodes.ssbo.upload(self.debug.addition_nodes.data.items) catch unreachable;
                },
                else => unreachable,
            };

            self.debug.removal_nodes.ssbo.upload(self.debug.removal_nodes.data.items) catch |err| switch (err) {
                error.DataTooLarge => {
                    self.debug.removal_nodes.ssbo.resize(self.debug.removal_nodes.data.items.len, 0);
                    self.debug.removal_nodes.ssbo.upload(self.debug.removal_nodes.data.items) catch unreachable;
                },
                else => unreachable,
            };
        }

        var upload_mesh = false;
        while (self.world.chunks_which_need_to_regenerate_meshes.dequeue()) |chunk_pos| {
            if (self.world.getChunkOrNull(chunk_pos) == null) continue;

            upload_mesh = true;

            self.world_mesh.invalidateChunkMesh(chunk_pos);
            try self.world_mesh.generateChunkMesh(gpa, &self.world, chunk_pos);
        }

        if (self.camera.changed) {
            try self.world_mesh.generateVisibleChunkMeshes(gpa, &self.world, &self.camera);
            try self.world_mesh.generateCommands(gpa);
            self.world_mesh.uploadCommands();
        }

        if (upload_mesh) {
            self.world_mesh.uploadMesh();
        }

        self.camera.changed = false;
    }

    fn render(self: *Game) void {
        gl.ClearColor(0.47843137254901963, 0.6588235294117647, 0.9921568627450981, 1.0);
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

        self.shader_programs.chunks.bind();
        inline for (BlockLayer.values) |block_layer| skip: {
            if (block_layer == .water) {
                gl.Disable(gl.CULL_FACE);
            }

            const world_mesh_layer = &self.world_mesh.layers[block_layer.idx()];
            if (world_mesh_layer.command.data.items.len == 0) {
                if (block_layer == .water) {
                    gl.Enable(gl.CULL_FACE);
                }
                break :skip;
            }

            world_mesh_layer.mesh.ssbo.bind(1);
            world_mesh_layer.chunk_mesh_pos.ssbo.bind(2);
            world_mesh_layer.command.ssbo.bindAsIndirectBuffer();

            gl.MultiDrawArraysIndirect(gl.TRIANGLES, null, @intCast(world_mesh_layer.command.data.items.len), 0);

            if (block_layer == .water) {
                gl.Enable(gl.CULL_FACE);
            }
        }

        // self.shader_programs.chunks_bb.bind();
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
        //     gl.DrawArraysInstanced(gl.TRIANGLES, 0, 36, @intCast(self.world_mesh.pos.data.items.len));
        //     gl.MemoryBarrier(gl.SHADER_STORAGE_BARRIER_BIT);
        // }

        gl.BlitNamedFramebuffer(0, self.offscreen_framebuffer.framebuffer_handle, 0, 0, self.screen.window_width, self.screen.window_height, 0, 0, self.screen.window_width, self.screen.window_height, gl.COLOR_BUFFER_BIT, gl.LINEAR);

        if (self.settings.chunk_borders) {
            self.shader_programs.chunks_debug.bind();
            {
                gl.Enable(gl.POLYGON_OFFSET_LINE);
                defer gl.Disable(gl.POLYGON_OFFSET_LINE);

                gl.PolygonOffset(-1.0, 1.0);
                defer gl.PolygonOffset(0.0, 0.0);

                gl.Enable(gl.LINE_SMOOTH);
                defer gl.Disable(gl.LINE_SMOOTH);

                gl.DrawArraysInstanced(gl.LINES, 0, 36, @intCast(self.world_mesh.visible_chunk_mesh_pos.data.items.len));
            }
        }

        if (self.selected_block.dir != .out_of_bounds and self.selected_block.dir != .inside) {
            if (self.selected_block.block) |_| {
                self.shader_programs.selected_side.bind();
                {
                    gl.Enable(gl.POLYGON_OFFSET_FILL);
                    defer gl.Disable(gl.POLYGON_OFFSET_FILL);

                    gl.PolygonOffset(-1.0, 1.0);
                    defer gl.PolygonOffset(0.0, 0.0);

                    gl.DrawArrays(gl.TRIANGLES, 0, 6);
                }
            }
        }

        if (self.settings.light_removal_nodes or self.settings.light_addition_nodes) {
            self.shader_programs.debug_nodes.bind();
            {
                gl.Enable(gl.POLYGON_OFFSET_LINE);
                defer gl.Disable(gl.POLYGON_OFFSET_LINE);

                gl.PolygonOffset(-2.0, 1.0);
                defer gl.PolygonOffset(0.0, 0.0);

                gl.Enable(gl.LINE_SMOOTH);
                defer gl.Disable(gl.LINE_SMOOTH);

                gl.DepthFunc(gl.LEQUAL);
                defer gl.DepthFunc(gl.LESS);

                if (self.settings.light_removal_nodes) {
                    self.shader_programs.debug_nodes.setUniform3f("uColor", 1, 0, 0);
                    self.debug.removal_nodes.ssbo.bind(15);
                    gl.DrawArraysInstanced(gl.LINES, 0, BlockModel.BOUNDING_BOX_LINES_BUFFER.len, @intCast(self.debug.removal_nodes.data.items.len));
                }

                if (self.settings.light_addition_nodes) {
                    self.shader_programs.debug_nodes.setUniform3f("uColor", 0, 0, 1);
                    self.debug.addition_nodes.ssbo.bind(15);
                    gl.DrawArraysInstanced(gl.LINES, 0, BlockModel.BOUNDING_BOX_LINES_BUFFER.len, @intCast(self.debug.addition_nodes.data.items.len));
                }
            }
        }

        self.shader_programs.selected_block.bind();
        {
            gl.Enable(gl.POLYGON_OFFSET_LINE);
            defer gl.Disable(gl.POLYGON_OFFSET_LINE);

            gl.PolygonOffset(-2.0, 1.0);
            defer gl.PolygonOffset(0.0, 0.0);

            gl.Enable(gl.LINE_SMOOTH);
            defer gl.Disable(gl.LINE_SMOOTH);

            gl.DepthFunc(gl.LEQUAL);
            defer gl.DepthFunc(gl.LESS);

            gl.DrawArrays(gl.LINES, 0, BlockModel.BOUNDING_BOX_LINES_BUFFER.len);
        }

        if (self.settings.relative_selector) {
            self.shader_programs.relative_selector.bind();

            gl.Enable(gl.POLYGON_OFFSET_LINE);
            defer gl.Disable(gl.POLYGON_OFFSET_LINE);

            gl.PolygonOffset(-2.0, 1.0);
            defer gl.PolygonOffset(0.0, 0.0);

            gl.Enable(gl.LINE_SMOOTH);
            defer gl.Disable(gl.LINE_SMOOTH);

            gl.DepthFunc(gl.LEQUAL);
            defer gl.DepthFunc(gl.LESS);

            gl.DrawArrays(gl.LINES, 0, BlockModel.BOUNDING_BOX_LINES_BUFFER.len);
        }

        self.shader_programs.crosshair.bind();
        gl.DrawArrays(gl.TRIANGLES, 0, 6);

        self.shader_programs.text.bind();
        gl.DrawArrays(gl.TRIANGLES, 0, @intCast(self.text_manager.vertices.data.items.len));
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

    try game.world.generate(gpa);

    // const index = try game.world.addBlockExtendedData(allocator, .initChest(@splat(0)));
    // try game.world.setBlock(allocator, .{ .x = 0, .y = 2, .z = 0 }, .initExtended(.chest, index));

    // for (0..6) |x| {
    //     for (0..6) |y| {
    //         for (0..6) |z| {
    //             try game.world.setBlock(allocator, .{ .x = @intCast(x + 6), .y = @intCast(y + 6), .z = @intCast(z + 6) }, .initNone(.stone));
    //         }
    //     }
    // }

    try game.world.propagateLights(gpa, &game.debug);
    game.debug.removal_nodes.data.clearRetainingCapacity();
    game.debug.addition_nodes.data.clearRetainingCapacity();

    try game.world_mesh.generateMesh(gpa, &game.world);
    try game.world_mesh.generateVisibleChunkMeshes(gpa, &game.world, &game.camera);
    try game.world_mesh.generateCommands(gpa);

    game.world_mesh.uploadMesh();
    game.world_mesh.uploadCommands();

    var delta_time: gl.float = 1.0 / 60.0;
    var timer: std.time.Timer = try .start();

    while (!game.window.shouldClose()) {
        try game.handleInput(gpa, delta_time);
        try game.appendText(gpa);

        try game.processChanges(gpa);

        game.render();

        delta_time = @floatCast(@as(f64, @floatFromInt(timer.lap())) / 1_000_000_000.0);

        game.window.swapBuffers();
        glfw.pollEvents();
    }
}
