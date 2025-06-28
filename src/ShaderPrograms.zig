const std = @import("std");
const assets = @import("assets.zig");
const World = @import("World.zig");
const Screen = @import("Screen.zig");
const ShaderProgram = @import("ShaderProgram.zig");

const ShaderPrograms = @This();

chunks: ShaderProgram,
chunks_bb: ShaderProgram,
chunks_debug: ShaderProgram,
selected_block: ShaderProgram,
selected_side: ShaderProgram,
crosshair: ShaderProgram,
text: ShaderProgram,

pub fn init(allocator: std.mem.Allocator, raycast_result: World.RaycastResult, screen: Screen) !ShaderPrograms {
    const chunks = try ShaderProgram.init(allocator, assets.vertexShaderPath("chunks"), assets.fragmentShaderPath("chunks"));
    chunks.label("Chunks Shader Program");

    const chunks_bb = try ShaderProgram.init(allocator, assets.vertexShaderPath("chunks_bb"), assets.fragmentShaderPath("chunks_bb"));
    chunks_bb.label("Chunks BB Shader Program");

    const chunks_lines = try ShaderProgram.init(allocator, assets.vertexShaderPath("chunks_lines"), assets.fragmentShaderPath("chunks_lines"));
    chunks_lines.label("Chunks Lines Shader Program");

    const selected_block = try ShaderProgram.init(allocator, assets.vertexShaderPath("selected_block"), assets.fragmentShaderPath("selected_block"));
    selected_block.label("Selected Block Shader Program");

    const selected_side = try ShaderProgram.init(allocator, assets.vertexShaderPath("selected_side"), assets.fragmentShaderPath("selected_side"));
    selected_side.label("Selected Side Shader Program");

    if (raycast_result.side != .out_of_bounds and raycast_result.side != .inside) {
        if (raycast_result.block) |block| {
            const model_idx = block.kind.getModelIndices().faces[raycast_result.side.idx()];
            selected_side.setUniform1ui("uModelIdx", model_idx);
        }
    }

    const crosshair = try ShaderProgram.init(allocator, assets.vertexShaderPath("crosshair"), assets.fragmentShaderPath("crosshair"));
    crosshair.label("Crosshair Shader Program");

    crosshair.setUniform2f("uWindowSize", screen.window_width_f, screen.window_height_f);

    const text = try ShaderProgram.init(allocator, assets.vertexShaderPath("text"), assets.fragmentShaderPath("text"));
    text.label("Text Shader Program");

    return .{
        .chunks = chunks,
        .chunks_bb = chunks_bb,
        .chunks_debug = chunks_lines,
        .selected_block = selected_block,
        .selected_side = selected_side,
        .crosshair = crosshair,
        .text = text,
    };
}
