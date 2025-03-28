const std = @import("std");
const gl = @import("gl");
const ShaderStorageBuffer = @import("shader_storage_buffer.zig").ShaderStorageBuffer;

pub const Text = struct {
    text: []const u8,
    pixel_x: i32,
    pixel_y: i32,

    pub fn new(text: []const u8, pixel_x: i32, pixel_y: i32) Text {
        return .{
            .text = text,
            .pixel_x = pixel_x,
            .pixel_y = pixel_y,
        };
    }

    pub const Vertex = struct {
        x: gl.float,
        y: gl.float,
        u: gl.float,
        v: gl.float,
        idx: gl.uint,
    };
};

pub const TextManager = struct {
    text_list: std.ArrayListUnmanaged(Text),
    text_vertices: ShaderStorageBuffer(Text.Vertex),

    pub fn init() TextManager {
        return .{
            .text_list = .empty,
            .text_vertices = .init(gl.DYNAMIC_STORAGE_BIT),
        };
    }

    pub fn append(self: *TextManager, allocator: std.mem.Allocator, text: Text) !void {
        try self.text_list.append(allocator, text);
    }

    pub fn clear(self: *TextManager) void {
        self.text_vertices.buffer.clearRetainingCapacity();
        self.text_list.clearRetainingCapacity();
    }

    pub fn buildVertices(self: *TextManager, allocator: std.mem.Allocator, window_width: gl.sizei, window_height: gl.sizei, ui_scale: gl.sizei) !void {
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

                try self.text_vertices.buffer.appendSlice(allocator, &.{
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
    }
};

pub const Glyph = enum(u8) {
    unknown,
    space,
    bang,
    quote,
    hash,
    dollar,
    percent,
    ampersand,
    apostrophe,
    left_paren,
    right_paren,
    asterisk,
    plus,
    comma,
    minus,
    dot,
    slash,
    zero,
    one,
    two,
    three,
    four,
    five,
    six,
    seven,
    eight,
    nine,
    colon,
    semicolon,
    less_than,
    equal,
    greater_than,
    question,
    at,
    A,
    B,
    C,
    D,
    E,
    F,
    G,
    H,
    I,
    J,
    K,
    L,
    M,
    N,
    O,
    P,
    Q,
    R,
    S,
    T,
    U,
    V,
    W,
    X,
    Y,
    Z,
    left_bracket,
    backslash,
    right_bracket,
    carot,
    underscore,
    grave,
    a,
    b,
    c,
    d,
    e,
    f,
    g,
    h,
    i,
    j,
    k,
    l,
    m,
    n,
    o,
    p,
    q,
    r,
    s,
    t,
    u,
    v,
    w,
    x,
    y,
    z,
    left_curly,
    pipe,
    right_curly,
    tilde,

    pub const len = 96;

    pub fn fromChar(char: u8) Glyph {
        return if (char >= ' ' and char <= '~') @enumFromInt(char - ' ' + 1) else .unknown;
    }

    pub fn idx(self: Glyph) usize {
        return @intFromEnum(self);
    }

    pub fn getWidth(self: Glyph) u31 {
        return switch (self) {
            .bang, .apostrophe, .comma, .dot, .colon, .semicolon, .i, .pipe => 1,

            .left_paren, .right_paren, .one, .left_bracket, .right_bracket, .grave, .l => 2,

            .unknown, .space, .quote, .asterisk, .plus, .minus, .slash, .less_than, .greater_than, .I, .backslash, .carot, .underscore, .j, .k, .t, .v, .left_curly, .right_curly => 3,

            .hash, .dollar, .percent, .ampersand, .at, .M, .O, .Q, .T, .V, .W, .X, .Y, .Z, .m, .w => 5,

            else => 4,
        };
    }
};
