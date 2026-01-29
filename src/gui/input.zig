const std = @import("std");

const GuiContext = @import("context.zig").GuiContext;
const shapes = @import("shapes.zig");
const window_mod = @import("window.zig");
const Window = window_mod.Window;
const c = @import("c.zig");

pub fn mouseButtonCallback(window_handle: c.Window, btn: c_int, action: c_int, mods: c_int) callconv(.c) void {
    _ = mods;
    const win = Window{ .handle = window_handle.? };
    const gui_ptr = win.getUserPointer();
    if (gui_ptr != null) {
        const gui: *GuiContext = @ptrCast(@alignCast(gui_ptr));
        gui.handleMouseButton(btn, action);
    }
}

pub fn charCallback(window_handle: c.Window, codepoint: c_uint) callconv(.c) void {
    const win = Window{ .handle = window_handle.? };
    const gui_ptr = win.getUserPointer();
    if (gui_ptr != null) {
        const gui: *GuiContext = @ptrCast(@alignCast(gui_ptr));
        gui.handleChar(codepoint);
    }
}

pub fn keyCallback(window_handle: c.Window, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.c) void {
    _ = scancode;
    const win = Window{ .handle = window_handle.? };
    const gui_ptr = win.getUserPointer();
    if (gui_ptr != null) {
        const gui: *GuiContext = @ptrCast(@alignCast(gui_ptr));
        gui.handleKey(key, action);
        gui.handleModifiers(mods);
    }
}

pub fn scrollCallback(window_handle: c.Window, xoffset: f64, yoffset: f64) callconv(.c) void {
    const win = Window{ .handle = window_handle.? };
    const gui_ptr = win.getUserPointer();
    if (gui_ptr != null) {
        const gui: *GuiContext = @ptrCast(@alignCast(gui_ptr));
        gui.handleScroll(xoffset, yoffset);
    }
}

pub fn framebufferSizeCallback(window_handle: c.Window, width: c_int, height: c_int) callconv(.c) void {
    const win = Window{ .handle = window_handle.? };
    const gui_ptr = win.getUserPointer();
    if (gui_ptr != null) {
        const gui: *GuiContext = @ptrCast(@alignCast(gui_ptr));
        // Convert framebuffer size to logical window size using content scale
        const logical_width = @as(f32, @floatFromInt(width)) / gui.content_scale_x;
        const logical_height = @as(f32, @floatFromInt(height)) / gui.content_scale_y;
        gui.setWindowSize(logical_width, logical_height);
    }
}

pub fn contentScaleCallback(window_handle: c.Window, xscale: f32, yscale: f32) callconv(.c) void {
    const win = Window{ .handle = window_handle.? };
    const gui_ptr = win.getUserPointer();
    if (gui_ptr != null) {
        const gui: *GuiContext = @ptrCast(@alignCast(gui_ptr));
        gui.handleContentScale(xscale, yscale);
    }
}

