const std = @import("std");
const gl = @import("gl");
const print = std.debug.print;

const Self = @This();

var currently_bound_vertex_shader: ?gl.uint = null;

pub const Vertex = packed struct(u32) {
    x: u6,
    y: u6,
    z: u6,
    u: u1,
    v: u1,
    _: u12 = 0, // padding
};

handle: gl.uint,
vertices_len: gl.int,

pub fn new(vertices: []const Vertex) !Self {
    const vertices_len = vertices.len;

    if (vertices_len % 3 != 0) {
        return error.NotTriangles;
    }

    if (vertices_len % 6 != 0) {
        return error.NotQuads;
    }

    var handle: gl.uint = undefined;
    gl.CreateVertexArrays(1, &handle);

    var vertex_buffer: gl.uint = undefined;
    gl.CreateBuffers(1, @ptrCast(&vertex_buffer));
    gl.NamedBufferData(vertex_buffer, @intCast(vertices_len * @sizeOf(Vertex)), vertices.ptr, gl.STATIC_DRAW);

    const binding_idx = 0;
    const attrib_idx = 0;

    gl.VertexArrayVertexBuffer(handle, binding_idx, vertex_buffer, 0, @sizeOf(Vertex));

    gl.EnableVertexArrayAttrib(handle, attrib_idx);
    gl.VertexArrayAttribIFormat(handle, attrib_idx, 1, gl.UNSIGNED_INT, 0);
    gl.VertexArrayAttribBinding(handle, attrib_idx, binding_idx);

    return .{ .handle = handle, .vertices_len = @intCast(vertices_len) };
}

pub fn bind(self: Self) void {
    if (currently_bound_vertex_shader) |handle| {
        if (handle != self.handle) {
            currently_bound_vertex_shader = self.handle;
            gl.BindVertexArray(self.handle);
        }
    } else {
        currently_bound_vertex_shader = self.handle;
        gl.BindVertexArray(self.handle);
    }
}
