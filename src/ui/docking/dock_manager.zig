const std = @import("std");
const types = @import("../core/types.zig");
const dock_node = @import("dock_node.zig");

pub const DockManager = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayList(dock_node.DockNode) = .empty,
    root: types.DockNodeId = types.invalid_dock_node,
    active_resize: ?ResizeState = null,

    pub const SplitResult = struct {
        split: types.DockNodeId,
        old_node: types.DockNodeId,
        new_leaf: types.DockNodeId,
    };

    pub const ResizeState = struct {
        split: types.DockNodeId,
        start_mouse_pos: types.Vec2,
        start_ratio: f32,
    };

    pub fn init(allocator: std.mem.Allocator) !DockManager {
        var self: DockManager = .{ .allocator = allocator };
        self.root = try self.appendNode(.{ .leaf = .{} });
        return self;
    }

    pub fn deinit(self: *DockManager) void {
        for (self.nodes.items) |*node| node.deinit(self.allocator);
        self.nodes.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn dockWindow(
        self: *DockManager,
        window: types.WindowId,
        target: types.DockNodeId,
        position: dock_node.DockPosition,
    ) !void {
        if (target == types.invalid_dock_node or target >= self.nodes.items.len) return error.InvalidDockTarget;
        try self.removeWindow(window, false);

        if (position == .center_tab) {
            switch (self.nodes.items[target]) {
                .leaf => |*leaf| {
                    try leaf.tabs.append(self.allocator, window);
                    leaf.active_tab = leaf.tabs.items.len - 1;
                },
                .split => return error.InvalidDockTarget,
            }
            self.cleanupEmptyLeaves();
            return;
        }

        const result = try self.splitNode(target, position, defaultDockSplitRatio(position));
        switch (self.nodes.items[result.new_leaf]) {
            .leaf => |*leaf| {
                try leaf.tabs.append(self.allocator, window);
                leaf.active_tab = leaf.tabs.items.len - 1;
            },
            .split => unreachable,
        }
        self.cleanupEmptyLeaves();
    }

    pub fn moveWindowToLeaf(self: *DockManager, window: types.WindowId, target: types.DockNodeId) !void {
        if (target == types.invalid_dock_node or target >= self.nodes.items.len) return error.InvalidDockTarget;
        try self.removeWindow(window, false);
        switch (self.nodes.items[target]) {
            .leaf => |*leaf| {
                try leaf.tabs.append(self.allocator, window);
                leaf.active_tab = leaf.tabs.items.len - 1;
            },
            .split => return error.InvalidDockTarget,
        }
        self.cleanupEmptyLeaves();
    }

    pub fn splitNode(
        self: *DockManager,
        target: types.DockNodeId,
        position: dock_node.DockPosition,
        ratio: f32,
    ) !SplitResult {
        if (target == types.invalid_dock_node or target >= self.nodes.items.len) return error.InvalidDockTarget;
        if (position == .center_tab) return error.InvalidDockTarget;

        const old = self.nodes.items[target];
        const new_leaf = dock_node.DockNode{ .leaf = .{} };
        const old_id = try self.appendNode(old);
        const new_id = try self.appendNode(new_leaf);
        const axis: dock_node.Axis = switch (position) {
            .left, .right => .x,
            .top, .bottom => .y,
            .center_tab => unreachable,
        };

        const first = switch (position) {
            .left, .top => new_id,
            .right, .bottom => old_id,
            .center_tab => unreachable,
        };
        const second = if (first == new_id) old_id else new_id;

        self.nodes.items[target] = .{ .split = .{
            .axis = axis,
            .ratio = sanitizeRatio(ratio),
            .first = first,
            .second = second,
        } };

        return .{
            .split = target,
            .old_node = old_id,
            .new_leaf = new_id,
        };
    }

    pub fn undockWindow(self: *DockManager, window: types.WindowId) !void {
        try self.removeWindow(window, true);
    }

    fn removeWindow(self: *DockManager, window: types.WindowId, cleanup: bool) !void {
        for (self.nodes.items) |*node| {
            switch (node.*) {
                .leaf => |*leaf| {
                    for (leaf.tabs.items, 0..) |tab, i| {
                        if (tab == window) {
                            _ = leaf.tabs.orderedRemove(i);
                            if (leaf.active_tab >= leaf.tabs.items.len) {
                                leaf.active_tab = if (leaf.tabs.items.len == 0) 0 else leaf.tabs.items.len - 1;
                            }
                            if (cleanup) self.cleanupEmptyLeaves();
                            return;
                        }
                    }
                },
                .split => {},
            }
        }
    }

    pub fn leafForWindow(self: *const DockManager, window: types.WindowId) ?types.DockNodeId {
        for (self.nodes.items, 0..) |node, i| {
            switch (node) {
                .leaf => |leaf| {
                    for (leaf.tabs.items) |tab| {
                        if (tab == window) return @intCast(i);
                    }
                },
                .split => {},
            }
        }
        return null;
    }

    pub fn activeWindow(self: *const DockManager, leaf_id: types.DockNodeId) ?types.WindowId {
        if (leaf_id == types.invalid_dock_node or leaf_id >= self.nodes.items.len) return null;
        return switch (self.nodes.items[leaf_id]) {
            .leaf => |leaf| if (leaf.tabs.items.len == 0) null else leaf.tabs.items[@min(leaf.active_tab, leaf.tabs.items.len - 1)],
            .split => null,
        };
    }

    pub fn setActiveWindow(self: *DockManager, leaf_id: types.DockNodeId, window: types.WindowId) bool {
        if (leaf_id == types.invalid_dock_node or leaf_id >= self.nodes.items.len) return false;
        switch (self.nodes.items[leaf_id]) {
            .leaf => |*leaf| {
                for (leaf.tabs.items, 0..) |tab, i| {
                    if (tab == window) {
                        leaf.active_tab = i;
                        return true;
                    }
                }
            },
            .split => {},
        }
        return false;
    }

    pub fn layout(self: *DockManager, available: types.Rect) void {
        self.layoutNode(self.root, available);
    }

    pub fn setSplitMinimums(self: *DockManager, split_id: types.DockNodeId, min_first_size: f32, min_second_size: f32) !void {
        const split = self.splitPtr(split_id) orelse return error.InvalidDockTarget;
        split.min_first_size = @max(0, min_first_size);
        split.min_second_size = @max(0, min_second_size);
        split.ratio = clampRatio(split.*, split.ratio, split.rect);
    }

    pub fn setSplitRatio(self: *DockManager, split_id: types.DockNodeId, ratio: f32) !void {
        const split = self.splitPtr(split_id) orelse return error.InvalidDockTarget;
        split.ratio = clampRatio(split.*, sanitizeRatio(ratio), split.rect);
    }

    pub fn splitRatio(self: *const DockManager, split_id: types.DockNodeId) ?f32 {
        const split = self.splitConstPtr(split_id) orelse return null;
        return split.ratio;
    }

    pub fn splitAxis(self: *const DockManager, split_id: types.DockNodeId) ?dock_node.Axis {
        const split = self.splitConstPtr(split_id) orelse return null;
        return split.axis;
    }

    pub fn nodeRect(self: *const DockManager, id: types.DockNodeId) ?types.Rect {
        if (id == types.invalid_dock_node or id >= self.nodes.items.len) return null;
        return switch (self.nodes.items[id]) {
            .leaf => |leaf| leaf.rect,
            .split => |split| split.rect,
        };
    }

    pub fn beginResize(self: *DockManager, split_id: types.DockNodeId, mouse_pos: types.Vec2) !void {
        const split = self.splitConstPtr(split_id) orelse return error.InvalidDockTarget;
        self.active_resize = .{
            .split = split_id,
            .start_mouse_pos = mouse_pos,
            .start_ratio = split.ratio,
        };
    }

    pub fn updateResize(self: *DockManager, mouse_pos: types.Vec2) bool {
        const resize = self.active_resize orelse return false;
        const split = self.splitPtr(resize.split) orelse {
            self.active_resize = null;
            return false;
        };

        const major = majorSize(split.rect, split.axis);
        if (major <= 0) return false;

        const delta = switch (split.axis) {
            .x => mouse_pos.x - resize.start_mouse_pos.x,
            .y => mouse_pos.y - resize.start_mouse_pos.y,
        };
        const next_ratio = clampRatio(split.*, resize.start_ratio + delta / major, split.rect);
        const changed = @abs(split.ratio - next_ratio) > 0.0001;
        split.ratio = next_ratio;
        return changed;
    }

    pub fn endResize(self: *DockManager) void {
        self.active_resize = null;
    }

    pub fn activeResizeSplit(self: *const DockManager) ?types.DockNodeId {
        return if (self.active_resize) |resize| resize.split else null;
    }

    pub fn resizeHandleRect(self: *const DockManager, split_id: types.DockNodeId, thickness: f32) ?types.Rect {
        const split = self.splitConstPtr(split_id) orelse return null;
        return handleRectForSplit(split.*, @max(0, thickness));
    }

    pub fn hitTestResizeHandle(self: *const DockManager, mouse_pos: types.Vec2, thickness: f32) ?types.DockNodeId {
        return self.hitTestResizeHandleNode(self.root, mouse_pos, @max(0, thickness));
    }

    pub fn hitTestLeaf(self: *const DockManager, mouse_pos: types.Vec2) ?types.DockNodeId {
        return self.hitTestLeafNode(self.root, mouse_pos);
    }

    fn layoutNode(self: *DockManager, id: types.DockNodeId, rect: types.Rect) void {
        if (id == types.invalid_dock_node or id >= self.nodes.items.len) return;
        switch (self.nodes.items[id]) {
            .leaf => |*leaf| leaf.rect = rect,
            .split => |*split| {
                split.rect = rect;
                split.ratio = clampRatio(split.*, split.ratio, rect);
                if (split.axis == .x) {
                    const first_w = rect.w * split.ratio;
                    self.layoutNode(split.first, .{ .x = rect.x, .y = rect.y, .w = first_w, .h = rect.h });
                    self.layoutNode(split.second, .{ .x = rect.x + first_w, .y = rect.y, .w = rect.w - first_w, .h = rect.h });
                } else {
                    const first_h = rect.h * split.ratio;
                    self.layoutNode(split.first, .{ .x = rect.x, .y = rect.y, .w = rect.w, .h = first_h });
                    self.layoutNode(split.second, .{ .x = rect.x, .y = rect.y + first_h, .w = rect.w, .h = rect.h - first_h });
                }
            },
        }
    }

    fn appendNode(self: *DockManager, node: dock_node.DockNode) !types.DockNodeId {
        const id: types.DockNodeId = @intCast(self.nodes.items.len);
        try self.nodes.append(self.allocator, node);
        return id;
    }

    fn splitPtr(self: *DockManager, id: types.DockNodeId) ?*dock_node.DockSplit {
        if (id == types.invalid_dock_node or id >= self.nodes.items.len) return null;
        return switch (self.nodes.items[id]) {
            .leaf => null,
            .split => |*split| split,
        };
    }

    fn splitConstPtr(self: *const DockManager, id: types.DockNodeId) ?*const dock_node.DockSplit {
        if (id == types.invalid_dock_node or id >= self.nodes.items.len) return null;
        return switch (self.nodes.items[id]) {
            .leaf => null,
            .split => |*split| split,
        };
    }

    fn hitTestResizeHandleNode(self: *const DockManager, id: types.DockNodeId, mouse_pos: types.Vec2, thickness: f32) ?types.DockNodeId {
        if (id == types.invalid_dock_node or id >= self.nodes.items.len) return null;
        switch (self.nodes.items[id]) {
            .leaf => return null,
            .split => |split| {
                if (self.hitTestResizeHandleNode(split.first, mouse_pos, thickness)) |hit| return hit;
                if (self.hitTestResizeHandleNode(split.second, mouse_pos, thickness)) |hit| return hit;
                if (handleRectForSplit(split, thickness).contains(mouse_pos)) return id;
                return null;
            },
        }
    }

    fn hitTestLeafNode(self: *const DockManager, id: types.DockNodeId, mouse_pos: types.Vec2) ?types.DockNodeId {
        if (id == types.invalid_dock_node or id >= self.nodes.items.len) return null;
        switch (self.nodes.items[id]) {
            .leaf => |leaf| return if (leaf.rect.contains(mouse_pos)) id else null,
            .split => |split| {
                if (self.hitTestLeafNode(split.first, mouse_pos)) |hit| return hit;
                if (self.hitTestLeafNode(split.second, mouse_pos)) |hit| return hit;
                return null;
            },
        }
    }

    fn cleanupEmptyLeaves(self: *DockManager) void {
        _ = self.collapseEmptyChild(self.root);
    }

    fn collapseEmptyChild(self: *DockManager, id: types.DockNodeId) bool {
        if (id == types.invalid_dock_node or id >= self.nodes.items.len) return false;
        switch (self.nodes.items[id]) {
            .leaf => |leaf| return leaf.tabs.items.len == 0,
            .split => |split| {
                const first_empty = self.collapseEmptyChild(split.first);
                const second_empty = self.collapseEmptyChild(split.second);
                if (first_empty and !second_empty) {
                    self.replaceNodeWith(id, split.second);
                    return self.collapseEmptyChild(id);
                }
                if (second_empty and !first_empty) {
                    self.replaceNodeWith(id, split.first);
                    return self.collapseEmptyChild(id);
                }
                return first_empty and second_empty;
            },
        }
    }

    fn replaceNodeWith(self: *DockManager, dst: types.DockNodeId, src: types.DockNodeId) void {
        if (dst == types.invalid_dock_node or dst >= self.nodes.items.len) return;
        if (src == types.invalid_dock_node or src >= self.nodes.items.len) return;
        const moved = self.nodes.items[src];
        self.nodes.items[src] = .{ .leaf = .{} };
        self.nodes.items[dst] = moved;
    }
};

