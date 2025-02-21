const std = @import("std");
const Vec3f = @import("vec3f.zig").Vec3f;
const Block = @import("block.zig").Block;

const Self = @This();

pub const BitSize = 5;
pub const Size = 1 << BitSize;
pub const Center = Size / 2;
pub const Radius: f32 = Center * std.math.sqrt(3.0);
pub const Edge = Size - 1;
pub const Area = Size * Size;
pub const Volume = Size * Size * Size;

blocks: *[Volume]Block,
pos: Pos,

pub fn new(allocator: std.mem.Allocator, pos: Pos, default_block: Block) !Self {
    const blocks = try allocator.create([Volume]Block);
    @memset(blocks, default_block);

    return .{ .blocks = blocks, .pos = pos };
}

pub const Pos = struct {
    x: i16,
    y: i16,
    z: i16,

    pub fn toVec3f(self: Pos) Vec3f {
        return .{ .x = @floatFromInt(self.x << BitSize), .y = @floatFromInt(self.y << BitSize), .z = @floatFromInt(self.z << BitSize) };
    }

    pub fn subtract(self: Pos, other: Pos) Pos {
        return .{ .x = self.x - other.x, .y = self.y - other.y, .z = self.z - other.z };
    }

    pub fn equal(self: Pos, other: Pos) bool {
        return self.x == other.x and self.y == other.y and self.z == other.z;
    }

    pub fn notEqual(self: Pos, other: Pos) bool {
        return self.x != other.x or self.y != other.y or self.z != other.z;
    }
};

pub const LocalPos = packed struct(u15) {
    x: u5,
    y: u5,
    z: u5,

    pub fn index(self: LocalPos) u15 {
        return @bitCast(self);
    }
};

pub fn getBlock(self: Self, pos: LocalPos) Block {
    return self.blocks[pos.index()];
}

pub fn setBlock(self: Self, pos: LocalPos, block: Block) void {
    self.blocks[pos.index()] = block;
}
