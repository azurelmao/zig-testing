const gl = @import("gl");
const Vec3f = @import("vec3f.zig").Vec3f;
const Matrix4x4f = @import("matrix4x4f.zig").Matrix4x4f;

const UniformBuffer = @This();

handle: gl.uint,

const Data = extern struct {
    view_projection_matrix: Matrix4x4f,
    selected_block_pos: Vec3f,
};

pub fn init(index: gl.uint) UniformBuffer {
    var handle: gl.uint = undefined;
    gl.CreateBuffers(1, @ptrCast(&handle));
    gl.NamedBufferStorage(handle, @sizeOf(Data), null, gl.DYNAMIC_STORAGE_BIT);
    gl.BindBufferBase(gl.UNIFORM_BUFFER, index, handle);

    return .{
        .handle = handle,
    };
}

pub fn uploadViewProjectionMatrix(self: UniformBuffer, view_projection_matrix: Matrix4x4f) void {
    gl.NamedBufferSubData(self.handle, 0, @sizeOf(Matrix4x4f), @ptrCast(&view_projection_matrix));
}

pub fn uploadSelectedBlockPos(self: UniformBuffer, selected_block_pos: Vec3f) void {
    gl.NamedBufferSubData(self.handle, @sizeOf(Matrix4x4f), @sizeOf(Vec3f), @ptrCast(&selected_block_pos));
}