fn handleRectForSplit(split: dock_node.DockSplit, thickness: f32) types.Rect {
    const half = thickness * 0.5;
    return switch (split.axis) {
        .x => .{
            .x = split.rect.x + split.rect.w * split.ratio - half,
            .y = split.rect.y,
            .w = thickness,
            .h = split.rect.h,
        },
        .y => .{
            .x = split.rect.x,
            .y = split.rect.y + split.rect.h * split.ratio - half,
            .w = split.rect.w,
            .h = thickness,
        },
    };
}

fn clampRatio(split: dock_node.DockSplit, ratio: f32, rect: types.Rect) f32 {
    const clean_ratio = sanitizeRatio(ratio);
    const major = majorSize(rect, split.axis);
    if (major <= 0) return clean_ratio;

    const min_ratio = @min(1, split.min_first_size / major);
    const max_ratio = @max(0, 1 - split.min_second_size / major);
    if (min_ratio > max_ratio) {
        const total_min = split.min_first_size + split.min_second_size;
        if (total_min > 0) return split.min_first_size / total_min;
        return 0.5;
    }
    return @min(max_ratio, @max(min_ratio, clean_ratio));
}

fn majorSize(rect: types.Rect, axis: dock_node.Axis) f32 {
    return switch (axis) {
        .x => rect.w,
        .y => rect.h,
    };
}

