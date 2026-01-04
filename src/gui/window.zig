const std = @import("std");
const c = @import("c.zig");
const glfw = c.glfw;

pub const Window = struct {
    handle: *glfw.GLFWwindow,

    pub fn init() !void {
        if (glfw.glfwInit() == 0) {
            return error.WindowInitFailed;
        }
    }

    pub fn deinit() void {
        glfw.glfwTerminate();
    }

    pub fn create(width: i32, height: i32, title: [*c]const u8) !Window {
        glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MAJOR, 3);
        glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MINOR, 3);
        glfw.glfwWindowHint(glfw.GLFW_OPENGL_PROFILE, glfw.GLFW_OPENGL_CORE_PROFILE);
        glfw.glfwWindowHint(glfw.GLFW_SAMPLES, 4);

        const handle = glfw.glfwCreateWindow(width, height, title, null, null);
        if (handle == null) {
            return error.WindowCreationFailed;
        }

        return Window{ .handle = handle.? };
    }

    pub fn destroy(self: Window) void {
        glfw.glfwDestroyWindow(self.handle);
    }

    pub fn makeContextCurrent(self: Window) void {
        glfw.glfwMakeContextCurrent(self.handle);
    }

    pub fn setSwapInterval(interval: i32) void {
        glfw.glfwSwapInterval(interval);
    }

    pub fn shouldClose(self: Window) bool {
        return glfw.glfwWindowShouldClose(self.handle) != 0;
    }

    pub fn pollEvents() void {
        glfw.glfwPollEvents();
    }

    pub fn swapBuffers(self: Window) void {
        glfw.glfwSwapBuffers(self.handle);
    }

    pub fn getSize(self: Window, width: *i32, height: *i32) void {
        glfw.glfwGetWindowSize(self.handle, width, height);
    }

    pub fn getFramebufferSize(self: Window, width: *i32, height: *i32) void {
        glfw.glfwGetFramebufferSize(self.handle, width, height);
    }

    pub fn getCursorPos(self: Window, x: *f64, y: *f64) void {
        glfw.glfwGetCursorPos(self.handle, x, y);
    }

    pub fn getMouseButton(self: Window, button: MouseButton) ButtonState {
        const state = glfw.glfwGetMouseButton(self.handle, @intFromEnum(button));
        return if (state == glfw.GLFW_PRESS) .pressed else .released;
    }

    pub fn getClipboardString(self: Window) [*:0]const u8 {
        return glfw.glfwGetClipboardString(self.handle);
    }

    pub fn setClipboardString(self: Window, string: [*c]const u8) void {
        glfw.glfwSetClipboardString(self.handle, string);
    }

    pub fn setUserPointer(self: Window, pointer: ?*anyopaque) void {
        glfw.glfwSetWindowUserPointer(self.handle, pointer);
    }

    pub fn getUserPointer(self: Window) ?*anyopaque {
        return glfw.glfwGetWindowUserPointer(self.handle);
    }

    pub fn setMouseButtonCallback(self: Window, callback: MouseButtonCallbackFn) void {
        _ = glfw.glfwSetMouseButtonCallback(self.handle, callback);
    }

    pub fn setCharCallback(self: Window, callback: CharCallbackFn) void {
        _ = glfw.glfwSetCharCallback(self.handle, callback);
    }

    pub fn setKeyCallback(self: Window, callback: KeyCallbackFn) void {
        _ = glfw.glfwSetKeyCallback(self.handle, callback);
    }

    pub fn setScrollCallback(self: Window, callback: ScrollCallbackFn) void {
        _ = glfw.glfwSetScrollCallback(self.handle, callback);
    }

    pub fn setFramebufferSizeCallback(self: Window, callback: FramebufferSizeCallbackFn) void {
        _ = glfw.glfwSetFramebufferSizeCallback(self.handle, callback);
    }

    pub fn setCursor(self: Window, cursor: ?*Cursor) void {
        glfw.glfwSetCursor(self.handle, @ptrCast(cursor));
    }

    pub fn getProcAddressFunction() *const fn ([*c]const u8) callconv(.c) ?*const fn () callconv(.c) void {
        return &glfw.glfwGetProcAddress;
    }
};

