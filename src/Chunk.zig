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
light: *[Volume]Light,
pos: Pos,

pub fn new(allocator: std.mem.Allocator, pos: Pos, default_block: Block) !Self {
    const blocks = try allocator.create([Volume]Block);
    @memset(blocks, default_block);

    const light = try allocator.create([Volume]Light);
    @memset(light, .{ .red = 0, .green = 0, .blue = 0, .sunlight = 1 });

    return .{
        .blocks = blocks,
        .light = light,
        .pos = pos,
    };
}

pub const Light = packed struct(u16) {
    red: u4,
    green: u4,
    blue: u4,
    sunlight: u4,
};

pub const Pos = struct {
    x: i16,
    y: i16,
    z: i16,

    pub fn toVec3f(self: Pos) Vec3f {
        return .{ .x = @floatFromInt(self.x << BitSize), .y = @floatFromInt(self.y << BitSize), .z = @floatFromInt(self.z << BitSize) };
    }

    pub fn add(self: Pos, other: Pos) Pos {
        return .{ .x = self.x + other.x, .y = self.y + other.y, .z = self.z + other.z };
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

const CHUNK_DISTANCE = 4;

pub fn generateChunks(allocator: std.mem.Allocator, rand: std.Random, chunks: *std.AutoHashMap(Pos, Self)) !void {
    for (0..CHUNK_DISTANCE * 2) |chunk_x_| {
        for (0..CHUNK_DISTANCE * 2) |chunk_z_| {
            const chunk = try generateChunk(allocator, rand, chunk_x_, chunk_z_);
            try chunks.put(chunk.pos, chunk);
        }
    }
}

pub fn generateChunk(allocator: std.mem.Allocator, rand: std.Random, chunk_x_: usize, chunk_z_: usize) !Self {
    const chunk_x = @as(i16, @intCast(chunk_x_)) - CHUNK_DISTANCE;
    const chunk_z = @as(i16, @intCast(chunk_z_)) - CHUNK_DISTANCE;

    var additional_height: u5 = 0;
    if (chunk_x_ == (CHUNK_DISTANCE * 2 - 1) or chunk_z_ == (CHUNK_DISTANCE * 2 - 1)) {
        additional_height = 16;
    } else if (chunk_x_ == 0 or chunk_z_ == 0) {
        additional_height = 24;
    }

    const chunk = try new(allocator, .{ .x = chunk_x, .y = 0, .z = chunk_z }, .air);

    for (0..Size) |x_| {
        for (0..Size) |z_| {
            const x: u5 = @intCast(x_);
            const z: u5 = @intCast(z_);

            const height = rand.intRangeAtMost(u5, 1, 7) + additional_height;

            for (0..height) |y_| {
                const y: u5 = @intCast(y_);

                const block: Block = if (y == height - 1) .grass else .stone;
                chunk.setBlock(.{ .x = x, .y = y, .z = z }, block);
            }

            if (height < 5) {
                for (1..5) |y_| {
                    const y: u5 = @intCast(y_);

                    if (chunk.getBlock(.{ .x = x, .y = y, .z = z }) == .air) {
                        chunk.setBlock(.{ .x = x, .y = y, .z = z }, .water);
                    }
                }
            }
        }
    }

    return chunk;
}
