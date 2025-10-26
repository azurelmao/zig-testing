const std = @import("std");
const Side = @import("side.zig").Side;
const Light = @import("light.zig").Light;
const Vec3f = @import("vec3f.zig").Vec3f;

pub const BlockKind = enum {
    air,
    stone,
    grass,
    bedrock,
    sand,
    bricks,
    water,
    lava,
    ice,
    glass_tinted,
    glass,
    chest,
    redstone_lamp,

    pub inline fn idx(self: BlockKind) usize {
        return @intFromEnum(self);
    }

    pub fn blockDataKind(self: BlockKind) BlockDataKind {
        return switch (self) {
            .chest => .extended,
            .redstone_lamp => .redstone_lamp,
            else => .none,
        };
    }

    pub fn getModelIdx(self: BlockKind) BlockModel.Index {
        return BlockModel.BLOCK_KIND_TO_MODEL_IDX[self.idx()];
    }

    pub fn isInteractable(self: BlockKind) bool {
        return switch (self) {
            .air, .water, .lava => false,
            else => true,
        };
    }

    pub fn isNotSolid(self: BlockKind) bool {
        return switch (self) {
            .air, .water, .ice, .glass, .glass_tinted => true,
            else => false,
        };
    }

    pub fn getLayer(self: BlockKind) BlockLayer {
        return switch (self) {
            .water => .water,
            .ice => .ice,
            .glass_tinted => .glass_stained,
            .glass => .glass,
            else => .solid,
        };
    }

    pub const LightOpacityKind = enum {
        @"opaque",
        translucent,
    };

    pub const LightOpacity = union(LightOpacityKind) {
        @"opaque",
        translucent: Light,
    };

    pub fn getLightOpacity(self: BlockKind) LightOpacity {
        return switch (self) {
            .air, .glass => .{ .translucent = .{
                .red = 0,
                .green = 0,
                .blue = 0,
                .indirect = 0,
            } },

            .water, .ice => .{ .translucent = .{
                .red = 1,
                .green = 1,
                .blue = 0,
                .indirect = 0,
            } },

            .glass_tinted => .{ .translucent = .{
                .red = 3,
                .green = 3,
                .blue = 3,
                .indirect = 3,
            } },

            else => .{ .@"opaque" = {} },
        };
    }

    pub fn getTextureScheme(self: BlockKind) BlockTextureScheme {
        return switch (self) {
            .stone => .allSides(.stone),
            .grass => .grass(.grass_top, .dirt, .grass_side),
            .bedrock => .allSides(.bedrock),
            .sand => .allSides(.sand),
            .bricks => .allSides(.bricks),
            .water => .allSides(.water),
            .lava => .allSides(.lava),
            .ice => .allSides(.ice),
            .glass_tinted => .allSides(.glass_tinted),
            .glass => .allSides(.glass),
            .chest => .allSides(.chest),
            .redstone_lamp => .allSides(.redstone_lamp_active),
            else => std.debug.panic("Block kind \"{s}\" is missing a texture scheme", .{@tagName(self)}),
        };
    }

    pub fn getModel(self: BlockKind) ?BlockModelKind {
        return switch (self) {
            .air => null,
            else => .square,
        };
    }
};

const ChestBlockData = struct {
    items: [9]u8,
};

const BlockExtendedDataKind = enum {
    chest,
};

pub const BlockExtendedData = union(BlockExtendedDataKind) {
    chest: ChestBlockData,

    pub fn initChest(items: [9]u8) BlockExtendedData {
        return .{ .chest = .{ .items = items } };
    }
};

pub const BlockExtendedDataStore = struct {
    array: std.ArrayListUnmanaged(BlockExtendedData),

    pub const empty = BlockExtendedDataStore{
        .array = .empty,
    };

    pub fn append(self: *BlockExtendedDataStore, allocator: std.mem.Allocator, data: BlockExtendedData) !usize {
        try self.array.append(allocator, data);
        const index = self.array.items.len - 1;

        return index;
    }

    pub fn get(self: BlockExtendedDataStore, index: usize) BlockExtendedData {
        return self.array.items[index];
    }
};

const BlockDataKind = enum {
    none,
    extended,
    redstone_lamp,
};

pub const BlockData = packed union {
    none: void,
    /// Index to the extended data store
    extended: usize,
    redstone_lamp: RedstoneLampData,

    pub fn initRedstoneLamp(powered: bool) BlockData {
        return .{ .redstone_lamp = powered };
    }
};

const RedstoneLampData = packed struct {
    powered: bool,
};

