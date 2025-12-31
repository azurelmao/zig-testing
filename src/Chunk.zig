const std = @import("std");
const Block = @import("block.zig").Block;
const Light = @import("light.zig").Light;
const World = @import("World.zig");
const Vec3f = @import("vec3f.zig").Vec3f;
const Dir = @import("dir.zig").Dir;

const Chunk = @This();

pub const BIT_SIZE = 5;
pub const BIT_MASK = 0b11111;
pub const SIZE = 1 << BIT_SIZE;
pub const AREA = SIZE * SIZE;
pub const VOLUME = SIZE * SIZE * SIZE;
pub const CENTER = SIZE / 2;
pub const RADIUS: f32 = CENTER * std.math.sqrt(3.0);
pub const EDGE = SIZE - 1;

block_to_index: std.HashMapUnmanaged(Block, u15, Block.Context, 80),
index_to_block: std.AutoHashMapUnmanaged(u15, Block),
blocks: []u8,
index_bit_size: u4,

light: *[VOLUME]Light,

air_bitset: *[AREA]u32,
water_bitset: *[AREA]u32,
num_of_air: u16,

const ChunkPos = struct {
    x: i11,
    y: i11,
    z: i11,

    pub const OFFSETS = std.EnumArray(Dir, ChunkPos).init(
        .{
            .west = .{ .x = -1, .y = 0, .z = 0 },
            .east = .{ .x = 1, .y = 0, .z = 0 },
            .bottom = .{ .x = 0, .y = -1, .z = 0 },
            .top = .{ .x = 0, .y = 1, .z = 0 },
            .north = .{ .x = 0, .y = 0, .z = -1 },
            .south = .{ .x = 0, .y = 0, .z = 1 },
        },
    );

    pub fn toWorldPos(chunk_pos: ChunkPos) World.Pos {
        return .{
            .x = @as(i16, @intCast(chunk_pos.x)) << BIT_SIZE,
            .y = @as(i16, @intCast(chunk_pos.y)) << BIT_SIZE,
            .z = @as(i16, @intCast(chunk_pos.z)) << BIT_SIZE,
        };
    }

    pub fn toVec3f(chunk_pos: ChunkPos) Vec3f {
        return .{
            .x = @floatFromInt(@as(i16, @intCast(chunk_pos.x)) << BIT_SIZE),
            .y = @floatFromInt(@as(i16, @intCast(chunk_pos.y)) << BIT_SIZE),
            .z = @floatFromInt(@as(i16, @intCast(chunk_pos.z)) << BIT_SIZE),
        };
    }

    pub fn add(chunk_pos: ChunkPos, other_chunk_pos: ChunkPos) ChunkPos {
        return .{
            .x = chunk_pos.x + other_chunk_pos.x,
            .y = chunk_pos.y + other_chunk_pos.y,
            .z = chunk_pos.z + other_chunk_pos.z,
        };
    }

    pub fn subtract(chunk_pos: ChunkPos, other_chunk_pos: ChunkPos) ChunkPos {
        return .{
            .x = chunk_pos.x - other_chunk_pos.x,
            .y = chunk_pos.y - other_chunk_pos.y,
            .z = chunk_pos.z - other_chunk_pos.z,
        };
    }

    pub fn equal(chunk_pos: ChunkPos, other_chunk_pos: ChunkPos) bool {
        return chunk_pos.x == other_chunk_pos.x and chunk_pos.y == other_chunk_pos.y and chunk_pos.z == other_chunk_pos.z;
    }

    pub fn notEqual(chunk_pos: ChunkPos, other_chunk_pos: ChunkPos) bool {
        return chunk_pos.x != other_chunk_pos.x or chunk_pos.y != other_chunk_pos.y or chunk_pos.z != other_chunk_pos.z;
    }
};

pub const Pos = ChunkPos;

pub const LocalPos = packed struct(u15) {
    x: u5,
    y: u5,
    z: u5,

    pub fn idx(local_pos: LocalPos) u15 {
        return @bitCast(local_pos);
    }
};

pub fn init(gpa: std.mem.Allocator) !Chunk {
    const idx = 0;
    const block: Block = .initNone(.air);

    var block_to_index = std.HashMapUnmanaged(Block, u15, Block.Context, 80).empty;
    try block_to_index.put(
        gpa,
        block,
        idx,
    );

    var index_to_block = std.AutoHashMapUnmanaged(u15, Block).empty;
    try index_to_block.put(
        gpa,
        idx,
        block,
    );

    const light = try gpa.create([VOLUME]Light);
    @memset(light, .{ .red = 0, .green = 0, .blue = 0, .indirect = 0 });

    const air_bitset = try gpa.create([AREA]u32);
    @memset(air_bitset, 0);

    const water_bitset = try gpa.create([AREA]u32);
    @memset(water_bitset, 0);

    return .{
        .block_to_index = block_to_index,
        .index_to_block = index_to_block,
        .blocks = &.{},
        .index_bit_size = 0,

        .light = light,

        .air_bitset = air_bitset,
        .water_bitset = water_bitset,
        .num_of_air = VOLUME,
    };
}