fn sanitizeRatio(ratio: f32) f32 {
    if (!std.math.isFinite(ratio)) return 0.5;
    return @min(1, @max(0, ratio));
}

fn defaultDockSplitRatio(position: dock_node.DockPosition) f32 {
    return switch (position) {
        .left, .top => 0.25,
        .right, .bottom => 0.75,
        .center_tab => 0.5,
    };
}

fn expectApprox(expected: f32, actual: f32) !void {
    try std.testing.expect(@abs(expected - actual) < 0.001);
}

test "horizontal split resize updates ratio from pointer delta" {
    var dock = try DockManager.init(std.testing.allocator);
    defer dock.deinit();

    const split = try dock.splitNode(dock.root, .left, 0.25);
    dock.layout(.{ .x = 0, .y = 0, .w = 1000, .h = 600 });

    try dock.beginResize(split.split, .{ .x = 250, .y = 0 });
    try std.testing.expect(dock.updateResize(.{ .x = 350, .y = 0 }));
    try expectApprox(0.35, dock.splitRatio(split.split).?);
}

test "vertical split resize updates ratio from pointer delta" {
    var dock = try DockManager.init(std.testing.allocator);
    defer dock.deinit();

    const split = try dock.splitNode(dock.root, .bottom, 0.8);
    dock.layout(.{ .x = 0, .y = 0, .w = 800, .h = 500 });

    try dock.beginResize(split.split, .{ .x = 0, .y = 400 });
    try std.testing.expect(dock.updateResize(.{ .x = 0, .y = 300 }));
    try expectApprox(0.6, dock.splitRatio(split.split).?);
}

