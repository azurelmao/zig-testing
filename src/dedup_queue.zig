const std = @import("std");

pub fn DedupQueue(T: type) type {
    return struct {
        in: std.AutoArrayHashMap(T, void),
        out: std.AutoArrayHashMap(T, void),

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .in = std.AutoArrayHashMap(T, void).init(allocator),
                .out = std.AutoArrayHashMap(T, void).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.in.deinit();
            self.out.deinit();
        }

        pub fn count(self: Self) usize {
            self.out.count();
        }

        pub fn enqueue(self: *Self, val: T) !void {
            if (self.in.contains(val) or self.out.contains(val)) return;
            try self.out.ensureUnusedCapacity(self.in.count() + 1);
            try self.in.put(val, {});
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
