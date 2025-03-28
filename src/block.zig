const std = @import("std");
const Side = @import("side.zig").Side;
const Light = @import("Chunk.zig").Light;

pub const Block = enum(u8) {
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

    pub const BLOCKS = std.enums.values(Block);

    pub const BLOCKS_WITH_A_MODEL = expr: {
        var blocks_with_a_model: []const Block = &.{};

        for (BLOCKS) |block| {
            if (block.hasModel()) {
                blocks_with_a_model = blocks_with_a_model ++ &[1]Block{block};
            }
        }

        break :expr blocks_with_a_model;
    };

    pub const VertexIndices = struct {
        faces: [6]u32,
    };

    pub const ModelIndices = struct {
        faces: [6]u11,
    };

    const tmp = expr: {
        var model_to_vertex_indices: [Model.MODELS.len]VertexIndices = undefined;
        var block_to_model_indices: [BLOCKS.len]ModelIndices = undefined;
        var vertex_buffer: []const Vertex = &.{};
        var vertex_idx_and_texture_idx_buffer: []const FaceVertex = &.{};

        for (Model.MODELS) |model| {
            const model_data = model.getData();

            var vertex_indices: VertexIndices = undefined;

            for (0..6) |face_idx| {
                vertex_indices.faces[face_idx] = @intCast(vertex_buffer.len);
                vertex_buffer = vertex_buffer ++ model_data.faces[face_idx];
            }

            model_to_vertex_indices[@intFromEnum(model)] = vertex_indices;
        }

        for (BLOCKS_WITH_A_MODEL) |block| {
            const model = block.getModel();
            const texture_schema = block.getTextureSchema();

            var model_indices: ModelIndices = undefined;

            for (0..6) |face_idx| {
                const vertex_idx_and_texture_idx = FaceVertex{
                    .vertex_idx = model_to_vertex_indices[@intFromEnum(model)].faces[face_idx],
                    .texture_idx = @intFromEnum(texture_schema.faces[face_idx]),
                };

                model_indices.faces[face_idx] = @intCast(vertex_idx_and_texture_idx_buffer.len);
                vertex_idx_and_texture_idx_buffer = vertex_idx_and_texture_idx_buffer ++ &[1]FaceVertex{vertex_idx_and_texture_idx};
            }

            block_to_model_indices[@intFromEnum(block)] = model_indices;
        }

        break :expr .{
            .vertex_buffer = vertex_buffer,
            .vertex_idx_and_texture_idx_buffer = vertex_idx_and_texture_idx_buffer,
            .block_to_model_indices = block_to_model_indices,
        };
    };

    pub const VERTEX_BUFFER = tmp.vertex_buffer;
    pub const VERTEX_IDX_AND_TEXTURE_IDX_BUFFER = tmp.vertex_idx_and_texture_idx_buffer;
    const BLOCK_TO_MODEL_INDICES = tmp.block_to_model_indices;

    pub fn getModelIndices(self: Block) ModelIndices {
        return BLOCK_TO_MODEL_INDICES[@intFromEnum(self)];
    }

    pub fn isInteractable(self: Block) bool {
        return switch (self) {
            .air, .water, .lava => false,
            else => true,
        };
    }

    pub fn isNotSolid(self: Block) bool {
        return switch (self) {
            .air, .water, .ice, .glass, .glass_tinted => true,
            else => false,
        };
    }

    pub const Layer = enum {
        solid,
        water,
        ice,
        glass_stained,
        glass,

        pub const len = std.enums.values(Layer).len;

        pub inline fn idx(self: Layer) usize {
            return @intFromEnum(self);
        }
    };

    pub fn getLayer(self: Block) Layer {
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

    pub fn getLightOpacity(self: Block) LightOpacity {
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

    pub const Texture = enum {
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

        pub const TEXTURES = std.enums.values(Texture);

        const TEXTURE_TO_PATH = expr: {
            var texture_to_path: [TEXTURES.len][:0]const u8 = undefined;

            for (TEXTURES) |texture| {
                texture_to_path[@intFromEnum(texture)] = "assets/textures/" ++ @tagName(texture) ++ ".png";
            }

            break :expr texture_to_path;
        };

        pub fn getPath(self: Texture) [:0]const u8 {
            return TEXTURE_TO_PATH[@intFromEnum(self)];
        }
    };

    pub const TextureScheme = struct {
        faces: [6]Texture,

        pub fn allSides(texture: Texture) TextureScheme {
            return .{ .faces = @splat(texture) };
        }

        pub fn grass(top: Texture, bottom: Texture, sides: Texture) TextureScheme {
            var faces: [6]Texture = @splat(sides);

            faces[Side.top.idx()] = top;
            faces[Side.bottom.idx()] = bottom;

            return .{ .faces = faces };
        }
    };

    pub fn getTextureSchema(comptime self: Block) TextureScheme {
        return switch (self) {
            .stone => TextureScheme.allSides(.stone),
            .grass => TextureScheme.grass(.grass_top, .dirt, .grass_side),
            .bedrock => TextureScheme.allSides(.bedrock),
            .sand => TextureScheme.allSides(.sand),
            .bricks => TextureScheme.allSides(.bricks),
            .water => TextureScheme.allSides(.water),
            .lava => TextureScheme.allSides(.lava),
            .ice => TextureScheme.allSides(.ice),
            .glass_tinted => TextureScheme.allSides(.glass_tinted),
            .glass => TextureScheme.allSides(.glass),
            else => std.debug.panic("Block {} doesn't have a texture", .{@tagName(self)}),
        };
    }

    pub fn hasModel(comptime self: Block) bool {
        return switch (self) {
            .air => false,
            else => true,
        };
    }

    pub fn getModel(comptime self: Block) Model {
        return switch (self) {
            .air => std.debug.panic("Air doesn't have a model", .{}),
            else => Model.square,
        };
    }

    pub const Model = enum {
        square,

        pub fn getData(comptime self: Model) ModelData {
            return switch (self) {
                .square => SQUARE,
            };
        }

        pub const MODELS = std.enums.values(Model);
    };

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

    pub const ModelData = struct {
        faces: [6][]const Vertex,
    };

    pub const SQUARE = expr: {
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

        break :expr ModelData{
            .faces = faces,
        };
    };
};