pub const Input = struct {
    cursor_x: f64,
    cursor_y: f64,
    mouse_left_pressed: bool,
    mouse_left_clicked: bool,
    mouse_left_click_count: u32,
    mouse_right_pressed: bool,
    mouse_right_clicked: bool,
    mouse_right_click_count: u32,
    mouse_middle_pressed: bool,
    mouse_middle_clicked: bool,
    mouse_middle_click_count: u32,

    // Scroll wheel
    scroll_x: f64,
    scroll_y: f64,

    // Keyboard input
    chars_buffer: [32]u32,
    chars_count: usize,
    keys_just_pressed: [512]bool,

    ctrl_pressed: bool,
    alt_pressed: bool,
    super_pressed: bool,
    shift_pressed: bool,

    // ctrl on windows/linux, command on macos
    primary_pressed: bool,

    pub fn init() Input {
        return Input{
            .cursor_x = 0,
            .cursor_y = 0,
            .mouse_left_pressed = false,
            .mouse_left_clicked = false,
            .mouse_left_click_count = 0,
            .mouse_right_pressed = false,
            .mouse_right_clicked = false,
            .mouse_right_click_count = 0,
            .mouse_middle_pressed = false,
            .mouse_middle_clicked = false,
            .mouse_middle_click_count = 0,
            .scroll_x = 0,
            .scroll_y = 0,
            .chars_buffer = [_]u32{0} ** 32,
            .chars_count = 0,
            .keys_just_pressed = [_]bool{false} ** 512,
            .ctrl_pressed = false,
            .alt_pressed = false,
            .super_pressed = false,
            .shift_pressed = false,
            .primary_pressed = false,
        };
    }

    pub fn beginFrame(self: *Input) void {
        self.mouse_left_clicked = self.mouse_left_click_count > 0;
        self.mouse_left_click_count = 0;
        self.mouse_right_clicked = self.mouse_right_click_count > 0;
        self.mouse_right_click_count = 0;
        self.mouse_middle_clicked = self.mouse_middle_click_count > 0;
        self.mouse_middle_click_count = 0;
        self.scroll_x = 0;
        self.scroll_y = 0;
        self.chars_count = 0;
        @memset(&self.keys_just_pressed, false);
    }

    pub fn registerMouseClick(self: *Input) void {
        self.mouse_left_click_count += 1;
    }

    pub fn registerRightClick(self: *Input) void {
        self.mouse_right_click_count += 1;
    }

    pub fn registerMiddleClick(self: *Input) void {
        self.mouse_middle_click_count += 1;
    }

    pub fn registerScroll(self: *Input, xoffset: f64, yoffset: f64) void {
        self.scroll_x += xoffset;
        self.scroll_y += yoffset;
    }

    pub fn update(self: *Input, win: Window) void {
        var window_x: f64 = 0;
        var window_y: f64 = 0;
        win.getCursorPos(&window_x, &window_y);

        var window_width: i32 = 0;
        var window_height: i32 = 0;
        var fb_width: i32 = 0;
        var fb_height: i32 = 0;
        win.getSize(&window_width, &window_height);
        win.getFramebufferSize(&fb_width, &fb_height);

        const scale_x = @as(f64, @floatFromInt(fb_width)) / @as(f64, @floatFromInt(window_width));
        const scale_y = @as(f64, @floatFromInt(fb_height)) / @as(f64, @floatFromInt(window_height));
        self.cursor_x = window_x * scale_x;
        self.cursor_y = window_y * scale_y;

        self.mouse_left_pressed = win.getMouseButton(.left) == .pressed;
        self.mouse_right_pressed = win.getMouseButton(.right) == .pressed;
        self.mouse_middle_pressed = win.getMouseButton(.middle) == .pressed;
    }

    pub fn isMouseInRect(self: *const Input, rect: shapes.Rect) bool {
        const mx = @as(f32, @floatCast(self.cursor_x));
        const my = @as(f32, @floatCast(self.cursor_y));
        return mx >= rect.x and mx <= rect.x + rect.w and my >= rect.y and my <= rect.y + rect.h;
    }

    pub fn registerChar(self: *Input, codepoint: u32) void {
        if (self.chars_count < self.chars_buffer.len) {
            self.chars_buffer[self.chars_count] = codepoint;
            self.chars_count += 1;
        }
    }

    pub fn registerKey(self: *Input, key: c_int, action: c_int) void {
        if (key >= 0 and key < 512) {
            const key_idx: usize = @intCast(key);
            const press_val = @intFromEnum(window_mod.KeyAction.press);
            const repeat_val = @intFromEnum(window_mod.KeyAction.repeat);
            // const release_val = @intFromEnum(window_mod.KeyAction.release);

            if (action == press_val or action == repeat_val) {
                self.keys_just_pressed[key_idx] = true;
            }
        }
    }

    /// Finalize per-frame input state after external event injection.
    /// In embedded mode, events are injected after beginFrame() clears state.
    /// This re-transfers accumulated click counts to clicked flags and
    /// should be called after all events for the current frame have been injected.
    pub fn finalizeInjectedInput(self: *Input) void {
        if (self.mouse_left_click_count > 0) {
            self.mouse_left_clicked = true;
            self.mouse_left_click_count = 0;
        }
        if (self.mouse_right_click_count > 0) {
            self.mouse_right_clicked = true;
            self.mouse_right_click_count = 0;
        }
        if (self.mouse_middle_click_count > 0) {
            self.mouse_middle_clicked = true;
            self.mouse_middle_click_count = 0;
        }
    }

    pub fn isKeyJustPressed(self: *const Input, key: c_int) bool {
        if (key >= 0 and key < 512) {
            const key_idx: usize = @intCast(key);
            return self.keys_just_pressed[key_idx];
        }
        return false;
    }
};
