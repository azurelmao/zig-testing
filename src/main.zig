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

const c = @import("vma");

pub const std_options: std.Options = .{
    .log_level = .debug,
};

const Settings = struct {
    ui_scale: gl.sizei = 2,
    mouse_speed: gl.float = 10.0,
    movement_speed: gl.float = 16.0,
    chunk_borders: bool = true,
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
    // offscreen_framebuffer: Framebuffer,
    text_manager: TextManager,
    world: World,
    world_mesh: WorldMesh,
    selected_block: World.RaycastResult,

    fn init(allocator: std.mem.Allocator) !Game {
        const settings: Settings = .{};
        const screen: Screen = .{};
        const camera: Camera = .init(.new(0, 0, 0), 0, 0, screen.aspect_ratio);

        const world: World = try .init(30);
        const selected_block = world.raycast(camera.position, camera.direction);

        try initGLFW();
        const window = try initWindow(&screen);

        const callback_user_data = try allocator.create(callback.UserData);
        callback_user_data.* = .default;
        window.setUserPointer(@ptrCast(callback_user_data));

        try initGL();
        var uniform_buffer: UniformBuffer = .init(0);
        uniform_buffer.uploadSelectedBlockPos(selected_block.pos.toVec3f());
        uniform_buffer.uploadViewProjectionMatrix(camera.view_projection_matrix);

        const shader_programs: ShaderPrograms = try .init(allocator, selected_block, screen);

        stbi.init(allocator);
        const textures: Textures = try .init();
        const shader_storage_buffers: ShaderStorageBuffers = try .init();
        // const offscreen_framebuffer: Framebuffer = try .init(3, screen.window_width, screen.window_height);
        const text_manager: TextManager = .init();

        const world_mesh: WorldMesh = .init();

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
            // .offscreen_framebuffer = offscreen_framebuffer,
            .text_manager = text_manager,
            .world = world,
            .world_mesh = world_mesh,
            .selected_block = selected_block,
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

        return window;
    }

    fn handleInput(self: *Game, allocator: std.mem.Allocator, delta_time: gl.float) !void {
        const mouse_speed = self.settings.mouse_speed * delta_time;
        const movement_speed = self.settings.movement_speed * delta_time;

        var calc_view_matrix = false;
        var calc_projection_matrix = false;

        if (self.callback_user_data.new_key_action) |new_key_action| {
            if (new_key_action.action == .press) switch (new_key_action.key) {
                .escape => self.window.setShouldClose(true),
                .F4 => self.settings.chunk_borders = !self.settings.chunk_borders,
                else => {},
            };

            self.callback_user_data.new_key_action = null;
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
            defer self.callback_user_data.new_window_size = null;

            self.screen.window_width = new_window_size.window_width;
            self.screen.window_height = new_window_size.window_height;
            self.screen.window_width_f = @floatFromInt(new_window_size.window_width);
            self.screen.window_height_f = @floatFromInt(new_window_size.window_height);

            self.screen.calcAspectRatio();
            self.shader_programs.crosshair.setUniform2f("uWindowSize", self.screen.window_width_f, self.screen.window_height_f);

            gl.Viewport(0, 0, self.screen.window_width, self.screen.window_height);

            // try self.offscreen_framebuffer.resizeAndBind(self.screen.window_width, self.screen.window_height, 3);

            calc_projection_matrix = true;
        }

        if (self.callback_user_data.new_cursor_pos) |new_cursor_pos| {
            defer self.callback_user_data.new_cursor_pos = null;

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

            try self.world_mesh.generateVisibleChunkMeshes(allocator, &self.world, &self.camera);
            try self.world_mesh.generateCommands(allocator);
            self.world_mesh.uploadCommands();

            self.selected_block = self.world.raycast(self.camera.position, self.camera.direction);

            const selected_block_pos = self.selected_block.pos.toVec3f();
            self.uniform_buffer.uploadSelectedBlockPos(selected_block_pos);

            const side = self.selected_block.side;

            if (side != .out_of_bounds and side != .inside) {
                if (self.selected_block.block) |block| {
                    const face_idx = block.kind.getModelIdx() + side.idx();
                    self.shader_programs.selected_side.setUniform1ui("uFaceIdx", @intCast(face_idx));
                }
            }

            self.uniform_buffer.uploadViewProjectionMatrix(self.camera.view_projection_matrix);
        }
    }

    fn appendRaycastText(self: *Game, allocator: std.mem.Allocator, original_line: i32) !i32 {
        const world_pos = self.selected_block.pos;
        const side = self.selected_block.side;

        var line = original_line;

        switch (side) {
            else => {
                try self.text_manager.append(allocator, .{
                    .pixel_x = 0,
                    .pixel_y = line * 6,
                    .text = try std.fmt.allocPrint(allocator, "looking at: [x: {d} y: {d} z: {d}] on side: {s}", .{
                        world_pos.x,
                        world_pos.y,
                        world_pos.z,
                        @tagName(side),
                    }),
                });
                line += 1;

                try self.text_manager.append(allocator, .{
                    .pixel_x = 0,
                    .pixel_y = line * 6,
                    .text = try std.fmt.allocPrint(allocator, "block: {s}", .{
                        if (self.selected_block.block) |block| @tagName(block.kind) else "null",
                    }),
                });
                line += 1;

                if (self.world.getLight(world_pos.add(World.Pos.Offsets[side.idx()]))) |light| {
                    try self.text_manager.append(allocator, .{
                        .pixel_x = 0,
                        .pixel_y = line * 6,
                        .text = try std.fmt.allocPrint(allocator, "light: [r: {} g: {} b: {} i: {}]", .{
                            light.red,
                            light.green,
                            light.blue,
                            light.indirect,
                        }),
                    });
                    line += 1;
                } else |_| {
                    try self.text_manager.append(allocator, .{
                        .pixel_x = 0,
                        .pixel_y = line * 6,
                        .text = try std.fmt.allocPrint(allocator, "light: out_of_bounds", .{}),
                    });
                    line += 1;
                }
            },

            .inside => {
                const light = try self.world.getLight(world_pos);

                try self.text_manager.append(allocator, .{
                    .pixel_x = 0,
                    .pixel_y = line * 6,
                    .text = try std.fmt.allocPrint(allocator, "looking at: [x: {d} y: {d} z: {d}] on side: {s}", .{
                        world_pos.x,
                        world_pos.y,
                        world_pos.z,
                        @tagName(side),
                    }),
                });
                line += 1;

                try self.text_manager.append(allocator, .{
                    .pixel_x = 0,
                    .pixel_y = line * 6,
                    .text = try std.fmt.allocPrint(allocator, "block: {s}", .{
                        if (self.selected_block.block) |block| @tagName(block.kind) else "null",
                    }),
                });
                line += 1;

                try self.text_manager.append(allocator, .{
                    .pixel_x = 0,
                    .pixel_y = line * 6,
                    .text = try std.fmt.allocPrint(allocator, "light: [r: {} g: {} b: {} i: {}]", .{
                        light.red,
                        light.green,
                        light.blue,
                        light.indirect,
                    }),
                });
                line += 1;
            },

            .out_of_bounds => {
                try self.text_manager.append(allocator, .{
                    .pixel_x = 0,
                    .pixel_y = line * 6,
                    .text = try std.fmt.allocPrint(allocator, "looking at: [x: {d} y: {d} z: {d}] on side: {s}", .{
                        world_pos.x,
                        world_pos.y,
                        world_pos.z,
                        @tagName(side),
                    }),
                });
                line += 1;
            },
        }

        return line;
    }

    fn appendText(self: *Game, allocator: std.mem.Allocator) !void {
        self.text_manager.clear();

        var line: i32 = 0;

        try self.text_manager.append(allocator, .{
            .pixel_x = 0,
            .pixel_y = line * 6,
            .text = TITLE,
        });
        line += 1;

        try self.text_manager.append(allocator, .{
            .pixel_x = 0,
            .pixel_y = line * 6,
            .text = try std.fmt.allocPrint(allocator, "visible: {}", .{self.world_mesh.visible_chunk_meshes.items.len}),
        });
        line += 1;

        const camera_world_pos = self.camera.position.toWorldPos();
        const camera_local_pos = camera_world_pos.toLocalPos();
        const camera_chunk_pos = camera_world_pos.toChunkPos();

        try self.text_manager.append(allocator, .{
            .pixel_x = 0,
            .pixel_y = line * 6,
            .text = try std.fmt.allocPrint(allocator, "chunk: [x: {} y: {} z: {}]", .{ camera_chunk_pos.x, camera_chunk_pos.y, camera_chunk_pos.z }),
        });
        line += 1;

        try self.text_manager.append(allocator, .{
            .pixel_x = 0,
            .pixel_y = line * 6,
            .text = try std.fmt.allocPrint(allocator, "local: [x: {} y: {} z: {}]", .{ camera_local_pos.x, camera_local_pos.y, camera_local_pos.z }),
        });
        line += 1;

        try self.text_manager.append(allocator, .{
            .pixel_x = 0,
            .pixel_y = line * 6,
            .text = try std.fmt.allocPrint(allocator, "world: [x: {} y: {} z: {}]", .{ camera_world_pos.x, camera_world_pos.y, camera_world_pos.z }),
        });
        line += 1;

        try self.text_manager.append(allocator, .{
            .pixel_x = 0,
            .pixel_y = line * 6,
            .text = try std.fmt.allocPrint(allocator, "camera: [x: {d:.6} y: {d:.6} z: {d:.6}]", .{ self.camera.position.x, self.camera.position.y, self.camera.position.z }),
        });
        line += 1;

        try self.text_manager.append(allocator, .{
            .pixel_x = 0,
            .pixel_y = line * 6,
            .text = try std.fmt.allocPrint(allocator, "yaw: {d:.2} pitch: {d:.2}", .{ @mod(self.camera.yaw, 360.0), self.camera.pitch }),
        });
        line += 1;

        line = try self.appendRaycastText(allocator, line);
        try self.text_manager.build(allocator, self.screen.window_width, self.screen.window_height, self.settings.ui_scale);
    }

    fn render(self: *Game) void {
        gl.ClearColor(0.47843137254901963, 0.6588235294117647, 0.9921568627450981, 1.0);
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

        self.shader_programs.chunks.bind();
        for (&self.world_mesh.layers) |*world_mesh_layer| {
            if (world_mesh_layer.command.data.items.len == 0) continue;

            world_mesh_layer.mesh.ssbo.bind(1);
            world_mesh_layer.chunk_mesh_pos.ssbo.bind(2);
            world_mesh_layer.command.ssbo.bindAsIndirectBuffer();

            gl.MultiDrawArraysIndirect(gl.TRIANGLES, null, @intCast(world_mesh_layer.command.data.items.len), 0);
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

        // gl.BlitNamedFramebuffer(0, self.offscreen_framebuffer.framebuffer_handle, 0, 0, self.screen.window_width, self.screen.window_height, 0, 0, self.screen.window_width, self.screen.window_height, gl.COLOR_BUFFER_BIT, gl.LINEAR);

        // if (self.settings.chunk_borders) {
        //     self.shader_programs.chunks_debug.bind();
        //     {
        //         gl.Enable(gl.POLYGON_OFFSET_LINE);
        //         defer gl.Disable(gl.POLYGON_OFFSET_LINE);

        //         gl.PolygonOffset(-1.0, 1.0);
        //         defer gl.PolygonOffset(0.0, 0.0);

        //         gl.Enable(gl.LINE_SMOOTH);
        //         defer gl.Disable(gl.LINE_SMOOTH);

        //         gl.DrawArraysInstanced(gl.LINES, 0, 36, @intCast(self.world_mesh.pos.data.items.len));
        //     }
        // }

        // if (self.selected_block.side != .out_of_bounds and self.selected_block.side != .inside) {
        //     if (self.selected_block.block) |_| {
        //         self.shader_programs.selected_side.bind();
        //         {
        //             gl.Enable(gl.POLYGON_OFFSET_FILL);
        //             defer gl.Disable(gl.POLYGON_OFFSET_FILL);

        //             gl.PolygonOffset(-1.0, 1.0);
        //             defer gl.PolygonOffset(0.0, 0.0);

        //             gl.DrawArrays(gl.TRIANGLES, 0, 6);
        //         }
        //     }
        // }

        // self.shader_programs.selected_block.bind();
        // {
        //     gl.Enable(gl.POLYGON_OFFSET_LINE);
        //     defer gl.Disable(gl.POLYGON_OFFSET_LINE);

        //     gl.PolygonOffset(-2.0, 1.0);
        //     defer gl.PolygonOffset(0.0, 0.0);

        //     gl.Enable(gl.LINE_SMOOTH);
        //     defer gl.Disable(gl.LINE_SMOOTH);

        //     gl.DepthFunc(gl.LEQUAL);
        //     defer gl.DepthFunc(gl.LESS);

        //     gl.DrawArrays(gl.LINES, 0, BlockModel.BOUNDING_BOX_LINES_BUFFER.len);
        // }

        // self.shader_programs.crosshair.bind();
        // gl.DrawArrays(gl.TRIANGLES, 0, 6);

        // self.shader_programs.text.bind();
        // gl.DrawArrays(gl.TRIANGLES, 0, @intCast(self.text_manager.vertices.data.items.len));
    }

    fn deinit(self: *Game) void {
        self.window.destroy();
        gl.makeProcTableCurrent(null);
        glfw.terminate();
        stbi.deinit();
    }
};

// pub fn RegionManager(comptime T: type) type {
//     return struct {
//         buffer: []T,
//         regions: std.ArrayListUnmanaged(Region),

//         const Self = @This();

//         pub fn init(allocator: std.mem.Allocator, len: usize) !Self {
//             const buffer = try allocator.alloc(T, len);

//             var regions: std.ArrayListUnmanaged(Region) = try .empty;
//             regions.append(allocator, .{
//                 .offset = 0,
//                 .len = len,
//                 .free = true,
//             });

//             return .{
//                 .buffer = buffer,
//                 .regions = regions,
//             };
//         }

//         pub fn create(self: *Self, allocator: std.mem.Allocator, data: []const T) !void {
//             for (self.regions.items) |*region| {
//                 if (region.free and region.len >= data.len) {
//                     const len_left = region.len - data.len;

//                     region.free = false;
//                     region.len = data.len;

//                     if (len_left != 0) {
//                         self.regions.append(allocator, .{
//                             .offset = data.len,
//                             .len = len_left,
//                             .free = true,
//                         });
//                     }

//                     @memcpy(self.buffer[0..data.len], data[0..]);

//                     return;
//                 }
//             }

//             // out of regions, have to realloc buffer, will also defragmentize
//             const new_buffer = try allocator.alloc(T, self.buffer.len + data.len);

//             var last_free_region_index: usize = 0;
//             var last_region_len: usize = 0;
//             for (self.regions.items, 0..) |region, index| {
//                 if (region.free) {
//                     last_free_region_index = index;
//                 } else {
//                     const last_free_region = self.regions.items[last_free_region_index];

//                     self.regions.items[last_free_region_index] = .{
//                         .offset = last_free_region.offset,
//                         .len = region.len,
//                         .free = false,
//                     };

//                     last_region_len =
//                 }
//             }
//         }

//         const Region = struct {
//             offset: usize,
//             len: usize,
//             free: bool,
//         };
//     };
// }

var procs: gl.ProcTable = undefined;

pub fn main() !void {
    // var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    // defer arena.deinit();
    // const allocator = arena.allocator();

    const allocator = std.heap.smp_allocator;

    var game: Game = try .init(allocator);
    defer game.deinit();

    try game.world.generate(allocator);

    // const index = try game.world.addBlockExtendedData(allocator, .initChest(@splat(0)));
    // try game.world.setBlock(allocator, .{ .x = 0, .y = 2, .z = 0 }, .initExtended(.chest, index));

    try game.world.propagateLights(allocator);

    try game.world_mesh.generateMesh(allocator, &game.world);
    try game.world_mesh.generateVisibleChunkMeshes(allocator, &game.world, &game.camera);
    try game.world_mesh.generateCommands(allocator);

    game.world_mesh.uploadMesh();
    game.world_mesh.uploadCommands();

    var delta_time: gl.float = 1.0 / 60.0;
    var timer: std.time.Timer = try .start();

    while (!game.window.shouldClose()) {
        try game.handleInput(allocator, delta_time);
        try game.appendText(allocator);

        game.render();

        delta_time = @floatCast(@as(f64, @floatFromInt(timer.lap())) / 1_000_000_000.0);

        game.window.swapBuffers();
        glfw.pollEvents();
    }
}
