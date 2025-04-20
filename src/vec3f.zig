const std = @import("std");
const gl = @import("gl");
const Chunk = @import("Chunk.zig");
const World = @import("World.zig");

pub const Vec3f = extern struct {
    x: gl.float,
    y: gl.float,
    z: gl.float,
    _: gl.float = undefined,

    pub fn new(x: gl.float, y: gl.float, z: gl.float) Vec3f {
        return .{
            .x = x,
            .y = y,
            .z = z,
        };
    }

    pub fn fromScalar(scalar: gl.float) Vec3f {
        return .{
            .x = scalar,
            .y = scalar,
            .z = scalar,
        };
    }

    pub fn toChunkPos(self: Vec3f) Chunk.Pos {
        const x = @as(i11, @intFromFloat(@floor(self.x))) >> Chunk.BitSize;
        const y = @as(i11, @intFromFloat(@floor(self.y))) >> Chunk.BitSize;
        const z = @as(i11, @intFromFloat(@floor(self.z))) >> Chunk.BitSize;

        return .{
            .x = x,
            .y = y,
            .z = z,
        };
    }

    pub fn toWorldPos(self: Vec3f) World.Pos {
        return .{
            .x = @intFromFloat(@floor(self.x)),
            .y = @intFromFloat(@floor(self.y)),
            .z = @intFromFloat(@floor(self.z)),
        };
    }

    pub fn floor(self: Vec3f) Vec3f {
        return .{
            .x = @floor(self.x),
            .y = @floor(self.y),
            .z = @floor(self.z),
        };
    }

    pub fn negate(self: Vec3f) Vec3f {
        return new(-self.x, -self.y, -self.z);
    }

    pub fn negateInPlace(self: *Vec3f) void {
        self.x = -self.x;
        self.y = -self.y;
        self.z = -self.z;
    }

    pub fn add(self: Vec3f, other: Vec3f) Vec3f {
        return new(self.x + other.x, self.y + other.y, self.z + other.z);
    }

    pub fn addInPlace(self: *Vec3f, other: Vec3f) void {
        self.x += other.x;
        self.y += other.y;
        self.z += other.z;
    }

    pub fn addScalar(self: Vec3f, scalar: gl.float) Vec3f {
        return new(self.x + scalar, self.y + scalar, self.z + scalar);
    }

    pub fn addInPlaceScalar(self: *Vec3f, scalar: gl.float) void {
        self.x += scalar;
        self.y += scalar;
        self.z += scalar;
    }

    pub fn subtract(self: Vec3f, other: Vec3f) Vec3f {
        return new(self.x - other.x, self.y - other.y, self.z - other.z);
    }

    pub fn subtractInPlace(self: *Vec3f, other: Vec3f) void {
        self.x -= other.x;
        self.y -= other.y;
        self.z -= other.z;
    }

    pub fn subtractScalar(self: Vec3f, scalar: gl.float) Vec3f {
        return new(self.x - scalar, self.y - scalar, self.z - scalar);
    }

    pub fn subtractInPlaceScalar(self: *Vec3f, scalar: gl.float) void {
        self.x -= scalar;
        self.y -= scalar;
        self.z -= scalar;
    }

    pub fn multiply(self: Vec3f, other: Vec3f) Vec3f {
        return new(self.x * other.x, self.y * other.y, self.z * other.z);
    }

    pub fn multiplyInPlace(self: *Vec3f, other: Vec3f) void {
        self.x *= other.x;
        self.y *= other.y;
        self.z *= other.z;
    }

    pub fn multiplyScalar(self: Vec3f, scalar: gl.float) Vec3f {
        return new(self.x * scalar, self.y * scalar, self.z * scalar);
    }

    pub fn multiplyInPlaceScalar(self: *Vec3f, scalar: gl.float) void {
        self.x *= scalar;
        self.y *= scalar;
        self.z *= scalar;
    }

    pub fn divide(self: Vec3f, other: Vec3f) Vec3f {
        return new(self.x / other.x, self.y / other.y, self.z / other.z);
    }

    pub fn divideInPlace(self: *Vec3f, other: Vec3f) void {
        self.x /= other.x;
        self.y /= other.y;
        self.z /= other.z;
    }

    pub fn divideScalar(self: Vec3f, scalar: gl.float) Vec3f {
        return new(self.x / scalar, self.y / scalar, self.z / scalar);
    }

    pub fn divideInPlaceScalar(self: *Vec3f, scalar: gl.float) void {
        self.x /= scalar;
        self.y /= scalar;
        self.z /= scalar;
    }

    pub fn normalize(self: Vec3f) Vec3f {
        const magnitude1 = self.magnitude();
        return new(self.x / magnitude1, self.y / magnitude1, self.z / magnitude1);
    }

    pub fn normalizeInPlace(self: *Vec3f) void {
        const magnitude1 = self.magnitude();
        self.x /= magnitude1;
        self.y /= magnitude1;
        self.z /= magnitude1;
    }

    pub fn cross(self: Vec3f, other: Vec3f) Vec3f {
        const a1 = self.y * other.z;
        const a2 = self.z * other.y;
        const a3 = self.z * other.x;
        const a4 = self.x * other.z;
        const a5 = self.x * other.y;
        const a6 = self.y * other.x;

        return new(a1 - a2, a3 - a4, a5 - a6);
    }

    pub fn dot(self: Vec3f, other: Vec3f) gl.float {
        return self.x * other.x + self.y * other.y + self.z * other.z;
    }

    pub fn magnitudeSquared(self: Vec3f) gl.float {
        return self.x * self.x + self.y * self.y + self.z * self.z;
    }

    pub fn magnitude(self: Vec3f) gl.float {
        return std.math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z);
    }

    pub fn abs(self: Vec3f) Vec3f {
        return .{
            .x = @abs(self.x),
            .y = @abs(self.y),
            .z = @abs(self.z),
        };
    }
};
