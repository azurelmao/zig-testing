pub const Vertex = packed struct(u32) {
    x: u5,
    y: u5,
    z: u5,
    u: u5,
    v: u5,
    _: u7 = 0,
};

pub const VertexIdxAndTextureIdx = packed struct(u64) {
    vertex_idx: u32,
    texture_idx: u11,
    _: u21 = 0,
};

pub const ModelId = enum {
    square,
};

pub const Model = struct {
    id: ModelId,
    west: []const Vertex,
    east: []const Vertex,
    bottom: []const Vertex,
    top: []const Vertex,
    north: []const Vertex,
    south: []const Vertex,
};

pub const SQUARE = Model{
    .id = .square,

    .west = &.{
        .{ .x = 0, .y = 1, .z = 1, .u = 1, .v = 0 },
        .{ .x = 0, .y = 1, .z = 0, .u = 0, .v = 0 },
        .{ .x = 0, .y = 0, .z = 0, .u = 0, .v = 1 },
        .{ .x = 0, .y = 0, .z = 0, .u = 0, .v = 1 },
        .{ .x = 0, .y = 0, .z = 1, .u = 1, .v = 1 },
        .{ .x = 0, .y = 1, .z = 1, .u = 1, .v = 0 },
    },

    .east = &.{
        .{ .x = 1, .y = 0, .z = 0, .u = 1, .v = 1 },
        .{ .x = 1, .y = 1, .z = 0, .u = 1, .v = 0 },
        .{ .x = 1, .y = 1, .z = 1, .u = 0, .v = 0 },
        .{ .x = 1, .y = 1, .z = 1, .u = 0, .v = 0 },
        .{ .x = 1, .y = 0, .z = 1, .u = 0, .v = 1 },
        .{ .x = 1, .y = 0, .z = 0, .u = 1, .v = 1 },
    },

    .bottom = &.{
        .{ .x = 0, .y = 0, .z = 0, .u = 1, .v = 1 },
        .{ .x = 1, .y = 0, .z = 0, .u = 1, .v = 0 },
        .{ .x = 1, .y = 0, .z = 1, .u = 0, .v = 0 },
        .{ .x = 1, .y = 0, .z = 1, .u = 0, .v = 0 },
        .{ .x = 0, .y = 0, .z = 1, .u = 0, .v = 1 },
        .{ .x = 0, .y = 0, .z = 0, .u = 1, .v = 1 },
    },

    .top = &.{
        .{ .x = 1, .y = 1, .z = 1, .u = 1, .v = 0 },
        .{ .x = 1, .y = 1, .z = 0, .u = 0, .v = 0 },
        .{ .x = 0, .y = 1, .z = 0, .u = 0, .v = 1 },
        .{ .x = 0, .y = 1, .z = 0, .u = 0, .v = 1 },
        .{ .x = 0, .y = 1, .z = 1, .u = 1, .v = 1 },
        .{ .x = 1, .y = 1, .z = 1, .u = 1, .v = 0 },
    },

    .north = &.{
        .{ .x = 0, .y = 0, .z = 0, .u = 1, .v = 1 },
        .{ .x = 0, .y = 1, .z = 0, .u = 1, .v = 0 },
        .{ .x = 1, .y = 1, .z = 0, .u = 0, .v = 0 },
        .{ .x = 1, .y = 1, .z = 0, .u = 0, .v = 0 },
        .{ .x = 1, .y = 0, .z = 0, .u = 0, .v = 1 },
        .{ .x = 0, .y = 0, .z = 0, .u = 1, .v = 1 },
    },

    .south = &.{
        .{ .x = 1, .y = 1, .z = 1, .u = 1, .v = 0 },
        .{ .x = 0, .y = 1, .z = 1, .u = 0, .v = 0 },
        .{ .x = 0, .y = 0, .z = 1, .u = 0, .v = 1 },
        .{ .x = 0, .y = 0, .z = 1, .u = 0, .v = 1 },
        .{ .x = 1, .y = 0, .z = 1, .u = 1, .v = 1 },
        .{ .x = 1, .y = 1, .z = 1, .u = 1, .v = 0 },
    },
};
