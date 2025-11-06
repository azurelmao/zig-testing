const std = @import("std");

pub const Dir = enum(u3) {
    west, // -x
    east, // +x
    bottom, // -y
    top, // +y
    north, // -z
    south, // +z

    pub const values = std.enums.values(Dir);
    pub const indices = expr: {
        var indices_temp: [len]u3 = undefined;

        for (values) |dir| {
            indices_temp[dir.idx()] = dir.idx();
        }

        break :expr indices_temp;
    };
    pub const len = values.len;

    pub inline fn idx(self: Dir) u3 {
        return @intFromEnum(self);
    }
};
