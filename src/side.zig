const std = @import("std");

pub const Side = enum(u3) {
    west, // -x
    east, // +x
    bottom, // -y
    top, // +y
    north, // -z
    south, // +z

    pub const values = std.enums.values(Side);
    pub const len = values.len;

    pub inline fn idx(self: Side) usize {
        return @intFromEnum(self);
    }
};
