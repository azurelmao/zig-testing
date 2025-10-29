const std = @import("std");
const gl = @import("gl");

pub fn ShaderStorageBuffer(comptime T: type) type {
    return struct {
        const Self = @This();

        handle: gl.uint,
        len: usize,
        capacity: usize,
        flags: gl.bitfield,

        pub fn init(capacity: usize, flags: gl.bitfield) Self {
            var handle: gl.uint = undefined;
            gl.CreateBuffers(1, @ptrCast(&handle));
            gl.NamedBufferStorage(
                handle,
                @intCast(@sizeOf(T) * capacity),
                null,
                flags,
            );

            return .{
                .handle = handle,
                .len = 0,
                .capacity = capacity,
                .flags = flags,
            };
        }

        pub fn initAndBind(index: gl.uint, capacity: usize, flags: gl.bitfield) Self {
            const self = init(capacity, flags);
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
                .capacity = data.len,
                .flags = flags,
            };
        }

        pub fn initFromSliceAndBind(index: gl.uint, data: []const T, flags: gl.bitfield) Self {
            const self = initFromSlice(data, flags);
            gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, index, self.handle);

            return self;
        }

        pub fn bind(self: Self, index: gl.uint) void {
            gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, index, self.handle);
        }

        pub fn bindAsIndirectBuffer(self: Self) void {
            gl.BindBuffer(gl.DRAW_INDIRECT_BUFFER, self.handle);
        }

        pub fn resize(self: *Self, len: usize, extra_capacity: usize) void {
            gl.DeleteBuffers(1, @ptrCast(&self.handle));

            gl.CreateBuffers(1, @ptrCast(&self.handle));

            self.len = len;
            self.capacity = len + extra_capacity;

            gl.NamedBufferStorage(
                self.handle,
                @intCast(@sizeOf(T) * self.capacity),
                null,
                self.flags,
            );
        }

        pub fn upload(self: *Self, data: []const T) !void {
            if (data.len > self.len and data.len <= self.capacity) self.len = data.len;
            if (data.len > self.capacity) return error.DataTooLarge;

            gl.NamedBufferSubData(
                self.handle,
                0,
                @intCast(@sizeOf(T) * data.len),
                @ptrCast(data.ptr),
            );
        }

        pub fn label(self: Self, name: [:0]const u8) void {
            gl.ObjectLabel(gl.BUFFER, self.handle, -1, name);
        }
    };
}

pub fn ShaderStorageBufferWithArrayList(comptime T: type) type {
    return struct {
        const Self = @This();

        data: std.ArrayListUnmanaged(T),
        ssbo: ShaderStorageBuffer(T),

        pub fn init(allocator: std.mem.Allocator, capacity: usize, flags: gl.bitfield) !Self {
            return .{
                .data = try .initCapacity(allocator, capacity),
                .ssbo = .init(capacity, flags),
            };
        }

        pub fn initAndBind(allocator: std.mem.Allocator, index: gl.uint, capacity: usize, flags: gl.bitfield) !Self {
            return .{
                .data = try .initCapacity(allocator, capacity),
                .ssbo = .initAndBind(index, capacity, flags),
            };
        }
    };
}
