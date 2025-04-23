const std = @import("std");
const stbi = @import("zstbi");
const assets = @import("assets.zig");
const Glyph = @import("glyph.zig").Glyph;
const Texture2D = @import("Texture2D.zig");
const TextureArray2D = @import("TextureArray2D.zig");
const Block = @import("block.zig").Block;

const Textures = @This();

block: TextureArray2D,
font: TextureArray2D,
crosshair: Texture2D,

pub fn init() !Textures {
    const block = try initBlockTextures();
    const font = try initFontTextures();
    const crosshair = try initCrosshairTexture();

    return .{
        .block = block,
        .font = font,
        .crosshair = crosshair,
    };
}

fn initBlockTextures() !TextureArray2D {
    const TEXTURE_INDICES = comptime std.enums.values(Block.TextureIndex);
    var block_images: [TEXTURE_INDICES.len]stbi.Image = undefined;

    inline for (TEXTURE_INDICES) |texture_index| {
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
    var font_image = try stbi.Image.loadFromFile(assets.texturePath("font"), 1);
    defer font_image.deinit();

    var glyph_images: [Glyph.len]stbi.Image = undefined;

    inline for (0..Glyph.len) |glyph_idx| {
        const base_x = glyph_idx * 6;

        var glyph_image = try stbi.Image.createEmpty(6, 6, 1, .{});

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
    var crosshair_image = try stbi.Image.loadFromFile(assets.texturePath("crosshair"), 1);
    defer crosshair_image.deinit();

    return Texture2D.init(2, crosshair_image, .{
        .texture_format = .r8,
        .data_format = .r,
    });
}
