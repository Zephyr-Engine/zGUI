const types = @import("../core/types.zig");

pub const MouseButton = enum {
    left,
    right,
    middle,
};

pub const Key = enum {
    unknown,
    escape,
    enter,
    tab,
    backspace,
    delete,
    left,
    right,
    up,
    down,
    a,
    b,
    c,
};

pub const CursorKind = enum {
    arrow,
    hand,
    text,
    resize_x,
    resize_y,
    resize_diag_a,
    resize_diag_b,
};

pub const PlatformEvent = union(enum) {
    mouse_move: types.Vec2,
    mouse_down: MouseButton,
    mouse_up: MouseButton,
    scroll: types.Vec2,
    key_down: Key,
    key_up: Key,
    text_input: []const u8,
    window_resize: types.Vec2,
    window_close,
};
