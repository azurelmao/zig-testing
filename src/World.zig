const std = @import("std");
const znoise = @import("znoise");
const Chunk = @import("Chunk.zig");
const Light = @import("light.zig").Light;
const LightNode = @import("light.zig").LightNode;
const Block = @import("block.zig").Block;
const BlockExtendedData = @import("block.zig").BlockExtendedData;
const BlockVolumeScheme = @import("block.zig").BlockVolumeScheme;
const Dir = @import("dir.zig").Dir;
const DedupQueue = @import("dedup_queue.zig").DedupQueue;
const Vec3f = @import("vec3f.zig").Vec3f;
const debug = @import("debug.zig");

const World = @This();

prng: std.Random.Xoshiro256,
seed: i32,
chunks: std.AutoHashMapUnmanaged(Chunk.Pos, Chunk),
chunks_which_need_to_regenerate_meshes: DedupQueue(Chunk.Pos),
block_extended_data_store: std.ArrayListUnmanaged(BlockExtendedData),

light_addition_queue: Queue(LightNode),
light_removal_queue: Queue(LightNode),

pub fn Queue(comptime T: type) type {
    return std.fifo.LinearFifo(T, .Dynamic);
}

pub const WIDTH = 1;
pub const HEIGHT = 4;
pub const VOLUME = (WIDTH * 2) * (WIDTH * 2) * HEIGHT;
pub const ABOVE_HEIGHT = 2;
pub const BELOW_HEIGHT = ABOVE_HEIGHT - HEIGHT;
pub const BOTTOM_OF_THE_WORLD = BELOW_HEIGHT * Chunk.SIZE;
pub const SEA_LEVEL = 0;
pub const SEA_LEVEL_DEEP = SEA_LEVEL - 16;

pub fn init(gpa: std.mem.Allocator, seed: i32) !World {
    const prng = std.Random.DefaultPrng.init(expr: {
        var prng_seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&prng_seed));
        break :expr prng_seed;
    });

    return .{
        .prng = prng,
        .seed = seed,
        .chunks = .empty,
        .chunks_which_need_to_regenerate_meshes = .empty,
        .block_extended_data_store = .empty,

        .light_addition_queue = .init(gpa),
        .light_removal_queue = .init(gpa),
    };
}

pub const Pos = packed struct {
    x: i16,
    y: i16,
    z: i16,

    pub const OFFSETS = [6]Pos{
        .{ .x = -1, .y = 0, .z = 0 },
        .{ .x = 1, .y = 0, .z = 0 },
        .{ .x = 0, .y = -1, .z = 0 },
        .{ .x = 0, .y = 1, .z = 0 },
        .{ .x = 0, .y = 0, .z = -1 },
        .{ .x = 0, .y = 0, .z = 1 },
    };

    pub fn from(chunk_pos: Chunk.Pos, local_pos: Chunk.LocalPos) Pos {
        return .{
            .x = (@as(i16, @intCast(chunk_pos.x)) << Chunk.BIT_SIZE) | @as(i16, @intCast(local_pos.x)),
            .y = (@as(i16, @intCast(chunk_pos.y)) << Chunk.BIT_SIZE) | @as(i16, @intCast(local_pos.y)),
            .z = (@as(i16, @intCast(chunk_pos.z)) << Chunk.BIT_SIZE) | @as(i16, @intCast(local_pos.z)),
        };
    }

    pub fn toChunkPos(world: Pos) Chunk.Pos {
        return .{
            .x = @intCast(world.x >> Chunk.BIT_SIZE),
            .y = @intCast(world.y >> Chunk.BIT_SIZE),
            .z = @intCast(world.z >> Chunk.BIT_SIZE),
        };
    }

    pub fn toLocalPos(world: Pos) Chunk.LocalPos {
        return .{
            .x = @intCast(world.x & Chunk.BIT_MASK),
            .y = @intCast(world.y & Chunk.BIT_MASK),
            .z = @intCast(world.z & Chunk.BIT_MASK),
        };
    }

    pub fn toVec3f(world: Pos) Vec3f {
        return .{
            .x = @floatFromInt(world.x),
            .y = @floatFromInt(world.y),
            .z = @floatFromInt(world.z),
        };
    }

    pub fn add(world: Pos, other: Pos) Pos {
        return .{
            .x = world.x + other.x,
            .y = world.y + other.y,
            .z = world.z + other.z,
        };
    }

    pub fn subtract(world: Pos, other: Pos) Pos {
        return .{
            .x = world.x - other.x,
            .y = world.y - other.y,
            .z = world.z - other.z,
        };
    }

    pub fn equal(world: Pos, other: Pos) bool {
        return world.x == other.x and world.y == other.y and world.z == other.z;
    }

    pub fn notEqual(world: Pos, other: Pos) bool {
        return world.x != other.x or world.y != other.y or world.z != other.z;
    }
};

const WorldPos = Pos;

pub fn getChunk(world: World, world_pos: Chunk.Pos) !*Chunk {
    return world.chunks.getPtr(world_pos) orelse error.ChunkNotFound;
}

