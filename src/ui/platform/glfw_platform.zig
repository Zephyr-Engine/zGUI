const std = @import("std");
const types = @import("../core/types.zig");
const events = @import("events.zig");
const platform_mod = @import("platform.zig");

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

    pub fn platform(self: *GlfwPlatform) platform_mod.Platform {
        self.installCallbacks();
        return .{
            .ptr = self,
            .pollEventsFn = pollEventsErased,
            .getWindowSizeFn = getWindowSizeErased,
            .setCursorFn = setCursorErased,
            .getClipboardFn = getClipboardErased,
            .setClipboardFn = setClipboardErased,
        };
    }

    pub fn pollEvents(self: *GlfwPlatform) []const events.PlatformEvent {
        self.installCallbacks();
        self.events.clearRetainingCapacity();
        self.text_buffer.clearRetainingCapacity();
        c.glfwPollEvents();
        return self.events.items;
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
        _ = c.glfwSetFramebufferSizeCallback(self.window, framebufferSizeCallback);
        _ = c.glfwSetWindowCloseCallback(self.window, windowCloseCallback);
        self.callbacks_installed = true;
    }

    pub fn getProcAddress(name: [*:0]const u8) ?*const anyopaque {
        return @ptrCast(c.glfwGetProcAddress(name));
    }

    fn appendEvent(self: *GlfwPlatform, event: events.PlatformEvent) void {
        self.events.append(self.allocator, event) catch {};
    }

    fn pollEventsErased(ptr: *anyopaque) []const events.PlatformEvent {
        const self: *GlfwPlatform = @ptrCast(@alignCast(ptr));
        return self.pollEvents();
    }

    fn getWindowSizeErased(ptr: *anyopaque) types.Vec2 {
        const self: *GlfwPlatform = @ptrCast(@alignCast(ptr));
        return self.getWindowSize();
    }

    fn setCursorErased(ptr: *anyopaque, cursor: events.CursorKind) void {
        const self: *GlfwPlatform = @ptrCast(@alignCast(ptr));
        self.setCursor(cursor);
    }

    fn getClipboardErased(ptr: *anyopaque) []const u8 {
        const self: *GlfwPlatform = @ptrCast(@alignCast(ptr));
        return self.getClipboard();
    }

    fn setClipboardErased(ptr: *anyopaque, text: []const u8) void {
        const self: *GlfwPlatform = @ptrCast(@alignCast(ptr));
        self.setClipboard(text);
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
        if (action == c.GLFW_PRESS) {
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

    fn framebufferSizeCallback(window: ?*c.GLFWwindow, width: c_int, height: c_int) callconv(.c) void {
        _ = window;
        _ = width;
        _ = height;
    }

    fn windowCloseCallback(window: ?*c.GLFWwindow) callconv(.c) void {
        const self = fromWindow(window) orelse return;
        self.appendEvent(.window_close);
    }
};

fn mapKey(key: c_int) events.Key {
    return switch (key) {
        c.GLFW_KEY_ESCAPE => .escape,
        c.GLFW_KEY_ENTER => .enter,
        c.GLFW_KEY_TAB => .tab,
        c.GLFW_KEY_BACKSPACE => .backspace,
        c.GLFW_KEY_DELETE => .delete,
        c.GLFW_KEY_LEFT => .left,
        c.GLFW_KEY_RIGHT => .right,
        c.GLFW_KEY_UP => .up,
        c.GLFW_KEY_DOWN => .down,
        c.GLFW_KEY_A => .a,
        c.GLFW_KEY_B => .b,
        c.GLFW_KEY_C => .c,
        else => .unknown,
    };
}
