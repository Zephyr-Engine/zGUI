const std = @import("std");
const types = @import("../core/types.zig");
const window_mod = @import("window.zig");

pub const WindowManager = struct {
    allocator: std.mem.Allocator,
    windows: std.ArrayList(window_mod.Window) = .empty,
    free_list: std.ArrayList(types.WindowId) = .empty,
    next_z: u32 = 1,
    focused: types.WindowId = types.invalid_window,

    pub fn init(allocator: std.mem.Allocator) WindowManager {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *WindowManager) void {
        for (self.windows.items) |*window| {
            if (window.open) self.allocator.free(window.title);
        }
        self.windows.deinit(self.allocator);
        self.free_list.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn createWindow(
        self: *WindowManager,
        title: []const u8,
        rect: types.Rect,
        root_node: types.NodeId,
        flags: window_mod.WindowFlags,
    ) !types.WindowId {
        const owned_title = try self.allocator.dupe(u8, title);
        errdefer self.allocator.free(owned_title);

        const id = self.free_list.pop() orelse blk: {
            const next: types.WindowId = @intCast(self.windows.items.len);
            try self.windows.append(self.allocator, undefined);
            break :blk next;
        };

        self.windows.items[id] = .{
            .id = id,
            .title = owned_title,
            .rect = rect,
            .root_node = root_node,
            .flags = flags,
            .z_index = self.nextZ(),
        };
        self.focused = id;
        return id;
    }

    pub fn closeWindow(self: *WindowManager, id: types.WindowId) void {
        const window = self.get(id) orelse return;
        self.allocator.free(window.title);
        window.title = &.{};
        window.open = false;
        self.free_list.append(self.allocator, id) catch {};
        if (self.focused == id) self.focused = types.invalid_window;
    }

    pub fn bringToFront(self: *WindowManager, id: types.WindowId) void {
        const window = self.get(id) orelse return;
        window.z_index = self.nextZ();
        self.focused = id;
    }

    pub fn get(self: *WindowManager, id: types.WindowId) ?*window_mod.Window {
        if (id == types.invalid_window or id >= self.windows.items.len) return null;
        const window = &self.windows.items[id];
        if (!window.open) return null;
        return window;
    }

    pub fn getConst(self: *const WindowManager, id: types.WindowId) ?*const window_mod.Window {
        if (id == types.invalid_window or id >= self.windows.items.len) return null;
        const window = &self.windows.items[id];
        if (!window.open) return null;
        return window;
    }

    fn nextZ(self: *WindowManager) u32 {
        const z = self.next_z;
        self.next_z +%= 1;
        if (self.next_z == 0) self.next_z = 1;
        return z;
    }
};
