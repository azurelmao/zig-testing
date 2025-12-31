const std = @import("std");
const znoise = @import("znoise");
const Block = @import("block.zig").Block;
const Chunk = @import("Chunk.zig");
const World = @import("World.zig");

const ChunkGenerator = @This();

pub const WIDTH = 1;
pub const HEIGHT = 4;
pub const VOLUME = (WIDTH * 2) * (WIDTH * 2) * HEIGHT;
pub const ABOVE_HEIGHT = 2;
pub const BELOW_HEIGHT = ABOVE_HEIGHT - HEIGHT;
pub const BOTTOM_OF_THE_WORLD = BELOW_HEIGHT * Chunk.SIZE;
pub const SEA_LEVEL = 0;
pub const SEA_LEVEL_DEEP = SEA_LEVEL - 16;

main_noise_gen: znoise.FnlGenerator,
height_maps: std.AutoHashMapUnmanaged(Chunk.Pos, HeightMap),

const HeightMap = struct {
    height_map: *[Chunk.AREA]i16,
    min_height: i16,
    max_height: i16,
};

pub fn init(seed: i32) ChunkGenerator {
    return .{
        .main_noise_gen = .{
            .noise_type = .opensimplex2,
            .seed = seed,
            .frequency = 1.0 / 16.0 / 16.0 / 16.0,
            // .lacunarity = 4,
            // .gain = 16,
            // .octaves = 8,
        },
        .height_maps = .empty,
    };
}

pub fn generateChunk(chunk_generator: *ChunkGenerator, gpa: std.mem.Allocator, chunk_pos: Chunk.Pos) !Chunk {
    const chunk_column_pos: Chunk.Pos = .{ .x = chunk_pos.x, .y = 0, .z = chunk_pos.z };

    const height_map = try chunk_generator.getOrGenerateHeightMap(gpa, chunk_column_pos);

    const min_chunk_height: i11 = @intCast((height_map.min_height >> Chunk.BIT_SIZE) - 1);
    const max_chunk_height: i11 = @intCast(height_map.max_height >> Chunk.BIT_SIZE);

    var chunk: Chunk = try .init(gpa);

    if (max_chunk_height < chunk_pos.y) {
        return chunk;
    }

    if (min_chunk_height < chunk_pos.y) {
        chunk.index_to_block.clearRetainingCapacity();
        chunk.block_to_index.clearRetainingCapacity();

        const idx = 0;
        const block: Block = .initNone(.stone);

        try chunk.index_to_block.put(gpa, idx, block);
        try chunk.block_to_index.put(gpa, block, idx);

        return chunk;
    }

    try chunk_generator.generateTerrain2D(gpa, &chunk, chunk_pos);

    return chunk;
}

pub fn getOrGenerateHeightMap(chunk_generator: *ChunkGenerator, gpa: std.mem.Allocator, chunk_column_pos: Chunk.Pos) !HeightMap {
    if (chunk_generator.height_maps.get(chunk_column_pos)) |height_map| return height_map;

    const height_map = try chunk_generator.generateHeightMap(gpa, chunk_column_pos);
    try chunk_generator.height_maps.put(gpa, chunk_column_pos, height_map);

    return height_map;
}

pub fn generateHeightMap(chunk_generator: *ChunkGenerator, gpa: std.mem.Allocator, chunk_column_pos: Chunk.Pos) !HeightMap {
    const height_map = try gpa.create([Chunk.AREA]i16);

    var min_height: ?i16 = null;
    var max_height: ?i16 = null;

    for (0..Chunk.SIZE) |z_usize| {
        for (0..Chunk.SIZE) |x_usize| {
            const idx = x_usize + Chunk.SIZE * z_usize;
            const local_pos: Chunk.LocalPos = .{ .x = @intCast(x_usize), .y = 0, .z = @intCast(z_usize) };
            const world_pos: World.Pos = .from(chunk_column_pos, local_pos);

            const height = chunk_generator.generateHeight(@floatFromInt(world_pos.x), @floatFromInt(world_pos.z));
            height_map[idx] = height;

            if (min_height) |value| min_height = @min(value, height) else min_height = height;
            if (max_height) |value| max_height = @max(value, height) else max_height = height;
        }
    }

    return .{
        .height_map = height_map,
        .min_height = min_height.?,
        .max_height = max_height.?,
    };
}

pub fn generateHeight(chunk_generator: ChunkGenerator, x: f32, z: f32) i16 {
    const noise1 = chunk_generator.main_noise_gen.noise2(x, z);

    return @intFromFloat(noise1);
}

pub fn generateTerrain2D(chunk_generator: ChunkGenerator, gpa: std.mem.Allocator, chunk: *Chunk, chunk_pos: Chunk.Pos) !void {
    const height_map = chunk_generator.height_maps.get(.{ .x = chunk_pos.x, .y = 0, .z = chunk_pos.z }) orelse unreachable;

    for (0..Chunk.SIZE) |z_usize| {
        const z = @as(u5, @intCast(z_usize));

        for (0..Chunk.SIZE) |x_usize| {
            const x = @as(u5, @intCast(x_usize));
            const idx = x_usize + Chunk.SIZE * z_usize;

            const height = height_map.height_map[idx];

            for (0..Chunk.SIZE) |y_usize| {
                const y = @as(u5, @intCast(y_usize));

                const local_pos: Chunk.LocalPos = .{ .x = x, .y = y, .z = z };
                const world_pos: World.Pos = .from(chunk_pos, local_pos);

                if (world_pos.y < height) {
                    if (world_pos.y == height - 1) {
                        if (world_pos.y < SEA_LEVEL) {
                            try chunk.setBlock(gpa, local_pos, .initNone(.sand));
                        } else {
                            try chunk.setBlock(gpa, local_pos, .initNone(.grass));
                        }
                    } else {
                        try chunk.setBlock(gpa, local_pos, .initNone(.stone));
                    }
                } else {
                    if (world_pos.y == BOTTOM_OF_THE_WORLD) {
                        try chunk.setBlock(gpa, local_pos, .initNone(.stone));
                    } else if (world_pos.y < SEA_LEVEL) {
                        try chunk.setBlock(gpa, local_pos, .initNone(.water));
                    }
                }
            }
        }
    }
}
