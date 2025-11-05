const std = @import("std");

pub const Side = enum(u3) {
    west, // -x
    east, // +x
    bottom, // -y
    top, // +y
    north, // -z
    south, // +z

    pub const values = std.enums.values(Side);
    pub const indices = expr: {
        const indices2: []const Side = &.{};

        for (values) |side| {
            indices2 = indices2 ++ &.{side.idx()};
        }

        break :expr indices2;
    };
    pub const len = values.len;

    pub inline fn idx(self: Side) usize {
        return @intFromEnum(self);
    }
};