pub const Block = struct {
    kind: BlockKind,
    data: BlockData,

    pub fn init(kind: BlockKind, data: BlockData) Block {
        return .{ .kind = kind, .data = data };
    }

    pub fn initNone(kind: BlockKind) Block {
        return .{ .kind = kind, .data = .{ .none = {} } };
    }

    pub fn initExtended(kind: BlockKind, index_to_extended_data: usize) Block {
        return .{ .kind = kind, .data = .{ .extended = index_to_extended_data } };
    }

    pub const Context = struct {
        pub fn hash(ctx: Context, key: Block) u64 {
            _ = ctx;
            @setEvalBranchQuota(10_000);

            var hasher: std.hash.Wyhash = .init(0);

            switch (key.kind.blockDataKind()) {
                .none => {
                    hasher.update(std.mem.asBytes(&BlockDataKind.none));
                    hasher.update(std.mem.asBytes(&key.kind));
                },
                .extended => {
                    hasher.update(std.mem.asBytes(&BlockDataKind.extended));
                    hasher.update(std.mem.asBytes(&key.kind));
                    hasher.update(std.mem.asBytes(&key.data.extended));
                },
                inline else => |tag| {
                    hasher.update(std.mem.asBytes(&tag));
                    hasher.update(std.mem.asBytes(&key.kind));

                    const data = @field(key.data, @tagName(tag));
                    hasher.update(std.mem.asBytes(&data));
                },
            }

            return hasher.final();
        }

        pub fn eql(ctx: Context, key1: Block, key2: Block) bool {
            _ = ctx;
            @setEvalBranchQuota(10_000);

            if (key1.kind != key2.kind) return false;

            switch (key1.kind.blockDataKind()) {
                .none => return true,
                .extended => {
                    const data1 = key1.data.extended;
                    const data2 = key2.data.extended;
                    return data1 == data2;
                },
                inline else => |tag| {
                    const data1 = @field(key1.data, @tagName(tag));
                    const data2 = @field(key2.data, @tagName(tag));
                    return std.meta.eql(data1, data2);
                },
            }
        }
    };
};

pub const BlockLayer = enum {
    solid,
    water,
    ice,
    glass_stained,
    glass,

    pub const len = std.enums.values(BlockLayer).len;

    pub inline fn idx(self: BlockLayer) usize {
        return @intFromEnum(self);
    }
};

pub const BlockTextureKind = enum(u11) {
    stone,
    grass_top,
    grass_side,
    dirt,
    bedrock,
    sand,
    bricks,
    water,
    lava,
    ice,
    glass,
    glass_tinted,
    chest,
    redstone_lamp_active,
    redstone_lamp_inactive,

    pub inline fn idx(self: BlockTextureKind) u11 {
        return @intFromEnum(self);
    }
};

pub const BlockTextureScheme = struct {
    faces: [6]BlockTextureKind,

    pub fn allSides(texture_index: BlockTextureKind) BlockTextureScheme {
        return .{ .faces = @splat(texture_index) };
    }

    pub fn grass(top: BlockTextureKind, bottom: BlockTextureKind, sides: BlockTextureKind) BlockTextureScheme {
        var faces: [6]BlockTextureKind = @splat(sides);

        faces[Side.top.idx()] = top;
        faces[Side.bottom.idx()] = bottom;

        return .{ .faces = faces };
    }
};

pub const BlockModelKind = enum {
    square,

    pub fn getModel(comptime self: BlockModelKind) BlockModel {
        return switch (self) {
            .square => .square,
        };
    }

    pub inline fn idx(self: BlockModelKind) usize {
        return @intFromEnum(self);
    }
};

