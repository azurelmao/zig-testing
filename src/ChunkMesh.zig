const Vec3f = @import("vec3f.zig").Vec3f;
const Chunk = @import("Chunk.zig");

pub const BOUNDING_BOX_LINES_BUFFER: []const Vec3f = &.{
    .{ .x = 0, .y = 0, .z = 0 },
    .{ .x = 0, .y = 0, .z = Chunk.Size },
    .{ .x = Chunk.Size, .y = 0, .z = 0 },
    .{ .x = Chunk.Size, .y = 0, .z = Chunk.Size },

    .{ .x = 0, .y = 0, .z = 0 },
    .{ .x = Chunk.Size, .y = 0, .z = 0 },
    .{ .x = 0, .y = 0, .z = Chunk.Size },
    .{ .x = Chunk.Size, .y = 0, .z = Chunk.Size },

    .{ .x = 0, .y = Chunk.Size, .z = 0 },
    .{ .x = 0, .y = Chunk.Size, .z = Chunk.Size },
    .{ .x = Chunk.Size, .y = Chunk.Size, .z = 0 },
    .{ .x = Chunk.Size, .y = Chunk.Size, .z = Chunk.Size },

    .{ .x = 0, .y = Chunk.Size, .z = 0 },
    .{ .x = Chunk.Size, .y = Chunk.Size, .z = 0 },
    .{ .x = 0, .y = Chunk.Size, .z = Chunk.Size },
    .{ .x = Chunk.Size, .y = Chunk.Size, .z = Chunk.Size },

    // vertical
    .{ .x = 0, .y = 0, .z = 0 },
    .{ .x = 0, .y = Chunk.Size, .z = 0 },

    .{ .x = 0, .y = 0, .z = Chunk.Size },
    .{ .x = 0, .y = Chunk.Size, .z = Chunk.Size },

    .{ .x = Chunk.Size, .y = 0, .z = 0 },
    .{ .x = Chunk.Size, .y = Chunk.Size, .z = 0 },

    .{ .x = Chunk.Size, .y = 0, .z = Chunk.Size },
    .{ .x = Chunk.Size, .y = Chunk.Size, .z = Chunk.Size },
};

pub const BOUNDING_BOX_BUFFER: []const Vec3f = west ++ east ++ bottom ++ top ++ north ++ south;

const west: []const Vec3f = &.{
    .{ .x = 0, .y = Chunk.Size, .z = Chunk.Size },
    .{ .x = 0, .y = Chunk.Size, .z = 0 },
    .{ .x = 0, .y = 0, .z = 0 },
    .{ .x = 0, .y = 0, .z = 0 },
    .{ .x = 0, .y = 0, .z = Chunk.Size },
    .{ .x = 0, .y = Chunk.Size, .z = Chunk.Size },
};

const east: []const Vec3f = &.{
    .{ .x = Chunk.Size, .y = 0, .z = 0 },
    .{ .x = Chunk.Size, .y = Chunk.Size, .z = 0 },
    .{ .x = Chunk.Size, .y = Chunk.Size, .z = Chunk.Size },
    .{ .x = Chunk.Size, .y = Chunk.Size, .z = Chunk.Size },
    .{ .x = Chunk.Size, .y = 0, .z = Chunk.Size },
    .{ .x = Chunk.Size, .y = 0, .z = 0 },
};

const bottom: []const Vec3f = &.{
    .{ .x = 0, .y = 0, .z = 0 },
    .{ .x = Chunk.Size, .y = 0, .z = 0 },
    .{ .x = Chunk.Size, .y = 0, .z = Chunk.Size },
    .{ .x = Chunk.Size, .y = 0, .z = Chunk.Size },
    .{ .x = 0, .y = 0, .z = Chunk.Size },
    .{ .x = 0, .y = 0, .z = 0 },
};

const top: []const Vec3f = &.{
    .{ .x = Chunk.Size, .y = Chunk.Size, .z = Chunk.Size },
    .{ .x = Chunk.Size, .y = Chunk.Size, .z = 0 },
    .{ .x = 0, .y = Chunk.Size, .z = 0 },
    .{ .x = 0, .y = Chunk.Size, .z = 0 },
    .{ .x = 0, .y = Chunk.Size, .z = Chunk.Size },
    .{ .x = Chunk.Size, .y = Chunk.Size, .z = Chunk.Size },
};

const north: []const Vec3f = &.{
    .{ .x = 0, .y = 0, .z = 0 },
    .{ .x = 0, .y = Chunk.Size, .z = 0 },
    .{ .x = Chunk.Size, .y = Chunk.Size, .z = 0 },
    .{ .x = Chunk.Size, .y = Chunk.Size, .z = 0 },
    .{ .x = Chunk.Size, .y = 0, .z = 0 },
    .{ .x = 0, .y = 0, .z = 0 },
};

const south: []const Vec3f = &.{
    .{ .x = Chunk.Size, .y = Chunk.Size, .z = Chunk.Size },
    .{ .x = 0, .y = Chunk.Size, .z = Chunk.Size },
    .{ .x = 0, .y = 0, .z = Chunk.Size },
    .{ .x = 0, .y = 0, .z = Chunk.Size },
    .{ .x = Chunk.Size, .y = 0, .z = Chunk.Size },
    .{ .x = Chunk.Size, .y = Chunk.Size, .z = Chunk.Size },
};
