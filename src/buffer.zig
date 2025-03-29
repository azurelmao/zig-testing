const std = @import("std");
const gl = @import("gl");

pub fn ShaderStorageBufferUnmanaged(comptime T: type) type {
    return struct {
        handle: gl.uint,
        flags: gl.bitfield,

        const Self = @This();

        pub fn init(flags: gl.bitfield) Self {
            return .{
                .handle = 0,
                .flags = flags,
            };
        }

        pub fn bindBuffer(self: *Self, index: gl.uint) void {
            gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, index, self.handle);
        }

        pub fn bindIndirectBuffer(self: *Self) void {
            gl.BindBuffer(gl.DRAW_INDIRECT_BUFFER, self.handle);
        }

        pub fn initBuffer(self: *Self, buffer: []const T) void {
            gl.CreateBuffers(1, @ptrCast(&self.handle));
            gl.NamedBufferStorage(
                self.handle,
                @intCast(@sizeOf(T) * buffer.len),
                @ptrCast(buffer.ptr),
                self.flags,
            );
        }

        pub fn initBufferAndBind(self: *Self, buffer: []const T, index: gl.uint) void {
            self.initBuffer(buffer);
            self.bindBuffer(index);
        }

        pub fn resizeBuffer(self: *Self, buffer: []const T) void {
            if (self.handle != 0) {
                gl.DeleteBuffers(1, @ptrCast(&self.handle));
                self.handle = 0;
            }

            gl.CreateBuffers(1, @ptrCast(&self.handle));
            gl.NamedBufferStorage(
                self.handle,
                @intCast(@sizeOf(T) * buffer.len),
                @ptrCast(buffer.ptr),
                self.flags,
            );
        }

        pub fn resizeBufferAndBind(self: *Self, buffer: []const T, index: gl.uint) void {
            self.resizeBuffer(buffer);
            self.bindBuffer(index);
        }

        pub fn uploadBuffer(self: *Self, buffer: []const T) void {
            gl.NamedBufferSubData(
                self.handle,
                0,
                @intCast(@sizeOf(T) * buffer.len),
                @ptrCast(buffer.ptr),
            );
        }
    };
}

pub fn ShaderStorageBuffer(comptime T: type) type {
    return struct {
        buffer: std.ArrayListUnmanaged(T),
        unmanaged: ShaderStorageBufferUnmanaged(T),

        const Self = @This();

        pub fn init(flags: gl.bitfield) Self {
            return .{
                .buffer = .empty,
                .unmanaged = .init(flags),
            };
        }

        pub fn bindBuffer(self: *Self, index: gl.uint) void {
            self.unmanaged.bindBuffer(index);
        }

        pub fn bindIndirectBuffer(self: *Self) void {
            self.unmanaged.bindIndirectBuffer();
        }

        pub fn initBuffer(self: *Self) void {
            self.unmanaged.initBuffer(self.buffer.items);
        }

        pub fn initBufferAndBind(self: *Self, index: gl.uint) void {
            self.unmanaged.initBufferAndBind(self.buffer.items, index);
        }

        pub fn resizeBuffer(self: *Self) void {
            self.unmanaged.resizeBuffer(self.buffer.items);
        }

        pub fn resizeBufferAndBind(self: *Self, index: gl.uint) void {
            self.unmanaged.resizeBufferAndBind(self.buffer.items, index);
        }

        pub fn uploadBuffer(self: *Self) void {
            self.unmanaged.uploadBuffer(self.buffer.items);
        }
    };
}
