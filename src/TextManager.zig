const std = @import("std");
const gl = @import("gl");
const Glyph = @import("glyph.zig").Glyph;
const ShaderStorageBufferWithArrayList = @import("shader_storage_buffer.zig").ShaderStorageBufferWithArrayList;

const TextManager = @This();

text_list: std.ArrayListUnmanaged(Text),
vertices: ShaderStorageBufferWithArrayList(Text.Vertex),

const Text = struct {
    text: []const u8,
    pixel_x: i32,
    pixel_y: i32,

    const Vertex = struct {
        x: gl.float,
        y: gl.float,
        u: gl.float,
        v: gl.float,
        idx: gl.uint,
    };
};

pub fn init(gpa: std.mem.Allocator) !TextManager {
    return .{
        .text_list = .empty,
        .vertices = try .init(gpa, 100, gl.DYNAMIC_STORAGE_BIT),
    };
}

pub fn append(self: *TextManager, gpa: std.mem.Allocator, text: Text) !void {
    try self.text_list.append(gpa, text);
}

pub fn clear(self: *TextManager) void {
    self.vertices.data.clearRetainingCapacity();
    self.text_list.clearRetainingCapacity();
}

pub fn build(self: *TextManager, gpa: std.mem.Allocator, window_width: gl.sizei, window_height: gl.sizei, ui_scale: gl.sizei) !void {
    const half_window_width = @divTrunc(window_width, 2 * ui_scale);
    const half_window_height = @divTrunc(window_height, 2 * ui_scale);
    const half_window_width_f = @as(gl.float, @floatFromInt(window_width)) / 2.0;
    const half_window_height_f = @as(gl.float, @floatFromInt(window_height)) / 2.0;
    const pixel_height = 6;
    const max_pixel_width = 6;
    const max_width: gl.float = @floatFromInt(max_pixel_width);

    for (self.text_list.items) |text| {
        var pixel_x = text.pixel_x - half_window_width;
        const pixel_y = half_window_height - text.pixel_y - pixel_height;

        const pixel_min_y = pixel_y;
        const pixel_max_y = pixel_y + pixel_height;

        const min_y = @as(gl.float, @floatFromInt(pixel_min_y * ui_scale)) / half_window_height_f;
        const max_y = @as(gl.float, @floatFromInt(pixel_max_y * ui_scale)) / half_window_height_f;

        for (text.text) |char| {
            const glyph = Glyph.fromChar(char);
            const pixel_width: i32 = @intCast(glyph.getWidth());
            const idx: gl.uint = @intCast(glyph.idx());

            const pixel_min_x = pixel_x;
            const pixel_max_x = pixel_x + pixel_width;

            const min_x = @as(gl.float, @floatFromInt(pixel_min_x * ui_scale)) / half_window_width_f;
            const max_x = @as(gl.float, @floatFromInt(pixel_max_x * ui_scale)) / half_window_width_f;

            const width: gl.float = @floatFromInt(pixel_width);
            const max_u = width / max_width;

            try self.vertices.data.appendSlice(gpa, &.{
                .{ .x = max_x, .y = max_y, .u = max_u, .v = 0, .idx = idx },
                .{ .x = min_x, .y = max_y, .u = 0, .v = 0, .idx = idx },
                .{ .x = min_x, .y = min_y, .u = 0, .v = 1, .idx = idx },
                .{ .x = min_x, .y = min_y, .u = 0, .v = 1, .idx = idx },
                .{ .x = max_x, .y = min_y, .u = max_u, .v = 1, .idx = idx },
                .{ .x = max_x, .y = max_y, .u = max_u, .v = 0, .idx = idx },
            });

            pixel_x += pixel_width + 1;
        }
    }

    self.vertices.ssbo.upload(self.vertices.data.items) catch {
        self.vertices.ssbo.resize(self.vertices.data.items.len, 6 * 20);
        self.vertices.ssbo.upload(self.vertices.data.items) catch unreachable;
    };

    self.vertices.ssbo.bind(14);
}
