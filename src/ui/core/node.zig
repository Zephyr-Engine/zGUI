const types = @import("types.zig");
const style_mod = @import("style.zig");
const layout_mod = @import("layout.zig");
const dirty_mod = @import("dirty.zig");

pub const NodeKind = enum {
    root,
    panel,
    label,
    button,
    image,
    custom,
};

pub const Image = struct {
    texture_id: u32 = 0,
    uv0: types.Vec2 = .{ .x = 0, .y = 0 },
    uv1: types.Vec2 = .{ .x = 1, .y = 1 },
    tint: types.Color = types.Color.rgba(255, 255, 255, 255),
};

pub const NodeFlags = packed struct {
    visible: bool = true,
    interactive: bool = false,
    hovered: bool = false,
    pressed: bool = false,
    focused: bool = false,
    clipped: bool = false,
};

pub const Node = struct {
    id: types.NodeId,
    generation: u32,

    kind: NodeKind,

    parent: types.NodeId = types.invalid_node,
    first_child: types.NodeId = types.invalid_node,
    last_child: types.NodeId = types.invalid_node,
    next_sibling: types.NodeId = types.invalid_node,
    prev_sibling: types.NodeId = types.invalid_node,

    bounds: types.Rect = .{},
    scroll_offset: types.Vec2 = .{},
    scroll_target_offset: types.Vec2 = .{},

    style: style_mod.Style = .{},
    layout: layout_mod.Layout = .{},
    dirty: dirty_mod.DirtyFlags = .{ .layout = true, .paint = true },

    flags: NodeFlags = .{},

    text: ?[]const u8 = null,
    image: ?Image = null,

    pub fn init(id: types.NodeId, generation: u32, kind: NodeKind) Node {
        return .{
            .id = id,
            .generation = generation,
            .kind = kind,
            .flags = .{ .interactive = kind == .button },
        };
    }
};
