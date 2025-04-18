const ASSETS_PATH = "assets/";
const SHADERS_PATH = ASSETS_PATH ++ "shaders/";
const TEXTURES_PATH = ASSETS_PATH ++ "textures/";

const SHADERS_EXTENSION = ".glsl";
const TEXTURES_EXTENSION = ".png";

const VERTEX_SHADER_POSTFIX = "_vs" ++ SHADERS_EXTENSION;
const FRAGMENT_SHADER_POSTFIX = "_fs" ++ SHADERS_EXTENSION;

pub fn vertexShaderPath(comptime file_name: [:0]const u8) [:0]const u8 {
    return SHADERS_PATH ++ file_name ++ VERTEX_SHADER_POSTFIX;
}

pub fn fragmentShaderPath(comptime file_name: [:0]const u8) [:0]const u8 {
    return SHADERS_PATH ++ file_name ++ FRAGMENT_SHADER_POSTFIX;
}

pub fn texturePath(comptime file_name: [:0]const u8) [:0]const u8 {
    return TEXTURES_PATH ++ file_name ++ TEXTURES_EXTENSION;
}
