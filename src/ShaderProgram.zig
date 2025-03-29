const std = @import("std");
const gl = @import("gl");
const print = std.debug.print;
const Matrix4x4f = @import("Matrix4x4f.zig");

const ShaderProgram = @This();

var currently_bound_shader_program: ?gl.uint = null;

handle: gl.uint,
uniforms: std.StringHashMapUnmanaged(gl.int),

pub fn init(allocator: std.mem.Allocator, vertex_shader_path: []const gl.char, fragment_shader_path: []const gl.char) !ShaderProgram {
    const handle = gl.CreateProgram();

    const vertexShader = try readAndCompileShader(allocator, vertex_shader_path, gl.VERTEX_SHADER);
    gl.AttachShader(handle, vertexShader);

    const fragmentShader = try readAndCompileShader(allocator, fragment_shader_path, gl.FRAGMENT_SHADER);
    gl.AttachShader(handle, fragmentShader);

    gl.LinkProgram(handle);

    var compiled: gl.int = undefined;
    gl.GetProgramiv(handle, gl.LINK_STATUS, &compiled);

    if (compiled == 0) {
        return error.ShaderLinkingFailed;
    }

    var count_uniforms: gl.int = undefined;
    var uniform_max_len: gl.int = undefined;
    gl.GetProgramiv(handle, gl.ACTIVE_UNIFORMS, &count_uniforms);
    gl.GetProgramiv(handle, gl.ACTIVE_UNIFORM_MAX_LENGTH, &uniform_max_len);

    var uniforms = std.StringHashMapUnmanaged(gl.int).empty;
    for (0..@intCast(count_uniforms)) |i| {
        const uniform_name = try allocator.alloc(gl.char, @intCast(uniform_max_len));

        var uniform_len: gl.sizei = undefined;
        gl.GetActiveUniformName(handle, @intCast(i), uniform_max_len, &uniform_len, uniform_name.ptr);

        const uniform_location = gl.GetUniformLocation(handle, @ptrCast(uniform_name.ptr));
        try uniforms.put(allocator, uniform_name[0..@intCast(uniform_len)], uniform_location);
    }

    return .{ .handle = handle, .uniforms = uniforms };
}

pub fn readAndCompileShader(allocator: std.mem.Allocator, shader_path: []const gl.char, @"type": gl.@"enum") !gl.uint {
    const shader_source: []const gl.char = try std.fs.cwd().readFileAllocOptions(allocator, shader_path, std.math.maxInt(u16), null, @alignOf(u8), 0);

    const handle = gl.CreateShader(@"type");
    gl.ShaderSource(handle, 1, @ptrCast(&shader_source.ptr), null);
    gl.CompileShader(handle);

    var compiled: gl.int = undefined;
    gl.GetShaderiv(handle, gl.COMPILE_STATUS, &compiled);

    if (compiled == 0) {
        var log_len: gl.int = undefined;
        gl.GetShaderiv(handle, gl.INFO_LOG_LENGTH, &log_len);

        const log = try allocator.alloc(gl.char, @intCast(log_len));
        gl.GetShaderInfoLog(handle, log_len, null, @ptrCast(log.ptr));
        std.log.err("{s}", .{log});

        return error.ShaderCompilationFailed;
    }

    return handle;
}

pub fn getUniformLocation(self: ShaderProgram, uniform: []const u8) gl.int {
    return self.uniforms.get(uniform) orelse {
        std.debug.panic("Unknown uniform '{s}'", .{uniform});
    };
}

pub fn setUniform1i(self: ShaderProgram, uniform: []const u8, v0: gl.int) void {
    const location = self.getUniformLocation(uniform);

    self.bind();
    gl.Uniform1i(location, v0);
}

pub fn setUniform2i(self: ShaderProgram, uniform: []const u8, v0: gl.int, v1: gl.int) void {
    const location = self.getUniformLocation(uniform);

    self.bind();
    gl.Uniform2i(location, v0, v1);
}

pub fn setUniform3i(self: ShaderProgram, uniform: []const u8, v0: gl.int, v1: gl.int, v2: gl.int) void {
    const location = self.getUniformLocation(uniform);

    self.bind();
    gl.Uniform3i(location, v0, v1, v2);
}

pub fn setUniform4i(self: ShaderProgram, uniform: []const u8, v0: gl.int, v1: gl.int, v2: gl.int, v3: gl.int) void {
    const location = self.getUniformLocation(uniform);

    self.bind();
    gl.Uniform4i(location, v0, v1, v2, v3);
}

pub fn setUniform1ui(self: ShaderProgram, uniform: []const u8, v0: gl.uint) void {
    const location = self.getUniformLocation(uniform);

    self.bind();
    gl.Uniform1ui(location, v0);
}

pub fn setUniform2ui(self: ShaderProgram, uniform: []const u8, v0: gl.uint, v1: gl.uint) void {
    const location = self.getUniformLocation(uniform);

    self.bind();
    gl.Uniform2ui(location, v0, v1);
}

pub fn setUniform3ui(self: ShaderProgram, uniform: []const u8, v0: gl.uint, v1: gl.uint, v2: gl.uint) void {
    const location = self.getUniformLocation(uniform);

    self.bind();
    gl.Uniform3ui(location, v0, v1, v2);
}

pub fn setUniform4ui(self: ShaderProgram, uniform: []const u8, v0: gl.uint, v1: gl.uint, v2: gl.uint, v3: gl.uint) void {
    const location = self.getUniformLocation(uniform);

    self.bind();
    gl.Uniform4ui(location, v0, v1, v2, v3);
}

pub fn setUniform1f(self: ShaderProgram, uniform: []const u8, v0: gl.float) void {
    const location = self.getUniformLocation(uniform);

    self.bind();
    gl.Uniform1f(location, v0);
}

pub fn setUniform2f(self: ShaderProgram, uniform: []const u8, v0: gl.float, v1: gl.float) void {
    const location = self.getUniformLocation(uniform);

    self.bind();
    gl.Uniform2f(location, v0, v1);
}

pub fn setUniform3f(self: ShaderProgram, uniform: []const u8, v0: gl.float, v1: gl.float, v2: gl.float) void {
    const location = self.getUniformLocation(uniform);

    self.bind();
    gl.Uniform3f(location, v0, v1, v2);
}

pub fn setUniform4f(self: ShaderProgram, uniform: []const u8, v0: gl.float, v1: gl.float, v2: gl.float, v3: gl.float) void {
    const location = self.getUniformLocation(uniform);

    self.bind();
    gl.Uniform4f(location, v0, v1, v2, v3);
}

pub fn setUniformMatrix4f(self: ShaderProgram, uniform: []const u8, matrix: Matrix4x4f) void {
    const location = self.getUniformLocation(uniform);

    self.bind();
    gl.UniformMatrix4fv(location, 1, 0, @ptrCast(&matrix.data));
}

pub fn bind(self: ShaderProgram) void {
    if (currently_bound_shader_program) |handle| {
        if (handle != self.handle) {
            currently_bound_shader_program = self.handle;
            gl.UseProgram(self.handle);
        }
    } else {
        currently_bound_shader_program = self.handle;
        gl.UseProgram(self.handle);
    }
}
