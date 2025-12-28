const std = @import("std");

pub fn DedupArraylist(T: type) type {
    return struct {
        array: std.AutoArrayHashMapUnmanaged(T, void),

        const Self = @This();

        pub const empty: Self = .{
            .array = .empty,
        };

        pub fn deinit(self: *Self) void {
            self.array.deinit();
        }

        pub fn count(self: Self) usize {
            return self.array.count();
        }

        pub fn items(self: Self) []const T {
            return self.array.keys();
        }

        pub fn contains(self: Self, val: T) bool {
            return self.array.contains(val);
        }

        pub fn append(self: *Self, gpa: std.mem.Allocator, val: T) !void {
            if (self.array.contains(val)) return;
            try self.array.put(gpa, val, {});
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            self.array.clearRetainingCapacity();
        }
    };
}