pub const BlockModel = struct {
    faces: [6][]const PerVertexData,

    pub const PerVertexData = packed struct(u32) {
        x: u5,
        y: u5,
        z: u5,
        u: u5,
        v: u5,
        _: u7 = 0,
    };

    const Index = u17;

    const tmp = expr: {
        const block_model_kinds = std.enums.values(BlockModelKind);
        const block_kinds = std.enums.values(BlockKind);

        var per_vertex_buffer: []const PerVertexData = &.{};
        var block_model_kind_to_model_idx: [block_model_kinds.len]Index = undefined;

        for (block_model_kinds) |block_model_kind| {
            const block_model = block_model_kind.getModel();
            const model_idx = per_vertex_buffer.len;

            for (block_model.faces) |block_model_face| {
                per_vertex_buffer = per_vertex_buffer ++ block_model_face;
            }

            block_model_kind_to_model_idx[block_model_kind.idx()] = model_idx;
        }

        var block_kind_to_model_idx: [block_kinds.len]Index = undefined;

        for (block_kinds) |block_kind| if (block_kind.getModel()) |block_model_kind| {
            block_kind_to_model_idx[block_kind.idx()] = block_model_kind_to_model_idx[block_model_kind.idx()];
        };

        break :expr .{
            .per_vertex_buffer = per_vertex_buffer,
            .block_kind_to_model_idx = block_kind_to_model_idx,
        };
    };

    pub const PER_VERTEX_BUFFER = tmp.per_vertex_buffer;
    const BLOCK_KIND_TO_MODEL_IDX = tmp.block_kind_to_model_idx;

    pub const BOUNDING_BOX_LINES_BUFFER: []const Vec3f = &.{
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 0, .y = 0, .z = 1 },
        .{ .x = 1, .y = 0, .z = 0 },
        .{ .x = 1, .y = 0, .z = 1 },

        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 1, .y = 0, .z = 0 },
        .{ .x = 0, .y = 0, .z = 1 },
        .{ .x = 1, .y = 0, .z = 1 },

        .{ .x = 0, .y = 1, .z = 0 },
        .{ .x = 0, .y = 1, .z = 1 },
        .{ .x = 1, .y = 1, .z = 0 },
        .{ .x = 1, .y = 1, .z = 1 },

        .{ .x = 0, .y = 1, .z = 0 },
        .{ .x = 1, .y = 1, .z = 0 },
        .{ .x = 0, .y = 1, .z = 1 },
        .{ .x = 1, .y = 1, .z = 1 },

        // vertical
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 0, .y = 1, .z = 0 },

        .{ .x = 0, .y = 0, .z = 1 },
        .{ .x = 0, .y = 1, .z = 1 },

        .{ .x = 1, .y = 0, .z = 0 },
        .{ .x = 1, .y = 1, .z = 0 },

        .{ .x = 1, .y = 0, .z = 1 },
        .{ .x = 1, .y = 1, .z = 1 },
    };

    const square = expr: {
        var faces: [6][]const PerVertexData = undefined;

        faces[Side.west.idx()] = &.{
            .{ .x = 0, .y = 1, .z = 1, .u = 1, .v = 0 },
            .{ .x = 0, .y = 1, .z = 0, .u = 0, .v = 0 },
            .{ .x = 0, .y = 0, .z = 0, .u = 0, .v = 1 },
            .{ .x = 0, .y = 0, .z = 0, .u = 0, .v = 1 },
            .{ .x = 0, .y = 0, .z = 1, .u = 1, .v = 1 },
            .{ .x = 0, .y = 1, .z = 1, .u = 1, .v = 0 },
        };

        faces[Side.east.idx()] = &.{
            .{ .x = 1, .y = 0, .z = 0, .u = 1, .v = 1 },
            .{ .x = 1, .y = 1, .z = 0, .u = 1, .v = 0 },
            .{ .x = 1, .y = 1, .z = 1, .u = 0, .v = 0 },
            .{ .x = 1, .y = 1, .z = 1, .u = 0, .v = 0 },
            .{ .x = 1, .y = 0, .z = 1, .u = 0, .v = 1 },
            .{ .x = 1, .y = 0, .z = 0, .u = 1, .v = 1 },
        };

        faces[Side.bottom.idx()] = &.{
            .{ .x = 0, .y = 0, .z = 0, .u = 1, .v = 1 },
            .{ .x = 1, .y = 0, .z = 0, .u = 1, .v = 0 },
            .{ .x = 1, .y = 0, .z = 1, .u = 0, .v = 0 },
            .{ .x = 1, .y = 0, .z = 1, .u = 0, .v = 0 },
            .{ .x = 0, .y = 0, .z = 1, .u = 0, .v = 1 },
            .{ .x = 0, .y = 0, .z = 0, .u = 1, .v = 1 },
        };

        faces[Side.top.idx()] = &.{
            .{ .x = 1, .y = 1, .z = 1, .u = 1, .v = 0 },
            .{ .x = 1, .y = 1, .z = 0, .u = 0, .v = 0 },
            .{ .x = 0, .y = 1, .z = 0, .u = 0, .v = 1 },
            .{ .x = 0, .y = 1, .z = 0, .u = 0, .v = 1 },
            .{ .x = 0, .y = 1, .z = 1, .u = 1, .v = 1 },
            .{ .x = 1, .y = 1, .z = 1, .u = 1, .v = 0 },
        };

        faces[Side.north.idx()] = &.{
            .{ .x = 0, .y = 0, .z = 0, .u = 1, .v = 1 },
            .{ .x = 0, .y = 1, .z = 0, .u = 1, .v = 0 },
            .{ .x = 1, .y = 1, .z = 0, .u = 0, .v = 0 },
            .{ .x = 1, .y = 1, .z = 0, .u = 0, .v = 0 },
            .{ .x = 1, .y = 0, .z = 0, .u = 0, .v = 1 },
            .{ .x = 0, .y = 0, .z = 0, .u = 1, .v = 1 },
        };

        faces[Side.south.idx()] = &.{
            .{ .x = 1, .y = 1, .z = 1, .u = 1, .v = 0 },
            .{ .x = 0, .y = 1, .z = 1, .u = 0, .v = 0 },
            .{ .x = 0, .y = 0, .z = 1, .u = 0, .v = 1 },
            .{ .x = 0, .y = 0, .z = 1, .u = 0, .v = 1 },
            .{ .x = 1, .y = 0, .z = 1, .u = 1, .v = 1 },
            .{ .x = 1, .y = 1, .z = 1, .u = 1, .v = 0 },
        };

        break :expr BlockModel{ .faces = faces };
    };
};
