const builtin = @import("builtin");
const std = @import("std");

pub const ActionId = u64;
pub const close_action: ActionId = std.math.maxInt(ActionId);
pub const Callback = *const fn (?*anyopaque, ActionId) callconv(.c) void;

const Menu = *opaque {};
const Handle = *opaque {};

pub const NativeMenu = struct {
    handle: Handle,
    callback: Callback,
    context: ?*anyopaque,

    pub fn init(window_handle: usize, title: []const u8, context: ?*anyopaque, callback: Callback) !NativeMenu {
        if (builtin.os.tag != .linux and builtin.os.tag != .macos and builtin.os.tag != .windows) return error.UnsupportedPlatform;
        const handle = zgui_native_menu_create(window_handle, title.ptr, title.len, context, callback) orelse return error.NativeMenuUnavailable;
        return .{ .handle = handle, .context = context, .callback = callback };
    }

    pub fn deinit(self: *NativeMenu) void {
        if (builtin.os.tag == .linux or builtin.os.tag == .macos or builtin.os.tag == .windows) zgui_native_menu_destroy(self.handle);
        self.* = undefined;
    }

    pub fn addMenu(self: *NativeMenu, label: []const u8) !Menu {
        const menu = zgui_native_menu_add_menu(self.handle, label.ptr, label.len) orelse return error.NativeMenuUnavailable;
        return menu;
    }

    pub fn addItem(self: *NativeMenu, menu: Menu, label: []const u8, action: ActionId) !void {
        if (zgui_native_menu_add_item(self.handle, menu, label.ptr, label.len, action) == 0) return error.NativeMenuUnavailable;
    }

    pub fn poll(self: *NativeMenu) void {
        zgui_native_menu_poll(self.handle);
    }

    pub fn scaleFactor(self: *const NativeMenu, child_width: u32) f32 {
        const logical_width = zgui_native_menu_content_width(self.handle);
        if (logical_width <= 0) return 1;
        const physical_width: f32 = @floatFromInt(child_width);
        return @max(1, physical_width / @as(f32, @floatFromInt(logical_width)));
    }
};

extern fn zgui_native_menu_create(usize, [*]const u8, usize, ?*anyopaque, Callback) ?Handle;
extern fn zgui_native_menu_destroy(Handle) void;
extern fn zgui_native_menu_add_menu(Handle, [*]const u8, usize) ?Menu;
extern fn zgui_native_menu_add_item(Handle, Menu, [*]const u8, usize, ActionId) c_int;
extern fn zgui_native_menu_poll(Handle) void;
extern fn zgui_native_menu_content_width(Handle) c_int;

test "native menus report unsupported platforms without a backend" {
    if (builtin.os.tag != .linux) {
        try std.testing.expectError(error.UnsupportedPlatform, NativeMenu.init(0, "Test", null, struct {
            fn callback(_: ?*anyopaque, _: ActionId) callconv(.c) void {}
        }.callback));
    }
}
