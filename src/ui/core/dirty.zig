const types = @import("types.zig");
const tree_mod = @import("tree.zig");

pub const DirtyFlags = packed struct {
    layout: bool = false,
    paint: bool = false,
    text: bool = false,
    children: bool = false,
    queued: bool = false,
};

pub fn markLayoutDirty(tree: *tree_mod.UiTree, id: types.NodeId) void {
    var current = id;
    while (tree.get(current)) |node| {
        node.dirty.layout = true;
        node.dirty.paint = true;
        tree.queueDirty(current);
        current = node.parent;
        if (current == types.invalid_node) break;
    }
}

pub fn markPaintDirty(tree: *tree_mod.UiTree, id: types.NodeId) void {
    if (tree.get(id)) |node| {
        node.dirty.paint = true;
        tree.queueDirty(id);
    }
}

