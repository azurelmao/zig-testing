const std = @import("std");
const gl = @import("gl");
const Vec3f = @import("vec3f.zig").Vec3f;
const WorldMesh = @import("WorldMesh.zig");
const ShaderStorageBufferWithArrayList = @import("shader_storage_buffer.zig").ShaderStorageBufferWithArrayList;

pub var addition_nodes: ShaderStorageBufferWithArrayList(Vec3f) = undefined;
pub var removal_nodes: ShaderStorageBufferWithArrayList(Vec3f) = undefined;
pub var visible_chunk_mesh_positions: ShaderStorageBufferWithArrayList(Vec3f) = undefined;
pub var upload_nodes: bool = false;

pub fn init(gpa: std.mem.Allocator) !void {
    addition_nodes = try .init(gpa, 10_000, gl.DYNAMIC_STORAGE_BIT);
    removal_nodes = try .init(gpa, 10_000, gl.DYNAMIC_STORAGE_BIT);
    visible_chunk_mesh_positions = try .init(gpa, WorldMesh.WorldMeshLayer.INITIAL_COMMAND_SIZE, gl.DYNAMIC_STORAGE_BIT);
}
