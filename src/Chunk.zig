const std = @import("std");
const Vec3f = @import("vec3f.zig").Vec3f;
const Block = @import("block.zig").Block;
const World = @import("World.zig");

const Chunk = @This();

pub const BitSize = 5;
pub const BitMask = 0b11111;
pub const Size = 1 << BitSize;
pub const Center = Size / 2;
pub const Radius: f32 = Center * std.math.sqrt(3.0);
pub const Edge = Size - 1;
pub const Area = Size * Size;
pub const Volume = Size * Size * Size;

const LightQueue = std.fifo.LinearFifo(LightNode, .Dynamic);

pos: Pos,
blocks: *[Volume]Block,
light: *[Volume]Light,

air_bitset: *[Area]u32,
water_bitset: *[Area]u32,
num_of_air: u16,

light_addition_queue: LightQueue,
light_removal_queue: LightQueue,

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

    pub fn toWorldPos(self: Pos) World.Pos {
        return .{
            .x = @as(i16, @intCast(self.x)) << BitSize,
            .y = @as(i16, @intCast(self.y)) << BitSize,
            .z = @as(i16, @intCast(self.z)) << BitSize,
        };
    }

    pub fn toVec3f(self: Pos) Vec3f {
        return .{
            .x = @floatFromInt(@as(i16, @intCast(self.x)) << BitSize),
            .y = @floatFromInt(@as(i16, @intCast(self.y)) << BitSize),
            .z = @floatFromInt(@as(i16, @intCast(self.z)) << BitSize),
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

pub fn new(allocator: std.mem.Allocator, pos: Pos, default_block: Block) !Chunk {
    const blocks = try allocator.create([Volume]Block);
    @memset(blocks, default_block);

    const light = try allocator.create([Volume]Light);
    @memset(light, .{ .red = 0, .green = 0, .blue = 0, .indirect = 0 });

    const air_bitset = try allocator.create([Area]u32);
    @memset(air_bitset, 0);

    const water_bitset = try allocator.create([Area]u32);
    @memset(water_bitset, 0);

    const light_addition_queue = LightQueue.init(allocator);
    const light_removal_queue = LightQueue.init(allocator);

    return .{
        .pos = pos,
        .blocks = blocks,
        .light = light,
        .air_bitset = air_bitset,
        .water_bitset = water_bitset,
        .num_of_air = Volume,
        .light_addition_queue = light_addition_queue,
        .light_removal_queue = light_removal_queue,
    };
}

pub fn getLight(self: *Chunk, pos: LocalPos) Light {
    return self.light[pos.index()];
}

pub fn setLight(self: *Chunk, pos: LocalPos, light: Light) void {
    self.light[pos.index()] = light;
}

pub fn getBlock(self: *Chunk, pos: LocalPos) Block {
    return self.blocks[pos.index()];
}

pub fn setBlock(self: *Chunk, pos: LocalPos, block: Block) void {
    const x: usize = @intCast(pos.x);
    const z: usize = @intCast(pos.z);
    const idx = x * Size + z;

    if (block == .air) {
        if (self.blocks[pos.index()] != .air) {
            self.num_of_air += 1;
        }

        self.air_bitset[idx] &= ~(@as(u32, 1) << pos.y); // sets bit at `pos.y` to 0
        self.water_bitset[idx] &= ~(@as(u32, 1) << pos.y); // sets bit at `pos.y` to 0
    } else if (block == .water) {
        self.air_bitset[idx] |= (@as(u32, 1) << pos.y); // sets bit at `pos.y` to 1
        self.water_bitset[idx] |= (@as(u32, 1) << pos.y); // sets bit at `pos.y` to 1
    } else {
        if (self.blocks[pos.index()] == .air) {
            self.num_of_air -= 1;
        }

        self.air_bitset[idx] |= (@as(u32, 1) << pos.y); // sets bit at `pos.y` to 1
        self.water_bitset[idx] &= ~(@as(u32, 1) << pos.y); // sets bit at `pos.y` to 0
    }

    self.blocks[pos.index()] = block;
}
