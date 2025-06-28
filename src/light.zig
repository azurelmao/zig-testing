const World = @import("World.zig");

pub const Light = packed struct(u16) {
    red: u4,
    green: u4,
    blue: u4,
    indirect: u4,
};

pub const LightNode = struct {
    pos: World.Pos,
    light: Light,
};
