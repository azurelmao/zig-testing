const std = @import("std");
const model = @import("model.zig");

pub const Block = enum(u8) {
    const Self = @This();

    air,
    stone,
    grass,
    bricks,
    water,
    ice,
    glass,

    pub const blocks_with_a_model = expr: {
        var blocks = std.enums.values(Block);
        break :expr blocks[1..];
    };

    pub fn getTextureIdx(self: Self) u10 {
        return switch (self) {
            .air => std.debug.panic("Air doesn't have a texture", .{}),
            .stone => 0,
            .grass => 1,
            .bricks => 2,
            .water => 3,
            .ice => 4,
            .glass => 5,
        };
    }

    pub fn getModel(self: Self) model.Model {
        return switch (self) {
            .air => std.debug.panic("Air doesn't have a model", .{}),
            else => model.SQUARE,
        };
    }

    pub fn isNotSolid(self: Self) bool {
        return switch (self) {
            .air, .water => true,
            else => false,
        };
    }
};
