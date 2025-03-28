const std = @import("std");
const gl = @import("gl");
const zstbi = @import("zstbi");
const print = std.debug.print;

const Self = @This();

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

const Options = struct {
    wrap_s: Wrapping = Wrapping.repeat,
    wrap_t: Wrapping = Wrapping.repeat,
    min_filter: MinFilter = MinFilter.nearest,
    mag_filter: MagFilter = MagFilter.nearest,
};

handle: gl.uint,

pub fn init(image: zstbi.Image, options: Options) Self {
    var handle: gl.uint = undefined;
    gl.CreateTextures(gl.TEXTURE_2D, 1, @ptrCast(&handle));
    gl.TextureStorage2D(handle, 1, gl.RGBA8, image.width, image.height);
    gl.TextureSubImage2D(handle, 0, 0, 0, image.width, image.height, gl.RGBA, gl.UNSIGNED_BYTE, @ptrCast(image.data.ptr));

    gl.TextureParameteri(handle, gl.TEXTURE_WRAP_S, @intFromEnum(options.wrap_s));
    gl.TextureParameteri(handle, gl.TEXTURE_WRAP_T, @intFromEnum(options.wrap_t));
    gl.TextureParameteri(handle, gl.TEXTURE_MIN_FILTER, @intFromEnum(options.min_filter));
    gl.TextureParameteri(handle, gl.TEXTURE_MAG_FILTER, @intFromEnum(options.mag_filter));

    return .{ .handle = handle };
}

pub fn bind(self: Self, unit: gl.uint) void {
    gl.BindTextureUnit(unit, self.handle);
}