test "split resize clamps to configured child minimum sizes" {
    var dock = try DockManager.init(std.testing.allocator);
    defer dock.deinit();

    const split = try dock.splitNode(dock.root, .left, 0.5);
    try dock.setSplitMinimums(split.split, 200, 300);
    dock.layout(.{ .x = 0, .y = 0, .w = 1000, .h = 500 });

    try dock.beginResize(split.split, .{ .x = 500, .y = 0 });
    try std.testing.expect(dock.updateResize(.{ .x = 0, .y = 0 }));
    try expectApprox(0.2, dock.splitRatio(split.split).?);

    try dock.beginResize(split.split, .{ .x = 200, .y = 0 });
    try std.testing.expect(dock.updateResize(.{ .x = 1000, .y = 0 }));
    try expectApprox(0.7, dock.splitRatio(split.split).?);
}

test "resize handle hit testing returns split under handle rect" {
    var dock = try DockManager.init(std.testing.allocator);
    defer dock.deinit();

    const split = try dock.splitNode(dock.root, .left, 0.25);
    dock.layout(.{ .x = 0, .y = 0, .w = 100, .h = 100 });

    try std.testing.expectEqual(split.split, dock.hitTestResizeHandle(.{ .x = 25, .y = 50 }, 10).?);
    try std.testing.expect(dock.hitTestResizeHandle(.{ .x = 10, .y = 50 }, 10) == null);
}

