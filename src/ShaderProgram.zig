const std = @import("std");
const gl = @import("gl");
const print = std.debug.print;
const Matrix4x4f = @import("Matrix4x4f.zig");

const Self = @This();

var currently_bound_shader_program: ?gl.uint = null;

handle: gl.uint,
uniforms: std.StringHashMap(gl.int),

pub fn new(allocator: std.mem.Allocator, vertex_shader_path: []const gl.char, fragment_shader_path: []const gl.char) !Self {
    const handle = gl.CreateProgram();
    var uniforms = std.StringHashMap(gl.int).init(allocator);

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

    for (0..@intCast(count_uniforms)) |i| {
        const uniform_name = try allocator.alloc(gl.char, @intCast(uniform_max_len));

        var uniform_len: gl.sizei = undefined;
        gl.GetActiveUniformName(handle, @intCast(i), uniform_max_len, &uniform_len, uniform_name.ptr);

        const uniform_location = gl.GetUniformLocation(handle, @ptrCast(uniform_name.ptr));
        try uniforms.put(uniform_name[0..@intCast(uniform_len)], uniform_location);
    }

    return .{ .handle = handle, .uniforms = uniforms };
}

pub fn readAndCompileShader(allocator: std.mem.Allocator, shader_path: []const gl.char, @"type": gl.@"enum") !gl.uint {
    const shader_source: []const gl.char = try std.fs.cwd().readFileAlloc(allocator, shader_path, 4000);

    const handle = gl.CreateShader(@"type");
    gl.ShaderSource(handle, 1, @ptrCast(&shader_source.ptr), null);
    gl.CompileShader(handle);

    var compiled: gl.int = undefined;
    gl.GetShaderiv(handle, gl.COMPILE_STATUS, &compiled);

    if (compiled == 0) {
        return error.ShaderCompilationFailed;
    }

    return handle;
}

pub fn setUniform1i(self: Self, location: []const u8, v0: gl.int) void {
    const location2 = self.uniforms.get(location) orelse {
        std.debug.panic("Unknown uniform '{s}'", .{location});
    };

    self.bind();
    gl.Uniform1i(location2, v0);
}

pub fn setUniform2i(self: Self, location: []const u8, v0: gl.int, v1: gl.int) void {
    const location2 = self.uniforms.get(location) orelse {
        std.debug.panic("Unknown uniform '{s}'", .{location});
    };

    self.bind();
    gl.Uniform2i(location2, v0, v1);
}

pub fn setUniform3i(self: Self, location: []const u8, v0: gl.int, v1: gl.int, v2: gl.int) void {
    const location2 = self.uniforms.get(location) orelse {
        std.debug.panic("Unknown uniform '{s}'", .{location});
    };

    self.bind();
    gl.Uniform3i(location2, v0, v1, v2);
}

pub fn setUniform4i(self: Self, location: []const u8, v0: gl.int, v1: gl.int, v2: gl.int, v3: gl.int) void {
    const location2 = self.uniforms.get(location) orelse {
        std.debug.panic("Unknown uniform '{s}'", .{location});
    };

    self.bind();
    gl.Uniform4i(location2, v0, v1, v2, v3);
}

pub fn setUniform1ui(self: Self, location: []const u8, v0: gl.uint) void {
    const location2 = self.uniforms.get(location) orelse {
        std.debug.panic("Unknown uniform '{s}'", .{location});
    };

    self.bind();
    gl.Uniform1ui(location2, v0);
}

pub fn setUniform2ui(self: Self, location: []const u8, v0: gl.uint, v1: gl.uint) void {
    const location2 = self.uniforms.get(location) orelse {
        std.debug.panic("Unknown uniform '{s}'", .{location});
    };

    self.bind();
    gl.Uniform2ui(location2, v0, v1);
}

pub fn setUniform3ui(self: Self, location: []const u8, v0: gl.uint, v1: gl.uint, v2: gl.uint) void {
    const location2 = self.uniforms.get(location) orelse {
        std.debug.panic("Unknown uniform '{s}'", .{location});
    };

    self.bind();
    gl.Uniform3ui(location2, v0, v1, v2);
}

pub fn setUniform4ui(self: Self, location: []const u8, v0: gl.uint, v1: gl.uint, v2: gl.uint, v3: gl.uint) void {
    const location2 = self.uniforms.get(location) orelse {
        std.debug.panic("Unknown uniform '{s}'", .{location});
    };

    self.bind();
    gl.Uniform4ui(location2, v0, v1, v2, v3);
}

pub fn setUniform1f(self: Self, location: []const u8, v0: gl.float) void {
    const location2 = self.uniforms.get(location) orelse {
        std.debug.panic("Unknown uniform '{s}'", .{location});
    };

    self.bind();
    gl.Uniform1f(location2, v0);
}

pub fn setUniform2f(self: Self, location: []const u8, v0: gl.float, v1: gl.float) void {
    const location2 = self.uniforms.get(location) orelse {
        std.debug.panic("Unknown uniform '{s}'", .{location});
    };

    self.bind();
    gl.Uniform2f(location2, v0, v1);
}

pub fn setUniform3f(self: Self, location: []const u8, v0: gl.float, v1: gl.float, v2: gl.float) void {
    const location2 = self.uniforms.get(location) orelse {
        std.debug.panic("Unknown uniform '{s}'", .{location});
    };

    self.bind();
    gl.Uniform3f(location2, v0, v1, v2);
}

pub fn setUniform4f(self: Self, location: []const u8, v0: gl.float, v1: gl.float, v2: gl.float, v3: gl.float) void {
    const location2 = self.uniforms.get(location) orelse {
        std.debug.panic("Unknown uniform '{s}'", .{location});
    };

    self.bind();
    gl.Uniform4f(location2, v0, v1, v2, v3);
}

pub fn setUniformMatrix4f(self: Self, location: []const u8, matrix: Matrix4x4f) void {
    const location2 = self.uniforms.get(location) orelse {
        std.debug.panic("Unknown uniform '{s}'", .{location});
    };

    self.bind();
    gl.UniformMatrix4fv(location2, 1, 0, @ptrCast(&matrix.data));
}

pub fn bind(self: Self) void {
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
