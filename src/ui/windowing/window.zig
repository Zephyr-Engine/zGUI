const types = @import("../core/types.zig");

pub const WindowFlags = packed struct {
    movable: bool = true,
    resizable: bool = true,
    closable: bool = true,
    dockable: bool = true,
    modal: bool = false,
    title_bar: bool = true,
};

pub const Window = struct {
    id: types.WindowId,
    title: []const u8,
    rect: types.Rect,
    min_size: types.Vec2 = .{ .x = 160, .y = 120 },
    flags: WindowFlags = .{},
    root_node: types.NodeId = types.invalid_node,
    z_index: u32 = 0,
    open: bool = true,
};
