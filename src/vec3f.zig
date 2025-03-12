const std = @import("std");
const gl = @import("gl");
const Chunk = @import("Chunk.zig");
const World = @import("World.zig");

pub const Vec3f = packed struct(u128) {
    x: gl.float,
    y: gl.float,
    z: gl.float,
    _: gl.float = 0,

    const Self = @This();

    pub fn new(x: gl.float, y: gl.float, z: gl.float) Self {
        return .{
            .x = x,
            .y = y,
            .z = z,
        };
    }

    pub fn fromScalar(scalar: gl.float) Self {
        return .{
            .x = scalar,
            .y = scalar,
            .z = scalar,
        };
    }

    pub fn toChunkPos(self: Self) Chunk.Pos {
        const x = @as(i11, @intFromFloat(@floor(self.x))) >> Chunk.BitSize;
        const y = @as(i11, @intFromFloat(@floor(self.y))) >> Chunk.BitSize;
        const z = @as(i11, @intFromFloat(@floor(self.z))) >> Chunk.BitSize;

        return .{
            .x = x,
            .y = y,
            .z = z,
        };
    }

    pub fn toWorldPos(self: Self) World.Pos {
        return .{
            .x = @intFromFloat(@floor(self.x)),
            .y = @intFromFloat(@floor(self.y)),
            .z = @intFromFloat(@floor(self.z)),
        };
    }

    pub fn floor(self: Self) Self {
        return .{
            .x = @floor(self.x),
            .y = @floor(self.y),
            .z = @floor(self.z),
        };
    }

    pub fn negate(self: Self) Self {
        return new(-self.x, -self.y, -self.z);
    }

    pub fn negateInPlace(self: *Self) void {
        self.x = -self.x;
        self.y = -self.y;
        self.z = -self.z;
    }

    pub fn add(self: Self, other: Self) Self {
        return new(self.x + other.x, self.y + other.y, self.z + other.z);
    }

    pub fn addInPlace(self: *Self, other: Self) void {
        self.x += other.x;
        self.y += other.y;
        self.z += other.z;
    }

    pub fn addScalar(self: Self, scalar: gl.float) Self {
        return new(self.x + scalar, self.y + scalar, self.z + scalar);
    }

    pub fn addInPlaceScalar(self: *Self, scalar: gl.float) void {
        self.x += scalar;
        self.y += scalar;
        self.z += scalar;
    }

    pub fn subtract(self: Self, other: Self) Self {
        return new(self.x - other.x, self.y - other.y, self.z - other.z);
    }

    pub fn subtractInPlace(self: *Self, other: Self) void {
        self.x -= other.x;
        self.y -= other.y;
        self.z -= other.z;
    }

    pub fn subtractScalar(self: Self, scalar: gl.float) Self {
        return new(self.x - scalar, self.y - scalar, self.z - scalar);
    }

    pub fn subtractInPlaceScalar(self: *Self, scalar: gl.float) void {
        self.x -= scalar;
        self.y -= scalar;
        self.z -= scalar;
    }

    pub fn multiply(self: Self, other: Self) Self {
        return new(self.x * other.x, self.y * other.y, self.z * other.z);
    }

    pub fn multiplyInPlace(self: *Self, other: Self) void {
        self.x *= other.x;
        self.y *= other.y;
        self.z *= other.z;
    }

    pub fn multiplyScalar(self: Self, scalar: gl.float) Self {
        return new(self.x * scalar, self.y * scalar, self.z * scalar);
    }

    pub fn multiplyInPlaceScalar(self: *Self, scalar: gl.float) void {
        self.x *= scalar;
        self.y *= scalar;
        self.z *= scalar;
    }

    pub fn divide(self: Self, other: Self) Self {
        return new(self.x / other.x, self.y / other.y, self.z / other.z);
    }

    pub fn divideInPlace(self: *Self, other: Self) void {
        self.x /= other.x;
        self.y /= other.y;
        self.z /= other.z;
    }

    pub fn divideScalar(self: Self, scalar: gl.float) Self {
        return new(self.x / scalar, self.y / scalar, self.z / scalar);
    }

    pub fn divideInPlaceScalar(self: *Self, scalar: gl.float) void {
        self.x /= scalar;
        self.y /= scalar;
        self.z /= scalar;
    }

    pub fn normalize(self: Self) Self {
        const magnitude1 = self.magnitude();
        return new(self.x / magnitude1, self.y / magnitude1, self.z / magnitude1);
    }

    pub fn normalizeInPlace(self: *Self) void {
        const magnitude1 = self.magnitude();
        self.x /= magnitude1;
        self.y /= magnitude1;
        self.z /= magnitude1;
    }

    pub fn cross(self: Self, other: Self) Self {
        const a1 = self.y * other.z;
        const a2 = self.z * other.y;
        const a3 = self.z * other.x;
        const a4 = self.x * other.z;
        const a5 = self.x * other.y;
        const a6 = self.y * other.x;

        return new(a1 - a2, a3 - a4, a5 - a6);
    }

    pub fn dot(self: Self, other: Self) gl.float {
        return self.x * other.x + self.y * other.y + self.z * other.z;
    }

    pub fn magnitudeSquared(self: Self) gl.float {
        return self.x * self.x + self.y * self.y + self.z * self.z;
    }

    pub fn magnitude(self: Self) gl.float {
        return std.math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z);
    }

    pub fn abs(self: Self) Self {
        return .{
            .x = @abs(self.x),
            .y = @abs(self.y),
            .z = @abs(self.z),
        };
    }
};
