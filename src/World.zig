const std = @import("std");
const Chunk = @import("Chunk.zig");
const Light = Chunk.Light;
const Block = @import("block.zig").Block;
const DedupQueue = @import("dedup_queue.zig").DedupQueue;

const Self = @This();

const Chunks = std.AutoHashMap(Chunk.Pos, Chunk);
const ChunkPosQueue = DedupQueue(Chunk.Pos);

allocator: std.mem.Allocator,
rand: std.Random,
chunks: Chunks,
chunks_which_need_to_add_lights: ChunkPosQueue,
chunks_which_need_to_remove_lights: ChunkPosQueue,

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

    var chunks = Chunks.init(allocator);
    try generateChunks(allocator, rand, &chunks);

    const chunks_which_need_to_add_lights = ChunkPosQueue.init(allocator);
    const chunks_which_need_to_remove_lights = ChunkPosQueue.init(allocator);

    return .{
        .allocator = allocator,
        .rand = rand,
        .chunks = chunks,
        .chunks_which_need_to_add_lights = chunks_which_need_to_add_lights,
        .chunks_which_need_to_remove_lights = chunks_which_need_to_remove_lights,
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

pub fn generateChunks(allocator: std.mem.Allocator, rand: std.Random, chunks: *Chunks) !void {
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

            const height = rand.intRangeAtMost(u5, 1, 3) + additional_height;

            for (0..height) |y_| {
                const y: u5 = @intCast(y_);

                const block: Block = if (y == height - 1) if (y < 5) .sand else .grass else .stone;
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

pub fn getLight(self: *Self, pos: Pos) !Light {
    const chunk = try self.getChunk(pos.toChunkPos());

    return chunk.getLight(pos.toLocalPos());
}

pub fn setLight(self: *Self, pos: Pos, light: Light) !void {
    const chunk = try self.getChunk(pos.toChunkPos());

    chunk.setLight(pos.toLocalPos(), light);
}

pub fn addLight(self: *Self, pos: Pos, light: Light) !void {
    const chunk_pos = pos.toChunkPos();
    var chunk = try self.getChunk(chunk_pos);

    try chunk.light_addition_queue.writeItem(.{
        .pos = pos,
        .light = light,
    });

    try self.chunks_which_need_to_add_lights.enqueue(chunk_pos);
}

pub fn removeLight(self: *Self, pos: Pos, light: Light) !void {
    const chunk_pos = pos.toChunkPos();
    const chunk = try self.getChunk(chunk_pos);

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

pub fn propagateLights(self: *Self) !void {
    while (self.chunks_which_need_to_add_lights.dequeue()) |chunk_pos| {
        const chunk = try self.getChunk(chunk_pos);

        try self.propagateLightAddition(chunk);
    }

    while (self.chunks_which_need_to_remove_lights.dequeue()) |chunk_pos| {
        const chunk = try self.getChunk(chunk_pos);

        try self.propagateLightRemoval(chunk);
    }

    while (self.chunks_which_need_to_add_lights.dequeue()) |chunk_pos| {
        const chunk = try self.getChunk(chunk_pos);

        try self.propagateLightAddition(chunk);
    }
}

pub fn propagateLightAddition(self: *Self, chunk: *Chunk) !void {
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

                if (enqueue) {
                    try neighbor_chunk.light_addition_queue.writeItem(.{
                        .pos = neighbor_world_pos,
                        .light = next_light,
                    });

                    if (is_neighbor_chunk) try self.chunks_which_need_to_add_lights.enqueue(neighbor_chunk_pos);
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

                if (enqueue_removal) {
                    try neighbor_chunk.light_removal_queue.writeItem(.{
                        .pos = neighbor_world_pos,
                        .light = next_light,
                    });

                    neighbor_chunk.setLight(neighbor_local_pos, removed_light);

                    if (is_neighbor_chunk) try self.chunks_which_need_to_remove_lights.enqueue(neighbor_chunk_pos);
                }

                if (enqueue_addition) {
                    try neighbor_chunk.light_addition_queue.writeItem(.{
                        .pos = neighbor_world_pos,
                        .light = neighbor_light,
                    });

                    try self.chunks_which_need_to_add_lights.enqueue(neighbor_chunk_pos);
                }
            }
        }
    }
}
