const std = @import("std");
const types = @import("types.zig");
const node_mod = @import("node.zig");

pub const UiTree = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayList(node_mod.Node) = .empty,
    free_list: std.ArrayList(types.NodeId) = .empty,

    pub fn init(allocator: std.mem.Allocator) UiTree {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *UiTree) void {
        self.nodes.deinit(self.allocator);
        self.free_list.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn createNode(self: *UiTree, kind: node_mod.NodeKind) !types.NodeId {
        if (self.free_list.pop()) |id| {
            const slot = &self.nodes.items[id];
            const next_generation = @max(1, slot.generation +% 1);
            slot.* = node_mod.Node.init(id, next_generation, kind);
            return id;
        }

        const id: types.NodeId = @intCast(self.nodes.items.len);
        try self.nodes.append(self.allocator, node_mod.Node.init(id, 1, kind));
        return id;
    }

    pub fn destroyNode(self: *UiTree, id: types.NodeId) void {
        var node = self.get(id) orelse return;

        while (node.first_child != types.invalid_node) {
            const child = node.first_child;
            self.destroyNode(child);
            node = self.get(id) orelse return;
        }

        if (node.parent != types.invalid_node) {
            self.removeChild(node.parent, id);
            node = self.get(id) orelse return;
        }

        node.generation = 0;
        node.parent = types.invalid_node;
        node.first_child = types.invalid_node;
        node.last_child = types.invalid_node;
        node.next_sibling = types.invalid_node;
        node.prev_sibling = types.invalid_node;
        node.text = null;
        node.image = null;
        node.flags = .{ .visible = false };
        self.free_list.append(self.allocator, id) catch {};
    }

    pub fn appendChild(self: *UiTree, parent: types.NodeId, child: types.NodeId) !void {
        if (parent == child) return;
        const parent_node = self.get(parent) orelse return;
        const child_node = self.get(child) orelse return;

        if (child_node.parent != types.invalid_node) {
            self.removeChild(child_node.parent, child);
        }

        child_node.parent = parent;
        child_node.prev_sibling = parent_node.last_child;
        child_node.next_sibling = types.invalid_node;

        if (parent_node.last_child != types.invalid_node) {
            self.get(parent_node.last_child).?.next_sibling = child;
        } else {
            parent_node.first_child = child;
        }
        parent_node.last_child = child;
        parent_node.dirty.children = true;
        parent_node.dirty.layout = true;
        parent_node.dirty.paint = true;
    }

    pub fn removeChild(self: *UiTree, parent: types.NodeId, child: types.NodeId) void {
        const parent_node = self.get(parent) orelse return;
        const child_node = self.get(child) orelse return;
        if (child_node.parent != parent) return;

        if (child_node.prev_sibling != types.invalid_node) {
            self.get(child_node.prev_sibling).?.next_sibling = child_node.next_sibling;
        } else {
            parent_node.first_child = child_node.next_sibling;
        }

        if (child_node.next_sibling != types.invalid_node) {
            self.get(child_node.next_sibling).?.prev_sibling = child_node.prev_sibling;
        } else {
            parent_node.last_child = child_node.prev_sibling;
        }

        child_node.parent = types.invalid_node;
        child_node.next_sibling = types.invalid_node;
        child_node.prev_sibling = types.invalid_node;
        parent_node.dirty.children = true;
        parent_node.dirty.layout = true;
        parent_node.dirty.paint = true;
    }

    pub fn get(self: *UiTree, id: types.NodeId) ?*node_mod.Node {
        if (id == types.invalid_node) return null;
        if (id >= self.nodes.items.len) return null;
        const node = &self.nodes.items[id];
        if (node.generation == 0) return null;
        return node;
    }

    pub fn getConst(self: *const UiTree, id: types.NodeId) ?*const node_mod.Node {
        if (id == types.invalid_node) return null;
        if (id >= self.nodes.items.len) return null;
        const node = &self.nodes.items[id];
        if (node.generation == 0) return null;
        return node;
    }
};

test "node slots are reused" {
    var tree = UiTree.init(std.testing.allocator);
    defer tree.deinit();

    const a = try tree.createNode(.panel);
    tree.destroyNode(a);
    const b = try tree.createNode(.label);
    try std.testing.expectEqual(a, b);
    try std.testing.expectEqual(node_mod.NodeKind.label, tree.get(b).?.kind);
}

test "append and remove child maintain links" {
    var tree = UiTree.init(std.testing.allocator);
    defer tree.deinit();

    const root = try tree.createNode(.root);
    const a = try tree.createNode(.panel);
    const b = try tree.createNode(.button);
    try tree.appendChild(root, a);
    try tree.appendChild(root, b);
    try std.testing.expectEqual(a, tree.get(root).?.first_child);
    try std.testing.expectEqual(b, tree.get(root).?.last_child);
    try std.testing.expectEqual(b, tree.get(a).?.next_sibling);
    tree.removeChild(root, a);
    try std.testing.expectEqual(b, tree.get(root).?.first_child);
    try std.testing.expectEqual(types.invalid_node, tree.get(b).?.prev_sibling);
}
