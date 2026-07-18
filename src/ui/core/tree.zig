const std = @import("std");
const types = @import("types.zig");
const node_mod = @import("node.zig");

pub const UiTree = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayList(node_mod.Node) = .empty,
    free_list: std.ArrayList(u32) = .empty,

    pub fn init(allocator: std.mem.Allocator) UiTree {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *UiTree) void {
        for (self.nodes.items) |*node| {
            if (node.text) |text| self.allocator.free(text);
        }
        self.nodes.deinit(self.allocator);
        self.free_list.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn createNode(self: *UiTree, kind: node_mod.NodeKind) !types.NodeId {
        if (self.free_list.pop()) |index| {
            const slot = &self.nodes.items[index];
            const next_generation: u8 = if (slot.generation == std.math.maxInt(u8)) 1 else slot.generation + 1;
            const id = types.makeNodeId(index, next_generation);
            slot.* = node_mod.Node.init(id, next_generation, kind);
            return id;
        }

        const index: u32 = @intCast(self.nodes.items.len);
        if (index > types.max_node_index) return error.TooManyNodes;
        const id = types.makeNodeId(index, 1);
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

        if (node.text) |text| self.allocator.free(text);
        node.text = null;
        node.generation = 0;
        node.parent = types.invalid_node;
        node.first_child = types.invalid_node;
        node.last_child = types.invalid_node;
        node.next_sibling = types.invalid_node;
        node.prev_sibling = types.invalid_node;
        node.image = null;
        node.flags = .{ .visible = false };
        self.free_list.append(self.allocator, types.nodeIndex(id)) catch {};
    }

    /// Copies `bytes` into tree-owned storage. No-op when the text is
    /// unchanged, so it is safe (and cheap) to call every frame.
    pub fn setText(self: *UiTree, id: types.NodeId, bytes: []const u8) !void {
        const node = self.get(id) orelse return;
        if (node.text) |existing| {
            if (std.mem.eql(u8, existing, bytes)) return;
        }
        const owned = try self.allocator.dupe(u8, bytes);
        if (node.text) |existing| self.allocator.free(existing);
        node.text = owned;
        node.dirty.text = true;
        node.dirty.layout = true;
        node.dirty.paint = true;
    }

    pub fn appendChild(self: *UiTree, parent: types.NodeId, child: types.NodeId) !void {
        if (parent == child) return;
        const parent_node = self.get(parent) orelse return;
        const child_node = self.get(child) orelse return;

        // Already the last child of this parent: nothing to do, and no dirty
        // marks, so per-frame re-appends stay free in the steady state.
        if (child_node.parent == parent and parent_node.last_child == child) return;

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
        const index = types.nodeIndex(id);
        if (index >= self.nodes.items.len) return null;
        const node = &self.nodes.items[index];
        if (node.generation == 0 or node.generation != types.nodeGeneration(id)) return null;
        return node;
    }

    pub fn getConst(self: *const UiTree, id: types.NodeId) ?*const node_mod.Node {
        if (id == types.invalid_node) return null;
        const index = types.nodeIndex(id);
        if (index >= self.nodes.items.len) return null;
        const node = &self.nodes.items[index];
        if (node.generation == 0 or node.generation != types.nodeGeneration(id)) return null;
        return node;
    }
};

test "node slots are reused with fresh generations" {
    var tree = UiTree.init(std.testing.allocator);
    defer tree.deinit();

    const a = try tree.createNode(.panel);
    tree.destroyNode(a);
    const b = try tree.createNode(.label);
    try std.testing.expectEqual(types.nodeIndex(a), types.nodeIndex(b));
    try std.testing.expect(a != b);
    try std.testing.expectEqual(node_mod.NodeKind.label, tree.get(b).?.kind);
}

test "stale node ids do not resolve after slot reuse" {
    var tree = UiTree.init(std.testing.allocator);
    defer tree.deinit();

    const a = try tree.createNode(.panel);
    tree.destroyNode(a);
    const b = try tree.createNode(.button);
    try std.testing.expect(tree.get(a) == null);
    try std.testing.expect(tree.getConst(a) == null);
    try std.testing.expect(tree.get(b) != null);
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

test "re-appending the last child is a no-op" {
    var tree = UiTree.init(std.testing.allocator);
    defer tree.deinit();

    const root = try tree.createNode(.root);
    const a = try tree.createNode(.panel);
    const b = try tree.createNode(.panel);
    try tree.appendChild(root, a);
    try tree.appendChild(root, b);
    tree.get(root).?.dirty = .{};

    try tree.appendChild(root, b);
    try std.testing.expect(!tree.get(root).?.dirty.children);
    try std.testing.expectEqual(b, tree.get(root).?.last_child);

    try tree.appendChild(root, a);
    try std.testing.expect(tree.get(root).?.dirty.children);
    try std.testing.expectEqual(a, tree.get(root).?.last_child);
}

test "setText copies into tree-owned storage and skips unchanged text" {
    var tree = UiTree.init(std.testing.allocator);
    defer tree.deinit();

    const label = try tree.createNode(.label);
    var buf: [16]u8 = undefined;
    const first = try std.fmt.bufPrint(&buf, "hello {d}", .{1});
    try tree.setText(label, first);
    buf = @splat(0);
    try std.testing.expectEqualStrings("hello 1", tree.get(label).?.text.?);

    tree.get(label).?.dirty = .{};
    try tree.setText(label, "hello 1");
    try std.testing.expect(!tree.get(label).?.dirty.text);

    try tree.setText(label, "hello 2");
    try std.testing.expect(tree.get(label).?.dirty.text);
    try std.testing.expectEqualStrings("hello 2", tree.get(label).?.text.?);
}
