const std = @import("std");
const gl = @import("gl");

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