pub fn getChunkOrNull(world: World, world_pos: Chunk.Pos) ?*Chunk {
    return world.chunks.getPtr(world_pos);
}

pub fn getBlock(world: World, world_pos: WorldPos) !Block {
    const chunk = try world.getChunk(world_pos.toChunkPos());

    return chunk.getBlock(world_pos.toLocalPos());
}

pub fn getBlockOrNull(world: World, world_pos: WorldPos) ?Block {
    const chunk = world.getChunkOrNull(world_pos.toChunkPos()) orelse return null;

    return chunk.getBlock(world_pos.toLocalPos());
}

pub fn setBlock(world: *World, gpa: std.mem.Allocator, world_pos: WorldPos, block: Block) !void {
    const chunk = try world.getChunk(world_pos.toChunkPos());

    try chunk.setBlock(gpa, world_pos.toLocalPos(), block);
}

pub fn addBlockExtendedData(world: *World, gpa: std.mem.Allocator, data: BlockExtendedData) !usize {
    try world.block_extended_data_store.append(gpa, data);
    const index = world.array.items.len - 1;

    return index;
}

pub fn onNeighborUpdate(world: *World, world_pos: WorldPos, block: Block, neighbor_world_pos: WorldPos, neighbor_block: Block) !void {
    _ = world_pos;
    _ = neighbor_block;

    switch (block.kind) {
        .lamp => {
            _ = try world.addLight(neighbor_world_pos, block.data.lamp.light);
        },
        else => {},
    }
}

pub fn placeBlock(world: *World, gpa: std.mem.Allocator, world_pos: WorldPos, block: Block) !void {
    debug.addition_nodes.data.clearRetainingCapacity();
    debug.removal_nodes.data.clearRetainingCapacity();
    debug.upload_nodes = true;

    _ = try world.removeLight(world_pos);
    try world.propagateLightRemoval(gpa);

    try world.setBlock(gpa, world_pos, block);

    switch (block.kind) {
        .lamp => {
            for (Dir.indices) |dir_idx| {
                const neighbor_world_pos = world_pos.add(World.WorldPos.OFFSETS[dir_idx]);
                _ = try world.addLight(neighbor_world_pos, block.data.lamp.light);
            }
        },
        else => {},
    }

    try world.propagateLightAddition(gpa);

    for (Dir.indices) |dir_idx| {
        const neighbor_world_pos = world_pos.add(WorldPos.OFFSETS[dir_idx]);
        try world.chunks_which_need_to_regenerate_meshes.enqueue(gpa, neighbor_world_pos.toChunkPos());
    }
}

pub fn breakBlock(world: *World, gpa: std.mem.Allocator, world_pos: WorldPos, block: Block) !void {
    debug.addition_nodes.data.clearRetainingCapacity();
    debug.removal_nodes.data.clearRetainingCapacity();
    debug.upload_nodes = true;

    try world.setBlock(gpa, world_pos, .initNone(.air));

    switch (block.kind) {
        .lamp => {
            for (Dir.indices) |dir_idx| {
                const neighbor_world_pos = world_pos.add(World.WorldPos.OFFSETS[dir_idx]);
                _ = try world.removeLight(neighbor_world_pos);
            }
        },
        else => {},
    }

    for (Dir.indices) |dir_idx| {
        const neighbor_world_pos = world_pos.add(World.WorldPos.OFFSETS[dir_idx]);
        const neighbor_block = try world.getBlock(neighbor_world_pos);

        try world.onNeighborUpdate(neighbor_world_pos, neighbor_block, world_pos, block);

        const neighbor_light = try world.getLight(neighbor_world_pos);
        _ = try world.addLight(neighbor_world_pos, neighbor_light);
    }

    try world.propagateLightRemoval(gpa);
    try world.propagateLightAddition(gpa);

    for (Dir.indices) |dir_idx| {
        const neighbor_world_pos = world_pos.add(WorldPos.OFFSETS[dir_idx]);
        try world.chunks_which_need_to_regenerate_meshes.enqueue(gpa, neighbor_world_pos.toChunkPos());
    }
}

// What will happen if a BED is deleted?
pub fn getBlockExtendedData(world: *World, index: usize) BlockExtendedData {
    return world.block_extended_data_store[index];
}

pub const RaycastDir = enum {
    west,
    east,
    bottom,
    top,
    north,
    south,
    inside,
    out_of_bounds,

    pub inline fn idx(world: RaycastDir) usize {
        return @intFromEnum(world);
    }

    pub fn toDir(self: RaycastDir) Dir {
        switch (self) {
            .west, .east, .bottom, .top, .north, .south => return @enumFromInt(self.idx()),
            else => unreachable,
        }
    }
};

pub const RaycastResult = struct {
    world_pos: WorldPos,
    dir: RaycastDir,
    block: ?Block,
};

const MAX_RAYCAST_STEPS = 120;

