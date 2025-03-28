const std = @import("std");
const znoise = @import("znoise");
const Chunk = @import("Chunk.zig");
const Light = Chunk.Light;
const Block = @import("block.zig").Block;
const Side = @import("side.zig").Side;
const DedupQueue = @import("dedup_queue.zig").DedupQueue;
const Vec3f = @import("vec3f.zig").Vec3f;

const Self = @This();

const Chunks = std.AutoHashMapUnmanaged(Chunk.Pos, Chunk);
const ChunkPosQueue = DedupQueue(Chunk.Pos);

prng: std.Random.Xoshiro256,
seed: i32,
chunks: Chunks,
chunks_which_need_to_add_lights: ChunkPosQueue,
chunks_which_need_to_remove_lights: ChunkPosQueue,

pub const Pos = struct {
    x: i16,
    y: i16,
    z: i16,

    pub const Offsets = [6]Pos{
        .{ .x = -1, .y = 0, .z = 0 },
        .{ .x = 1, .y = 0, .z = 0 },
        .{ .x = 0, .y = -1, .z = 0 },
        .{ .x = 0, .y = 1, .z = 0 },
        .{ .x = 0, .y = 0, .z = -1 },
        .{ .x = 0, .y = 0, .z = 1 },
    };

    pub fn from(chunk_pos: Chunk.Pos, local_pos: Chunk.LocalPos) Pos {
        return .{
            .x = (@as(i16, @intCast(chunk_pos.x)) << Chunk.BitSize) + @as(i16, @intCast(local_pos.x)),
            .y = (@as(i16, @intCast(chunk_pos.y)) << Chunk.BitSize) + @as(i16, @intCast(local_pos.y)),
            .z = (@as(i16, @intCast(chunk_pos.z)) << Chunk.BitSize) + @as(i16, @intCast(local_pos.z)),
        };
    }

    pub fn toChunkPos(self: Pos) Chunk.Pos {
        return .{
            .x = @intCast(self.x >> Chunk.BitSize),
            .y = @intCast(self.y >> Chunk.BitSize),
            .z = @intCast(self.z >> Chunk.BitSize),
        };
    }

    pub fn toLocalPos(self: Pos) Chunk.LocalPos {
        return .{
            .x = @intCast(self.x & Chunk.BitMask),
            .y = @intCast(self.y & Chunk.BitMask),
            .z = @intCast(self.z & Chunk.BitMask),
        };
    }

    pub fn toVec3f(self: Pos) Vec3f {
        return .{
            .x = @floatFromInt(self.x),
            .y = @floatFromInt(self.y),
            .z = @floatFromInt(self.z),
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

pub fn init(seed: i32) !Self {
    const prng = std.Random.DefaultPrng.init(expr: {
        var prng_seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&prng_seed));
        break :expr prng_seed;
    });

    return .{
        .prng = prng,
        .seed = seed,
        .chunks = .empty,
        .chunks_which_need_to_add_lights = .empty,
        .chunks_which_need_to_remove_lights = .empty,
    };
}

pub fn getChunk(self: *Self, pos: Chunk.Pos) !*Chunk {
    return self.chunks.getPtr(pos) orelse error.ChunkNotFound;
}

pub fn getChunkOrNull(self: *Self, pos: Chunk.Pos) ?*Chunk {
    return self.chunks.getPtr(pos);
}

pub fn getBlock(self: *Self, pos: Pos) !Block {
    const chunk = try self.getChunk(pos.toChunkPos());

    return chunk.getBlock(pos.toLocalPos());
}

pub fn getBlockOrNull(self: *Self, pos: Pos) ?Block {
    const chunk = self.getChunkOrNull(pos.toChunkPos()) orelse return null;

    return chunk.getBlock(pos.toLocalPos());
}

pub fn setBlock(self: *Self, pos: Pos, block: Block) !void {
    const chunk = try self.getChunk(pos.toChunkPos());

    chunk.setBlock(pos.toLocalPos(), block);
}

pub fn setBlockAndAffectLight(self: *Self, pos: Pos, block: Block) !void {
    const chunk_pos = pos.toChunkPos();
    const chunk = try self.getChunk(chunk_pos);

    const local_pos = pos.toLocalPos();
    const light = chunk.getLight(local_pos);
    try chunk.light_removal_queue.writeItem(.{ .pos = Pos.from(chunk_pos, local_pos), .light = light });
    try self.chunks_which_need_to_remove_lights.enqueue(chunk_pos);

    chunk.setBlock(local_pos, block);
}

pub const RaycastSide = enum {
    west,
    east,
    bottom,
    top,
    north,
    south,
    inside,
    out_of_bounds,
};

pub const RaycastResult = struct {
    pos: Pos,
    side: RaycastSide,
    block: ?Block,
};

pub fn raycast(self: *Self, origin: Vec3f, direction: Vec3f) RaycastResult {
    var moving_position = origin.floor();

    const step = Vec3f.new(std.math.sign(direction.x), std.math.sign(direction.y), std.math.sign(direction.z));
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

    for (0..120) |_| {
        const block_world_pos = moving_position.toWorldPos();
        const block_or_null = self.getBlockOrNull(block_world_pos);

        if (block_or_null) |block| {
            if (block.isInteractable()) {
                const side: RaycastSide = expr: {
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
                    .pos = block_world_pos,
                    .side = side,
                    .block = block,
                };
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
        .pos = moving_position.toWorldPos(),
        .side = .out_of_bounds,
        .block = null,
    };
}

pub const Width = 1;
pub const Height = 8;
pub const AboveHeight = 2;
pub const BelowHeight = AboveHeight - Height;
pub const BottomOfTheWorld = BelowHeight * Chunk.Size;
pub const SeaLevel = 0;
pub const SeaLevelDeep = SeaLevel - 16;

pub fn generate(self: *Self, allocator: std.mem.Allocator) !void {
    const gen1 = znoise.FnlGenerator{
        .noise_type = .opensimplex2,
        .seed = self.seed,
        .frequency = 1.0 / 16.0 / 16.0 / 16.0,
        // .lacunarity = 4,
        // .gain = 16,
        // .octaves = 8,
    };

    const gen2 = znoise.FnlGenerator{
        .noise_type = .opensimplex2,
        .seed = self.seed,
        .frequency = 1.0 / 16.0 / 16.0,
        // .lacunarity = 8,
        // .gain = 1,
        // .octaves = 8,
    };

    const gen3 = znoise.FnlGenerator{
        .noise_type = .opensimplex2,
        .seed = self.seed,
        .frequency = 1.0 / 16.0,
        // .lacunarity = 16,
        // .gain = 1.0 / 16.0,
        // .octaves = 8,
    };

    const sea_gen = znoise.FnlGenerator{
        .noise_type = .opensimplex2,
        .seed = self.seed,
        .frequency = 0.05,
        .fractal_type = .ridged,
        .octaves = 6,
        .lacunarity = 0.37,
        .gain = 10,
        .weighted_strength = 0.94,
    };

    const cave_gen = znoise.FnlGenerator{
        .noise_type = .opensimplex2,
        .seed = self.seed,
        .frequency = 0.01,
        .fractal_type = .fbm,
        .octaves = 5,
        .lacunarity = 2,
        .gain = 0.4,
        .weighted_strength = -1,
    };

    var height_map = try allocator.create([Chunk.Area]i16);

    for (0..Width * 2) |chunk_x_| {
        for (0..Width * 2) |chunk_z_| {
            var min_height: ?i16 = null;
            var max_height: ?i16 = null;

            for (0..Chunk.Size) |x_| {
                for (0..Chunk.Size) |z_| {
                    const x: f32 = @floatFromInt((chunk_x_ << Chunk.BitSize) + x_);
                    const z: f32 = @floatFromInt((chunk_z_ << Chunk.BitSize) + z_);
                    const height_idx = x_ * Chunk.Size + z_;

                    const height = getHeight(&gen1, &gen2, &gen3, &sea_gen, x, z);
                    height_map[height_idx] = height;

                    if (min_height) |value| min_height = @min(value, height) else min_height = height;
                    if (max_height) |value| max_height = @max(value, height) else max_height = height;
                }
            }

            const min_chunk_height: i11 = @intCast((min_height.? >> Chunk.BitSize) - 1);
            const max_chunk_height: i11 = @intCast(max_height.? >> Chunk.BitSize);

            var chunk_y: i11 = AboveHeight - 1;
            while (chunk_y >= BelowHeight) : (chunk_y -= 1) {
                const chunk_x = @as(i11, @intCast(chunk_x_)) - Width;
                const chunk_z = @as(i11, @intCast(chunk_z_)) - Width;
                const chunk_pos = Chunk.Pos{ .x = chunk_x, .y = chunk_y, .z = chunk_z };

                var chunk = try Chunk.new(allocator, chunk_pos, .air);

                if (chunk_y >= min_chunk_height and chunk_y <= max_chunk_height) {
                    try generateNoise2D(&chunk, height_map);
                } else if (chunk_y <= min_chunk_height) {
                    try generateNoise3D(&chunk, &cave_gen);
                }

                try self.chunks.put(allocator, chunk.pos, chunk);
            }
        }
    }

    const indirect_light_bitset = try allocator.create([Chunk.Area]u32);
    const cave_bitset = try allocator.create([Chunk.Area]u32);

    for (0..Width * 2) |chunk_x_| {
        for (0..Width * 2) |chunk_z_| {
            const chunk_x = @as(i11, @intCast(chunk_x_)) - Width;
            const chunk_z = @as(i11, @intCast(chunk_z_)) - Width;

            var chunk_y: i11 = AboveHeight - 1;
            {
                const chunk_pos = Chunk.Pos{ .x = chunk_x, .y = chunk_y, .z = chunk_z };
                const chunk = try self.getChunk(chunk_pos);

                try generateIndirectLight(chunk, indirect_light_bitset);
                try fillChunkWithIndirectLight(chunk, indirect_light_bitset, cave_bitset);
                try self.chunks_which_need_to_add_lights.enqueue(allocator, chunk.pos);
            }

            chunk_y -= 1;
            while (chunk_y >= BelowHeight) : (chunk_y -= 1) {
                const chunk_pos = Chunk.Pos{ .x = chunk_x, .y = chunk_y, .z = chunk_z };
                const chunk = try self.getChunk(chunk_pos);

                try continueIndirectLight(chunk, indirect_light_bitset);
                try fillChunkWithIndirectLight(chunk, indirect_light_bitset, cave_bitset);
                try self.chunks_which_need_to_add_lights.enqueue(allocator, chunk.pos);
            }
        }
    }
}

pub fn getHeight(gen1: *const znoise.FnlGenerator, gen2: *const znoise.FnlGenerator, gen3: *const znoise.FnlGenerator, sea_rift_gen: *const znoise.FnlGenerator, x: f32, z: f32) i16 {
    const noise1 = gen1.noise2(x, z) * 64;
    const noise2 = gen2.noise2(x, z) * 20;
    const noise3 = gen3.noise2(x, z);

    var height = SeaLevel + noise1 + noise2 + noise3;

    if (height < SeaLevelDeep) {
        var sea_noise1 = @abs(sea_rift_gen.noise2(x, z)) * 16;
        const sea_noise2 = @abs(sea_rift_gen.noise2(x / 2, z / 2)) * 16;
        const sea_noise3 = @abs(sea_rift_gen.noise2(x / 10, z / 10)) * 16;

        if (sea_noise1 < 3) {
            sea_noise1 = 1;
        }

        const sea_noise = sea_noise1 + sea_noise2 + sea_noise3;

        if (SeaLevelDeep - sea_noise > height) {
            height = SeaLevelDeep - sea_noise;
        }
    }

    return @max(BottomOfTheWorld, @as(i16, @intFromFloat(@floor(height))));
}

pub fn generateNoise2D(chunk: *Chunk, height_map: *[Chunk.Area]i16) !void {
    for (0..Chunk.Size) |x_| {
        for (0..Chunk.Size) |z_| {
            const x: u5 = @intCast(x_);
            const z: u5 = @intCast(z_);

            const height_idx = x_ * Chunk.Size + z_;
            const height = height_map[height_idx];

            for (0..Chunk.Size) |y_| {
                const y: u5 = @intCast(y_);
                const local_pos = Chunk.LocalPos{ .x = x, .y = y, .z = z };
                const world_pos = Pos.from(chunk.pos, local_pos);

                if (world_pos.y < height) {
                    if (world_pos.y == height - 1) {
                        if (world_pos.y < SeaLevel) {
                            chunk.setBlock(local_pos, .sand);
                        } else {
                            chunk.setBlock(local_pos, .grass);
                        }
                    } else {
                        chunk.setBlock(local_pos, .stone);
                    }
                } else {
                    if (world_pos.y == BottomOfTheWorld) {
                        chunk.setBlock(local_pos, .stone);
                    } else if (world_pos.y < SeaLevel) {
                        chunk.setBlock(local_pos, .water);
                    }
                }
            }
        }
    }
}

pub fn generateNoise3D(chunk: *Chunk, gen: *const znoise.FnlGenerator) !void {
    for (0..Chunk.Size) |x_| {
        for (0..Chunk.Size) |z_| {
            const x: u5 = @intCast(x_);
            const z: u5 = @intCast(z_);

            for (0..Chunk.Size) |y_| {
                const y: u5 = @intCast(y_);
                const local_pos = Chunk.LocalPos{ .x = x, .y = y, .z = z };
                const world_pos = Pos.from(chunk.pos, local_pos);
                const noise_pos = world_pos.toVec3f();

                const density = gen.noise3(noise_pos.x, noise_pos.y, noise_pos.z);

                if (density > 0.0) {
                    chunk.setBlock(local_pos, .stone);
                } else {
                    if (world_pos.y == BottomOfTheWorld) {
                        chunk.setBlock(local_pos, .bedrock);
                    } else if (world_pos.y == BottomOfTheWorld + 1) {
                        chunk.setBlock(local_pos, .lava);

                        var light_pos = world_pos;
                        light_pos.y += 1;

                        try chunk.light_addition_queue.writeItem(.{
                            .light = .{ .red = 15, .green = 6, .blue = 1, .indirect = 0 },
                            .pos = light_pos,
                        });
                    }
                }
            }
        }
    }
}

pub fn generateIndirectLight(chunk: *Chunk, indirect_light_bitset: *[Chunk.Area]u32) !void {
    for (0..Chunk.Size) |x| {
        for (0..Chunk.Size) |z| {
            const idx = x * Chunk.Size + z;
            const air_column = chunk.air_bitset[idx];

            var indirect_light_column = air_column;
            for (1..Chunk.Size) |y| {
                indirect_light_column |= (indirect_light_column >> @intCast(y));
            }

            indirect_light_bitset[idx] = indirect_light_column;
        }
    }
}

pub fn continueIndirectLight(chunk: *Chunk, indirect_light_bitset: *[Chunk.Area]u32) !void {
    for (0..Chunk.Size) |x| {
        for (0..Chunk.Size) |z| {
            const idx = x * Chunk.Size + z;
            const air_column = chunk.air_bitset[idx];

            const top_indirect_light_column = indirect_light_bitset[idx];

            var indirect_light_column: u32 = 0xFF_FF_FF_FF;
            if (top_indirect_light_column & 1 == 0) {
                const water_column = chunk.water_bitset[idx];

                if (((water_column >> Chunk.Edge) & 1) == 1) {
                    const world_pos = Pos.from(
                        chunk.pos,
                        .{
                            .x = @intCast(x),
                            .y = Chunk.Edge,
                            .z = @intCast(z),
                        },
                    );

                    const light = Light{
                        .red = 0,
                        .green = 0,
                        .blue = 0,
                        .indirect = 15,
                    };

                    try chunk.light_addition_queue.writeItem(.{
                        .pos = world_pos,
                        .light = light,
                    });
                }

                indirect_light_column = air_column;

                for (1..Chunk.Size) |y| {
                    indirect_light_column |= (indirect_light_column >> @intCast(y));
                }
            }

            indirect_light_bitset[idx] = indirect_light_column;
        }
    }
}

pub fn fillChunkWithIndirectLight(chunk: *Chunk, indirect_light_bitset: *[Chunk.Area]u32, cave_bitset: *[Chunk.Area]u32) !void {
    for (0..Chunk.Size) |x| {
        for (0..Chunk.Size) |z| {
            const idx = x * Chunk.Size + z;
            const air_column = chunk.air_bitset[idx];
            const indirect_light_column = indirect_light_bitset[idx];

            const cave_column = air_column ^ indirect_light_column;
            cave_bitset[idx] = cave_column;
        }
    }

    for (0..Chunk.Size) |x| {
        for (0..Chunk.Size) |z| {
            const idx = x * Chunk.Size + z;

            const indirect_light_column = indirect_light_bitset[idx];
            const inverted_indirect_light_column = ~indirect_light_column;

            const top_water_column = chunk.water_bitset[idx] << 1;
            const cave_column = cave_bitset[idx];

            var west_water_column = top_water_column;
            var west_cave_column = cave_column;
            if (x != 0) {
                const west_idx = (x - 1) * Chunk.Size + z;

                west_water_column = chunk.water_bitset[west_idx];
                west_cave_column = cave_bitset[west_idx];
            }

            var east_water_column = top_water_column;
            var east_cave_column = cave_column;
            if (x != Chunk.Edge) {
                const east_idx = (x + 1) * Chunk.Size + z;

                east_water_column = chunk.water_bitset[east_idx];
                east_cave_column = cave_bitset[east_idx];
            }

            var north_water_column = top_water_column;
            var north_cave_column = cave_column;
            if (z != 0) {
                const north_idx = x * Chunk.Size + z - 1;

                north_water_column = chunk.water_bitset[north_idx];
                north_cave_column = cave_bitset[north_idx];
            }

            var south_water_column = top_water_column;
            var south_cave_column = cave_column;
            if (z != Chunk.Edge) {
                const south_idx = x * Chunk.Size + z + 1;

                south_water_column = chunk.water_bitset[south_idx];
                south_cave_column = cave_bitset[south_idx];
            }

            const water_neighbors_column = top_water_column | west_water_column | east_water_column | north_water_column | south_water_column;
            const cave_neighbors_column = west_cave_column | east_cave_column | north_cave_column | south_cave_column;

            const neighbors_column = cave_neighbors_column | water_neighbors_column;
            const edges_column = neighbors_column & inverted_indirect_light_column;

            for (0..Chunk.Size) |y| {
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
                        try chunk.light_addition_queue.writeItem(.{
                            .pos = Pos.from(chunk.pos, local_pos),
                            .light = light,
                        });
                    }
                }
            }
        }
    }
}

pub fn getLight(self: *Self, pos: Pos) !Light {
    const chunk = self.getChunk(pos.toChunkPos()) catch {
        return error.GetLight;
    };

    return chunk.getLight(pos.toLocalPos());
}

pub fn setLight(self: *Self, pos: Pos, light: Light) !void {
    const chunk = self.getChunk(pos.toChunkPos()) catch {
        return error.SetLight;
    };

    chunk.setLight(pos.toLocalPos(), light);
}

pub fn addLight(self: *Self, pos: Pos, light: Light) !void {
    const chunk_pos = pos.toChunkPos();
    var chunk = self.getChunk(chunk_pos) catch {
        return error.AddLight;
    };

    try chunk.light_addition_queue.writeItem(.{
        .pos = pos,
        .light = light,
    });

    try self.chunks_which_need_to_add_lights.enqueue(chunk_pos);
}

pub fn removeLight(self: *Self, pos: Pos, light: Light) !void {
    const chunk_pos = pos.toChunkPos();
    const chunk = self.getChunk(chunk_pos) catch {
        return error.RemoveLight;
    };

    try chunk.light_removal_queue.writeItem(.{
        .pos = pos,
        .light = light,
    });

    try self.chunks_which_need_to_remove_lights.enqueue(chunk_pos);
}

const NeighborChunks = struct {
    chunks: [6]?*Chunk,
};

pub fn getNeighborChunks(self: *Self, chunk_pos: Chunk.Pos) NeighborChunks {
    var chunks: [6]?*Chunk = undefined;

    inline for (0..6) |face_idx| {
        chunks[face_idx] = self.getChunkOrNull(chunk_pos.add(Chunk.Pos.Offsets[face_idx]));
    }

    return .{ .chunks = chunks };
}

pub fn propagateLights(self: *Self, allocator: std.mem.Allocator) !void {
    while (self.chunks_which_need_to_add_lights.dequeue()) |chunk_pos| {
        const chunk = self.getChunk(chunk_pos) catch {
            std.log.err("{}", .{chunk_pos});
            return error.PropAdd1;
        };

        try self.propagateLightAddition(allocator, chunk);
    }

    while (self.chunks_which_need_to_remove_lights.dequeue()) |chunk_pos| {
        const chunk = self.getChunk(chunk_pos) catch {
            return error.PropRem;
        };

        try self.propagateLightRemoval(allocator, chunk);
    }

    while (self.chunks_which_need_to_add_lights.dequeue()) |chunk_pos| {
        const chunk = self.getChunk(chunk_pos) catch {
            return error.PropAdd2;
        };

        try self.propagateLightAddition(allocator, chunk);
    }
}

pub fn propagateLightAddition(self: *Self, allocator: std.mem.Allocator, chunk: *Chunk) !void {
    for (0..chunk.light_addition_queue.readableLength()) |node_idx| {
        const node = chunk.light_addition_queue.peekItem(node_idx);
        const local_pos = node.pos.toLocalPos();
        const light = node.light;

        const current_light = chunk.getLight(local_pos);
        const next_light = Light{
            .red = @max(current_light.red, light.red),
            .green = @max(current_light.green, light.green),
            .blue = @max(current_light.blue, light.blue),
            .indirect = @max(current_light.indirect, light.indirect),
        };

        chunk.setLight(local_pos, next_light);
    }

    const neighbor_chunks = self.getNeighborChunks(chunk.pos);

    while (chunk.light_addition_queue.readableLength() > 0) {
        const node = chunk.light_addition_queue.readItem().?;
        const world_pos = node.pos;
        const light = node.light;

        inline for (0..6) |face_idx| {
            skip: {
                const neighbor_world_pos = world_pos.add(Pos.Offsets[face_idx]);
                const neighbor_chunk_pos = neighbor_world_pos.toChunkPos();

                var is_neighbor_chunk = false;

                const neighbor_chunk = expr: {
                    if (neighbor_chunk_pos.notEqual(chunk.pos)) {
                        if (neighbor_chunks.chunks[face_idx]) |neighbor_chunk| {
                            is_neighbor_chunk = true;

                            break :expr neighbor_chunk;
                        } else {
                            break :skip;
                        }
                    } else {
                        break :expr chunk;
                    }
                };

                const neighbor_local_pos = neighbor_world_pos.toLocalPos();
                const neighbor_block = neighbor_chunk.getBlock(neighbor_local_pos);

                const neighbor_light_opacity = switch (neighbor_block.getLightOpacity()) {
                    .translucent => |light_opacity| light_opacity,
                    .@"opaque" => break :skip,
                };

                var neighbor_light = neighbor_chunk.getLight(neighbor_local_pos);
                var next_light = neighbor_light;

                var enqueue = false;
                if (@as(u5, @intCast(neighbor_light.red)) + 1 < light.red) {
                    enqueue = true;

                    const light_to_subtract = neighbor_light_opacity.red + 1;
                    const max_light = @max(neighbor_light.red, light.red);
                    next_light.red = if (max_light <= light_to_subtract) 0 else max_light - light_to_subtract;

                    neighbor_chunk.setLight(neighbor_local_pos, next_light);
                }

                if (@as(u5, @intCast(neighbor_light.green)) + 1 < light.green) {
                    enqueue = true;

                    neighbor_light = neighbor_chunk.getLight(neighbor_local_pos);

                    const light_to_subtract = neighbor_light_opacity.green + 1;
                    const max_light = @max(neighbor_light.green, light.green);
                    next_light.green = if (max_light <= light_to_subtract) 0 else max_light - light_to_subtract;

                    neighbor_chunk.setLight(neighbor_local_pos, next_light);
                }

                if (@as(u5, @intCast(neighbor_light.blue)) + 1 < light.blue) {
                    enqueue = true;

                    neighbor_light = neighbor_chunk.getLight(neighbor_local_pos);

                    const light_to_subtract = neighbor_light_opacity.blue + 1;
                    const max_light = @max(neighbor_light.blue, light.blue);
                    next_light.blue = if (max_light <= light_to_subtract) 0 else max_light - light_to_subtract;

                    neighbor_chunk.setLight(neighbor_local_pos, next_light);
                }

                if (face_idx == Side.bottom.idx() and light.indirect == 15 and neighbor_block == .air) {
                    enqueue = true;

                    neighbor_light = neighbor_chunk.getLight(neighbor_local_pos);

                    next_light.indirect = @max(neighbor_light.indirect, light.indirect);

                    neighbor_chunk.setLight(neighbor_local_pos, next_light);
                } else if (@as(u5, @intCast(neighbor_light.indirect)) + 1 < light.indirect) {
                    enqueue = true;

                    neighbor_light = neighbor_chunk.getLight(neighbor_local_pos);

                    const light_to_subtract = neighbor_light_opacity.indirect + 1;
                    const max_light = @max(neighbor_light.indirect, light.indirect);
                    next_light.indirect = if (max_light <= light_to_subtract) 0 else max_light - light_to_subtract;

                    neighbor_chunk.setLight(neighbor_local_pos, next_light);
                }

                if (enqueue) {
                    try neighbor_chunk.light_addition_queue.writeItem(.{
                        .pos = neighbor_world_pos,
                        .light = next_light,
                    });

                    if (is_neighbor_chunk) try self.chunks_which_need_to_add_lights.enqueue(allocator, neighbor_chunk_pos);
                }
            }
        }
    }
}

pub fn propagateLightRemoval(self: *Self, allocator: std.mem.Allocator, chunk: *Chunk) !void {
    for (0..chunk.light_removal_queue.readableLength()) |i| {
        const node = chunk.light_removal_queue.peekItem(i);
        const local_pos = node.pos.toLocalPos();
        const node_light = node.light;

        const light = chunk.getLight(local_pos);
        const next_light = Light{
            .red = light.red - node_light.red,
            .green = light.green - node_light.green,
            .blue = light.blue - node_light.blue,
            .indirect = light.indirect,
        };

        chunk.setLight(local_pos, next_light);
    }

    const neighbor_chunks = self.getNeighborChunks(chunk.pos);

    while (chunk.light_removal_queue.readableLength() > 0) {
        const node = chunk.light_removal_queue.readItem().?;
        const world_pos = node.pos;
        const light = node.light;

        inline for (0..6) |face_idx| {
            skip: {
                const neighbor_world_pos = world_pos.add(Pos.Offsets[face_idx]);
                const neighbor_chunk_pos = neighbor_world_pos.toChunkPos();

                var is_neighbor_chunk = false;

                const neighbor_chunk = expr: {
                    if (neighbor_chunk_pos.notEqual(chunk.pos)) {
                        if (neighbor_chunks.chunks[face_idx]) |neighbor_chunk| {
                            is_neighbor_chunk = true;

                            break :expr neighbor_chunk;
                        } else {
                            break :skip;
                        }
                    } else {
                        break :expr chunk;
                    }
                };

                const neighbor_local_pos = neighbor_world_pos.toLocalPos();
                const neighbor_block = neighbor_chunk.getBlock(neighbor_local_pos);

                const neighbor_light_opacity = switch (neighbor_block.getLightOpacity()) {
                    .translucent => |light_opacity| light_opacity,
                    .@"opaque" => break :skip,
                };

                const neighbor_light = neighbor_chunk.getLight(neighbor_local_pos);
                var removed_light = neighbor_light;
                var next_light = light;

                var enqueue_removal = false;
                var enqueue_addition = false;

                if (neighbor_light.red > 0 and neighbor_light.red <= light.red) {
                    enqueue_removal = true;
                    removed_light.red = 0;

                    const light_to_subtract = neighbor_light_opacity.red + 1;
                    const max_light = @max(neighbor_light.red, light.red);
                    next_light.red = if (max_light <= light_to_subtract) 0 else max_light - light_to_subtract;
                } else if (light.red > 0 and neighbor_light.red > light.red) {
                    enqueue_addition = true;
                }

                if (neighbor_light.green > 0 and neighbor_light.green <= light.green) {
                    enqueue_removal = true;
                    removed_light.green = 0;

                    const light_to_subtract = neighbor_light_opacity.green + 1;
                    const max_light = @max(neighbor_light.green, light.green);
                    next_light.green = if (max_light <= light_to_subtract) 0 else max_light - light_to_subtract;
                } else if (light.green > 0 and neighbor_light.green > light.green) {
                    enqueue_addition = true;
                }

                if (neighbor_light.blue > 0 and neighbor_light.blue <= light.blue) {
                    enqueue_removal = true;
                    removed_light.blue = 0;

                    const light_to_subtract = neighbor_light_opacity.blue + 1;
                    const max_light = @max(neighbor_light.blue, light.blue);
                    next_light.blue = if (max_light <= light_to_subtract) 0 else max_light - light_to_subtract;
                } else if (light.blue > 0 and neighbor_light.blue > light.blue) {
                    enqueue_addition = true;
                }

                if (neighbor_light.indirect > 0 and neighbor_light.indirect <= light.indirect) {
                    enqueue_removal = true;
                    removed_light.indirect = 0;

                    const light_to_subtract = neighbor_light_opacity.indirect + 1;
                    const max_light = @max(neighbor_light.indirect, light.indirect);
                    next_light.indirect = if (max_light <= light_to_subtract) 0 else max_light - light_to_subtract;
                } else if (light.indirect > 0 and neighbor_light.indirect > light.indirect) {
                    enqueue_addition = true;
                }

                if (enqueue_removal) {
                    try neighbor_chunk.light_removal_queue.writeItem(.{
                        .pos = neighbor_world_pos,
                        .light = next_light,
                    });

                    neighbor_chunk.setLight(neighbor_local_pos, removed_light);

                    if (is_neighbor_chunk) try self.chunks_which_need_to_remove_lights.enqueue(allocator, neighbor_chunk_pos);
                }

                if (enqueue_addition) {
                    try neighbor_chunk.light_addition_queue.writeItem(.{
                        .pos = neighbor_world_pos,
                        .light = neighbor_light,
                    });

                    try self.chunks_which_need_to_add_lights.enqueue(allocator, neighbor_chunk_pos);
                }
            }
        }
    }
}
