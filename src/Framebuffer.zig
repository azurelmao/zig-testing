const std = @import("std");
const gl = @import("gl");

const Framebuffer = @This();

texture_handle: gl.uint,
framebuffer_handle: gl.uint,

pub fn init(unit: gl.uint, width: gl.sizei, height: gl.sizei) !Framebuffer {
    var texture_handle: gl.uint = undefined;
    gl.CreateTextures(gl.TEXTURE_2D, 1, @ptrCast(&texture_handle));
    gl.TextureStorage2D(texture_handle, 1, gl.RGBA8, width, height);
    gl.BindTextureUnit(unit, texture_handle);

    var framebuffer_handle: gl.uint = undefined;
    gl.CreateFramebuffers(1, @ptrCast(&framebuffer_handle));
    gl.NamedFramebufferTexture(framebuffer_handle, gl.COLOR_ATTACHMENT0, texture_handle, 0);

    if (gl.CheckNamedFramebufferStatus(framebuffer_handle, gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE) {
        return error.IncompleteFramebuffer;
    }

    return .{
        .texture_handle = texture_handle,
        .framebuffer_handle = framebuffer_handle,
    };
}

pub fn resize(self: *Framebuffer, width: gl.sizei, height: gl.sizei) !void {
    gl.DeleteTextures(1, @ptrCast(&self.texture_handle));

    gl.CreateTextures(gl.TEXTURE_2D, 1, @ptrCast(&self.texture_handle));
    gl.TextureStorage2D(self.texture_handle, 1, gl.RGBA8, width, height);

    gl.DeleteFramebuffers(1, @ptrCast(&self.framebuffer_handle));

    gl.CreateFramebuffers(1, @ptrCast(&self.framebuffer_handle));
    gl.NamedFramebufferTexture(self.framebuffer_handle, gl.COLOR_ATTACHMENT0, self.texture_handle, 0);

    if (gl.CheckNamedFramebufferStatus(self.framebuffer_handle, gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE) {
        return error.IncompleteFramebuffer;
    }
}

pub fn resizeAndBind(self: *Framebuffer, width: gl.sizei, height: gl.sizei, unit: gl.uint) !void {
    try self.resize(width, height);
    self.bind(unit);
}

pub fn bind(self: Framebuffer, unit: gl.uint) void {
    gl.BindTextureUnit(unit, self.texture_handle);
}

pub fn label(self: Framebuffer, name: [:0]const u8) void {
    gl.ObjectLabel(gl.FRAMEBUFFER, self.handle, -1, name);
}
