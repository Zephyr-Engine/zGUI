const std = @import("std");
const types = @import("../core/types.zig");
const style = @import("../core/style.zig");
const app = @import("../core/ui_context.zig");
const theme = @import("../theme.zig");

pub fn createPanel(ui: *app.Ui, parent: types.NodeId) !types.NodeId {
    const id = try ui.createNode(.panel);
    errdefer ui.destroySubtree(id);
    try ui.tree.appendChild(parent, id);
    var next = ui.nodeStyle(id).?;
    next.direction = .absolute;
    try ui.setStyle(id, next);
    try ui.setVisible(id, true);
    return id;
}

pub fn setPanel(ui: *app.Ui, id: types.NodeId, rect: types.Rect, origin: types.Vec2, background: theme.ColorRole, interactive: bool) void {
    setPanelStyled(ui, id, rect, origin, background, .transparent, 0, interactive, 0);
}

pub fn setPanelStyled(
    ui: *app.Ui,
    id: types.NodeId,
    rect: types.Rect,
    origin: types.Vec2,
    background: theme.ColorRole,
    border: theme.ColorRole,
    border_width: f32,
    interactive: bool,
    radius: f32,
) void {
    if (ui.nodeStyle(id)) |current| {
        var next = current;
        next.width = .{ .px = @max(0, rect.w) };
        next.height = .{ .px = @max(0, rect.h) };
        next.margin = style.Edges{ .left = rect.x - origin.x, .top = rect.y - origin.y };
        next.background = ui.theme.color(background);
        next.border_color = ui.theme.color(border);
        next.border_width = border_width;
        next.radius = style.CornerRadii.all(radius);
        next.direction = .absolute;
        const visible = rect.w > 0 and rect.h > 0;
        ui.setStyle(id, next) catch {};
        ui.setVisible(id, visible) catch {};
        ui.setInteractive(id, interactive) catch {};
    }
}

pub fn hideNode(ui: *app.Ui, id: types.NodeId) void {
    ui.setVisible(id, false) catch {};
    ui.setInteractive(id, false) catch {};
}

pub fn ensureTailOrder(ui: *app.Ui, parent: types.NodeId, desired: []const types.NodeId) void {
    const parent_node = ui.tree.getConst(parent) orelse return;
    var current = parent_node.last_child;
    var i = desired.len;
    var matches = true;
    while (i > 0) : (i -= 1) {
        if (current != desired[i - 1]) {
            matches = false;
            break;
        }
        current = if (ui.tree.getConst(current)) |node| node.prev_sibling else types.invalid_node;
    }
    if (matches) return;
    for (desired) |id| ui.tree.appendChild(parent, id) catch {};
}

pub fn nodeOrigin(ui: *const app.Ui, id: types.NodeId) types.Vec2 {
    const rect = ui.bounds(id) orelse return .{};
    return .{ .x = rect.x, .y = rect.y };
}

pub fn setContentRoot(ui: *app.Ui, id: types.NodeId) void {
    if (ui.nodeStyle(id)) |current| {
        var next = current;
        next.width = .fill;
        next.height = .fill;
        next.margin = .{};
        next.overflow_x = .scroll;
        next.overflow_y = .scroll;
        ui.setStyle(id, next) catch {};
        ui.setVisible(id, true) catch {};
    }
}

pub fn setLabel(ui: *app.Ui, id: types.NodeId, bytes: []const u8, active: bool) void {
    ui.setText(id, bytes) catch {};
    if (ui.nodeStyle(id)) |current| {
        var next = current;
        next.width = .fill;
        next.height = .fill;
        next.padding = .{ .left = 10, .right = 8, .top = 7, .bottom = 5 };
        next.foreground = ui.theme.color(if (active) .text else .text_muted);
        next.font_size = ui.theme.font.small;
        ui.setStyle(id, next) catch {};
        ui.setVisible(id, true) catch {};
    }
}

pub fn ensureRootParent(ui: *app.Ui, node_id: types.NodeId, parent: types.NodeId) void {
    const node = ui.tree.get(node_id) orelse return;
    if (parent == types.invalid_node) {
        if (node.parent != types.invalid_node) ui.tree.removeChild(node.parent, node_id);
        ui.setVisible(node_id, false) catch {};
        return;
    }
    if (node.parent != parent) ui.tree.appendChild(parent, node_id) catch {};
}

test "node origin uses retained bounds" {
    var ui_state = try app.Ui.init(std.testing.allocator);
    defer ui_state.deinit();
    const panel = try createPanel(&ui_state, ui_state.rootNode());
    ui_state.tree.get(panel).?.bounds = .{ .x = 14, .y = 27, .w = 10, .h = 10 };
    try std.testing.expectEqual(types.Vec2{ .x = 14, .y = 27 }, nodeOrigin(&ui_state, panel));
}
