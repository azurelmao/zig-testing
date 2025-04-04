const gl = @import("gl");

const Screen = @This();

const INITIAL_WINDOW_WIDTH = 640.0;
const INITIAL_WINDOW_HEIGHT = 480.0;

window_width: gl.sizei = INITIAL_WINDOW_WIDTH,
window_height: gl.sizei = INITIAL_WINDOW_HEIGHT,
window_width_f: gl.float = INITIAL_WINDOW_WIDTH,
window_height_f: gl.float = INITIAL_WINDOW_HEIGHT,

prev_cursor_x: gl.float = INITIAL_WINDOW_WIDTH / 2.0,
prev_cursor_y: gl.float = INITIAL_WINDOW_HEIGHT / 2.0,

aspect_ratio: gl.float = INITIAL_WINDOW_WIDTH / INITIAL_WINDOW_HEIGHT,

pub fn calcAspectRatio(self: *Screen) void {
    self.aspect_ratio = self.window_width_f / self.window_height_f;
}
