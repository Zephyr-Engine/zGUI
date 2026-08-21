const types = @import("types.zig");
const tree_mod = @import("tree.zig");

pub const DirtyFlags = packed struct {
    layout: bool = false,
    paint: bool = false,
    text: bool = false,
    children: bool = false,
    queued: bool = false,
    /// True once layout dirtiness has been propagated through the current
    /// ancestor chain. This lets repeated mutations in one frame stop early.
    layout_propagated: bool = false,
};

pub fn markLayoutDirty(tree: *tree_mod.UiTree, id: types.NodeId) void {
    tree.markLayoutDirty(id);
}

pub fn markPaintDirty(tree: *tree_mod.UiTree, id: types.NodeId) void {
    if (tree.get(id)) |node| {
        node.dirty.paint = true;
        tree.queueDirty(id);
    }
}
