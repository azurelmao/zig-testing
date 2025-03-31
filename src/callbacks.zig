const std = @import("std");
const gl = @import("gl");
const glfw = @import("glfw");

const NewWindowSize = struct {
    window_width: gl.sizei,
    window_height: gl.sizei,
};

const NewCursorPos = struct {
    cursor_x: gl.float,
    cursor_y: gl.float,
};

pub const WindowUserData = struct {
    new_window_size: ?NewWindowSize = null,
    new_cursor_pos: ?NewCursorPos = null,
};

pub fn errorCallback(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    std.log.err("glfw: {}: {s}\n", .{ error_code, description });
}

pub fn keyCallback(window: glfw.Window, key: glfw.Key, scancode: i32, action: glfw.Action, mods: glfw.Mods) void {
    _ = scancode;
    _ = mods;

    switch (key) {
        .escape => if (action == .press) {
            window.setShouldClose(true);
        },
        else => {},
    }
}

pub fn cursorCallback(window: glfw.Window, cursor_x: f64, cursor_y: f64) void {
    window.getUserPointer(WindowUserData).?.*.new_cursor_pos = .{
        .cursor_x = @floatCast(cursor_x),
        .cursor_y = @floatCast(cursor_y),
    };
}

pub fn framebufferSizeCallback(window: glfw.Window, window_width: u32, window_height: u32) void {
    window.getUserPointer(WindowUserData).?.*.new_window_size = .{
        .window_width = @intCast(window_width),
        .window_height = @intCast(window_height),
    };
}

pub fn debugCallback(source: gl.@"enum", @"type": gl.@"enum", id: gl.uint, severity: gl.@"enum", length: gl.sizei, message: [*:0]const u8, user_params: ?*const anyopaque) callconv(gl.APIENTRY) void {
    _ = user_params;

    const message_slice = message[0..@intCast(length)];

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

    const format = "opengl: id: {} source: {s} type: {s}\n{?s}";
    const args = .{ id, source_str, type_str, message_slice };

    switch (severity) {
        gl.DEBUG_SEVERITY_HIGH => std.log.err(format, args),
        gl.DEBUG_SEVERITY_MEDIUM => std.log.warn(format, args),
        else => std.log.info(format, args),
    }
}
