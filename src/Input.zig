const std = @import("std");
const glfw = @import("glfw");

const Input = @This();

bindings: std.AutoHashMapUnmanaged(KeyBinding, KeyAction),

/// Pressed keys will be held until they are released.
/// This is what continuous actions like movement should use.
/// Valid states are true (.press) and false (.release).
cached_keys: std.EnumArray(KeyAction, bool),

/// Pressed keys will be held until the next frame.
/// This is what text input or one-time actions like toggles should use.
/// Valid states are .press, .repeat, and .release.
uncached_keys: std.EnumArray(KeyAction, glfw.Action),

pub fn init(gpa: std.mem.Allocator) !Input {
    var bindings: std.AutoHashMapUnmanaged(KeyBinding, KeyAction) = .empty;
    try bindings.put(gpa, .initKey(.escape), .close_window);
    try bindings.put(gpa, .initKey(.q), .pause);

    try bindings.put(gpa, .initKey(.F4), .toggle_chunk_borders);
    try bindings.put(gpa, .initKey(.F3), .toggle_light_removal_nodes);
    try bindings.put(gpa, .initKey(.F2), .toggle_light_addition_nodes);
    try bindings.put(gpa, .initKey(.F1), .toggle_relative_selector);

    try bindings.put(gpa, .initKey(.one), .slot_1);
    try bindings.put(gpa, .initKey(.two), .slot_2);
    try bindings.put(gpa, .initKey(.three), .slot_3);
    try bindings.put(gpa, .initKey(.four), .slot_4);
    try bindings.put(gpa, .initKey(.five), .slot_5);
    try bindings.put(gpa, .initKey(.six), .slot_6);
    try bindings.put(gpa, .initKey(.seven), .slot_7);

    try bindings.put(gpa, .initKey(.kp_2), .move_selector_west);
    try bindings.put(gpa, .initKey(.kp_8), .move_selector_east);
    try bindings.put(gpa, .initKey(.kp_3), .move_selector_down);
    try bindings.put(gpa, .initKey(.kp_9), .move_selector_up);
    try bindings.put(gpa, .initKey(.kp_4), .move_selector_north);
    try bindings.put(gpa, .initKey(.kp_6), .move_selector_south);

    try bindings.put(gpa, .initKey(.a), .move_camera_left);
    try bindings.put(gpa, .initKey(.d), .move_camera_right);
    try bindings.put(gpa, .initKey(.left_shift), .move_camera_down);
    try bindings.put(gpa, .initKey(.space), .move_camera_up);
    try bindings.put(gpa, .initKey(.s), .move_camera_backward);
    try bindings.put(gpa, .initKey(.w), .move_camera_forward);

    try bindings.put(gpa, .initButton(.left), .primary_action);
    try bindings.put(gpa, .initButton(.right), .secondary_action);

    return .{
        .bindings = bindings,
        .cached_keys = .initFill(false),
        .uncached_keys = .initFill(.release),
    };
}

pub fn set(self: *Input, key_or_button: KeyOrButton, action: glfw.Action) void {
    if (self.bindings.get(.{ .key_or_button = key_or_button })) |key_action| {
        switch (action) {
            .press => self.cached_keys.set(key_action, true),
            .release => self.cached_keys.set(key_action, false),
            else => {},
        }

        self.uncached_keys.set(key_action, action);
    }
}

/// Pressed keys will be held until they are released.
/// This is what continuous actions like movement should use.
/// Valid states are true (.press) and false (.release).
pub fn getCached(self: *Input, key_action: KeyAction) bool {
    return self.cached_keys.get(key_action);
}

/// Pressed keys will be held until the next frame.
/// This is what text input or one-time actions like toggles should use.
/// Valid states are .press, .repeat, and .release.
pub fn getUncached(self: *Input, key_action: KeyAction) glfw.Action {
    return self.uncached_keys.get(key_action);
}

pub fn resetUncachedKeys(self: *Input) void {
    self.uncached_keys = .initFill(.release);
}

const KeyOrButton = union(enum) {
    key: glfw.Key,
    button: glfw.MouseButton,
};

const KeyBinding = struct {
    key_or_button: KeyOrButton,

    pub fn initKey(key: glfw.Key) KeyBinding {
        return .{
            .key_or_button = .{ .key = key },
        };
    }

    pub fn initButton(button: glfw.MouseButton) KeyBinding {
        return .{
            .key_or_button = .{ .button = button },
        };
    }
};

const KeyAction = enum {
    close_window,
    pause,

    toggle_chunk_borders,
    toggle_light_removal_nodes,
    toggle_light_addition_nodes,
    toggle_relative_selector,

    slot_1,
    slot_2,
    slot_3,
    slot_4,
    slot_5,
    slot_6,
    slot_7,

    move_selector_west,
    move_selector_east,
    move_selector_down,
    move_selector_up,
    move_selector_north,
    move_selector_south,

    move_camera_left,
    move_camera_right,
    move_camera_down,
    move_camera_up,
    move_camera_backward,
    move_camera_forward,

    primary_action,
    secondary_action,
};
