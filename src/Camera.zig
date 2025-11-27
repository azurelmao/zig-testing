const std = @import("std");
const gl = @import("gl");
const Vec3f = @import("vec3f.zig").Vec3f;
const Matrix4x4f = @import("matrix4x4f.zig").Matrix4x4f;
const Chunk = @import("Chunk.zig");

const Camera = @This();

position: Vec3f,
direction: Vec3f,
horizontal_direction: Vec3f,
right: Vec3f,

yaw: gl.float,
pitch: gl.float,

fov_x: gl.float,
near: gl.float,
far: gl.float,

view_matrix: Matrix4x4f,
projection_matrix: Matrix4x4f,
view_projection_matrix: Matrix4x4f,

plane_left: [4]gl.float,
plane_right: [4]gl.float,
plane_bottom: [4]gl.float,
plane_top: [4]gl.float,

pub const up: Vec3f = Vec3f.init(0.0, 1.0, 0.0);
const DEG_TO_RAD: gl.float = std.math.pi / 180.0;

pub fn init(position: Vec3f, yaw: gl.float, pitch: gl.float, aspect_ratio: gl.float) Camera {
    const yaw_rads = yaw * DEG_TO_RAD;
    const pitch_rads = pitch * DEG_TO_RAD;

    const xz_len = std.math.cos(pitch_rads);
    const x = xz_len * std.math.cos(yaw_rads);
    const y = std.math.sin(pitch_rads);
    const z = xz_len * std.math.sin(yaw_rads);

    const direction = Vec3f.init(x, y, z).normalize();
    const horizontal_direction = Vec3f.init(x, 0, z).normalize();
    const right = horizontal_direction.cross(up).normalize();

    const fov_x: gl.float = 90.0;
    const near: gl.float = 0.1;
    const far: gl.float = 32 * Chunk.SIZE * std.math.sqrt(3.0);

    const view_matrix = Matrix4x4f.lookToward(position, direction, up);
    const projection_matrix = Matrix4x4f.perspective(fov_x, aspect_ratio, near, far);
    const view_projection_matrix = view_matrix.multiply(projection_matrix);

    var plane_left: [4]gl.float = undefined;
    var plane_right: [4]gl.float = undefined;
    var plane_bottom: [4]gl.float = undefined;
    var plane_top: [4]gl.float = undefined;

    for (0..4) |i| {
        plane_left[i] = view_projection_matrix.data[i * 4 + 3] + view_projection_matrix.data[i * 4 + 0];
        plane_right[i] = view_projection_matrix.data[i * 4 + 3] - view_projection_matrix.data[i * 4 + 0];
        plane_bottom[i] = view_projection_matrix.data[i * 4 + 3] + view_projection_matrix.data[i * 4 + 1];
        plane_top[i] = view_projection_matrix.data[i * 4 + 3] - view_projection_matrix.data[i * 4 + 1];
    }

    return .{
        .position = position,
        .direction = direction,
        .horizontal_direction = horizontal_direction,
        .right = right,
        .yaw = yaw,
        .pitch = pitch,
        .fov_x = fov_x,
        .near = near,
        .far = far,
        .view_matrix = view_matrix,
        .projection_matrix = projection_matrix,
        .view_projection_matrix = view_projection_matrix,
        .plane_left = plane_left,
        .plane_right = plane_right,
        .plane_bottom = plane_bottom,
        .plane_top = plane_top,
    };
}

pub fn calcDirectionAndRight(self: *Camera) void {
    const yaw_rads = self.yaw * DEG_TO_RAD;
    const pitch_rads = self.pitch * DEG_TO_RAD;

    const xz_len = std.math.cos(pitch_rads);
    const x = xz_len * std.math.cos(yaw_rads);
    const y = std.math.sin(pitch_rads);
    const z = xz_len * std.math.sin(yaw_rads);

    self.direction = Vec3f.init(x, y, z).normalize();
    self.horizontal_direction = Vec3f.init(x, 0, z).normalize();
    self.right = self.horizontal_direction.cross(up).normalize();
}

pub fn calcViewMatrix(self: *Camera) void {
    self.view_matrix.lookTowardInPlace(self.position, self.direction, up);
}

pub fn calcProjectionMatrix(self: *Camera, aspect_ratio: gl.float) void {
    self.projection_matrix.perspectiveInPlace(self.fov_x, aspect_ratio, self.near, self.far);
}

pub fn calcViewProjectionMatrix(self: *Camera) void {
    self.view_projection_matrix = self.view_matrix.multiply(self.projection_matrix);
}

pub fn calcFrustumPlanes(self: *Camera) void {
    for (0..4) |i| {
        self.plane_left[i] = self.view_projection_matrix.data[i * 4 + 3] + self.view_projection_matrix.data[i * 4 + 0];
        self.plane_right[i] = self.view_projection_matrix.data[i * 4 + 3] - self.view_projection_matrix.data[i * 4 + 0];
        self.plane_bottom[i] = self.view_projection_matrix.data[i * 4 + 3] + self.view_projection_matrix.data[i * 4 + 1];
        self.plane_top[i] = self.view_projection_matrix.data[i * 4 + 3] - self.view_projection_matrix.data[i * 4 + 1];
    }
}
