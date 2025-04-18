const std = @import("std");
const gl = @import("gl");

pub fn ShaderStorageBuffer(comptime T: type) type {
    return struct {
        handle: gl.uint,
        len: usize,
        flags: gl.bitfield,

        const Self = @This();

        pub fn init(len: usize, flags: gl.bitfield) Self {
            var handle: gl.uint = undefined;
            gl.CreateBuffers(1, @ptrCast(&handle));
            gl.NamedBufferStorage(
                handle,
                @intCast(@sizeOf(T) * len),
                null,
                flags,
            );

            return .{
                .handle = handle,
                .len = len,
                .flags = flags,
            };
        }

        pub fn initAndBind(index: gl.uint, len: usize, flags: gl.bitfield) Self {
            const self = init(len, flags);
            gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, index, self.handle);

            return self;
        }

        pub fn initFromSlice(data: []const T, flags: gl.bitfield) Self {
            var handle: gl.uint = undefined;
            gl.CreateBuffers(1, @ptrCast(&handle));
            gl.NamedBufferStorage(
                handle,
                @intCast(@sizeOf(T) * data.len),
                @ptrCast(data.ptr),
                flags,
            );

            return .{
                .handle = handle,
                .len = data.len,
                .flags = flags,
            };
        }

        pub fn initFromSliceAndBind(index: gl.uint, data: []const T, flags: gl.bitfield) Self {
            const self = initFromSlice(data, flags);
            gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, index, self.handle);

            return self;
        }

        pub fn bind(self: *const Self, index: gl.uint) void {
            gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, index, self.handle);
        }

        pub fn bindAsIndirectBuffer(self: *const Self) void {
            gl.BindBuffer(gl.DRAW_INDIRECT_BUFFER, self.handle);
        }

        pub fn resize(self: *Self, len: usize) void {
            gl.DeleteBuffers(1, @ptrCast(&self.handle));

            gl.CreateBuffers(1, @ptrCast(&self.handle));
            gl.NamedBufferStorage(
                self.handle,
                @intCast(@sizeOf(T) * len),
                null,
                self.flags,
            );
        }

        pub fn upload(self: *const Self, data: []const T) !void {
            if (data.len > self.len) return error.DataTooLarge;

            gl.NamedBufferSubData(
                self.handle,
                0,
                @intCast(@sizeOf(T) * data.len),
                @ptrCast(data.ptr),
            );
        }

        pub fn uploadAndOrResize(self: *Self, data: []const T) void {
            if (data.len > self.len) {
                gl.DeleteBuffers(1, @ptrCast(&self.handle));

                gl.CreateBuffers(1, @ptrCast(&self.handle));
                gl.NamedBufferStorage(
                    self.handle,
                    @intCast(@sizeOf(T) * data.len),
                    @ptrCast(data.ptr),
                    self.flags,
                );
            } else {
                gl.NamedBufferSubData(
                    self.handle,
                    0,
                    @intCast(@sizeOf(T) * data.len),
                    @ptrCast(data.ptr),
                );
            }
        }

        pub fn label(self: *const Self, name: [:0]const u8) void {
            gl.ObjectLabel(gl.BUFFER, self.handle, -1, name);
        }
    };
}

pub fn ShaderStorageBufferWithArrayList(comptime T: type) type {
    return struct {
        data: std.ArrayListUnmanaged(T),
        ssbo: ShaderStorageBuffer(T),

        const Self = @This();

        pub fn init(len: usize, flags: gl.bitfield) Self {
            return .{
                .data = .empty,
                .ssbo = .init(len, flags),
            };
        }

        pub fn initAndBind(index: gl.uint, len: usize, flags: gl.bitfield) Self {
            return .{
                .data = .empty,
                .ssbo = .initAndBind(index, len, flags),
            };
        }

        pub fn bind(self: *const Self, index: gl.uint) void {
            self.ssbo.bind(index);
        }

        pub fn bindAsIndirectBuffer(self: *const Self) void {
            self.ssbo.bindAsIndirectBuffer();
        }

        pub fn resize(self: *Self, len: usize) void {
            self.ssbo.resize(len);
        }

        pub fn upload(self: *const Self) !void {
            self.ssbo.upload(self.data.items);
        }

        pub fn uploadAndOrResize(self: *Self) void {
            self.ssbo.uploadAndOrResize(self.data.items);
        }
    };
}
