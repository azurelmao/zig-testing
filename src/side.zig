const std = @import("std");

pub const Side = enum(u8) {
    west, // -x
    east, // +x
    bottom, // -y
    top, // +y
    north, // -z
    south, // +z

    pub const values = std.enums.values(Side);

    pub inline fn idx(self: Side) usize {
        return @intFromEnum(self);
    }
};