pub fn getLight(self: *Chunk, local_pos: LocalPos) Light {
    return self.light[local_pos.idx()];
}

pub fn setLight(self: *Chunk, local_pos: LocalPos, light: Light) void {
    self.light[local_pos.idx()] = light;
}

pub fn getBlock(self: Chunk, local_pos: LocalPos) Block {
    switch (self.index_bit_size) {
        0 => return self.index_to_block.get(0) orelse unreachable,

        inline else => |bit_size| {
            const int_type = std.meta.Int(.unsigned, bit_size);
            const bit_offset = @as(usize, @intCast(local_pos.idx())) * @as(usize, @intCast(bit_size));

            const block_index: u15 = @intCast(std.mem.readPackedIntNative(int_type, self.blocks, bit_offset));
            const block = self.index_to_block.get(block_index).?;

            return block;
        },
    }
}

pub fn setBlock(self: *Chunk, gpa: std.mem.Allocator, local_pos: LocalPos, block: Block) !void {
    const x: usize = @intCast(local_pos.x);
    const z: usize = @intCast(local_pos.z);
    const idx = x * SIZE + z;

    if (!self.block_to_index.contains(block)) {
        var prev_count = self.block_to_index.count();

        if (prev_count >= VOLUME - 1) {
            prev_count = VOLUME - 1;
            // TODO cleanup
        }

        const block_index: u15 = @intCast(prev_count);

        try self.block_to_index.put(gpa, block, block_index);
        try self.index_to_block.put(gpa, block_index, block);

        const count = prev_count + 1;
        const count_f: f32 = @floatFromInt(count);

        const item_size_in_bits: usize = @intFromFloat(@ceil(@log2(count_f)));

        const total_size_in_bits = VOLUME * item_size_in_bits;
        const total_size_in_bytes = total_size_in_bits / 8;

        if (item_size_in_bits > self.index_bit_size) {
            const new_blocks = try gpa.alloc(u8, total_size_in_bytes);

            self.index_bit_size = @intCast(item_size_in_bits);

            switch (self.index_bit_size) {
                0 => unreachable,
                1 => @memset(new_blocks, 0),

                inline else => |new_bit_size| {
                    for (0..VOLUME) |index| {
                        const prev_bit_size = new_bit_size - 1;

                        const prev_bit_offset = index * prev_bit_size;
                        const new_bit_offset = index * new_bit_size;

                        const prev_int_type = std.meta.Int(.unsigned, prev_bit_size);
                        const new_int_type = std.meta.Int(.unsigned, new_bit_size);

                        const value = std.mem.readPackedIntNative(prev_int_type, self.blocks, prev_bit_offset);
                        std.mem.writePackedIntNative(new_int_type, new_blocks, new_bit_offset, @intCast(value));
                    }
                },
            }

            gpa.free(self.blocks);
            self.blocks = new_blocks;
        }
    }

    const block_index = self.block_to_index.get(block).?;

    switch (self.index_bit_size) {
        0 => {},

        inline else => |bit_size| {
            const int_type = std.meta.Int(.unsigned, bit_size);
            const bit_offset = @as(usize, @intCast(local_pos.idx())) * @as(usize, @intCast(bit_size));

            const prev_block_index = std.mem.readPackedIntNative(int_type, self.blocks, bit_offset);
            const prev_block = self.index_to_block.get(prev_block_index).?;

            if (block.kind == .air) {
                if (prev_block.kind != .air) {
                    self.num_of_air += 1;
                }

                self.air_bitset[idx] &= ~(@as(u32, 1) << local_pos.y); // sets bit at `pos.y` to 0
                self.water_bitset[idx] &= ~(@as(u32, 1) << local_pos.y); // sets bit at `pos.y` to 0
            } else if (block.kind == .water) {
                self.air_bitset[idx] |= (@as(u32, 1) << local_pos.y); // sets bit at `pos.y` to 1
                self.water_bitset[idx] |= (@as(u32, 1) << local_pos.y); // sets bit at `pos.y` to 1
            } else {
                if (prev_block.kind == .air) {
                    self.num_of_air -= 1;
                }

                self.air_bitset[idx] |= (@as(u32, 1) << local_pos.y); // sets bit at `pos.y` to 1
                self.water_bitset[idx] &= ~(@as(u32, 1) << local_pos.y); // sets bit at `pos.y` to 0
            }

            std.mem.writePackedIntNative(int_type, self.blocks, bit_offset, @intCast(block_index));
        },
    }
}