test "redocking center leaf into right leaf preserves surrounding dock tree" {
    var dock = try DockManager.init(std.testing.allocator);
    defer dock.deinit();

    const viewport: types.WindowId = 1;
    const console: types.WindowId = 2;
    const scene: types.WindowId = 3;
    const inspector: types.WindowId = 4;

    try dock.moveWindowToLeaf(viewport, dock.root);
    const bottom = try dock.splitNode(dock.root, .bottom, 0.82);
    try dock.moveWindowToLeaf(console, bottom.new_leaf);

    const left = try dock.splitNode(bottom.old_node, .left, 0.18);
    try dock.moveWindowToLeaf(scene, left.new_leaf);

    const right = try dock.splitNode(left.old_node, .right, 0.72);
    try dock.moveWindowToLeaf(inspector, right.new_leaf);

    try dock.dockWindow(viewport, right.new_leaf, .right);
    dock.layout(.{ .x = 0, .y = 0, .w = 1200, .h = 800 });

    try std.testing.expect(dock.leafForWindow(scene) != null);
    try std.testing.expect(dock.leafForWindow(viewport) != null);
    try std.testing.expect(dock.leafForWindow(inspector) != null);
    try std.testing.expect(dock.leafForWindow(console) != null);
    try std.testing.expect((dock.nodeRect(dock.leafForWindow(viewport).?) orelse .{}).w > 0);
    try std.testing.expect((dock.nodeRect(dock.leafForWindow(inspector).?) orelse .{}).w > 0);
}
