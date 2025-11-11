const std = @import("std");

pub fn DedupQueue(T: type) type {
    return struct {
        in: std.AutoArrayHashMapUnmanaged(T, void),
        out: std.AutoArrayHashMapUnmanaged(T, void),

        const Self = @This();

        pub const empty: Self = .{
            .in = .empty,
            .out = .empty,
        };

        pub fn deinit(self: *Self) void {
            self.in.deinit();
            self.out.deinit();
        }

        pub fn count(self: Self) usize {
            return self.in.count();
        }

        pub fn enqueue(self: *Self, gpa: std.mem.Allocator, val: T) !void {
            if (self.in.contains(val) or self.out.contains(val)) return;
            try self.out.ensureUnusedCapacity(gpa, self.in.count() + 1);
            try self.in.put(gpa, val, {});
        }

        pub fn dequeue(self: *Self) ?T {
            if (self.out.count() == 0) while (self.in.pop()) |kv| {
                self.out.putAssumeCapacity(kv.key, {});
            };

            const kv = self.out.pop() orelse return null;
            return kv.key;
        }
    };
}
