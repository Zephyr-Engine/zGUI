const std = @import("std");
const types = @import("../core/types.zig");
const window_mod = @import("window.zig");

pub const WindowManager = struct {
    allocator: std.mem.Allocator,
    windows: std.ArrayList(window_mod.Window) = .empty,
    free_list: std.ArrayList(u32) = .empty,
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
        try self.free_list.ensureTotalCapacity(self.allocator, self.windows.items.len + 1);

        const reused_index = self.free_list.pop();
        const index = reused_index orelse blk: {
            const next: u32 = @intCast(self.windows.items.len);
            try self.windows.append(self.allocator, undefined);
            break :blk next;
        };
        const generation: u8 = if (reused_index != null)
            nextGeneration(types.windowGeneration(self.windows.items[index].id))
        else
            1;
        const id = types.makeWindowId(index, generation);

        self.windows.items[index] = .{
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
        self.free_list.appendAssumeCapacity(types.windowIndex(id));
        if (self.focused == id) self.focused = types.invalid_window;
    }

    pub fn bringToFront(self: *WindowManager, id: types.WindowId) void {
        const window = self.get(id) orelse return;
        window.z_index = self.nextZ();
        self.focused = id;
    }

    pub fn get(self: *WindowManager, id: types.WindowId) ?*window_mod.Window {
        if (id == types.invalid_window) return null;
        const index = types.windowIndex(id);
        if (index >= self.windows.items.len) return null;
        const window = &self.windows.items[index];
        if (!window.open or window.id != id) return null;
        return window;
    }

    pub fn getConst(self: *const WindowManager, id: types.WindowId) ?*const window_mod.Window {
        if (id == types.invalid_window) return null;
        const index = types.windowIndex(id);
        if (index >= self.windows.items.len) return null;
        const window = &self.windows.items[index];
        if (!window.open or window.id != id) return null;
        return window;
    }

    fn nextZ(self: *WindowManager) u32 {
        const z = self.next_z;
        self.next_z +%= 1;
        if (self.next_z == 0) self.next_z = 1;
        return z;
    }
};

fn nextGeneration(current: u8) u8 {
    return if (current == std.math.maxInt(u8)) 1 else current + 1;
}

test "closed window slots are reused with a fresh generation" {
    var windows = WindowManager.init(std.testing.allocator);
    defer windows.deinit();

    const first = try windows.createWindow("First", .{}, types.invalid_node, .{});
    windows.closeWindow(first);
    const second = try windows.createWindow("Second", .{}, types.invalid_node, .{});

    try std.testing.expectEqual(types.windowIndex(first), types.windowIndex(second));
    try std.testing.expect(first != second);
    try std.testing.expect(windows.get(first) == null);
    try std.testing.expect(windows.get(second) != null);
}
