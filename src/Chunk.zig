const std = @import("std");
const Vec3f = @import("vec3f.zig").Vec3f;
const Block = @import("block.zig").Block;
const World = @import("World.zig");

const Self = @This();

pub const BitSize = 5;
pub const BitMask = 0b11111;
pub const Size = 1 << BitSize;
pub const Center = Size / 2;
pub const Radius: f32 = Center * std.math.sqrt(3.0);
pub const Edge = Size - 1;
pub const Area = Size * Size;
pub const Volume = Size * Size * Size;

const LightQueue = std.fifo.LinearFifo(LightNode, .Dynamic);

blocks: *[Volume]Block,
light: *[Volume]Light,
light_addition_queue: LightQueue,
light_removal_queue: LightQueue,
pos: Pos,

pub const LightNode = struct {
    pos: World.Pos,
    light: Light,
};

pub const Light = packed struct(u16) {
    red: u4,
    green: u4,
    blue: u4,
    indirect: u4,
};

pub const Pos = struct {
    x: i11,
    y: i11,
    z: i11,

    pub const Offsets = [6]Pos{
        .{ .x = -1, .y = 0, .z = 0 },
        .{ .x = 1, .y = 0, .z = 0 },
        .{ .x = 0, .y = -1, .z = 0 },
        .{ .x = 0, .y = 1, .z = 0 },
        .{ .x = 0, .y = 0, .z = -1 },
        .{ .x = 0, .y = 0, .z = 1 },
    };

    pub fn toVec3f(self: Pos) Vec3f {
        return .{
            .x = @floatFromInt(self.x << BitSize),
            .y = @floatFromInt(self.y << BitSize),
            .z = @floatFromInt(self.z << BitSize),
        };
    }

    pub fn add(self: Pos, other: Pos) Pos {
        return .{
            .x = self.x + other.x,
            .y = self.y + other.y,
            .z = self.z + other.z,
        };
    }

    pub fn subtract(self: Pos, other: Pos) Pos {
        return .{
            .x = self.x - other.x,
            .y = self.y - other.y,
            .z = self.z - other.z,
        };
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

pub fn new(allocator: std.mem.Allocator, pos: Pos, default_block: Block) !Self {
    const blocks = try allocator.create([Volume]Block);
    @memset(blocks, default_block);

    const light = try allocator.create([Volume]Light);
    @memset(light, .{ .red = 0, .green = 0, .blue = 0, .indirect = 0 });

    return .{
        .blocks = blocks,
        .light = light,
        .light_addition_queue = LightQueue.init(allocator),
        .light_removal_queue = LightQueue.init(allocator),
        .pos = pos,
    };
}

pub fn getLight(self: Self, pos: LocalPos) Light {
    return self.light[pos.index()];
}

pub fn setLight(self: Self, pos: LocalPos, light: Light) void {
    self.light[pos.index()] = light;
}

pub fn getBlock(self: Self, pos: LocalPos) Block {
    return self.blocks[pos.index()];
}

pub fn setBlock(self: Self, pos: LocalPos, block: Block) void {
    self.blocks[pos.index()] = block;
}
