const std = @import("std");
const Dir = @import("dir.zig").Dir;
const RaycastDir = @import("World.zig").RaycastDir;
const Light = @import("light.zig").Light;
const Vec3f = @import("vec3f.zig").Vec3f;
const World = @import("World.zig");

pub const BlockKind = enum(u16) {
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
    lamp,
    torch,

    pub inline fn idx(self: BlockKind) usize {
        return @intFromEnum(self);
    }

    pub fn blockDataKind(self: BlockKind) BlockDataKind {
        return switch (self) {
            .chest => .extended,
            .lamp => .lamp,
            else => .none,
        };
    }

    /// Meshing related flags
    const MeshFlags = packed struct {
        makes_neighbor_blocks_emit_mesh: bool,
        makes_same_kind_neighbor_blocks_emit_mesh: bool,
    };

    pub fn getMeshFlags(self: BlockKind) MeshFlags {
        return switch (self) {
            .air, .water, .ice, .glass, .glass_tinted => .{
                .makes_neighbor_blocks_emit_mesh = true,
                .makes_same_kind_neighbor_blocks_emit_mesh = false,
            },
            .torch => .{
                .makes_neighbor_blocks_emit_mesh = true,
                .makes_same_kind_neighbor_blocks_emit_mesh = true,
            },
            else => .{
                .makes_neighbor_blocks_emit_mesh = false,
                .makes_same_kind_neighbor_blocks_emit_mesh = false,
            },
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
            .air, .glass, .torch => .{ .translucent = .{
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
            .grass => .grass(.dirt, .grass_top, .grass_side),
            .bedrock => .allSides(.bedrock),
            .sand => .allSides(.sand),
            .bricks => .allSides(.bricks),
            .water => .allSides(.water),
            .lava => .allSides(.lava),
            .ice => .allSides(.ice),
            .glass_tinted => .allSides(.glass_tinted),
            .glass => .allSides(.glass),
            .chest => .allSides(.chest),
            .lamp => .allSides(.lamp),
            .torch => .torch(.torch),
            else => std.debug.panic("Block kind \"{s}\" is missing a texture scheme", .{@tagName(self)}),
        };
    }

    pub fn getModelScheme(self: BlockKind) ?BlockModelScheme {
        return switch (self) {
            .air => null,
            .torch => .torch,
            else => .cube,
        };
    }

    pub inline fn getModel(self: BlockKind) *const BlockModel {
        return &BlockModel.BLOCK_KIND_TO_BLOCK_MODEL.get(self);
    }

    pub fn getVolume(self: BlockKind) BlockVolume {
        return switch (self) {
            .air, .water, .lava => .none,
            .torch => .{ .detailed = &.torch },
            else => .full,
        };
    }

    pub fn getVolumeIndexAndLen(self: BlockKind) BlockVolumeScheme.IndexAndLen {
        return BlockVolumeScheme.BLOCK_KIND_TO_BLOCK_VOLUME_INDEX_AND_LEN.get(self);
    }
};

const ChestBlockData = struct {
    items: [9]u8,
};

pub const BlockExtendedData = union(enum) {
    chest: ChestBlockData,

    pub fn initChest(items: [9]u8) BlockExtendedData {
        return .{ .chest = .{ .items = items } };
    }
};

const BlockDataKind = enum {
    none,
    extended,
    lamp,
};

pub const BlockData = packed union {
    none: void,
    /// Index to the extended data store
    extended: u48,
    lamp: LampData,

    comptime {
        std.debug.assert(@bitSizeOf(BlockData) == 48);
    }
};

const LampData = packed struct(u16) {
    light: Light,
};

pub const Block = packed struct(u64) {
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

    pub const values = std.enums.values(BlockLayer);
    pub const len = values.len;

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
    lamp,
    torch,

    pub inline fn idx(self: BlockTextureKind) u11 {
        return @intFromEnum(self);
    }
};

pub const BlockVolume = union(enum) {
    none,
    full,
    detailed: *const BlockVolumeScheme,
};

pub const BlockVolumeScheme = struct {
    cuboids: []const Cuboid,

    const torch: BlockVolumeScheme = expr: {
        var scheme: BlockVolumeScheme = .empty;
        scheme.addCuboid(.{ .x = 7, .y = 0, .z = 7 }, .{ .x = 9, .y = 11, .z = 9 });
        break :expr scheme;
    };

    pub const IndexAndLen = struct {
        index: usize,
        len: usize,
    };

    const tmp = expr: {
        @setEvalBranchQuota(10_000);

        const block_kinds = std.enums.values(BlockKind);
        var block_volume_buffer: []const Vec3f = &.{};
        var block_kind_to_block_volume_index_and_len: std.EnumArray(BlockKind, IndexAndLen) = .initUndefined();

        block_volume_buffer = block_volume_buffer ++ emitLines(.{ .x = 0, .y = 0, .z = 0 }, .{ .x = 16, .y = 16, .z = 16 });
        const full_len = block_volume_buffer.len;

        for (block_kinds) |block_kind| {
            const index_and_len: BlockVolumeScheme.IndexAndLen = switch (block_kind.getVolume()) {
                .none => continue,
                .full => .{ .index = 0, .len = full_len },
                .detailed => |block_volume_scheme| expr2: {
                    const index = block_volume_buffer.len;

                    for (block_volume_scheme.cuboids) |cuboid| {
                        block_volume_buffer = block_volume_buffer ++ emitLines(cuboid.min, cuboid.max);
                    }

                    const len = block_volume_buffer.len - index;

                    break :expr2 .{ .index = index, .len = len };
                },
            };

            block_kind_to_block_volume_index_and_len.set(block_kind, index_and_len);
        }

        break :expr .{
            .block_volume_buffer = block_volume_buffer,
            .block_kind_to_block_volume_index_and_len = block_kind_to_block_volume_index_and_len,
            .full_len = full_len,
        };
    };

    pub const BLOCK_VOLUME_BUFFER = tmp.block_volume_buffer;
    const BLOCK_KIND_TO_BLOCK_VOLUME_INDEX_AND_LEN = tmp.block_kind_to_block_volume_index_and_len;
    pub const FULL_LEN = tmp.full_len;

    const empty: BlockVolumeScheme = .{
        .cuboids = &.{},
    };

    fn addCuboid(self: *BlockVolumeScheme, min: Vec3u5, max: Vec3u5) void {
        const cuboid: Cuboid = .{ .min = min, .max = max };
        self.cuboids = self.cuboids ++ .{cuboid};
    }

    fn emitLines(min: Vec3u5, max: Vec3u5) []const Vec3f {
        const min_f: Vec3f = .{
            .x = @as(f32, @floatFromInt(min.x)) / 16.0,
            .y = @as(f32, @floatFromInt(min.y)) / 16.0,
            .z = @as(f32, @floatFromInt(min.z)) / 16.0,
        };

        const max_f: Vec3f = .{
            .x = @as(f32, @floatFromInt(max.x)) / 16.0,
            .y = @as(f32, @floatFromInt(max.y)) / 16.0,
            .z = @as(f32, @floatFromInt(max.z)) / 16.0,
        };

        return &.{
            .{ .x = min_f.x, .y = min_f.y, .z = min_f.z },
            .{ .x = min_f.x, .y = min_f.y, .z = max_f.z },
            .{ .x = max_f.x, .y = min_f.y, .z = min_f.z },
            .{ .x = max_f.x, .y = min_f.y, .z = max_f.z },

            .{ .x = min_f.x, .y = min_f.y, .z = min_f.z },
            .{ .x = max_f.x, .y = min_f.y, .z = min_f.z },
            .{ .x = min_f.x, .y = min_f.y, .z = max_f.z },
            .{ .x = max_f.x, .y = min_f.y, .z = max_f.z },

            .{ .x = min_f.x, .y = max_f.y, .z = min_f.z },
            .{ .x = min_f.x, .y = max_f.y, .z = max_f.z },
            .{ .x = max_f.x, .y = max_f.y, .z = min_f.z },
            .{ .x = max_f.x, .y = max_f.y, .z = max_f.z },

            .{ .x = min_f.x, .y = max_f.y, .z = min_f.z },
            .{ .x = max_f.x, .y = max_f.y, .z = min_f.z },
            .{ .x = min_f.x, .y = max_f.y, .z = max_f.z },
            .{ .x = max_f.x, .y = max_f.y, .z = max_f.z },

            // vertical
            .{ .x = min_f.x, .y = min_f.y, .z = min_f.z },
            .{ .x = min_f.x, .y = max_f.y, .z = min_f.z },

            .{ .x = min_f.x, .y = min_f.y, .z = max_f.z },
            .{ .x = min_f.x, .y = max_f.y, .z = max_f.z },

            .{ .x = max_f.x, .y = min_f.y, .z = min_f.z },
            .{ .x = max_f.x, .y = max_f.y, .z = min_f.z },

            .{ .x = max_f.x, .y = min_f.y, .z = max_f.z },
            .{ .x = max_f.x, .y = max_f.y, .z = max_f.z },
        };
    }

    pub fn intersect(self: *const BlockVolumeScheme, block_pos: Vec3f, origin: Vec3f, direction: Vec3f) RaycastDir {
        for (self.cuboids) |cuboid| {
            const min: Vec3f = .{
                .x = @as(f32, @floatFromInt(cuboid.min.x)) / 16.0 + block_pos.x,
                .y = @as(f32, @floatFromInt(cuboid.min.y)) / 16.0 + block_pos.y,
                .z = @as(f32, @floatFromInt(cuboid.min.z)) / 16.0 + block_pos.z,
            };

            const max: Vec3f = .{
                .x = @as(f32, @floatFromInt(cuboid.max.x)) / 16.0 + block_pos.x,
                .y = @as(f32, @floatFromInt(cuboid.max.y)) / 16.0 + block_pos.y,
                .z = @as(f32, @floatFromInt(cuboid.max.z)) / 16.0 + block_pos.z,
            };

            const t1 = (min.x - origin.x) / direction.x;
            const t2 = (max.x - origin.x) / direction.x;
            const t3 = (min.y - origin.y) / direction.y;
            const t4 = (max.y - origin.y) / direction.y;
            const t5 = (min.z - origin.z) / direction.z;
            const t6 = (max.z - origin.z) / direction.z;

            const min_time = @max(@min(t1, t2), @min(t3, t4), @min(t5, t6));
            const max_time = @min(@max(t1, t2), @max(t3, t4), @max(t5, t6));

            if (max_time < 0.001 or min_time > max_time) continue;

            const hit_time = if (min_time < 0.001) max_time else min_time;

            var dir: RaycastDir = .out_of_bounds;
            if (@abs(hit_time - t1) < 0.01) {
                dir = .west;
            } else if (@abs(hit_time - t2) < 0.01) {
                dir = .east;
            } else if (@abs(hit_time - t3) < 0.01) {
                dir = .bottom;
            } else if (@abs(hit_time - t4) < 0.01) {
                dir = .top;
            } else if (@abs(hit_time - t5) < 0.01) {
                dir = .north;
            } else if (@abs(hit_time - t6) < 0.01) {
                dir = .south;
            }

            return dir;
        }

        return .out_of_bounds;
    }

    pub const Vec3u5 = struct {
        x: u5,
        y: u5,
        z: u5,
    };

    const Cuboid = struct {
        min: Vec3u5,
        max: Vec3u5,
    };
};

pub const BlockTextureScheme = struct {
    faces: std.EnumArray(Dir, []const TextureFace),

    const empty: BlockTextureScheme = .{
        .faces = .initFill(&.{}),
    };

    fn addFace(self: *BlockTextureScheme, dir: Dir, face: TextureFace) void {
        self.faces.set(dir, self.faces.get(dir) ++ .{face});
    }

    pub fn allSides(texture: BlockTextureKind) BlockTextureScheme {
        var scheme: BlockTextureScheme = .empty;

        scheme.addFace(.west, .emitWest(.{ .u = 0, .v = 0 }, .{ .u = 16, .v = 16 }, texture));
        scheme.addFace(.east, .emitEast(.{ .u = 0, .v = 0 }, .{ .u = 16, .v = 16 }, texture));
        scheme.addFace(.bottom, .emitBottom(.{ .u = 0, .v = 0 }, .{ .u = 16, .v = 16 }, texture));
        scheme.addFace(.top, .emitTop(.{ .u = 0, .v = 0 }, .{ .u = 16, .v = 16 }, texture));
        scheme.addFace(.north, .emitNorth(.{ .u = 0, .v = 0 }, .{ .u = 16, .v = 16 }, texture));
        scheme.addFace(.south, .emitSouth(.{ .u = 0, .v = 0 }, .{ .u = 16, .v = 16 }, texture));

        return scheme;
    }

    pub fn grass(bottom: BlockTextureKind, top: BlockTextureKind, sides: BlockTextureKind) BlockTextureScheme {
        var scheme: BlockTextureScheme = .empty;

        scheme.addFace(.west, .emitWest(.{ .u = 0, .v = 0 }, .{ .u = 16, .v = 16 }, sides));
        scheme.addFace(.east, .emitEast(.{ .u = 0, .v = 0 }, .{ .u = 16, .v = 16 }, sides));
        scheme.addFace(.bottom, .emitBottom(.{ .u = 0, .v = 0 }, .{ .u = 16, .v = 16 }, bottom));
        scheme.addFace(.top, .emitTop(.{ .u = 0, .v = 0 }, .{ .u = 16, .v = 16 }, top));
        scheme.addFace(.north, .emitNorth(.{ .u = 0, .v = 0 }, .{ .u = 16, .v = 16 }, sides));
        scheme.addFace(.south, .emitSouth(.{ .u = 0, .v = 0 }, .{ .u = 16, .v = 16 }, sides));

        return scheme;
    }

    pub fn torch(texture: BlockTextureKind) BlockTextureScheme {
        var scheme: BlockTextureScheme = .empty;

        scheme.addFace(.west, .emitWest(.{ .u = 7, .v = 6 }, .{ .u = 9, .v = 16 }, texture));
        scheme.addFace(.east, .emitEast(.{ .u = 7, .v = 6 }, .{ .u = 9, .v = 16 }, texture));
        scheme.addFace(.bottom, .emitBottom(.{ .u = 7, .v = 14 }, .{ .u = 9, .v = 16 }, texture));
        scheme.addFace(.top, .emitTop(.{ .u = 7, .v = 6 }, .{ .u = 9, .v = 8 }, texture));
        scheme.addFace(.north, .emitNorth(.{ .u = 7, .v = 6 }, .{ .u = 9, .v = 16 }, texture));
        scheme.addFace(.south, .emitSouth(.{ .u = 7, .v = 6 }, .{ .u = 9, .v = 16 }, texture));

        return scheme;
    }

    const Vec2u5 = struct {
        u: u5,
        v: u5,
    };

    const TextureFace = struct {
        vertices: [6]Data,
        texture_idx: BlockTextureKind,

        const Data = struct {
            u: u5,
            v: u5,
        };

        pub fn emitWest(min: Vec2u5, max: Vec2u5, texture_idx: BlockTextureKind) TextureFace {
            return .{
                .vertices = .{
                    .{ .u = max.u, .v = min.v },
                    .{ .u = min.u, .v = min.v },
                    .{ .u = min.u, .v = max.v },
                    .{ .u = min.u, .v = max.v },
                    .{ .u = max.u, .v = max.v },
                    .{ .u = max.u, .v = min.v },
                },
                .texture_idx = texture_idx,
            };
        }

        pub fn emitEast(min: Vec2u5, max: Vec2u5, texture_idx: BlockTextureKind) TextureFace {
            return .{
                .vertices = .{
                    .{ .u = max.u, .v = max.v },
                    .{ .u = max.u, .v = min.v },
                    .{ .u = min.u, .v = min.v },
                    .{ .u = min.u, .v = min.v },
                    .{ .u = min.u, .v = max.v },
                    .{ .u = max.u, .v = max.v },
                },
                .texture_idx = texture_idx,
            };
        }

        pub fn emitBottom(min: Vec2u5, max: Vec2u5, texture_idx: BlockTextureKind) TextureFace {
            return .{
                .vertices = .{
                    .{ .u = max.u, .v = max.v },
                    .{ .u = max.u, .v = min.v },
                    .{ .u = min.u, .v = min.v },
                    .{ .u = min.u, .v = min.v },
                    .{ .u = min.u, .v = max.v },
                    .{ .u = max.u, .v = max.v },
                },
                .texture_idx = texture_idx,
            };
        }

        pub fn emitTop(min: Vec2u5, max: Vec2u5, texture_idx: BlockTextureKind) TextureFace {
            return .{
                .vertices = .{
                    .{ .u = max.u, .v = min.v },
                    .{ .u = min.u, .v = min.v },
                    .{ .u = min.u, .v = max.v },
                    .{ .u = min.u, .v = max.v },
                    .{ .u = max.u, .v = max.v },
                    .{ .u = max.u, .v = min.v },
                },
                .texture_idx = texture_idx,
            };
        }

        pub fn emitNorth(min: Vec2u5, max: Vec2u5, texture_idx: BlockTextureKind) TextureFace {
            return .{
                .vertices = .{
                    .{ .u = max.u, .v = max.v },
                    .{ .u = max.u, .v = min.v },
                    .{ .u = min.u, .v = min.v },
                    .{ .u = min.u, .v = min.v },
                    .{ .u = min.u, .v = max.v },
                    .{ .u = max.u, .v = max.v },
                },
                .texture_idx = texture_idx,
            };
        }

        pub fn emitSouth(min: Vec2u5, max: Vec2u5, texture_idx: BlockTextureKind) TextureFace {
            return .{
                .vertices = .{
                    .{ .u = max.u, .v = min.v },
                    .{ .u = min.u, .v = min.v },
                    .{ .u = min.u, .v = max.v },
                    .{ .u = min.u, .v = max.v },
                    .{ .u = max.u, .v = max.v },
                    .{ .u = max.u, .v = min.v },
                },
                .texture_idx = texture_idx,
            };
        }
    };
};

pub const BlockModelScheme = struct {
    faces: std.EnumArray(Dir, []const ModelFace),

    const cube: BlockModelScheme = expr: {
        var scheme: BlockModelScheme = .empty;
        scheme.addCuboid(.{ .x = 0, .y = 0, .z = 0 }, .{ .x = 16, .y = 16, .z = 16 });
        break :expr scheme;
    };

    const torch: BlockModelScheme = expr: {
        var scheme: BlockModelScheme = .empty;
        scheme.addCuboid(.{ .x = 7, .y = 0, .z = 7 }, .{ .x = 9, .y = 11, .z = 9 });
        break :expr scheme;
    };

    const empty: BlockModelScheme = .{
        .faces = .initFill(&.{}),
    };

    fn addFace(self: *BlockModelScheme, dir: Dir, face: ModelFace) void {
        self.faces.set(dir, self.faces.get(dir) ++ .{face});
    }

    const Vec3u5 = struct {
        x: u5,
        y: u5,
        z: u5,
    };

    const Vec2u5 = struct {
        min: u5,
        max: u5,
    };

    fn addCuboid(self: *BlockModelScheme, min: Vec3u5, max: Vec3u5) void {
        self.addFace(.west, .emitWest(
            min.x,
            .{ .min = min.y, .max = max.y },
            .{ .min = min.z, .max = max.z },
        ));

        self.addFace(.east, .emitEast(
            max.x,
            .{ .min = min.y, .max = max.y },
            .{ .min = min.z, .max = max.z },
        ));

        self.addFace(.bottom, .emitBottom(
            min.y,
            .{ .min = min.x, .max = max.z },
            .{ .min = min.z, .max = max.z },
        ));

        self.addFace(.top, .emitTop(
            max.y,
            .{ .min = min.x, .max = max.z },
            .{ .min = min.z, .max = max.z },
        ));

        self.addFace(.north, .emitNorth(
            min.z,
            .{ .min = min.x, .max = max.z },
            .{ .min = min.y, .max = max.y },
        ));

        self.addFace(.south, .emitSouth(
            max.z,
            .{ .min = min.x, .max = max.z },
            .{ .min = min.y, .max = max.y },
        ));
    }

    const ModelFace = struct {
        vertices: [6]Data,

        const Data = struct {
            x: u5,
            y: u5,
            z: u5,
        };

        fn emitWest(x: u5, y: Vec2u5, z: Vec2u5) ModelFace {
            return .{
                .vertices = .{
                    .{ .x = x, .y = y.max, .z = z.max },
                    .{ .x = x, .y = y.max, .z = z.min },
                    .{ .x = x, .y = y.min, .z = z.min },
                    .{ .x = x, .y = y.min, .z = z.min },
                    .{ .x = x, .y = y.min, .z = z.max },
                    .{ .x = x, .y = y.max, .z = z.max },
                },
            };
        }

        fn emitEast(x: u5, y: Vec2u5, z: Vec2u5) ModelFace {
            return .{
                .vertices = .{
                    .{ .x = x, .y = y.min, .z = z.min },
                    .{ .x = x, .y = y.max, .z = z.min },
                    .{ .x = x, .y = y.max, .z = z.max },
                    .{ .x = x, .y = y.max, .z = z.max },
                    .{ .x = x, .y = y.min, .z = z.max },
                    .{ .x = x, .y = y.min, .z = z.min },
                },
            };
        }

        fn emitBottom(y: u5, x: Vec2u5, z: Vec2u5) ModelFace {
            return .{
                .vertices = .{
                    .{ .x = x.min, .y = y, .z = z.min },
                    .{ .x = x.max, .y = y, .z = z.min },
                    .{ .x = x.max, .y = y, .z = z.max },
                    .{ .x = x.max, .y = y, .z = z.max },
                    .{ .x = x.min, .y = y, .z = z.max },
                    .{ .x = x.min, .y = y, .z = z.min },
                },
            };
        }

        fn emitTop(y: u5, x: Vec2u5, z: Vec2u5) ModelFace {
            return .{
                .vertices = .{
                    .{ .x = x.max, .y = y, .z = z.max },
                    .{ .x = x.max, .y = y, .z = z.min },
                    .{ .x = x.min, .y = y, .z = z.min },
                    .{ .x = x.min, .y = y, .z = z.min },
                    .{ .x = x.min, .y = y, .z = z.max },
                    .{ .x = x.max, .y = y, .z = z.max },
                },
            };
        }

        fn emitNorth(z: u5, x: Vec2u5, y: Vec2u5) ModelFace {
            return .{
                .vertices = .{
                    .{ .x = x.min, .y = y.min, .z = z },
                    .{ .x = x.min, .y = y.max, .z = z },
                    .{ .x = x.max, .y = y.max, .z = z },
                    .{ .x = x.max, .y = y.max, .z = z },
                    .{ .x = x.max, .y = y.min, .z = z },
                    .{ .x = x.min, .y = y.min, .z = z },
                },
            };
        }

        fn emitSouth(z: u5, x: Vec2u5, y: Vec2u5) ModelFace {
            return .{
                .vertices = .{
                    .{ .x = x.max, .y = y.max, .z = z },
                    .{ .x = x.min, .y = y.max, .z = z },
                    .{ .x = x.min, .y = y.min, .z = z },
                    .{ .x = x.min, .y = y.min, .z = z },
                    .{ .x = x.max, .y = y.min, .z = z },
                    .{ .x = x.max, .y = y.max, .z = z },
                },
            };
        }
    };
};

pub const BlockModel = struct {
    faces: std.EnumArray(Dir, []const ModelFaceIdx),

    pub const PerVertexData = packed union {
        vertex: packed struct(u32) {
            x: u5,
            y: u5,
            z: u5,
            u: u5,
            v: u5,
            _: u7 = 0,
        },
        texture_idx: BlockTextureKind,
    };

    const ModelFaceIdx = u17;

    const tmp = expr: {
        @setEvalBranchQuota(10_000);

        const block_kinds: []const BlockKind = std.enums.values(BlockKind);

        var per_vertex_buffer: []const PerVertexData = &.{};
        var block_kind_to_block_model: std.EnumArray(BlockKind, BlockModel) = .initUndefined();

        for (block_kinds) |block_kind| {
            const model_scheme = block_kind.getModelScheme() orelse continue;
            const texture_scheme = block_kind.getTextureScheme();

            var block_model: BlockModel = .{ .faces = .initFill(&.{}) };

            for (Dir.values) |dir| {
                const model_faces = model_scheme.faces.get(dir);
                const texture_faces = texture_scheme.faces.get(dir);

                if (model_faces.len == 0 and texture_faces.len == 0) continue;

                std.debug.assert(model_faces.len == texture_faces.len);
                std.debug.assert(model_faces.len > 0);

                for (model_faces, texture_faces) |model_face, texture_face| {
                    var vertices: [7]PerVertexData = undefined;

                    for (0..6) |idx| {
                        vertices[idx] = .{ .vertex = .{
                            .x = model_face.vertices[idx].x,
                            .y = model_face.vertices[idx].y,
                            .z = model_face.vertices[idx].z,
                            .u = texture_face.vertices[idx].u,
                            .v = texture_face.vertices[idx].v,
                        } };
                    }

                    vertices[6] = .{ .texture_idx = texture_face.texture_idx };

                    const block_model_face_idx = per_vertex_buffer.len;
                    block_model.faces.set(dir, block_model.faces.get(dir) ++ .{block_model_face_idx});

                    per_vertex_buffer = per_vertex_buffer ++ vertices;
                }
            }

            block_kind_to_block_model.set(block_kind, block_model);
        }

        break :expr .{
            .per_vertex_buffer = per_vertex_buffer,
            .block_kind_to_block_model = block_kind_to_block_model,
        };
    };

    pub const PER_VERTEX_BUFFER = tmp.per_vertex_buffer;
    const BLOCK_KIND_TO_BLOCK_MODEL = tmp.block_kind_to_block_model;
};
