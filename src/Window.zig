const std = @import("std");
const gl = @import("gl");
const glfw = @import("glfw");
const callback = @import("callback.zig");

const Window = @This();

pub const INITIAL_WIDTH = 640.0;
pub const INITIAL_HEIGHT = 480.0;

handle: glfw.Window,
width: gl.sizei,
height: gl.sizei,
width_f: gl.float,
height_f: gl.float,

prev_cursor_x: gl.float,
prev_cursor_y: gl.float,

aspect_ratio: gl.float,

pub fn init(width: gl.sizei, height: gl.sizei, title: [*:0]const u8, debug_context: bool) !Window {
    const handle = glfw.Window.create(@intCast(width), @intCast(height), title, null, null, .{
        .opengl_profile = .opengl_core_profile,
        .context_version_major = 4,
        .context_version_minor = 6,
        .context_debug = debug_context,
    }) orelse {
        std.log.err("failed to create GLFW window: {?s}", .{glfw.getErrorString()});
        return error.WindowCreationFailed;
    };

    glfw.makeContextCurrent(handle);

    const width_f: gl.float = @floatFromInt(width);
    const height_f: gl.float = @floatFromInt(height);

    const prev_cursor_x = width_f / 2.0;
    const prev_cursor_y = height_f / 2.0;

    handle.setInputModeCursor(.disabled);
    handle.setCursorPos(prev_cursor_x, prev_cursor_y);
    handle.setCursorPosCallback(callback.cursorCallback);
    handle.setFramebufferSizeCallback(callback.framebufferSizeCallback);
    handle.setKeyCallback(callback.keyCallback);
    handle.setMouseButtonCallback(callback.buttonCallback);

    return .{
        .handle = handle,
        .width = width,
        .height = height,
        .width_f = width_f,
        .height_f = height_f,
        .prev_cursor_x = prev_cursor_x,
        .prev_cursor_y = prev_cursor_y,
        .aspect_ratio = width_f / height_f,
    };
}

pub fn calcAspectRatio(window: *Window) void {
    window.aspect_ratio = window.width_f / window.height_f;
}