pub fn raycast(world: World, origin: Vec3f, direction: Vec3f) RaycastResult {
    var moving_position = origin.floor();

    const step: Vec3f = .init(std.math.sign(direction.x), std.math.sign(direction.y), std.math.sign(direction.z));
    const delta_distance = Vec3f.fromScalar(direction.magnitude()).divide(direction).abs();
    var side_distance = step.multiply(moving_position.subtract(origin)).add(step.multiplyScalar(0.5).addScalar(0.5)).multiply(delta_distance);

    var mask = packed struct {
        x: bool,
        y: bool,
        z: bool,
    }{
        .x = false,
        .y = false,
        .z = false,
    };

    for (0..MAX_RAYCAST_STEPS) |_| {
        const block_world_pos = moving_position.toWorldPos();
        const block_or_null = world.getBlockOrNull(block_world_pos);

        if (block_or_null) |block| {
            const block_volume = block.kind.getVolume();

            switch (block_volume) {
                .none => {},
                .full => {
                    const dir: RaycastDir = expr: {
                        if (mask.x) {
                            if (step.x > 0) {
                                break :expr .west;
                            } else if (step.x < 0) {
                                break :expr .east;
                            }
                        } else if (mask.y) {
                            if (step.y > 0) {
                                break :expr .bottom;
                            } else if (step.y < 0) {
                                break :expr .top;
                            }
                        } else if (mask.z) {
                            if (step.z > 0) {
                                break :expr .north;
                            } else if (step.z < 0) {
                                break :expr .south;
                            }
                        }

                        break :expr .inside;
                    };

                    return .{
                        .world_pos = block_world_pos,
                        .dir = dir,
                        .block = block,
                    };
                },
                .detailed => |block_volume_scheme| skip: {
                    const dir = block_volume_scheme.intersect(block_world_pos.toVec3f(), origin, direction);
                    if (dir == .out_of_bounds) break :skip;

                    // const hit_pos = origin.add(direction).multiplyScalar(intersection_result.hit_time);
                    // _ = hit_pos;

                    return .{
                        .world_pos = block_world_pos,
                        .dir = dir,
                        .block = block,
                    };
                },
            }
        }

        if (side_distance.x < side_distance.y) {
            if (side_distance.x < side_distance.z) {
                side_distance.x += delta_distance.x;
                moving_position.x += step.x;
                mask = .{ .x = true, .y = false, .z = false };
            } else {
                side_distance.z += delta_distance.z;
                moving_position.z += step.z;
                mask = .{ .x = false, .y = false, .z = true };
            }
        } else {
            if (side_distance.y < side_distance.z) {
                side_distance.y += delta_distance.y;
                moving_position.y += step.y;
                mask = .{ .x = false, .y = true, .z = false };
            } else {
                side_distance.z += delta_distance.z;
                moving_position.z += step.z;
                mask = .{ .x = false, .y = false, .z = true };
            }
        }
    }

    return .{
        .world_pos = moving_position.toWorldPos(),
        .dir = .out_of_bounds,
        .block = null,
    };
}

