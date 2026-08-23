const std = @import("std");
const types = @import("../core/types.zig");
const app = @import("../core/ui_context.zig");
const primitives = @import("primitives.zig");

/// A retained popup/list building block. The caller supplies an overlay host
/// (normally a last child of the root or dock overlay host).
pub const SelectionList = struct {
    allocator: std.mem.Allocator,
    root_node: types.NodeId,
    item_nodes: std.ArrayListUnmanaged(types.NodeId) = .empty,
    open: bool = false,
    highlighted: usize = 0,

    pub fn init(allocator: std.mem.Allocator, ui: *app.Ui, overlay_host: types.NodeId) !SelectionList {
        const root = try primitives.surface(ui, overlay_host, .{
            .width = .{ .px = 220 },
            .height = .hug,
            .direction = .column,
            .background = .card,
            .border = .stroke,
            .border_width = 1,
            .radius = .control,
        });
        errdefer ui.destroySubtree(root);
        ui.tree.get(root).?.flags.interactive = true;
        try ui.setVisible(root, false);
        return .{ .allocator = allocator, .root_node = root };
    }

    pub fn deinit(self: *SelectionList, ui: *app.Ui) void {
        ui.destroySubtree(self.root_node);
        self.item_nodes.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn show(self: *SelectionList, ui: *app.Ui, position: types.Vec2) !void {
        var style = ui.nodeStyle(self.root_node) orelse return error.InvalidNode;
        style.margin.left = position.x;
        style.margin.top = position.y;
        try ui.setStyle(self.root_node, style);
        try ui.setVisible(self.root_node, true);
        ui.requestFocus(self.root_node);
        self.highlighted = 0;
        self.open = true;
    }

    pub fn close(self: *SelectionList, ui: *app.Ui) !void {
        if (isDescendant(ui, ui.focusedNode(), self.root_node)) ui.clearFocus();
        try ui.setVisible(self.root_node, false);
        self.open = false;
    }

    pub fn setItems(self: *SelectionList, ui: *app.Ui, labels: []const []const u8) !void {
        while (self.item_nodes.items.len > labels.len) {
            const node = self.item_nodes.pop().?;
            ui.destroySubtree(node);
        }
        while (self.item_nodes.items.len < labels.len) {
            const item = try primitives.themedButton(ui, self.root_node, "", .{
                .width = .fill,
                .height = .{ .px = 28 },
                .padding = .{ .left = 14, .right = 14, .top = 2, .bottom = 8 },
                .variant = .ghost,
                .border = .transparent,
                .border_width = 0,
                .font_size = ui.theme.font.body + 2,
            });
            applyItemStyle(ui, item);
            try self.item_nodes.append(self.allocator, item);
        }
        for (labels, self.item_nodes.items) |label, node| try ui.setText(node, label);
    }

    pub fn update(self: *SelectionList, ui: *app.Ui) !?usize {
        if (!self.open) return null;
        ui.capturePointer();
        if (ui.keyPressed(.escape)) {
            try self.close(ui);
            return null;
        }
        if (self.item_nodes.items.len != 0) {
            if (ui.keyPressed(.down)) self.highlighted = @min(self.highlighted + 1, self.item_nodes.items.len - 1);
            if (ui.keyPressed(.up)) self.highlighted -|= 1;
            if (ui.keyPressed(.enter) or ui.keyPressed(.space)) {
                const selected = self.highlighted;
                try self.close(ui);
                return selected;
            }
        }
        if (ui.mousePressed(.left) and !isDescendant(ui, ui.input.hovered, self.root_node)) {
            try self.close(ui);
            return null;
        }
        for (self.item_nodes.items, 0..) |node, index| {
            if (ui.input.hovered == node) ui.requestCursor(.hand);
            if (ui.activated(node)) {
                try self.close(ui);
                return index;
            }
        }
        return null;
    }
};

fn applyItemStyle(ui: *app.Ui, item: types.NodeId) void {
    const current = ui.nodeStyle(item) orelse return;
    var next = current;
    next.hover_background = ui.theme.color(.interaction_hover);
    next.pressed_background = ui.theme.color(.interaction_pressed);
    ui.setStyle(item, next) catch {};
}

fn isDescendant(ui: *const app.Ui, candidate: types.NodeId, ancestor: types.NodeId) bool {
    var node = candidate;
    while (node != types.invalid_node) {
        if (node == ancestor) return true;
        node = if (ui.tree.getConst(node)) |entry| entry.parent else types.invalid_node;
    }
    return false;
}
