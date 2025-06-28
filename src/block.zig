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

    pub fn getModelIndices(self: BlockKind) BlockModel.ModelIndices {
        return BlockModel.BLOCK_KIND_TO_MODEL_INDICES[self.idx()];
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
                .blue = 1,
                .indirect = 1,
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
            else => @compileError(std.fmt.comptimePrint("Block kind \"{s}\" is missing a texture scheme", .{@tagName(self)})),
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

    pub fn append(self: *BlockExtendedDataStore, allocator: std.mem.Allocator, data: BlockExtendedData) !BlockData {
        try self.array.append(allocator, data);
        const index = self.array.items.len - 1;

        return .{ .extended = index };
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
    /// Is an index to the extended data store
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
        block_extended_data_store: *const BlockExtendedDataStore,

        pub fn init(block_extended_data_store: *const BlockExtendedDataStore) Context {
            return .{ .block_extended_data_store = block_extended_data_store };
        }

        pub fn hash(ctx: Context, key: Block) u64 {
            @setEvalBranchQuota(10_000);

            switch (key.kind.blockDataKind()) {
                .none => return std.hash.RapidHash.hash(0, std.mem.asBytes(&key)),
                .extended => {
                    const data = ctx.block_extended_data_store.get(key.data.extended);
                    return std.hash.RapidHash.hash(0, std.mem.asBytes(&.{ key.kind, data }));
                },
                inline else => |tag| {
                    const data = @field(key.data, @tagName(tag));
                    return std.hash.RapidHash.hash(0, std.mem.asBytes(&.{ key.kind, data }));
                },
            }
        }

        pub fn eql(ctx: Context, key1: Block, key2: Block) bool {
            @setEvalBranchQuota(10_000);

            if (key1.kind != key2.kind) return false;

            switch (key1.kind.blockDataKind()) {
                .none => return true,
                .extended => {
                    const data1 = ctx.block_extended_data_store.get(key1.data.extended);
                    const data2 = ctx.block_extended_data_store.get(key2.data.extended);
                    return std.meta.eql(data1, data2);
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

pub const BlockTextureKind = enum {
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

    pub inline fn idx(self: BlockTextureKind) usize {
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

    pub fn getData(comptime self: BlockModelKind) BlockModel {
        return switch (self) {
            .square => .square,
        };
    }

    pub inline fn idx(self: BlockModelKind) usize {
        return @intFromEnum(self);
    }
};

pub const BlockModel = struct {
    faces: [6][]const Vertex,

    pub const Vertex = packed struct(u32) {
        x: u5,
        y: u5,
        z: u5,
        u: u5,
        v: u5,
        _: u7 = 0,
    };

    pub const FaceVertex = packed struct(u64) {
        vertex_idx: u32,
        texture_idx: u11,
        _: u21 = 0,
    };

    pub const VertexIndices = struct {
        faces: [6]u32,
    };

    pub const ModelIndices = struct {
        faces: [6]u11,
    };

    const tmp = expr: {
        const block_models = std.enums.values(BlockModelKind);
        const block_kinds = std.enums.values(BlockKind);

        var model_kind_to_vertex_indices: [block_models.len]VertexIndices = undefined;
        var block_kind_to_model_indices: [block_kinds.len]ModelIndices = undefined;
        var vertex_buffer: []const BlockModel.Vertex = &.{};
        var face_buffer: []const BlockModel.FaceVertex = &.{};

        for (block_models) |model| {
            const model_data = model.getData();

            var vertex_indices: VertexIndices = undefined;

            for (0..6) |face_idx| {
                vertex_indices.faces[face_idx] = @intCast(vertex_buffer.len);
                vertex_buffer = vertex_buffer ++ model_data.faces[face_idx];
            }

            model_kind_to_vertex_indices[model.idx()] = vertex_indices;
        }

        for (block_kinds) |block_kind| {
            const model = block_kind.getModel() orelse continue;
            const texture_scheme = block_kind.getTextureScheme();

            var model_indices: ModelIndices = undefined;

            for (0..6) |face_idx| {
                const face_vertex = BlockModel.FaceVertex{
                    .vertex_idx = model_kind_to_vertex_indices[model.idx()].faces[face_idx],
                    .texture_idx = texture_scheme.faces[face_idx].idx(),
                };

                model_indices.faces[face_idx] = @intCast(face_buffer.len);
                face_buffer = face_buffer ++ &[1]BlockModel.FaceVertex{face_vertex};
            }

            block_kind_to_model_indices[block_kind.idx()] = model_indices;
        }

        break :expr .{
            .vertex_buffer = vertex_buffer,
            .face_buffer = face_buffer,
            .block_kind_to_model_indices = block_kind_to_model_indices,
        };
    };

    pub const VERTEX_BUFFER = tmp.vertex_buffer;
    pub const FACE_BUFFER = tmp.face_buffer;
    const BLOCK_KIND_TO_MODEL_INDICES = tmp.block_kind_to_model_indices;

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
        var faces: [6][]const Vertex = undefined;

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