pub fn generate(world: *World, gpa: std.mem.Allocator) !void {
    const gen1 = znoise.FnlGenerator{
        .noise_type = .opensimplex2,
        .seed = world.seed,
        .frequency = 1.0 / 16.0 / 16.0 / 16.0,
        // .lacunarity = 4,
        // .gain = 16,
        // .octaves = 8,
    };

    const gen2 = znoise.FnlGenerator{
        .noise_type = .opensimplex2,
        .seed = world.seed,
        .frequency = 1.0 / 16.0 / 16.0,
        // .lacunarity = 8,
        // .gain = 1,
        // .octaves = 8,
    };

    const gen3 = znoise.FnlGenerator{
        .noise_type = .opensimplex2,
        .seed = world.seed,
        .frequency = 1.0 / 16.0,
        // .lacunarity = 16,
        // .gain = 1.0 / 16.0,
        // .octaves = 8,
    };

    const sea_rift_gen = znoise.FnlGenerator{
        .noise_type = .opensimplex2,
        .seed = world.seed,
        .frequency = 0.05,
        .fractal_type = .ridged,
        .octaves = 6,
        .lacunarity = 0.37,
        .gain = 10,
        .weighted_strength = 0.94,
    };

    const cave_gen = znoise.FnlGenerator{
        .noise_type = .opensimplex2,
        .seed = world.seed,
        .frequency = 0.01,
        .fractal_type = .fbm,
        .octaves = 5,
        .lacunarity = 2,
        .gain = 0.4,
        .weighted_strength = -1,
    };

    var height_map = try gpa.create([Chunk.AREA]i16);

    for (0..WIDTH * 2) |chunk_x_| {
        for (0..WIDTH * 2) |chunk_z_| {
            var min_height: ?i16 = null;
            var max_height: ?i16 = null;

            for (0..Chunk.SIZE) |x_| {
                for (0..Chunk.SIZE) |z_| {
                    const x: f32 = @floatFromInt((chunk_x_ << Chunk.BIT_SIZE) + x_);
                    const z: f32 = @floatFromInt((chunk_z_ << Chunk.BIT_SIZE) + z_);
                    const height_idx = x_ * Chunk.SIZE + z_;

                    const height = getHeight(&gen1, &gen2, &gen3, &sea_rift_gen, x, z);
                    height_map[height_idx] = height;

                    if (min_height) |value| min_height = @min(value, height) else min_height = height;
                    if (max_height) |value| max_height = @max(value, height) else max_height = height;
                }
            }

            const min_chunk_height: i11 = @intCast((min_height.? >> Chunk.BIT_SIZE) - 1);
            const max_chunk_height: i11 = @intCast(max_height.? >> Chunk.BIT_SIZE);

            var chunk_y: i11 = ABOVE_HEIGHT - 1;
            while (chunk_y >= BELOW_HEIGHT) : (chunk_y -= 1) {
                const chunk_x = @as(i11, @intCast(chunk_x_)) - WIDTH;
                const chunk_z = @as(i11, @intCast(chunk_z_)) - WIDTH;
                const chunk_pos = Chunk.Pos{ .x = chunk_x, .y = chunk_y, .z = chunk_z };

                try world.chunks.put(gpa, chunk_pos, try Chunk.init(gpa, chunk_pos));
                const chunk = world.getChunkOrNull(chunk_pos) orelse unreachable;

                if (chunk_y >= min_chunk_height and chunk_y <= max_chunk_height) {
                    try generateNoise2D(gpa, chunk, height_map);
                } else if (chunk_y < min_chunk_height) {
                    try generateFillWithStone(gpa, chunk);
                }

                try generateNoise3D(world, gpa, chunk, &cave_gen, world.prng.random());
            }
        }
    }

    const indirect_light_bitset = try gpa.create([Chunk.AREA]u32);
    const cave_bitset = try gpa.create([Chunk.AREA]u32);

    for (0..WIDTH * 2) |chunk_x_| {
        for (0..WIDTH * 2) |chunk_z_| {
            const chunk_x = @as(i11, @intCast(chunk_x_)) - WIDTH;
            const chunk_z = @as(i11, @intCast(chunk_z_)) - WIDTH;

            var chunk_y: i11 = ABOVE_HEIGHT - 1;
            {
                const chunk_pos = Chunk.Pos{ .x = chunk_x, .y = chunk_y, .z = chunk_z };
                const chunk = try world.getChunk(chunk_pos);

                try generateIndirectLight(chunk, indirect_light_bitset);
                try world.fillChunkWithIndirectLight(chunk, indirect_light_bitset, cave_bitset);
            }

            chunk_y -= 1;
            while (chunk_y >= BELOW_HEIGHT) : (chunk_y -= 1) {
                const chunk_pos = Chunk.Pos{ .x = chunk_x, .y = chunk_y, .z = chunk_z };
                const chunk = try world.getChunk(chunk_pos);

                try world.continueIndirectLight(chunk, indirect_light_bitset);
                try world.fillChunkWithIndirectLight(chunk, indirect_light_bitset, cave_bitset);
            }
        }
    }
}

pub fn getHeight(gen1: *const znoise.FnlGenerator, gen2: *const znoise.FnlGenerator, gen3: *const znoise.FnlGenerator, sea_rift_gen: *const znoise.FnlGenerator, x: f32, z: f32) i16 {
    const noise1 = gen1.noise2(x, z) * 64;
    const noise2 = gen2.noise2(x, z) * 20;
    const noise3 = gen3.noise2(x, z);

    var height = SEA_LEVEL + noise1 + noise2 + noise3;

    if (height < SEA_LEVEL_DEEP) {
        var sea_noise1 = @abs(sea_rift_gen.noise2(x, z)) * 16;
        const sea_noise2 = @abs(sea_rift_gen.noise2(x / 2, z / 2)) * 16;
        const sea_noise3 = @abs(sea_rift_gen.noise2(x / 10, z / 10)) * 16;

        if (sea_noise1 < 3) {
            sea_noise1 = 1;
        }

        const sea_noise = sea_noise1 + sea_noise2 + sea_noise3;

        if (SEA_LEVEL_DEEP - sea_noise > height) {
            height = SEA_LEVEL_DEEP - sea_noise;
        }
    }

    return @max(BOTTOM_OF_THE_WORLD, @as(i16, @intFromFloat(@floor(height))));
}