// Cursor management
pub const Cursor = glfw.GLFWcursor;

pub const CursorShape = enum(c_int) {
    arrow = glfw.GLFW_ARROW_CURSOR,
    ibeam = glfw.GLFW_IBEAM_CURSOR,
    crosshair = glfw.GLFW_CROSSHAIR_CURSOR,
    hand = glfw.GLFW_HAND_CURSOR,
    hresize = glfw.GLFW_HRESIZE_CURSOR,
    vresize = glfw.GLFW_VRESIZE_CURSOR,
};

pub fn createStandardCursor(shape: CursorShape) ?*Cursor {
    return glfw.glfwCreateStandardCursor(@intFromEnum(shape));
}

pub fn destroyCursor(cursor: ?*Cursor) void {
    if (cursor) |cur| {
        glfw.glfwDestroyCursor(cur);
    }
}

// Time
pub fn getTime() f64 {
    return glfw.glfwGetTime();
}

// Callback types
pub const MouseButtonCallbackFn = *const fn (?*glfw.GLFWwindow, c_int, c_int, c_int) callconv(.c) void;
pub const CharCallbackFn = *const fn (?*glfw.GLFWwindow, c_uint) callconv(.c) void;
pub const KeyCallbackFn = *const fn (?*glfw.GLFWwindow, c_int, c_int, c_int, c_int) callconv(.c) void;
pub const ScrollCallbackFn = *const fn (?*glfw.GLFWwindow, f64, f64) callconv(.c) void;
pub const FramebufferSizeCallbackFn = *const fn (?*glfw.GLFWwindow, c_int, c_int) callconv(.c) void;

