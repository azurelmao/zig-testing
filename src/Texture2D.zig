const std = @import("std");
const gl = @import("gl");
const stbi = @import("zstbi");

const Texture2D = @This();

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
    min_filter: MinFilter = MinFilter.nearest,
    mag_filter: MagFilter = MagFilter.nearest,
    texture_format: TextureFormat,
    data_format: DataFormat,
};

handle: gl.uint,

pub fn init(unit: gl.uint, image: stbi.Image, options: Options) Texture2D {
    var handle: gl.uint = undefined;
    gl.CreateTextures(gl.TEXTURE_2D, 1, @ptrCast(&handle));
    gl.TextureStorage2D(handle, 1, @intFromEnum(options.texture_format), @intCast(image.width), @intCast(image.height));
    gl.TextureSubImage2D(handle, 0, 0, 0, @intCast(image.width), @intCast(image.height), @intFromEnum(options.data_format), gl.UNSIGNED_BYTE, @ptrCast(image.data.ptr));

    gl.TextureParameteri(handle, gl.TEXTURE_WRAP_S, @intFromEnum(options.wrap_s));
    gl.TextureParameteri(handle, gl.TEXTURE_WRAP_T, @intFromEnum(options.wrap_t));
    gl.TextureParameteri(handle, gl.TEXTURE_MIN_FILTER, @intFromEnum(options.min_filter));
    gl.TextureParameteri(handle, gl.TEXTURE_MAG_FILTER, @intFromEnum(options.mag_filter));

    gl.BindTextureUnit(unit, handle);

    return .{ .handle = handle };
}
