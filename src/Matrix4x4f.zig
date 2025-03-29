const std = @import("std");
const gl = @import("gl");
const Vec3f = @import("vec3f.zig").Vec3f;

const Matrix4x4f = @This();

data: [16]gl.float,

pub fn zero() Matrix4x4f {
    return .{ .data = @splat(0) };
}

pub fn identity() Matrix4x4f {
    var result = zero();
    result.identityInPlace();
    return result;
}

/// `self` has to be a zeroed matrix for the correct matrix to be constructed
pub fn identityInPlace(self: *Matrix4x4f) void {
    self.data[0] = 1;
    self.data[5] = 1;
    self.data[10] = 1;
    self.data[15] = 1;
}

pub fn translation(vec: Vec3f) Matrix4x4f {
    var result = identity();
    result.translationInPlace(vec);
    return result;
}

/// `self` has to be an identity or same matrix for the correct matrix to be constructed
pub fn translationInPlace(self: *Matrix4x4f, vec: Vec3f) void {
    self.data[12] = vec.x;
    self.data[13] = vec.y;
    self.data[14] = vec.z;
}

pub fn lookAt(eye: Vec3f, target: Vec3f, up: Vec3f) Matrix4x4f {
    var result = identity();
    result.lookAtInPlace(eye, target, up);
    return result;
}

/// `self` has to be an identity or same matrix for the correct matrix to be constructed
pub fn lookAtInPlace(self: *Matrix4x4f, eye: Vec3f, target: Vec3f, up: Vec3f) void {
    var forward = eye.subtract(target);
    forward.normalizeInPlace();

    var left = up.cross(forward);
    left.normalizeInPlace();

    const up2 = forward.cross(left);

    self.data[0] = left.x;
    self.data[4] = left.y;
    self.data[8] = left.z;

    self.data[1] = up2.x;
    self.data[5] = up2.y;
    self.data[9] = up2.z;

    self.data[2] = forward.x;
    self.data[6] = forward.y;
    self.data[10] = forward.z;

    self.data[12] = -left.x * eye.x - left.y * eye.y - left.z * eye.z;
    self.data[13] = -up2.x * eye.x - up2.y * eye.y - up2.z * eye.z;
    self.data[14] = -forward.x * eye.x - forward.y * eye.y - forward.z * eye.z;
}

pub fn lookToward(eye: Vec3f, direction: Vec3f, up: Vec3f) Matrix4x4f {
    var result = identity();
    result.lookTowardInPlace(eye, direction, up);
    return result;
}

/// `self` has to be an identity or same matrix for the correct matrix to be constructed
pub fn lookTowardInPlace(self: *Matrix4x4f, eye: Vec3f, direction: Vec3f, up: Vec3f) void {
    var forward = direction.negate();
    forward.normalizeInPlace();

    var left = up.cross(forward);
    left.normalizeInPlace();

    const up2 = forward.cross(left);

    self.data[0] = left.x;
    self.data[4] = left.y;
    self.data[8] = left.z;

    self.data[1] = up2.x;
    self.data[5] = up2.y;
    self.data[9] = up2.z;

    self.data[2] = forward.x;
    self.data[6] = forward.y;
    self.data[10] = forward.z;

    self.data[12] = -left.x * eye.x - left.y * eye.y - left.z * eye.z;
    self.data[13] = -up2.x * eye.x - up2.y * eye.y - up2.z * eye.z;
    self.data[14] = -forward.x * eye.x - forward.y * eye.y - forward.z * eye.z;
}

pub fn perspective(fov_x: gl.float, aspect_ratio: gl.float, near: gl.float, far: gl.float) Matrix4x4f {
    var result = zero();
    result.perspectiveInPlace(fov_x, aspect_ratio, near, far);
    return result;
}

const DEG_TO_RAD: gl.float = std.math.pi / 180.0;

/// `self` has to be a zeroed or same matrix for the correct matrix to be constructed
/// `near` cannot be equal to 0.0
pub fn perspectiveInPlace(self: *Matrix4x4f, fov_x: gl.float, aspect_ratio: gl.float, near: gl.float, far: gl.float) void {
    const tangent = std.math.tan(fov_x / 2 * DEG_TO_RAD);
    const right = near * tangent;
    const top = right / aspect_ratio;

    self.data[0] = near / right;
    self.data[5] = near / top;
    self.data[10] = -(far + near) / (far - near);
    self.data[11] = -1;
    self.data[14] = -(2 * far * near) / (far - near);
    self.data[15] = 0;
}

pub fn multiply(self: Matrix4x4f, other: Matrix4x4f) Matrix4x4f {
    var result = zero();

    for (0..4) |i| {
        for (0..4) |j| {
            var c: gl.float = 0.0;

            for (0..4) |k| {
                c += self.data[i * 4 + k] * other.data[k * 4 + j];
            }

            result.data[i * 4 + j] = c;
        }
    }

    return result;
}

pub fn print(self: *Matrix4x4f) void {
    for (self.data, 0..) |value, idx| {
        if (idx % 4 == 0) {
            std.debug.print("| ", .{});
        }

        std.debug.print("{d}", .{value});

        if (idx % 4 != 3) {
            std.debug.print(", ", .{});
        }

        if (idx % 4 == 3) {
            std.debug.print(" |\n", .{});
        }
    }
}
