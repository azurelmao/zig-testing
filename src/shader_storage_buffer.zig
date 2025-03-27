const std = @import("std");
const gl = @import("gl");

pub fn ShaderStorageBuffer(comptime T: type) type {
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
