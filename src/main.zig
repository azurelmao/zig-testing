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
const chunk_bounding_box = @import("chunk_bounding_box.zig");
const callbacks = @import("callbacks.zig");
const ui = @import("ui.zig");

pub const std_options: std.Options = .{
    .log_level = .info,
};

var procs: gl.ProcTable = undefined;

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

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    stbi.init(allocator);

    glfw.setErrorCallback(callbacks.errorCallback);
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
        gl.DebugMessageCallback(callbacks.debugCallback, null);
        gl.DebugMessageControl(gl.DONT_CARE, gl.DONT_CARE, gl.DONT_CARE, 0, null, gl.TRUE);
    } else if (debug_context) {
        std.log.err("Failed to load OpenGL debug context", .{});
    }

    var window_user_data = callbacks.WindowUserData{};

    window.setUserPointer(@ptrCast(&window_user_data));

    window.setInputModeCursor(.disabled);
    window.setCursorPos(screen.prev_cursor_x, screen.prev_cursor_y);
    window.setCursorPosCallback(callbacks.cursorCallback);
    window.setFramebufferSizeCallback(callbacks.framebufferSizeCallback);
    window.setKeyCallback(callbacks.keyCallback);

    const Sun = struct {
        const Sun = @This();

        angle: gl.float,
        position: Vec3f,
        shadow_map_width: gl.sizei,
        shadow_map_height: gl.sizei,
        shadow_map_near: gl.float,
        shadow_map_far: gl.float,
        view_projection_matrix: Matrix4x4f,

        pub fn init(angle: gl.float, shadow_map_width: gl.sizei, shadow_map_height: gl.sizei, shadow_map_near: gl.float, shadow_map_far: gl.float) Sun {
            var sun = Sun{
                .angle = angle,
                .shadow_map_width = shadow_map_width,
                .shadow_map_height = shadow_map_height,
                .shadow_map_near = shadow_map_near,
                .shadow_map_far = shadow_map_far,
                .position = undefined,
                .view_projection_matrix = undefined,
            };

            sun.calcViewProjectionMatrix();

            return sun;
        }

        const DEG_TO_RAD: gl.float = std.math.pi / 180.0;

        pub fn calcViewProjectionMatrix(self: *Sun) void {
            const angle_rads = self.angle * DEG_TO_RAD;

            const x = std.math.cos(angle_rads);
            const y = std.math.sin(angle_rads);

            const position = Vec3f.new(x, y, 0).normalize().multiplyScalar(30);

            const view_matrix = Matrix4x4f.lookAt(position, Vec3f.new(0, 0, 0), Vec3f.new(0, 0, 1));
            const projection_matrix = Matrix4x4f.orthographic(@floatFromInt(self.shadow_map_width), @floatFromInt(self.shadow_map_height), self.shadow_map_near, self.shadow_map_far);

            self.view_projection_matrix = view_matrix.multiply(projection_matrix);
            self.position = position;
        }
    };
    var sun = Sun.init(90, 100, 100, 1, 60);

    var sun_shader_program = try ShaderProgram.init(allocator, "assets/shaders/sun_vs.glsl", "assets/shaders/sun_fs.glsl");
    sun_shader_program.setUniformMatrix4f("uViewProjection", sun.view_projection_matrix);

    var chunks_shader_program = try ShaderProgram.init(allocator, "assets/shaders/chunks_vs.glsl", "assets/shaders/chunks_fs.glsl");
    chunks_shader_program.setUniformMatrix4f("uViewProjection", camera.view_projection_matrix);
    chunks_shader_program.setUniformMatrix4f("uSunViewProjection", sun.view_projection_matrix);

    var chunks_bb_shader_program = try ShaderProgram.init(allocator, "assets/shaders/chunks_bb_vs.glsl", "assets/shaders/chunks_bb_fs.glsl");
    chunks_bb_shader_program.setUniformMatrix4f("uViewProjection", camera.view_projection_matrix);

    var chunks_debug_shader_program = try ShaderProgram.init(allocator, "assets/shaders/chunks_debug_vs.glsl", "assets/shaders/chunks_debug_fs.glsl");
    chunks_debug_shader_program.setUniformMatrix4f("uViewProjection", camera.view_projection_matrix);

    var text_shader_program = try ShaderProgram.init(allocator, "assets/shaders/text_vs.glsl", "assets/shaders/text_fs.glsl");

    var selected_block_shader_program = try ShaderProgram.init(allocator, "assets/shaders/selected_block_vs.glsl", "assets/shaders/selected_block_fs.glsl");
    selected_block_shader_program.setUniformMatrix4f("uViewProjection", camera.view_projection_matrix);

    var selected_side_shader_program = try ShaderProgram.init(allocator, "assets/shaders/selected_side_vs.glsl", "assets/shaders/selected_side_fs.glsl");
    selected_side_shader_program.setUniformMatrix4f("uViewProjection", camera.view_projection_matrix);

    var crosshair_shader_program = try ShaderProgram.init(allocator, "assets/shaders/crosshair_vs.glsl", "assets/shaders/crosshair_fs.glsl");
    crosshair_shader_program.setUniform2f("uWindowSize", screen.window_width_f, screen.window_height_f);

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

    var crosshair_image = try stbi.Image.loadFromFile("assets/textures/crosshair.png", 1);

    const crosshair_texture = Texture2D.init(crosshair_image, .{
        .texture_format = .r8,
        .data_format = .r,
    });
    crosshair_texture.bind(2);

    var indirect_light_image = try stbi.Image.loadFromFile("assets/textures/indirect_light.png", 4);
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

    var result = world.raycast(camera.position, camera.direction);
    var draw_selected_side = false;
    {
        const selected_pos = result.pos.toVec3f();
        selected_block_shader_program.setUniform3f("uBlockPosition", selected_pos.x, selected_pos.y, selected_pos.z);
        selected_side_shader_program.setUniform3f("uBlockPosition", selected_pos.x, selected_pos.y, selected_pos.z);

        const side = result.side;

        if (side != .out_of_bounds and side != .inside) {
            if (result.block) |block| {
                const model_idx = block.getModelIndices().faces[side.idx()];
                selected_side_shader_program.setUniform1ui("uModelIdx", model_idx);

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
    try chunk_mesh_layers.generate(allocator, &world);

    debug_time = @as(f64, @floatFromInt(debug_timer.lap())) / 1_000_000_000.0;
    std.log.info("Chunk mesh buffers done. {d} s", .{debug_time});

    debug_timer.reset();
    var visible_num = chunk_mesh_layers.cull(&camera);

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

    var selected_block_buffer = ShaderStorageBufferUnmanaged(Vec3f).init(gl.DYNAMIC_STORAGE_BIT);
    selected_block_buffer.initBufferAndBind(Block.bounding_box, 13);

    var text_manager = ui.TextManager.init();

    var vao_handle: gl.uint = undefined;
    gl.GenVertexArrays(1, @ptrCast(&vao_handle));
    gl.BindVertexArray(vao_handle);

    var offscreen_texture_handle: gl.uint = undefined;
    gl.CreateTextures(gl.TEXTURE_2D, 1, @ptrCast(&offscreen_texture_handle));
    gl.TextureStorage2D(offscreen_texture_handle, 1, gl.RGBA8, screen.window_width, screen.window_height);
    gl.BindTextureUnit(3, offscreen_texture_handle);

    var offscreen_framebuffer_handle: gl.uint = undefined;
    gl.CreateFramebuffers(1, @ptrCast(&offscreen_framebuffer_handle));
    gl.NamedFramebufferTexture(offscreen_framebuffer_handle, gl.COLOR_ATTACHMENT0, offscreen_texture_handle, 0);

    if (gl.CheckNamedFramebufferStatus(offscreen_framebuffer_handle, gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE) {
        std.debug.panic("Incomplete offscreen framebuffer status", .{});
    }

    var shadow_texture_handle: gl.uint = undefined;
    gl.CreateTextures(gl.TEXTURE_2D, 1, @ptrCast(&shadow_texture_handle));
    gl.TextureStorage2D(shadow_texture_handle, 1, gl.DEPTH_COMPONENT32F, sun.shadow_map_width, sun.shadow_map_height);
    gl.TextureParameteri(shadow_texture_handle, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.TextureParameteri(shadow_texture_handle, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.BindTextureUnit(4, shadow_texture_handle);

    var shadow_framebuffer_handle: gl.uint = undefined;
    gl.CreateFramebuffers(1, @ptrCast(&shadow_framebuffer_handle));
    gl.NamedFramebufferTexture(shadow_framebuffer_handle, gl.DEPTH_ATTACHMENT, shadow_texture_handle, 0);

    if (gl.CheckNamedFramebufferStatus(shadow_framebuffer_handle, gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE) {
        std.debug.panic("Incomplete shadow framebuffer status", .{});
    }

    gl.Enable(gl.DEPTH_TEST);
    gl.Enable(gl.CULL_FACE);
    gl.Enable(gl.BLEND);
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

    var delta_time: gl.float = 1.0 / 60.0;
    var timer = try std.time.Timer.start();

    while (!window.shouldClose()) {
        const mouse_speed = settings.mouse_speed * delta_time;
        const movement_speed = settings.movement_speed * delta_time;

        var calc_view_matrix = false;
        var calc_projection_matrix = false;

        if (window.getKey(glfw.Key.s) == .press) {
            camera.position.subtractInPlace(camera.horizontal_direction.multiplyScalar(movement_speed));
            calc_view_matrix = true;
        }

        if (window.getKey(glfw.Key.w) == .press) {
            camera.position.addInPlace(camera.horizontal_direction.multiplyScalar(movement_speed));
            calc_view_matrix = true;
        }

        if (window.getKey(glfw.Key.left_shift) == .press) {
            camera.position.subtractInPlace(Camera.up.multiplyScalar(movement_speed));
            calc_view_matrix = true;
        }

        if (window.getKey(glfw.Key.space) == .press) {
            camera.position.addInPlace(Camera.up.multiplyScalar(movement_speed));
            calc_view_matrix = true;
        }

        if (window.getKey(glfw.Key.a) == .press) {
            camera.position.subtractInPlace(camera.right.multiplyScalar(movement_speed));
            calc_view_matrix = true;
        }

        if (window.getKey(glfw.Key.d) == .press) {
            camera.position.addInPlace(camera.right.multiplyScalar(movement_speed));
            calc_view_matrix = true;
        }

        if (window_user_data.new_window_size) |new_window_size| {
            screen.window_width = new_window_size.window_width;
            screen.window_height = new_window_size.window_height;
            screen.window_width_f = @floatFromInt(new_window_size.window_width);
            screen.window_height_f = @floatFromInt(new_window_size.window_height);

            screen.calcAspectRatio();
            crosshair_shader_program.setUniform2f("uWindowSize", screen.window_width_f, screen.window_height_f);

            gl.Viewport(0, 0, screen.window_width, screen.window_height);

            gl.DeleteTextures(1, @ptrCast(&offscreen_texture_handle));
            gl.CreateTextures(gl.TEXTURE_2D, 1, @ptrCast(&offscreen_texture_handle));
            gl.TextureStorage2D(offscreen_texture_handle, 1, gl.RGBA8, screen.window_width, screen.window_height);
            gl.BindTextureUnit(3, offscreen_texture_handle);

            gl.DeleteFramebuffers(1, @ptrCast(&offscreen_framebuffer_handle));
            gl.CreateFramebuffers(1, @ptrCast(&offscreen_framebuffer_handle));
            gl.NamedFramebufferTexture(offscreen_framebuffer_handle, gl.COLOR_ATTACHMENT0, offscreen_texture_handle, 0);

            calc_projection_matrix = true;
        }

        if (window_user_data.new_cursor_pos) |new_cursor_pos| {
            const offset_x = (new_cursor_pos.cursor_x - screen.prev_cursor_x) * mouse_speed;
            const offset_y = (screen.prev_cursor_y - new_cursor_pos.cursor_y) * mouse_speed;

            screen.prev_cursor_x = new_cursor_pos.cursor_x;
            screen.prev_cursor_y = new_cursor_pos.cursor_y;

            camera.yaw += offset_x;
            camera.pitch = std.math.clamp(camera.pitch + offset_y, -89.0, 89.0);

            camera.calcDirectionAndRight();

            calc_view_matrix = true;
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

            visible_num = chunk_mesh_layers.cull(&camera);
            chunk_mesh_layers.uploadCommandBuffers();

            result = world.raycast(camera.position, camera.direction);

            const selected_pos = result.pos.toVec3f();
            selected_block_shader_program.setUniform3f("uBlockPosition", selected_pos.x, selected_pos.y, selected_pos.z);
            selected_side_shader_program.setUniform3f("uBlockPosition", selected_pos.x, selected_pos.y, selected_pos.z);

            const side = result.side;

            if (side != .out_of_bounds and side != .inside) {
                if (result.block) |block| {
                    const model_idx = block.getModelIndices().faces[side.idx()];
                    selected_side_shader_program.setUniform1ui("uModelIdx", model_idx);

                    draw_selected_side = true;
                } else {
                    draw_selected_side = false;
                }
            } else {
                draw_selected_side = false;
            }

            chunks_shader_program.setUniformMatrix4f("uViewProjection", camera.view_projection_matrix);
            chunks_bb_shader_program.setUniformMatrix4f("uViewProjection", camera.view_projection_matrix);
            chunks_debug_shader_program.setUniformMatrix4f("uViewProjection", camera.view_projection_matrix);
            selected_block_shader_program.setUniformMatrix4f("uViewProjection", camera.view_projection_matrix);
            selected_side_shader_program.setUniformMatrix4f("uViewProjection", camera.view_projection_matrix);
        }

        const depth: gl.float = 1.0;
        gl.ClearNamedFramebufferfv(shadow_framebuffer_handle, gl.DEPTH, 0, @ptrCast(&depth));

        sun_shader_program.bind();
        {
            gl.BindFramebuffer(gl.FRAMEBUFFER, shadow_framebuffer_handle);
            defer gl.BindFramebuffer(gl.FRAMEBUFFER, 0);

            gl.Viewport(0, 0, sun.shadow_map_width, sun.shadow_map_height);
            defer gl.Viewport(0, 0, screen.window_width, screen.window_height);

            inline for (0..Block.Layer.len) |layer_idx| {
                const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];

                if (chunk_mesh_layer.mesh.buffer.items.len > 0) {
                    chunk_mesh_layer.mesh.bindBuffer(3);
                    chunk_mesh_layer.command.bindIndirectBuffer();

                    gl.MultiDrawArraysIndirect(gl.TRIANGLES, null, @intCast(chunk_mesh_layer.command.buffer.items.len), 0);
                }
            }
        }

        gl.ClearColor(0.47843137254901963, 0.6588235294117647, 0.9921568627450981, 1.0);
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

        chunks_shader_program.bind();
        inline for (0..Block.Layer.len) |layer_idx| {
            const chunk_mesh_layer = &chunk_mesh_layers.layers[layer_idx];

            if (chunk_mesh_layer.mesh.buffer.items.len > 0) {
                chunk_mesh_layer.mesh.bindBuffer(3);
                chunk_mesh_layer.command.bindIndirectBuffer();

                gl.MultiDrawArraysIndirect(gl.TRIANGLES, null, @intCast(chunk_mesh_layer.command.buffer.items.len), 0);
            }
        }

        chunk_mesh_layers.clearCommandBuffers();
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

        if (draw_selected_side) {
            selected_side_shader_program.bind();
            {
                gl.Enable(gl.POLYGON_OFFSET_FILL);
                defer gl.Disable(gl.POLYGON_OFFSET_FILL);

                gl.PolygonOffset(-1.0, 1.0);
                defer gl.PolygonOffset(0.0, 0.0);

                gl.DrawArrays(gl.TRIANGLES, 0, 6);
            }
        }

        selected_block_shader_program.bind();
        selected_block_shader_program.setUniform3f("uBlockPosition", sun.position.x, sun.position.y, sun.position.z);
        {
            gl.Enable(gl.POLYGON_OFFSET_LINE);
            defer gl.Disable(gl.POLYGON_OFFSET_LINE);

            gl.PolygonOffset(-2.0, 1.0);
            defer gl.PolygonOffset(0.0, 0.0);

            gl.Enable(gl.LINE_SMOOTH);
            defer gl.Disable(gl.LINE_SMOOTH);

            gl.DepthFunc(gl.LEQUAL);
            defer gl.DepthFunc(gl.LESS);

            gl.DrawArrays(gl.LINES, 0, Block.bounding_box.len);
        }

        crosshair_shader_program.bind();
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

        try onRaycast(allocator, &world, &text_manager, result);

        try text_manager.buildVertices(allocator, screen.window_width, screen.window_height, settings.ui_scale);
        text_manager.text_vertices.resizeBufferAndBind(12);

        text_shader_program.bind();
        gl.DrawArrays(gl.TRIANGLES, 0, @intCast(text_manager.text_vertices.buffer.items.len));

        sun.calcViewProjectionMatrix();
        sun_shader_program.setUniformMatrix4f("uViewProjection", sun.view_projection_matrix);
        chunks_shader_program.setUniformMatrix4f("uSunViewProjection", sun.view_projection_matrix);

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
    crosshair_image.deinit();

    stbi.deinit();
}