// Input constants
pub const Key = enum(c_int) {
    // Printable keys
    space = glfw.GLFW_KEY_SPACE,
    apostrophe = glfw.GLFW_KEY_APOSTROPHE,
    comma = glfw.GLFW_KEY_COMMA,
    minus = glfw.GLFW_KEY_MINUS,
    period = glfw.GLFW_KEY_PERIOD,
    slash = glfw.GLFW_KEY_SLASH,
    key_0 = glfw.GLFW_KEY_0,
    key_1 = glfw.GLFW_KEY_1,
    key_2 = glfw.GLFW_KEY_2,
    key_3 = glfw.GLFW_KEY_3,
    key_4 = glfw.GLFW_KEY_4,
    key_5 = glfw.GLFW_KEY_5,
    key_6 = glfw.GLFW_KEY_6,
    key_7 = glfw.GLFW_KEY_7,
    key_8 = glfw.GLFW_KEY_8,
    key_9 = glfw.GLFW_KEY_9,
    semicolon = glfw.GLFW_KEY_SEMICOLON,
    equal = glfw.GLFW_KEY_EQUAL,
    a = glfw.GLFW_KEY_A,
    b = glfw.GLFW_KEY_B,
    c = glfw.GLFW_KEY_C,
    d = glfw.GLFW_KEY_D,
    e = glfw.GLFW_KEY_E,
    f = glfw.GLFW_KEY_F,
    g = glfw.GLFW_KEY_G,
    h = glfw.GLFW_KEY_H,
    i = glfw.GLFW_KEY_I,
    j = glfw.GLFW_KEY_J,
    k = glfw.GLFW_KEY_K,
    l = glfw.GLFW_KEY_L,
    m = glfw.GLFW_KEY_M,
    n = glfw.GLFW_KEY_N,
    o = glfw.GLFW_KEY_O,
    p = glfw.GLFW_KEY_P,
    q = glfw.GLFW_KEY_Q,
    r = glfw.GLFW_KEY_R,
    s = glfw.GLFW_KEY_S,
    t = glfw.GLFW_KEY_T,
    u = glfw.GLFW_KEY_U,
    v = glfw.GLFW_KEY_V,
    w = glfw.GLFW_KEY_W,
    x = glfw.GLFW_KEY_X,
    y = glfw.GLFW_KEY_Y,
    z = glfw.GLFW_KEY_Z,
    left_bracket = glfw.GLFW_KEY_LEFT_BRACKET,
    backslash = glfw.GLFW_KEY_BACKSLASH,
    right_bracket = glfw.GLFW_KEY_RIGHT_BRACKET,
    grave_accent = glfw.GLFW_KEY_GRAVE_ACCENT,

    // Function keys
    escape = glfw.GLFW_KEY_ESCAPE,
    enter = glfw.GLFW_KEY_ENTER,
    tab = glfw.GLFW_KEY_TAB,
    backspace = glfw.GLFW_KEY_BACKSPACE,
    insert = glfw.GLFW_KEY_INSERT,
    delete = glfw.GLFW_KEY_DELETE,
    right = glfw.GLFW_KEY_RIGHT,
    left = glfw.GLFW_KEY_LEFT,
    down = glfw.GLFW_KEY_DOWN,
    up = glfw.GLFW_KEY_UP,
    page_up = glfw.GLFW_KEY_PAGE_UP,
    page_down = glfw.GLFW_KEY_PAGE_DOWN,
    home = glfw.GLFW_KEY_HOME,
    end = glfw.GLFW_KEY_END,
    caps_lock = glfw.GLFW_KEY_CAPS_LOCK,
    scroll_lock = glfw.GLFW_KEY_SCROLL_LOCK,
    num_lock = glfw.GLFW_KEY_NUM_LOCK,
    print_screen = glfw.GLFW_KEY_PRINT_SCREEN,
    pause = glfw.GLFW_KEY_PAUSE,
    f1 = glfw.GLFW_KEY_F1,
    f2 = glfw.GLFW_KEY_F2,
    f3 = glfw.GLFW_KEY_F3,
    f4 = glfw.GLFW_KEY_F4,
    f5 = glfw.GLFW_KEY_F5,
    f6 = glfw.GLFW_KEY_F6,
    f7 = glfw.GLFW_KEY_F7,
    f8 = glfw.GLFW_KEY_F8,
    f9 = glfw.GLFW_KEY_F9,
    f10 = glfw.GLFW_KEY_F10,
    f11 = glfw.GLFW_KEY_F11,
    f12 = glfw.GLFW_KEY_F12,

    // Modifier keys
    left_shift = glfw.GLFW_KEY_LEFT_SHIFT,
    left_control = glfw.GLFW_KEY_LEFT_CONTROL,
    left_alt = glfw.GLFW_KEY_LEFT_ALT,
    left_super = glfw.GLFW_KEY_LEFT_SUPER,
    right_shift = glfw.GLFW_KEY_RIGHT_SHIFT,
    right_control = glfw.GLFW_KEY_RIGHT_CONTROL,
    right_alt = glfw.GLFW_KEY_RIGHT_ALT,
    right_super = glfw.GLFW_KEY_RIGHT_SUPER,
    menu = glfw.GLFW_KEY_MENU,
};

pub const MouseButton = enum(c_int) {
    left = glfw.GLFW_MOUSE_BUTTON_LEFT,
    right = glfw.GLFW_MOUSE_BUTTON_RIGHT,
    middle = glfw.GLFW_MOUSE_BUTTON_MIDDLE,
};

pub const ButtonState = enum {
    pressed,
    released,
};

pub const KeyAction = enum(c_int) {
    release = glfw.GLFW_RELEASE,
    press = glfw.GLFW_PRESS,
    repeat = glfw.GLFW_REPEAT,
};

pub const ModifierKey = enum(c_int) {
    shift = glfw.GLFW_MOD_SHIFT,
    control = glfw.GLFW_MOD_CONTROL,
    alt = glfw.GLFW_MOD_ALT,
    super = glfw.GLFW_MOD_SUPER,
    caps_lock = glfw.GLFW_MOD_CAPS_LOCK,
    num_lock = glfw.GLFW_MOD_NUM_LOCK,
};

// Helper to check if modifier is active
pub fn hasModifier(mods: c_int, modifier: ModifierKey) bool {
    return (mods & @intFromEnum(modifier)) != 0;
}