pub fn generateNoise2D(gpa: std.mem.Allocator, chunk: *Chunk, height_map: *[Chunk.AREA]i16) !void {
    for (0..Chunk.SIZE) |x_| {
        for (0..Chunk.SIZE) |z_| {
            const x: u5 = @intCast(x_);
            const z: u5 = @intCast(z_);

            const height_idx = x_ * Chunk.SIZE + z_;
            const height = height_map[height_idx];

            for (0..Chunk.SIZE) |y_| {
                const y: u5 = @intCast(y_);
                const local_pos: Chunk.LocalPos = .{ .x = x, .y = y, .z = z };
                const world_pos: WorldPos = .from(chunk.pos, local_pos);

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

pub fn generateFillWithStone(gpa: std.mem.Allocator, chunk: *Chunk) !void {
    for (0..Chunk.SIZE) |x_| {
        const x: u5 = @intCast(x_);

        for (0..Chunk.SIZE) |z_| {
            const z: u5 = @intCast(z_);

            for (0..Chunk.SIZE) |y_| {
                const y: u5 = @intCast(y_);
                const local_pos: Chunk.LocalPos = .{ .x = x, .y = y, .z = z };

                try chunk.setBlock(gpa, local_pos, .initNone(.stone));
            }
        }
    }
}

pub fn caveThreshold(height: f32) f32 {
    const xmin = BOTTOM_OF_THE_WORLD;
    const xmax = 128;

    const ymax: f32 = 1.0;

    return (-ymax / (xmin - xmax)) * (height - xmax) + ymax;
}

pub fn generateNoise3D(world: *World, gpa: std.mem.Allocator, chunk: *Chunk, gen: *const znoise.FnlGenerator, random: std.Random) !void {
    for (0..Chunk.SIZE) |x_| {
        const x: u5 = @intCast(x_);

        for (0..Chunk.SIZE) |z_| {
            const z: u5 = @intCast(z_);

            for (0..Chunk.SIZE) |y_| {
                const y: u5 = @intCast(y_);
                const local_pos: Chunk.LocalPos = .{ .x = x, .y = y, .z = z };
                const world_pos: WorldPos = .from(chunk.pos, local_pos);
                const noise_pos = world_pos.toVec3f();

                const density = gen.noise3(noise_pos.x, noise_pos.y, noise_pos.z);
                const threshold = caveThreshold(noise_pos.y);

                if (density < -threshold) {
                    if (world_pos.y == BOTTOM_OF_THE_WORLD) {
                        try chunk.setBlock(gpa, local_pos, .initNone(.bedrock));
                    } else if (world_pos.y == BOTTOM_OF_THE_WORLD + 1) {
                        try chunk.setBlock(gpa, local_pos, .initNone(.lava));

                        var light_pos = world_pos;
                        light_pos.y += 1;

                        const light: Light = .{
                            .red = 15,
                            .green = 6,
                            .blue = 1,
                            .indirect = 0,
                        };

                        try world.light_addition_queue.writeItem(.{
                            .world_pos = light_pos,
                            .light = light,
                        });

                        chunk.setLight(local_pos, light);
                    } else {
                        const prev_block = chunk.getBlock(local_pos);
                        if (prev_block.kind != .water and prev_block.kind != .sand) {
                            try chunk.setBlock(gpa, local_pos, .initNone(.air));

                            _ = random;
                            // if (random.uintAtMost(u32, 1000) == 0) {
                            //     try chunk.light_addition_queue.writeItem(.{
                            //         .light = .{ .red = random.uintAtMost(u4, 15), .green = random.uintAtMost(u4, 15), .blue = random.uintAtMost(u4, 15), .indirect = 0 },
                            //         .world_pos = world_pos,
                            //     });
                            // }
                        }
                    }
                }
            }
        }
    }
}

pub fn generateIndirectLight(chunk: *Chunk, indirect_light_bitset: *[Chunk.AREA]u32) !void {
    for (0..Chunk.SIZE) |x| {
        for (0..Chunk.SIZE) |z| {
            const idx = x * Chunk.SIZE + z;
            const air_column = chunk.air_bitset[idx];

            var indirect_light_column = air_column;
            for (1..Chunk.SIZE) |y| {
                indirect_light_column |= (indirect_light_column >> @intCast(y));
            }

            indirect_light_bitset[idx] = indirect_light_column;
        }
    }
}

pub fn continueIndirectLight(world: *World, chunk: *Chunk, indirect_light_bitset: *[Chunk.AREA]u32) !void {
    for (0..Chunk.SIZE) |x| {
        for (0..Chunk.SIZE) |z| {
            const idx = x * Chunk.SIZE + z;
            const air_column = chunk.air_bitset[idx];

            const top_indirect_light_column = indirect_light_bitset[idx];

            var indirect_light_column: u32 = 0xFF_FF_FF_FF;
            if (top_indirect_light_column & 1 == 0) {
                const water_column = chunk.water_bitset[idx];

                if (((water_column >> Chunk.EDGE) & 1) == 1) {
                    const world_pos = WorldPos.from(
                        chunk.pos,
                        .{
                            .x = @intCast(x),
                            .y = Chunk.EDGE,
                            .z = @intCast(z),
                        },
                    );

                    const light = Light{
                        .red = 0,
                        .green = 0,
                        .blue = 0,
                        .indirect = 15,
                    };

                    try world.light_addition_queue.writeItem(.{
                        .world_pos = world_pos,
                        .light = light,
                    });
                }

                indirect_light_column = air_column;

                for (1..Chunk.SIZE) |y| {
                    indirect_light_column |= (indirect_light_column >> @intCast(y));
                }
            }

            indirect_light_bitset[idx] = indirect_light_column;
        }
    }
}

pub fn fillChunkWithIndirectLight(world: *World, chunk: *Chunk, indirect_light_bitset: *[Chunk.AREA]u32, cave_bitset: *[Chunk.AREA]u32) !void {
    for (0..Chunk.SIZE) |x| {
        for (0..Chunk.SIZE) |z| {
            const idx = x * Chunk.SIZE + z;
            const air_column = chunk.air_bitset[idx];
            const indirect_light_column = indirect_light_bitset[idx];

            const cave_column = air_column ^ indirect_light_column;
            cave_bitset[idx] = cave_column;
        }
    }

    for (0..Chunk.SIZE) |x| {
        for (0..Chunk.SIZE) |z| {
            const idx = x * Chunk.SIZE + z;

            const indirect_light_column = indirect_light_bitset[idx];
            const inverted_indirect_light_column = ~indirect_light_column;

            const top_water_column = chunk.water_bitset[idx] << 1;
            const cave_column = cave_bitset[idx];

            var west_water_column = top_water_column;
            var west_cave_column = cave_column;
            if (x != 0) {
                const west_idx = (x - 1) * Chunk.SIZE + z;

                west_water_column = chunk.water_bitset[west_idx];
                west_cave_column = cave_bitset[west_idx];
            }

            var east_water_column = top_water_column;
            var east_cave_column = cave_column;
            if (x != Chunk.EDGE) {
                const east_idx = (x + 1) * Chunk.SIZE + z;

                east_water_column = chunk.water_bitset[east_idx];
                east_cave_column = cave_bitset[east_idx];
            }

            var north_water_column = top_water_column;
            var north_cave_column = cave_column;
            if (z != 0) {
                const north_idx = x * Chunk.SIZE + z - 1;

                north_water_column = chunk.water_bitset[north_idx];
                north_cave_column = cave_bitset[north_idx];
            }

            var south_water_column = top_water_column;
            var south_cave_column = cave_column;
            if (z != Chunk.EDGE) {
                const south_idx = x * Chunk.SIZE + z + 1;

                south_water_column = chunk.water_bitset[south_idx];
                south_cave_column = cave_bitset[south_idx];
            }

            const water_neighbors_column = top_water_column | west_water_column | east_water_column | north_water_column | south_water_column;
            const cave_neighbors_column = west_cave_column | east_cave_column | north_cave_column | south_cave_column;

            const neighbors_column = cave_neighbors_column | water_neighbors_column;
            const edges_column = neighbors_column & inverted_indirect_light_column;

            for (0..Chunk.SIZE) |y| {
                const local_pos = Chunk.LocalPos{
                    .x = @intCast(x),
                    .y = @intCast(y),
                    .z = @intCast(z),
                };

                if (((indirect_light_column >> @intCast(y)) & 1) == 0) {
                    const light = Light{
                        .red = 0,
                        .green = 0,
                        .blue = 0,
                        .indirect = 15,
                    };

                    chunk.setLight(local_pos, light);

                    if (((edges_column >> @intCast(y)) & 1) == 1) {
                        try world.light_addition_queue.writeItem(.{
                            .world_pos = WorldPos.from(chunk.pos, local_pos),
                            .light = light,
                        });
                    }
                }
            }
        }
    }
}

pub fn getLight(world: *World, world_pos: WorldPos) !Light {
    const chunk = try world.getChunk(world_pos.toChunkPos());

    return chunk.getLight(world_pos.toLocalPos());
}

pub fn getLightOrNull(world: *World, world_pos: WorldPos) ?Light {
    const chunk = world.getChunkOrNull(world_pos.toChunkPos()) orelse return null;

    return chunk.getLight(world_pos.toLocalPos());
}

pub fn setLight(world: *World, world_pos: WorldPos, light: Light) !void {
    const chunk = try world.getChunk(world_pos.toChunkPos());

    chunk.setLight(world_pos.toLocalPos(), light);
}

pub const NeighborChunks = struct {
    chunks: [6]?*Chunk,

    pub const inEdge = .{
        inWestEdge,
        inEastEdge,
        inBottomEdge,
        inTopEdge,
        inNorthEdge,
        inSouthEdge,
    };

    pub const getPos = .{
        getWestPos,
        getEastPos,
        getBottomPos,
        getTopPos,
        getNorthPos,
        getSouthPos,
    };

    pub const getNeighborPos = .{
        getWestNeighborPos,
        getEastNeighborPos,
        getBottomNeighborPos,
        getTopNeighborPos,
        getNorthNeighborPos,
        getSouthNeighborPos,
    };

    fn inWestEdge(world_pos: Chunk.LocalPos) bool {
        return world_pos.x == 0;
    }

    fn inEastEdge(world_pos: Chunk.LocalPos) bool {
        return world_pos.x == Chunk.EDGE;
    }

    fn inBottomEdge(world_pos: Chunk.LocalPos) bool {
        return world_pos.y == 0;
    }

    fn inTopEdge(world_pos: Chunk.LocalPos) bool {
        return world_pos.y == Chunk.EDGE;
    }

    fn inNorthEdge(world_pos: Chunk.LocalPos) bool {
        return world_pos.z == 0;
    }

    fn inSouthEdge(world_pos: Chunk.LocalPos) bool {
        return world_pos.z == Chunk.EDGE;
    }

    fn getWestPos(world_pos: Chunk.LocalPos) Chunk.LocalPos {
        var new_pos = world_pos;
        new_pos.x -= 1;
        return new_pos;
    }

    fn getEastPos(world_pos: Chunk.LocalPos) Chunk.LocalPos {
        var new_pos = world_pos;
        new_pos.x += 1;
        return new_pos;
    }

    fn getBottomPos(world_pos: Chunk.LocalPos) Chunk.LocalPos {
        var new_pos = world_pos;
        new_pos.y -= 1;
        return new_pos;
    }

    fn getTopPos(world_pos: Chunk.LocalPos) Chunk.LocalPos {
        var new_pos = world_pos;
        new_pos.y += 1;
        return new_pos;
    }

    fn getNorthPos(world_pos: Chunk.LocalPos) Chunk.LocalPos {
        var new_pos = world_pos;
        new_pos.z -= 1;
        return new_pos;
    }

    fn getSouthPos(world_pos: Chunk.LocalPos) Chunk.LocalPos {
        var new_pos = world_pos;
        new_pos.z += 1;
        return new_pos;
    }

    fn getWestNeighborPos(world_pos: Chunk.LocalPos) Chunk.LocalPos {
        var new_pos = world_pos;
        new_pos.x = Chunk.EDGE;
        return new_pos;
    }

    fn getEastNeighborPos(world_pos: Chunk.LocalPos) Chunk.LocalPos {
        var new_pos = world_pos;
        new_pos.x = 0;
        return new_pos;
    }

    fn getBottomNeighborPos(world_pos: Chunk.LocalPos) Chunk.LocalPos {
        var new_pos = world_pos;
        new_pos.y = Chunk.EDGE;
        return new_pos;
    }

    fn getTopNeighborPos(world_pos: Chunk.LocalPos) Chunk.LocalPos {
        var new_pos = world_pos;
        new_pos.y = 0;
        return new_pos;
    }

    fn getNorthNeighborPos(world_pos: Chunk.LocalPos) Chunk.LocalPos {
        var new_pos = world_pos;
        new_pos.z = Chunk.EDGE;
        return new_pos;
    }

    fn getSouthNeighborPos(world_pos: Chunk.LocalPos) Chunk.LocalPos {
        var new_pos = world_pos;
        new_pos.z = 0;
        return new_pos;
    }
};

pub fn getNeighborChunks(world: *World, chunk_pos: Chunk.Pos) NeighborChunks {
    var chunks: [6]?*Chunk = undefined;

    inline for (Dir.indices) |dir_idx| {
        chunks[dir_idx] = world.getChunkOrNull(chunk_pos.add(Chunk.Pos.OFFSETS[dir_idx]));
    }

    return .{ .chunks = chunks };
}

pub fn addLight(world: *World, world_pos: WorldPos, light: Light) !bool {
    const chunk_pos = world_pos.toChunkPos();
    const chunk = world.getChunkOrNull(chunk_pos) orelse return false;

    const local_pos = world_pos.toLocalPos();
    const block = chunk.getBlock(local_pos);

    const light_opacity = switch (block.kind.getLightOpacity()) {
        .translucent => |light_opacity| light_opacity,
        .@"opaque" => return false,
    };

    const current_light = chunk.getLight(local_pos);
    const next_light: Light = .{
        .red = @max(current_light.red, light.red -| light_opacity.red),
        .green = @max(current_light.green, light.green -| light_opacity.green),
        .blue = @max(current_light.blue, light.blue -| light_opacity.blue),
        .indirect = @max(current_light.indirect, light.indirect -| light_opacity.indirect),
    };

    chunk.setLight(local_pos, next_light);

    try world.light_addition_queue.writeItem(.{
        .world_pos = world_pos,
        .light = light,
    });

    return true;
}

pub fn removeLight(world: *World, world_pos: WorldPos) !bool {
    const chunk_pos = world_pos.toChunkPos();
    const chunk = world.getChunkOrNull(chunk_pos) orelse return false;

    const local_pos = world_pos.toLocalPos();
    switch (chunk.getBlock(local_pos).kind.getLightOpacity()) {
        .translucent => {},
        .@"opaque" => return false,
    }

    const light = chunk.getLight(local_pos);
    chunk.setLight(local_pos, .zeroed);

    try world.light_removal_queue.writeItem(.{
        .world_pos = world_pos,
        .light = light,
    });

    return true;
}

pub fn propagateLightAddition(world: *World, gpa: std.mem.Allocator) !void {
    while (world.light_addition_queue.readItem()) |node| {
        const world_pos = node.world_pos;
        const node_light = node.light;

        inline for (Dir.values) |dir| skip: {
            const dir_idx = dir.idx();
            const neighbor_world_pos = world_pos.add(WorldPos.OFFSETS[dir_idx]);
            const neighbor_chunk_pos = neighbor_world_pos.toChunkPos();

            const neighbor_chunk = expr: {
                if (world.getChunkOrNull(neighbor_chunk_pos)) |neighbor_chunk| {
                    break :expr neighbor_chunk;
                } else break :skip;
            };

            const neighbor_local_pos = neighbor_world_pos.toLocalPos();
            const neighbor_block = neighbor_chunk.getBlock(neighbor_local_pos);

            const neighbor_light_opacity = switch (neighbor_block.kind.getLightOpacity()) {
                .translucent => |light_opacity| light_opacity,
                .@"opaque" => break :skip,
            };

            const neighbor_light = neighbor_chunk.getLight(neighbor_local_pos);
            var light_to_enqueue_and_set = neighbor_light;
            var enqueue = false;

            inline for ([_]Light.Color{ .red, .green, .blue }) |color| {
                const next_light = node_light.get(color) -| (neighbor_light_opacity.get(color) +| 1);

                if (neighbor_light.get(color) < next_light) {
                    enqueue = true;

                    light_to_enqueue_and_set.set(color, next_light);

                    neighbor_chunk.setLight(neighbor_local_pos, light_to_enqueue_and_set);
                }
            }

            {
                const next_light = node_light.indirect -| (neighbor_light_opacity.indirect +| 1);

                if (dir == .bottom and node_light.indirect == 15 and neighbor_light_opacity.indirect == 0) {
                    enqueue = true;

                    light_to_enqueue_and_set.indirect = 15;

                    neighbor_chunk.setLight(neighbor_local_pos, light_to_enqueue_and_set);
                } else if (neighbor_light.indirect < next_light) {
                    enqueue = true;

                    light_to_enqueue_and_set.indirect = next_light;

                    neighbor_chunk.setLight(neighbor_local_pos, light_to_enqueue_and_set);
                }
            }

            if (enqueue) {
                try world.light_addition_queue.writeItem(.{
                    .world_pos = neighbor_world_pos,
                    .light = light_to_enqueue_and_set,
                });

                try world.chunks_which_need_to_regenerate_meshes.enqueue(gpa, neighbor_chunk.pos);
            }
        }
    }
}

pub fn propagateLightRemoval(world: *World, gpa: std.mem.Allocator) !void {
    while (world.light_removal_queue.readItem()) |node| {
        const world_pos = node.world_pos;
        const node_light = node.light;

        inline for (Dir.values) |dir| skip: {
            const dir_idx = dir.idx();
            const neighbor_world_pos = world_pos.add(WorldPos.OFFSETS[dir_idx]);
            const neighbor_chunk_pos = neighbor_world_pos.toChunkPos();

            const neighbor_chunk = expr: {
                if (world.getChunkOrNull(neighbor_chunk_pos)) |neighbor_chunk| {
                    break :expr neighbor_chunk;
                } else break :skip;
            };

            const neighbor_local_pos = neighbor_world_pos.toLocalPos();
            const neighbor_block = neighbor_chunk.getBlock(neighbor_local_pos);

            const neighbor_light_opacity = switch (neighbor_block.kind.getLightOpacity()) {
                .translucent => |light_opacity| light_opacity,
                .@"opaque" => break :skip,
            };

            const neighbor_light = neighbor_chunk.getLight(neighbor_local_pos);

            var light_to_set_at_removal = neighbor_light;
            var light_to_enqueue_at_addition: Light = .zeroed;

            var enqueue_removal = false;
            var enqueue_addition = false;

            inline for (Light.Color.values) |color| {
                const next_light = node_light.get(color) -| (neighbor_light_opacity.get(color) +| 1);

                if (neighbor_light.get(color) > 0 and neighbor_light.get(color) == next_light) {
                    enqueue_removal = true;

                    light_to_set_at_removal.set(color, 0);
                    neighbor_chunk.setLight(neighbor_local_pos, light_to_set_at_removal);
                } else if (node_light.get(color) > 0 and neighbor_light.get(color) >= node_light.get(color)) {
                    enqueue_addition = true;

                    light_to_enqueue_at_addition.set(color, neighbor_light.get(color));
                }
            }

            if (enqueue_removal) {
                try world.light_removal_queue.writeItem(.{
                    .world_pos = neighbor_world_pos,
                    .light = neighbor_light,
                });

                try world.chunks_which_need_to_regenerate_meshes.enqueue(gpa, neighbor_chunk.pos);

                try debug.removal_nodes.data.append(gpa, neighbor_world_pos.toVec3f());
            }

            if (enqueue_addition) {
                try world.light_addition_queue.writeItem(.{
                    .world_pos = neighbor_world_pos,
                    .light = light_to_enqueue_at_addition,
                });

                try world.chunks_which_need_to_regenerate_meshes.enqueue(gpa, neighbor_chunk.pos);

                try debug.addition_nodes.data.append(gpa, neighbor_world_pos.toVec3f());
            }
        }
    }
}
