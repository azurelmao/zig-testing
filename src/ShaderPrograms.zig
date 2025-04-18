const std = @import("std");
const assets = @import("assets.zig");
const ShaderProgram = @import("ShaderProgram.zig");

const ShaderPrograms = @This();

chunks: ShaderProgram,
chunks_bb: ShaderProgram,
chunks_debug: ShaderProgram,
selected_block: ShaderProgram,
selected_side: ShaderProgram,
crosshair: ShaderProgram,
text: ShaderProgram,

pub fn init(allocator: std.mem.Allocator) !ShaderPrograms {
    const chunks = try ShaderProgram.init(allocator, assets.vertexShaderPath("chunks"), assets.fragmentShaderPath("chunks"));
    const chunks_bb = try ShaderProgram.init(allocator, assets.vertexShaderPath("chunks_bb"), assets.fragmentShaderPath("chunks_bb"));
    const chunks_debug = try ShaderProgram.init(allocator, assets.vertexShaderPath("chunks_debug"), assets.fragmentShaderPath("chunks_debug"));
    const selected_block = try ShaderProgram.init(allocator, assets.vertexShaderPath("selected_block"), assets.fragmentShaderPath("selected_block"));
    const selected_side = try ShaderProgram.init(allocator, assets.vertexShaderPath("selected_side"), assets.fragmentShaderPath("selected_side"));
    const crosshair = try ShaderProgram.init(allocator, assets.vertexShaderPath("crosshair"), assets.fragmentShaderPath("crosshair"));
    const text = try ShaderProgram.init(allocator, assets.vertexShaderPath("text"), assets.fragmentShaderPath("text"));

    return .{
        .chunks = chunks,
        .chunks_bb = chunks_bb,
        .chunks_debug = chunks_debug,
        .selected_block = selected_block,
        .selected_side = selected_side,
        .crosshair = crosshair,
        .text = text,
    };
}
