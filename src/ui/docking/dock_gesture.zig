const types = @import("../core/types.zig");
const style = @import("../core/style.zig");
const events = @import("../platform/events.zig");
const dock_node = @import("dock_node.zig");

pub const DragState = struct {
    window: types.WindowId,
    source_leaf: ?types.DockNodeId = null,
    start_mouse: types.Vec2,
    dragging: bool = false,
    floating: bool = false,
};

pub const DropZone = enum {
    left,
    right,
    top,
    bottom,
    center_tab,
};

pub fn tabRect(leaf_rect: types.Rect, tab_index: usize, tab_count: usize, tab_height: f32, nominal_width: f32, min_width: f32) types.Rect {
    const count: f32 = @floatFromInt(@max(1, tab_count));
    const width = @min(nominal_width, @max(min_width, leaf_rect.w / count));
    const x = leaf_rect.x + @as(f32, @floatFromInt(tab_index)) * width;
    const right = @min(x + width, leaf_rect.x + leaf_rect.w);
    return .{ .x = x, .y = leaf_rect.y, .w = @max(0, right - x), .h = tab_height };
}

pub fn resizeHandleVisualRect(rect: types.Rect, axis: dock_node.Axis, thickness: f32) types.Rect {
    return switch (axis) {
        .x => .{ .x = rect.x + rect.w * 0.5 - thickness * 0.5, .y = rect.y, .w = thickness, .h = rect.h },
        .y => .{ .x = rect.x, .y = rect.y + rect.h * 0.5 - thickness * 0.5, .w = rect.w, .h = thickness },
    };
}

pub fn cursorForSplit(axis: dock_node.Axis) events.CursorKind {
    return switch (axis) {
        .x => .resize_x,
        .y => .resize_y,
    };
}

pub fn dropZoneFor(rect: types.Rect, mouse_pos: types.Vec2) DropZone {
    const edge = @min(80, @min(rect.w, rect.h) * 0.28);
    if (mouse_pos.x < rect.x + edge) return .left;
    if (mouse_pos.x > rect.x + rect.w - edge) return .right;
    if (mouse_pos.y < rect.y + edge) return .top;
    if (mouse_pos.y > rect.y + rect.h - edge) return .bottom;
    return .center_tab;
}

pub fn dropPreviewRect(rect: types.Rect, zone: DropZone) types.Rect {
    const edge_w = @max(42, rect.w * 0.32);
    const edge_h = @max(36, rect.h * 0.32);
    return switch (zone) {
        .left => .{ .x = rect.x, .y = rect.y, .w = @min(edge_w, rect.w), .h = rect.h },
        .right => .{ .x = rect.x + @max(0, rect.w - edge_w), .y = rect.y, .w = @min(edge_w, rect.w), .h = rect.h },
        .top => .{ .x = rect.x, .y = rect.y, .w = rect.w, .h = @min(edge_h, rect.h) },
        .bottom => .{ .x = rect.x, .y = rect.y + @max(0, rect.h - edge_h), .w = rect.w, .h = @min(edge_h, rect.h) },
        .center_tab => rect.inset(style.Edges.all(@min(18, @min(rect.w, rect.h) * 0.08))),
    };
}

test "drop zones prefer edges and preserve center" {
    const testing = @import("std").testing;
    const rect: types.Rect = .{ .w = 500, .h = 300 };
    try testing.expectEqual(DropZone.left, dropZoneFor(rect, .{ .x = 2, .y = 150 }));
    try testing.expectEqual(DropZone.center_tab, dropZoneFor(rect, .{ .x = 250, .y = 150 }));
}
