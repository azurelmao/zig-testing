const std = @import("std");
const gl = @import("gl");
const stbi = @import("zstbi");

const TextureArray2D = @This();

const Wrapping = enum(gl.int) {
    clamp_to_edge = gl.CLAMP_TO_EDGE,
    clamp_to_border = gl.CLAMP_TO_BORDER,
    repeat = gl.REPEAT,
    mirrored_repeat = gl.MIRRORED_REPEAT,
};

const MinFilter = enum(gl.int) {
    nearest = gl.NEAREST,
    linear = gl.LINEAR,
    nearest_mipmap_nearest = gl.NEAREST_MIPMAP_NEAREST,
    linear_mipmap_nearest = gl.LINEAR_MIPMAP_NEAREST,
    nearest_mipmap_linear = gl.NEAREST_MIPMAP_LINEAR,
    linear_mipmap_linear = gl.LINEAR_MIPMAP_LINEAR,
};

const MagFilter = enum(gl.int) {
    nearest = gl.NEAREST,
    linear = gl.LINEAR,
};

const TextureFormat = enum(gl.uint) {
    rgba8 = gl.RGBA8,
    rgb8 = gl.RGB8,
    r8 = gl.R8,
};

const DataFormat = enum(gl.uint) {
    rgba = gl.RGBA,
    rgb = gl.RGB,
    r = gl.RED,
};

const Options = struct {
    wrap_s: Wrapping = Wrapping.repeat,
    wrap_t: Wrapping = Wrapping.repeat,
    wrap_r: Wrapping = Wrapping.repeat,
    min_filter: MinFilter = MinFilter.nearest,
    mag_filter: MagFilter = MagFilter.nearest,
    texture_format: TextureFormat,
    data_format: DataFormat,
};

handle: gl.uint,

pub fn init(unit: gl.uint, images: []const stbi.Image, width: gl.sizei, height: gl.sizei, options: Options) !TextureArray2D {
    for (images) |image| {
        if (image.width != width or image.height != height) {
            return error.IncorrectImageSize;
        }
    }

    var handle: gl.uint = undefined;
    gl.CreateTextures(gl.TEXTURE_2D_ARRAY, 1, @ptrCast(&handle));
    gl.TextureStorage3D(handle, 1, @intFromEnum(options.texture_format), width, height, @intCast(images.len));

    for (images, 0..) |image, offset_z| {
        gl.TextureSubImage3D(handle, 0, 0, 0, @intCast(offset_z), width, height, 1, @intFromEnum(options.data_format), gl.UNSIGNED_BYTE, @ptrCast(image.data.ptr));
    }

    gl.TextureParameteri(handle, gl.TEXTURE_WRAP_S, @intFromEnum(options.wrap_s));
    gl.TextureParameteri(handle, gl.TEXTURE_WRAP_T, @intFromEnum(options.wrap_t));
    gl.TextureParameteri(handle, gl.TEXTURE_WRAP_R, @intFromEnum(options.wrap_r));
    gl.TextureParameteri(handle, gl.TEXTURE_MIN_FILTER, @intFromEnum(options.min_filter));
    gl.TextureParameteri(handle, gl.TEXTURE_MAG_FILTER, @intFromEnum(options.mag_filter));

    gl.BindTextureUnit(unit, handle);

    return .{ .handle = handle };
}
