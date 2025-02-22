const std = @import("std");

pub const Block = enum(u8) {
    const Self = @This();

    air,
    stone,
    grass,
    bricks,
    water,
    ice,
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
        var block_to_model_indices: [Block.BLOCKS.len]ModelIndices = undefined;
        var vertex_buffer: []const Vertex = &.{};
        var vertex_idx_and_texture_idx_buffer: []const VertexIdxAndTextureIdx = &.{};

        for (Model.MODELS) |model| {
            const model_data = model.getData();

            var vertex_indices: VertexIndices = undefined;

            for (0..6) |face_idx| {
                vertex_indices.faces[face_idx] = @intCast(vertex_buffer.len);
                vertex_buffer = vertex_buffer ++ model_data.faces[face_idx];
            }

            model_to_vertex_indices[@intFromEnum(model)] = vertex_indices;
        }

        for (Block.BLOCKS_WITH_A_MODEL) |block| {
            const model = block.getModel();
            const texture = block.getTexture();

            var model_indices: ModelIndices = undefined;

            for (0..6) |face_idx| {
                const vertex_idx_and_texture_idx = VertexIdxAndTextureIdx{
                    .vertex_idx = model_to_vertex_indices[@intFromEnum(model)].faces[face_idx],
                    .texture_idx = @intFromEnum(texture),
                };

                model_indices.faces[face_idx] = @intCast(vertex_idx_and_texture_idx_buffer.len);
                vertex_idx_and_texture_idx_buffer = vertex_idx_and_texture_idx_buffer ++ &[1]VertexIdxAndTextureIdx{vertex_idx_and_texture_idx};
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
    pub const BLOCK_TO_MODEL_INDICES = tmp.block_to_model_indices;

    // comptime {
    //     var face_model_idx: u17 = 0;
    //     for (BLOCKS_WITH_A_MODEL) |block| {
    //         const block_model = block.getModel();
    //         const texture_idx = block.getTextureIdx();
    //         const vertex_indices = model_id_to_vertex_indices.get(block_model.id) orelse std.debug.panic("Should be impossible", .{});
    //         var face_indices: FaceIndices = undefined;

    //         for (0..6) |face_idx| {
    //             face_indices[face_idx] = face_model_idx;
    //             face_model_idx += 1;
    //             const vertex_idx_and_texture_idx = model.VertexIdxAndTextureIdx{
    //                 .vertex_idx = vertex_indices[face_idx],
    //                 .texture_idx = texture_idx,
    //             };
    //             try vertex_idx_and_texture_idx_buffer.append(vertex_idx_and_texture_idx);
    //         }

    //         try block_to_face_indices.put(block, face_indices);
    //     }
    // }

    pub fn getTexture(comptime self: Self) Texture {
        return switch (self) {
            .air => std.debug.panic("Air doesn't have a texture", .{}),
            .stone => .cobble,
            .grass => .grass,
            .bricks => .bricks,
            .water => .water,
            .ice => .ice,
            .glass => .glass,
        };
    }

    pub fn hasModel(comptime self: Self) bool {
        return switch (self) {
            .air => false,
            else => true,
        };
    }

    pub fn getModel(comptime self: Self) Model {
        return switch (self) {
            .air => std.debug.panic("Air doesn't have a model", .{}),
            else => Model.square,
        };
    }

    pub fn isNotSolid(self: Self) bool {
        return switch (self) {
            .air, .water => true,
            else => false,
        };
    }

    pub const Texture = enum {
        cobble,
        grass,
        bricks,
        water,
        ice,
        glass,

        pub const TEXTURES = std.enums.values(Texture);

        pub const TEXTURE_TO_PATH = expr: {
            var texture_to_path: [TEXTURES.len][:0]const u8 = undefined;

            for (TEXTURES) |texture| {
                texture_to_path[@intFromEnum(texture)] = "assets/textures/" ++ @tagName(texture) ++ ".png";
            }

            break :expr texture_to_path;
        };
    };

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

    pub const Model = enum {
        square,

        pub fn getData(comptime self: Model) ModelData {
            return switch (self) {
                .square => SQUARE,
            };
        }

        pub const MODELS = std.enums.values(Model);
    };

    pub const ModelData = struct {
        faces: [6][]const Vertex,
    };

    pub const Quad = struct {
        vertices: []const Vertex,
        texture: Texture,
    };

    pub const SQUARE = expr: {
        var faces: [6][]const Vertex = undefined;

        faces[0] = &.{
            .{ .x = 0, .y = 1, .z = 1, .u = 1, .v = 0 },
            .{ .x = 0, .y = 1, .z = 0, .u = 0, .v = 0 },
            .{ .x = 0, .y = 0, .z = 0, .u = 0, .v = 1 },
            .{ .x = 0, .y = 0, .z = 0, .u = 0, .v = 1 },
            .{ .x = 0, .y = 0, .z = 1, .u = 1, .v = 1 },
            .{ .x = 0, .y = 1, .z = 1, .u = 1, .v = 0 },
        };

        faces[1] = &.{
            .{ .x = 1, .y = 0, .z = 0, .u = 1, .v = 1 },
            .{ .x = 1, .y = 1, .z = 0, .u = 1, .v = 0 },
            .{ .x = 1, .y = 1, .z = 1, .u = 0, .v = 0 },
            .{ .x = 1, .y = 1, .z = 1, .u = 0, .v = 0 },
            .{ .x = 1, .y = 0, .z = 1, .u = 0, .v = 1 },
            .{ .x = 1, .y = 0, .z = 0, .u = 1, .v = 1 },
        };

        faces[2] = &.{
            .{ .x = 0, .y = 0, .z = 0, .u = 1, .v = 1 },
            .{ .x = 1, .y = 0, .z = 0, .u = 1, .v = 0 },
            .{ .x = 1, .y = 0, .z = 1, .u = 0, .v = 0 },
            .{ .x = 1, .y = 0, .z = 1, .u = 0, .v = 0 },
            .{ .x = 0, .y = 0, .z = 1, .u = 0, .v = 1 },
            .{ .x = 0, .y = 0, .z = 0, .u = 1, .v = 1 },
        };

        faces[3] = &.{
            .{ .x = 1, .y = 1, .z = 1, .u = 1, .v = 0 },
            .{ .x = 1, .y = 1, .z = 0, .u = 0, .v = 0 },
            .{ .x = 0, .y = 1, .z = 0, .u = 0, .v = 1 },
            .{ .x = 0, .y = 1, .z = 0, .u = 0, .v = 1 },
            .{ .x = 0, .y = 1, .z = 1, .u = 1, .v = 1 },
            .{ .x = 1, .y = 1, .z = 1, .u = 1, .v = 0 },
        };

        faces[4] = &.{
            .{ .x = 0, .y = 0, .z = 0, .u = 1, .v = 1 },
            .{ .x = 0, .y = 1, .z = 0, .u = 1, .v = 0 },
            .{ .x = 1, .y = 1, .z = 0, .u = 0, .v = 0 },
            .{ .x = 1, .y = 1, .z = 0, .u = 0, .v = 0 },
            .{ .x = 1, .y = 0, .z = 0, .u = 0, .v = 1 },
            .{ .x = 0, .y = 0, .z = 0, .u = 1, .v = 1 },
        };

        faces[5] = &.{
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
