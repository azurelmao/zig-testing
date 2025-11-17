const std = @import("std");
const World = @import("World.zig");

pub const Light = packed struct(u16) {
    red: u4,
    green: u4,
    blue: u4,
    indirect: u4,

    pub const zeroed: Light = .{
        .red = 0,
        .green = 0,
        .blue = 0,
        .indirect = 0,
    };

    pub const Color = enum(u2) {
        red,
        green,
        blue,
        indirect,

        pub const values = std.enums.values(Color);

        pub fn idx(self: Color) u2 {
            return @intFromEnum(self);
        }
    };

    pub inline fn set(self: *Light, comptime color: Color, value: u4) void {
        switch (color) {
            inline .red => self.red = value,
            inline .green => self.green = value,
            inline .blue => self.blue = value,
            inline .indirect => self.indirect = value,
        }
    }

    pub inline fn get(self: Light, comptime color: Color) u4 {
        return switch (color) {
            inline .red => self.red,
            inline .green => self.green,
            inline .blue => self.blue,
            inline .indirect => self.indirect,
        };
    }
};

pub const LightNode = packed struct {
    world_pos: World.Pos,
    light: Light,
};
