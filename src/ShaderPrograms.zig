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
debug_nodes: ShaderProgram,

pub fn init(gpa: std.mem.Allocator, raycast_result: World.RaycastResult, screen: Screen) !ShaderPrograms {
    const chunks = try ShaderProgram.init(gpa, assets.vertexShaderPath("chunks"), assets.fragmentShaderPath("chunks"));
    chunks.label("Chunks Shader Program");

    const chunks_bb = try ShaderProgram.init(gpa, assets.vertexShaderPath("chunks_bb"), assets.fragmentShaderPath("chunks_bb"));
    chunks_bb.label("Chunks BB Shader Program");

    const chunks_debug = try ShaderProgram.init(gpa, assets.vertexShaderPath("chunks_debug"), assets.fragmentShaderPath("chunks_debug"));
    chunks_debug.label("Chunks Lines Shader Program");

    const selected_block = try ShaderProgram.init(gpa, assets.vertexShaderPath("selected_block"), assets.fragmentShaderPath("selected_block"));
    selected_block.label("Selected Block Shader Program");

    const selected_side = try ShaderProgram.init(gpa, assets.vertexShaderPath("selected_side"), assets.fragmentShaderPath("selected_side"));
    selected_side.label("Selected Dir Shader Program");

    if (raycast_result.dir != .out_of_bounds and raycast_result.dir != .inside) {
        if (raycast_result.block) |block| {
            const dir_idx = block.kind.getModelIdx() + raycast_result.dir.idx();
            selected_side.setUniform1ui("uFaceIdx", @intCast(dir_idx));
        }
    }

    const crosshair = try ShaderProgram.init(gpa, assets.vertexShaderPath("crosshair"), assets.fragmentShaderPath("crosshair"));
    crosshair.label("Crosshair Shader Program");

    crosshair.setUniform2f("uWindowSize", screen.window_width_f, screen.window_height_f);

    const text = try ShaderProgram.init(gpa, assets.vertexShaderPath("text"), assets.fragmentShaderPath("text"));
    text.label("Text Shader Program");

    const debug_nodes = try ShaderProgram.init(gpa, assets.vertexShaderPath("debug_nodes"), assets.fragmentShaderPath("debug_nodes"));
    debug_nodes.label("Debug Nodes Shader Program");

    return .{
        .chunks = chunks,
        .chunks_bb = chunks_bb,
        .chunks_debug = chunks_debug,
        .selected_block = selected_block,
        .selected_side = selected_side,
        .crosshair = crosshair,
        .text = text,
        .debug_nodes = debug_nodes,
    };
}
