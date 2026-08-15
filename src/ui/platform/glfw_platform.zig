const std = @import("std");
const ui = @import("zGUI");
const types = struct {
    const Vec2 = ui.Vec2;
};
const events = struct {
    const PlatformEvent = ui.PlatformEvent;
    const CursorKind = ui.CursorKind;
    const MouseButton = ui.MouseButton;
    const Key = ui.Key;
};

const c = @cImport({
    @cInclude("GLFW/glfw3.h");
});

pub const GlfwPlatform = struct {
    allocator: std.mem.Allocator,
    window: *c.GLFWwindow,
    events: std.ArrayList(events.PlatformEvent) = .empty,
    text_buffer: std.ArrayList(u8) = .empty,
    clipboard_buffer: std.ArrayList(u8) = .empty,
    arrow_cursor: ?*c.GLFWcursor = null,
    hand_cursor: ?*c.GLFWcursor = null,
    text_cursor: ?*c.GLFWcursor = null,
    resize_x_cursor: ?*c.GLFWcursor = null,
    resize_y_cursor: ?*c.GLFWcursor = null,
    callbacks_installed: bool = false,

    pub fn init(
        allocator: std.mem.Allocator,
        width: u32,
        height: u32,
        title: [:0]const u8,
    ) !GlfwPlatform {
        if (c.glfwInit() == 0) return error.GlfwInitFailed;
        errdefer c.glfwTerminate();

        c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 3);
        c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 3);
        c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);
        c.glfwWindowHint(c.GLFW_SAMPLES, 4);

        const window = c.glfwCreateWindow(@intCast(width), @intCast(height), title.ptr, null, null) orelse return error.GlfwCreateWindowFailed;
        errdefer c.glfwDestroyWindow(window);

        c.glfwMakeContextCurrent(window);
        c.glfwSwapInterval(1);

        var self: GlfwPlatform = .{
            .allocator = allocator,
            .window = window,
        };

        self.arrow_cursor = c.glfwCreateStandardCursor(c.GLFW_ARROW_CURSOR);
        self.hand_cursor = c.glfwCreateStandardCursor(c.GLFW_HAND_CURSOR);
        self.text_cursor = c.glfwCreateStandardCursor(c.GLFW_IBEAM_CURSOR);
        self.resize_x_cursor = c.glfwCreateStandardCursor(c.GLFW_HRESIZE_CURSOR);
        self.resize_y_cursor = c.glfwCreateStandardCursor(c.GLFW_VRESIZE_CURSOR);

        return self;
    }

    pub fn deinit(self: *GlfwPlatform) void {
        if (self.arrow_cursor) |cursor| c.glfwDestroyCursor(cursor);
        if (self.hand_cursor) |cursor| c.glfwDestroyCursor(cursor);
        if (self.text_cursor) |cursor| c.glfwDestroyCursor(cursor);
        if (self.resize_x_cursor) |cursor| c.glfwDestroyCursor(cursor);
        if (self.resize_y_cursor) |cursor| c.glfwDestroyCursor(cursor);
        c.glfwDestroyWindow(self.window);
        c.glfwTerminate();
        self.events.deinit(self.allocator);
        self.text_buffer.deinit(self.allocator);
        self.clipboard_buffer.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn pollEvents(self: *GlfwPlatform) []const events.PlatformEvent {
        self.installCallbacks();
        self.events.clearRetainingCapacity();
        self.text_buffer.clearRetainingCapacity();
        c.glfwPollEvents();
        self.repairTextSlices();
        return self.events.items;
    }

    /// Re-points text_input slices at the final text_buffer storage. The
    /// callbacks append to text_buffer as chars arrive, and a growth
    /// reallocation would leave earlier event slices dangling; the lengths
    /// stay valid, so the slices can be rebuilt in order after polling.
    fn repairTextSlices(self: *GlfwPlatform) void {
        var offset: usize = 0;
        for (self.events.items) |*event| {
            switch (event.*) {
                .text_input => |text| {
                    event.* = .{ .text_input = self.text_buffer.items[offset .. offset + text.len] };
                    offset += text.len;
                },
                else => {},
            }
        }
    }

    pub fn getWindowSize(self: *GlfwPlatform) types.Vec2 {
        var width: c_int = 0;
        var height: c_int = 0;
        c.glfwGetWindowSize(self.window, &width, &height);
        return .{ .x = @floatFromInt(width), .y = @floatFromInt(height) };
    }

    pub fn getFramebufferSize(self: *GlfwPlatform) types.Vec2 {
        var width: c_int = 0;
        var height: c_int = 0;
        c.glfwGetFramebufferSize(self.window, &width, &height);
        return .{ .x = @floatFromInt(width), .y = @floatFromInt(height) };
    }

    pub fn getContentScale(self: *GlfwPlatform) types.Vec2 {
        var x_scale: f32 = 1;
        var y_scale: f32 = 1;
        c.glfwGetWindowContentScale(self.window, &x_scale, &y_scale);
        return .{ .x = x_scale, .y = y_scale };
    }

    pub fn setCursor(self: *GlfwPlatform, cursor: events.CursorKind) void {
        const handle = switch (cursor) {
            .arrow => self.arrow_cursor,
            .hand => self.hand_cursor,
            .text => self.text_cursor,
            .resize_x => self.resize_x_cursor,
            .resize_y => self.resize_y_cursor,
            .resize_diag_a, .resize_diag_b => self.arrow_cursor,
        };
        c.glfwSetCursor(self.window, handle);
    }

    pub fn getClipboard(self: *GlfwPlatform) []const u8 {
        const ptr = c.glfwGetClipboardString(self.window) orelse return "";
        return std.mem.span(ptr);
    }

    pub fn setClipboard(self: *GlfwPlatform, text: []const u8) void {
        self.clipboard_buffer.clearRetainingCapacity();
        self.clipboard_buffer.appendSlice(self.allocator, text) catch return;
        self.clipboard_buffer.append(self.allocator, 0) catch return;
        c.glfwSetClipboardString(self.window, @ptrCast(self.clipboard_buffer.items.ptr));
    }

    pub fn clipboard(self: *GlfwPlatform) ui.Clipboard {
        return .{
            .context = self,
            .read_fn = clipboardRead,
            .write_fn = clipboardWrite,
        };
    }

    fn clipboardRead(context: ?*anyopaque) []const u8 {
        const self: *GlfwPlatform = @ptrCast(@alignCast(context orelse return ""));
        return self.getClipboard();
    }

    fn clipboardWrite(context: ?*anyopaque, text: []const u8) void {
        const self: *GlfwPlatform = @ptrCast(@alignCast(context orelse return));
        self.setClipboard(text);
    }

    pub fn swapBuffers(self: *GlfwPlatform) void {
        c.glfwSwapBuffers(self.window);
    }

    pub fn shouldClose(self: *GlfwPlatform) bool {
        return c.glfwWindowShouldClose(self.window) != 0;
    }

    pub fn makeContextCurrent(self: *GlfwPlatform) void {
        c.glfwMakeContextCurrent(self.window);
    }

    pub fn installCallbacks(self: *GlfwPlatform) void {
        if (self.callbacks_installed) return;
        c.glfwSetWindowUserPointer(self.window, self);
        _ = c.glfwSetCursorPosCallback(self.window, cursorPosCallback);
        _ = c.glfwSetMouseButtonCallback(self.window, mouseButtonCallback);
        _ = c.glfwSetScrollCallback(self.window, scrollCallback);
        _ = c.glfwSetKeyCallback(self.window, keyCallback);
        _ = c.glfwSetCharCallback(self.window, charCallback);
        _ = c.glfwSetWindowSizeCallback(self.window, windowSizeCallback);
        _ = c.glfwSetWindowCloseCallback(self.window, windowCloseCallback);
        self.callbacks_installed = true;
    }

    pub fn getProcAddress(name: [*:0]const u8) ?*const anyopaque {
        return @ptrCast(c.glfwGetProcAddress(name));
    }

    fn appendEvent(self: *GlfwPlatform, event: events.PlatformEvent) void {
        self.events.append(self.allocator, event) catch {};
    }

    fn fromWindow(window: ?*c.GLFWwindow) ?*GlfwPlatform {
        const raw = c.glfwGetWindowUserPointer(window) orelse return null;
        return @ptrCast(@alignCast(raw));
    }

    fn cursorPosCallback(window: ?*c.GLFWwindow, x: f64, y: f64) callconv(.c) void {
        const self = fromWindow(window) orelse return;
        self.appendEvent(.{ .mouse_move = .{ .x = @floatCast(x), .y = @floatCast(y) } });
    }

    fn mouseButtonCallback(window: ?*c.GLFWwindow, button: c_int, action: c_int, mods: c_int) callconv(.c) void {
        _ = mods;
        const self = fromWindow(window) orelse return;
        const mouse_button = switch (button) {
            c.GLFW_MOUSE_BUTTON_LEFT => events.MouseButton.left,
            c.GLFW_MOUSE_BUTTON_RIGHT => events.MouseButton.right,
            c.GLFW_MOUSE_BUTTON_MIDDLE => events.MouseButton.middle,
            else => return,
        };
        if (action == c.GLFW_PRESS) {
            self.appendEvent(.{ .mouse_down = mouse_button });
        } else if (action == c.GLFW_RELEASE) {
            self.appendEvent(.{ .mouse_up = mouse_button });
        }
    }

    fn scrollCallback(window: ?*c.GLFWwindow, x: f64, y: f64) callconv(.c) void {
        const self = fromWindow(window) orelse return;
        self.appendEvent(.{ .scroll = .{ .x = @floatCast(x), .y = @floatCast(y) } });
    }

    fn keyCallback(window: ?*c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.c) void {
        _ = scancode;
        _ = mods;
        const self = fromWindow(window) orelse return;
        const mapped = mapKey(key);
        if (action == c.GLFW_PRESS or action == c.GLFW_REPEAT) {
            self.appendEvent(.{ .key_down = mapped });
        } else if (action == c.GLFW_RELEASE) {
            self.appendEvent(.{ .key_up = mapped });
        }
    }

    fn charCallback(window: ?*c.GLFWwindow, codepoint: c_uint) callconv(.c) void {
        const self = fromWindow(window) orelse return;
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(@intCast(codepoint), &buf) catch return;
        const start = self.text_buffer.items.len;
        self.text_buffer.appendSlice(self.allocator, buf[0..len]) catch return;
        self.appendEvent(.{ .text_input = self.text_buffer.items[start .. start + len] });
    }

    fn windowSizeCallback(window: ?*c.GLFWwindow, width: c_int, height: c_int) callconv(.c) void {
        const self = fromWindow(window) orelse return;
        self.appendEvent(.{ .window_resize = .{ .x = @floatFromInt(width), .y = @floatFromInt(height) } });
    }

    fn windowCloseCallback(window: ?*c.GLFWwindow) callconv(.c) void {
        const self = fromWindow(window) orelse return;
        self.appendEvent(.window_close);
    }
};

