const std = @import("std");
const stbi = @import("zstbi");
const assets = @import("assets.zig");
const Glyph = @import("glyph.zig").Glyph;
const Texture2D = @import("Texture2D.zig");
const TextureArray2D = @import("TextureArray2D.zig");
const BlockTextureKind = @import("block.zig").BlockTextureKind;

const Textures = @This();

block: TextureArray2D,
font: TextureArray2D,
crosshair: Texture2D,
// indirect_light: Texture2D,

pub fn init() !Textures {
    const block = try initBlockTextures();
    const font = try initFontTextures();
    const crosshair = try initCrosshairTexture();
    // const indirect_light = try initIndirectLightTexture();

    return .{
        .block = block,
        .font = font,
        .crosshair = crosshair,
        // .indirect_light = indirect_light,
    };
}

fn initBlockTextures() !TextureArray2D {
    const block_texture_kinds = comptime std.enums.values(BlockTextureKind);
    var block_images: [block_texture_kinds.len]stbi.Image = undefined;

    inline for (block_texture_kinds) |texture_index| {
        const image = try stbi.Image.loadFromFile(assets.texturePath(@tagName(texture_index)), 4);
        block_images[@intFromEnum(texture_index)] = image;
    }

    defer {
        for (&block_images) |*image| {
            image.deinit();
        }
    }

    return TextureArray2D.init(0, &block_images, 16, 16, .{
        .texture_format = .rgba8,
        .data_format = .rgba,
    });
}

fn initFontTextures() !TextureArray2D {
    var font_image: stbi.Image = try .loadFromFile(assets.texturePath("font"), 1);
    defer font_image.deinit();

    var glyph_images: [Glyph.len]stbi.Image = undefined;

    inline for (0..Glyph.len) |glyph_idx| {
        const base_x = glyph_idx * 6;

        var glyph_image: stbi.Image = try .createEmpty(6, 6, 1, .{});

        var data_idx: usize = 0;
        for (0..6) |y| {
            for (0..6) |x_| {
                const x = base_x + x_;
                const image_idx = y * font_image.width + x;

                glyph_image.data[data_idx] = font_image.data[image_idx];
                data_idx += 1;
            }
        }

        glyph_images[glyph_idx] = glyph_image;
    }

    defer {
        for (&glyph_images) |*image| {
            image.deinit();
        }
    }

    return TextureArray2D.init(1, &glyph_images, 6, 6, .{
        .texture_format = .r8,
        .data_format = .r,
    });
}

fn initCrosshairTexture() !Texture2D {
    var crosshair_image: stbi.Image = try .loadFromFile(assets.texturePath("crosshair"), 1);
    defer crosshair_image.deinit();

    return Texture2D.initFromImage(2, crosshair_image, .{
        .texture_format = .r8,
        .data_format = .r,
    });
}

fn initIndirectLightTexture() !Texture2D {
    var indirect_light_image: stbi.Image = try .loadFromFile(assets.texturePath("indirect_light"), 4);
    defer indirect_light_image.deinit();

    return Texture2D.initFromImage(4, indirect_light_image, .{
        .wrap_s = .clamp_to_edge,
        .wrap_t = .clamp_to_edge,
        .min_filter = .linear,
        .mag_filter = .linear,
        .texture_format = .rgba8,
        .data_format = .rgba,
    });
}
