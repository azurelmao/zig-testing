const std = @import("std");
const Chunk = @import("Chunk.zig");
const Light = Chunk.Light;
const Block = @import("block.zig").Block;

const Self = @This();

allocator: std.mem.Allocator,
rand: std.Random,
chunks: std.AutoHashMap(Chunk.Pos, Chunk),

pub const Pos = struct {
    x: i16,
    y: i16,
    z: i16,

    const Offsets = [6]Pos{
        .{ .x = -1, .y = 0, .z = 0 },
        .{ .x = 1, .y = 0, .z = 0 },
        .{ .x = 0, .y = -1, .z = 0 },
        .{ .x = 0, .y = 1, .z = 0 },
        .{ .x = 0, .y = 0, .z = -1 },
        .{ .x = 0, .y = 0, .z = 1 },
    };

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

pub fn new(allocator: std.mem.Allocator) !Self {
    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rand = prng.random();

    var chunks = std.AutoHashMap(Chunk.Pos, Chunk).init(allocator);
    try generateChunks(allocator, rand, &chunks);

    return .{
        .allocator = allocator,
        .rand = rand,
        .chunks = chunks,
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

pub fn setBlock(self: *Self, pos: Pos, block: Block) !void {
    const chunk = try self.getChunk(pos.toChunkPos());

    chunk.setBlock(pos.toLocalPos(), block);
}

const CHUNK_DISTANCE = 4;

pub fn generateChunks(allocator: std.mem.Allocator, rand: std.Random, chunks: *std.AutoHashMap(Chunk.Pos, Chunk)) !void {
    for (0..CHUNK_DISTANCE * 2) |chunk_x_| {
        for (0..CHUNK_DISTANCE * 2) |chunk_z_| {
            const chunk = try generateChunk(allocator, rand, chunk_x_, chunk_z_);
            try chunks.put(chunk.pos, chunk);
        }
    }
}

pub fn generateChunk(allocator: std.mem.Allocator, rand: std.Random, chunk_x_: usize, chunk_z_: usize) !Chunk {
    const chunk_x = @as(i11, @intCast(chunk_x_)) - CHUNK_DISTANCE;
    const chunk_z = @as(i11, @intCast(chunk_z_)) - CHUNK_DISTANCE;

    var additional_height: u5 = 0;
    if (chunk_x_ == (CHUNK_DISTANCE * 2 - 1) or chunk_z_ == (CHUNK_DISTANCE * 2 - 1)) {
        additional_height = 16;
    } else if (chunk_x_ == 0 or chunk_z_ == 0) {
        additional_height = 24;
    }

    const chunk = try Chunk.new(allocator, .{ .x = chunk_x, .y = 0, .z = chunk_z }, .air);

    for (0..Chunk.Size) |x_| {
        for (0..Chunk.Size) |z_| {
            const x: u5 = @intCast(x_);
            const z: u5 = @intCast(z_);

            // const height = rand.intRangeAtMost(u5, 1, 7) + additional_height;
            const height = 5;

            _ = rand;

            for (0..height) |y_| {
                const y: u5 = @intCast(y_);

                const block: Block = if (y == height - 1) .grass else .stone;
                chunk.setBlock(.{ .x = x, .y = y, .z = z }, block);
            }

            // if (height < 5) {
            //     for (1..5) |y_| {
            //         const y: u5 = @intCast(y_);

            //         if (chunk.getBlock(.{ .x = x, .y = y, .z = z }) == .air) {
            //             chunk.setBlock(.{ .x = x, .y = y, .z = z }, .water);
            //         }
            //     }
            // }
        }
    }

    return chunk;
}

pub fn getLight(self: *Self, pos: Pos) !Chunk.Light {
    const chunk = try self.getChunk(pos.toChunkPos());

    return chunk.getLight(pos.toLocalPos());
}

pub fn setLight(self: *Self, pos: Pos, light: Chunk.Light) !void {
    const chunk = try self.getChunk(pos.toChunkPos());

    chunk.setLight(pos.toLocalPos(), light);
}

pub fn addLight(self: *Self, pos: Pos, light: Chunk.Light) !void {
    var chunk = try self.getChunk(pos.toChunkPos());

    try chunk.light_addition_queue.writeItem(.{
        .pos = pos,
        .light = light,
    });
}

pub fn removeLight(self: *Self, pos: Pos, light: Light) !void {
    const chunk = try self.getChunk(pos.toChunkPos());

    try chunk.light_removal_queue.writeItem(.{
        .pos = pos,
        .light = light,
    });
}

const NeighborChunks = struct {
    chunks: [27]?*Chunk,

    const LocalChunkPos = struct {
        x: u2,
        y: u2,
        z: u2,

        pub fn new(origin_chunk_pos: Chunk.Pos, chunk_pos: Chunk.Pos) LocalChunkPos {
            return .{
                .x = @intCast(chunk_pos.x - origin_chunk_pos.x + 1),
                .y = @intCast(chunk_pos.y - origin_chunk_pos.y + 1),
                .z = @intCast(chunk_pos.z - origin_chunk_pos.z + 1),
            };
        }

        pub fn index(self: LocalChunkPos) u8 {
            return @as(u8, @intCast(self.x)) * 9 + @as(u8, @intCast(self.y)) * 3 + @as(u8, @intCast(self.z));
        }
    };
};

pub fn propagateLights(self: *Self) !void {
    var iter = self.chunks.valueIterator();
    while (iter.next()) |chunk| {
        try self.propagateLightAddition(chunk);
    }

    iter = self.chunks.valueIterator();
    while (iter.next()) |chunk| {
        try self.propagateLightRemoval(chunk);
    }

    iter = self.chunks.valueIterator();
    while (iter.next()) |chunk| {
        try self.propagateLightAddition(chunk);
    }
}

pub fn getNeighborChunks(self: *Self, origin_chunk_pos: Chunk.Pos) NeighborChunks {
    var chunks: [27]?*Chunk = undefined;

    for (0..3) |x_| {
        for (0..3) |y_| {
            for (0..3) |z_| {
                const neighbor_chunk_pos = origin_chunk_pos.add(.{
                    .x = @as(i11, @intCast(x_)) - 1,
                    .y = @as(i11, @intCast(y_)) - 1,
                    .z = @as(i11, @intCast(z_)) - 1,
                });

                const neighbor_local_chunk_pos = NeighborChunks.LocalChunkPos{
                    .x = @intCast(x_),
                    .y = @intCast(y_),
                    .z = @intCast(z_),
                };

                chunks[neighbor_local_chunk_pos.index()] = self.getChunkOrNull(neighbor_chunk_pos);
            }
        }
    }

    return .{ .chunks = chunks };
}

pub fn propagateLightAddition(self: *Self, chunk: *Chunk) !void {
    const neighbor_chunks = self.getNeighborChunks(chunk.pos);

    for (0..chunk.light_addition_queue.readableLength()) |node_idx| {
        const node = chunk.light_addition_queue.peekItem(node_idx);
        const pos = node.pos;
        const light = node.light;

        const neighbor_chunk_pos = pos.toChunkPos();
        const neighbor_local_chunk_pos = NeighborChunks.LocalChunkPos.new(chunk.pos, neighbor_chunk_pos);
        const neighbor_chunk = neighbor_chunks.chunks[neighbor_local_chunk_pos.index()] orelse continue;

        const local_pos = pos.toLocalPos();

        const current_light = neighbor_chunk.getLight(local_pos);
        const next_light = Chunk.Light{
            .red = @max(current_light.red, light.red),
            .green = @max(current_light.green, light.green),
            .blue = @max(current_light.blue, light.blue),
            .sunlight = @max(current_light.sunlight, light.sunlight),
        };

        neighbor_chunk.setLight(local_pos, next_light);
    }

    while (chunk.light_addition_queue.readableLength() > 0) {
        const node = chunk.light_addition_queue.readItem().?;
        const pos = node.pos;
        const light = node.light;

        inline for (0..6) |face_idx| {
            skip: {
                const neighbor_world_pos = pos.add(Pos.Offsets[face_idx]);
                const neighbor_chunk_pos = neighbor_world_pos.toChunkPos();
                const neighbor_local_chunk_pos = NeighborChunks.LocalChunkPos.new(chunk.pos, neighbor_chunk_pos);

                const neighbor_chunk = neighbor_chunks.chunks[neighbor_local_chunk_pos.index()] orelse break :skip;

                const neighbor_pos = neighbor_world_pos.toLocalPos();
                const neighbor_block = neighbor_chunk.getBlock(neighbor_pos);

                if (neighbor_block.letsLightThrough()) {
                    var neighbor_light = neighbor_chunk.getLight(neighbor_pos);
                    var next_light = neighbor_light;

                    var enqueue = false;
                    if (@as(u5, @intCast(neighbor_light.red)) + 1 < light.red) {
                        enqueue = true;

                        next_light.red = @max(neighbor_light.red, light.red) - 1;

                        neighbor_chunk.setLight(neighbor_pos, next_light);
                    }

                    if (@as(u5, @intCast(neighbor_light.green)) + 1 < light.green) {
                        enqueue = true;

                        neighbor_light = neighbor_chunk.getLight(neighbor_pos);

                        next_light.green = @max(neighbor_light.green, light.green) - 1;

                        neighbor_chunk.setLight(neighbor_pos, next_light);
                    }

                    if (@as(u5, @intCast(neighbor_light.blue)) + 1 < light.blue) {
                        enqueue = true;

                        neighbor_light = neighbor_chunk.getLight(neighbor_pos);

                        next_light.blue = @max(neighbor_light.blue, light.blue) - 1;

                        neighbor_chunk.setLight(neighbor_pos, next_light);
                    }

                    if (enqueue) {
                        try chunk.light_addition_queue.writeItem(.{
                            .pos = neighbor_world_pos,
                            .light = next_light,
                        });
                    }
                }
            }
        }
    }
}

pub fn propagateLightRemoval(self: *Self, chunk: *Chunk) !void {
    for (0..chunk.light_removal_queue.readableLength()) |i| {
        const node = chunk.light_removal_queue.peekItem(i);
        const local_pos = node.pos.toLocalPos();
        const node_light = node.light;

        const light = chunk.getLight(local_pos);

        chunk.setLight(local_pos, .{
            .red = light.red - node_light.red,
            .green = light.green - node_light.green,
            .blue = light.blue - node_light.blue,
            .sunlight = light.sunlight,
        });
    }

    const neighbor_chunks = self.getNeighborChunks(chunk.pos);

    while (chunk.light_removal_queue.readableLength() > 0) {
        const node = chunk.light_removal_queue.readItem().?;
        const pos = node.pos;
        const light = node.light;

        inline for (0..6) |face_idx| {
            skip: {
                var the_correct_chunk: *Chunk = undefined;

                const neighbor_world_pos = pos.add(Pos.Offsets[face_idx]);
                const neighbor_chunk_pos = neighbor_world_pos.toChunkPos();
                const neighbor_local_chunk_pos = NeighborChunks.LocalChunkPos.new(chunk.pos, neighbor_chunk_pos);

                if (neighbor_chunks.chunks[neighbor_local_chunk_pos.index()]) |neighbor_chunk| {
                    the_correct_chunk = neighbor_chunk;
                } else {
                    // TODO: Save light nodes for unloaded chunk
                    break :skip;
                }

                const neighbor_pos = neighbor_world_pos.toLocalPos();
                const neighbor_block = the_correct_chunk.getBlock(neighbor_pos);

                if (neighbor_block.letsLightThrough()) {
                    const neighbor_light = the_correct_chunk.getLight(neighbor_pos);
                    var next_light = neighbor_light;

                    var some_other_light = Chunk.Light{
                        .red = 0,
                        .green = 0,
                        .blue = 0,
                        .sunlight = neighbor_light.sunlight,
                    };

                    var enqueue_removal = false;
                    var enqueue_addition = false;

                    if (neighbor_light.red > 0 and neighbor_light.red <= light.red) {
                        enqueue_removal = true;
                        next_light.red = 0;

                        the_correct_chunk.setLight(neighbor_pos, next_light);
                    } else if (neighbor_light.red > light.red) {
                        enqueue_addition = true;
                        some_other_light.red = neighbor_light.red;
                    }

                    if (neighbor_light.green > 0 and neighbor_light.green <= light.green) {
                        enqueue_removal = true;
                        next_light.green = 0;

                        the_correct_chunk.setLight(neighbor_pos, next_light);
                    } else if (neighbor_light.green > light.green) {
                        enqueue_addition = true;
                        some_other_light.green = neighbor_light.green;
                    }

                    if (neighbor_light.blue > 0 and neighbor_light.blue <= light.blue) {
                        enqueue_removal = true;
                        next_light.blue = 0;

                        the_correct_chunk.setLight(neighbor_pos, next_light);
                    } else if (neighbor_light.blue > light.blue) {
                        enqueue_addition = true;
                        some_other_light.blue = neighbor_light.blue;
                    }

                    if (enqueue_removal) {
                        try chunk.light_removal_queue.writeItem(.{
                            .pos = neighbor_world_pos,
                            .light = neighbor_light,
                        });
                    }

                    if (enqueue_addition) {
                        try chunk.light_addition_queue.writeItem(.{
                            .pos = neighbor_world_pos,
                            .light = some_other_light,
                        });
                    }
                }
            }
        }
    }
}