fn mapKey(key: c_int) events.Key {
    return switch (key) {
        c.GLFW_KEY_SPACE => .space,
        c.GLFW_KEY_APOSTROPHE => .apostrophe,
        c.GLFW_KEY_COMMA => .comma,
        c.GLFW_KEY_MINUS => .minus,
        c.GLFW_KEY_PERIOD => .period,
        c.GLFW_KEY_SLASH => .slash,
        c.GLFW_KEY_0 => .num_0,
        c.GLFW_KEY_1 => .num_1,
        c.GLFW_KEY_2 => .num_2,
        c.GLFW_KEY_3 => .num_3,
        c.GLFW_KEY_4 => .num_4,
        c.GLFW_KEY_5 => .num_5,
        c.GLFW_KEY_6 => .num_6,
        c.GLFW_KEY_7 => .num_7,
        c.GLFW_KEY_8 => .num_8,
        c.GLFW_KEY_9 => .num_9,
        c.GLFW_KEY_SEMICOLON => .semicolon,
        c.GLFW_KEY_EQUAL => .equal,
        c.GLFW_KEY_A => .a,
        c.GLFW_KEY_B => .b,
        c.GLFW_KEY_C => .c,
        c.GLFW_KEY_D => .d,
        c.GLFW_KEY_E => .e,
        c.GLFW_KEY_F => .f,
        c.GLFW_KEY_G => .g,
        c.GLFW_KEY_H => .h,
        c.GLFW_KEY_I => .i,
        c.GLFW_KEY_J => .j,
        c.GLFW_KEY_K => .k,
        c.GLFW_KEY_L => .l,
        c.GLFW_KEY_M => .m,
        c.GLFW_KEY_N => .n,
        c.GLFW_KEY_O => .o,
        c.GLFW_KEY_P => .p,
        c.GLFW_KEY_Q => .q,
        c.GLFW_KEY_R => .r,
        c.GLFW_KEY_S => .s,
        c.GLFW_KEY_T => .t,
        c.GLFW_KEY_U => .u,
        c.GLFW_KEY_V => .v,
        c.GLFW_KEY_W => .w,
        c.GLFW_KEY_X => .x,
        c.GLFW_KEY_Y => .y,
        c.GLFW_KEY_Z => .z,
        c.GLFW_KEY_LEFT_BRACKET => .left_bracket,
        c.GLFW_KEY_BACKSLASH => .backslash,
        c.GLFW_KEY_RIGHT_BRACKET => .right_bracket,
        c.GLFW_KEY_GRAVE_ACCENT => .grave_accent,
        c.GLFW_KEY_WORLD_1 => .world_1,
        c.GLFW_KEY_WORLD_2 => .world_2,
        c.GLFW_KEY_ESCAPE => .escape,
        c.GLFW_KEY_ENTER => .enter,
        c.GLFW_KEY_TAB => .tab,
        c.GLFW_KEY_BACKSPACE => .backspace,
        c.GLFW_KEY_INSERT => .insert,
        c.GLFW_KEY_DELETE => .delete,
        c.GLFW_KEY_LEFT => .left,
        c.GLFW_KEY_RIGHT => .right,
        c.GLFW_KEY_UP => .up,
        c.GLFW_KEY_DOWN => .down,
        c.GLFW_KEY_PAGE_UP => .page_up,
        c.GLFW_KEY_PAGE_DOWN => .page_down,
        c.GLFW_KEY_HOME => .home,
        c.GLFW_KEY_END => .end,
        c.GLFW_KEY_CAPS_LOCK => .caps_lock,
        c.GLFW_KEY_SCROLL_LOCK => .scroll_lock,
        c.GLFW_KEY_NUM_LOCK => .num_lock,
        c.GLFW_KEY_PRINT_SCREEN => .print_screen,
        c.GLFW_KEY_PAUSE => .pause,
        c.GLFW_KEY_F1 => .f1,
        c.GLFW_KEY_F2 => .f2,
        c.GLFW_KEY_F3 => .f3,
        c.GLFW_KEY_F4 => .f4,
        c.GLFW_KEY_F5 => .f5,
        c.GLFW_KEY_F6 => .f6,
        c.GLFW_KEY_F7 => .f7,
        c.GLFW_KEY_F8 => .f8,
        c.GLFW_KEY_F9 => .f9,
        c.GLFW_KEY_F10 => .f10,
        c.GLFW_KEY_F11 => .f11,
        c.GLFW_KEY_F12 => .f12,
        c.GLFW_KEY_F13 => .f13,
        c.GLFW_KEY_F14 => .f14,
        c.GLFW_KEY_F15 => .f15,
        c.GLFW_KEY_F16 => .f16,
        c.GLFW_KEY_F17 => .f17,
        c.GLFW_KEY_F18 => .f18,
        c.GLFW_KEY_F19 => .f19,
        c.GLFW_KEY_F20 => .f20,
        c.GLFW_KEY_F21 => .f21,
        c.GLFW_KEY_F22 => .f22,
        c.GLFW_KEY_F23 => .f23,
        c.GLFW_KEY_F24 => .f24,
        c.GLFW_KEY_F25 => .f25,
        c.GLFW_KEY_KP_0 => .kp_0,
        c.GLFW_KEY_KP_1 => .kp_1,
        c.GLFW_KEY_KP_2 => .kp_2,
        c.GLFW_KEY_KP_3 => .kp_3,
        c.GLFW_KEY_KP_4 => .kp_4,
        c.GLFW_KEY_KP_5 => .kp_5,
        c.GLFW_KEY_KP_6 => .kp_6,
        c.GLFW_KEY_KP_7 => .kp_7,
        c.GLFW_KEY_KP_8 => .kp_8,
        c.GLFW_KEY_KP_9 => .kp_9,
        c.GLFW_KEY_KP_DECIMAL => .kp_decimal,
        c.GLFW_KEY_KP_DIVIDE => .kp_divide,
        c.GLFW_KEY_KP_MULTIPLY => .kp_multiply,
        c.GLFW_KEY_KP_SUBTRACT => .kp_subtract,
        c.GLFW_KEY_KP_ADD => .kp_add,
        c.GLFW_KEY_KP_ENTER => .kp_enter,
        c.GLFW_KEY_KP_EQUAL => .kp_equal,
        c.GLFW_KEY_LEFT_SHIFT => .left_shift,
        c.GLFW_KEY_LEFT_CONTROL => .left_control,
        c.GLFW_KEY_LEFT_ALT => .left_alt,
        c.GLFW_KEY_LEFT_SUPER => .left_super,
        c.GLFW_KEY_RIGHT_SHIFT => .right_shift,
        c.GLFW_KEY_RIGHT_CONTROL => .right_control,
        c.GLFW_KEY_RIGHT_ALT => .right_alt,
        c.GLFW_KEY_RIGHT_SUPER => .right_super,
        c.GLFW_KEY_MENU => .menu,
        else => .unknown,
    };
}
