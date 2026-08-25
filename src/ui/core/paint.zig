const std = @import("std");
const types = @import("types.zig");
const style_mod = @import("style.zig");
const tree_mod = @import("tree.zig");

pub const PaintCommand = union(enum) {
    rect: RectPaint,
    border: BorderPaint,
    image: ImagePaint,
    text: TextPaint,
    clip_push: types.Rect,
    clip_pop,
};

pub const RectPaint = struct {
    rect: types.Rect,
    color: types.Color,
    radius: style_mod.CornerRadii = .{},
};

pub const BorderPaint = struct {
    rect: types.Rect,
    color: types.Color,
    widths: style_mod.Edges,
    radius: style_mod.CornerRadii = .{},
};

pub const TextPaint = struct {
    source_node: types.NodeId = 0,
    text_revision: u32 = 0,
    pos: types.Vec2,
    text: []const u8,
    size: f32,
    color: types.Color,
};

pub const ImagePaint = struct {
    rect: types.Rect,
    texture: types.TextureHandle,
    uv0: types.Vec2 = .{ .x = 0, .y = 0 },
    uv1: types.Vec2 = .{ .x = 1, .y = 1 },
    tint: types.Color = types.Color.rgba(255, 255, 255, 255),
    radius: style_mod.CornerRadii = .{},
};

pub const PaintList = struct {
    allocator: std.mem.Allocator,
    commands: std.ArrayList(PaintCommand) = .empty,

    pub fn init(allocator: std.mem.Allocator) PaintList {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *PaintList) void {
        self.commands.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn clearRetainingCapacity(self: *PaintList) void {
        self.commands.clearRetainingCapacity();
    }

    pub fn append(self: *PaintList, command: PaintCommand) !void {
        try self.commands.append(self.allocator, command);
    }
};

pub const PaintStats = struct {
    visited_nodes: u32 = 0,
    culled_subtrees: u32 = 0,
    culled_commands: u32 = 0,
};

pub fn buildPaintList(tree: *const tree_mod.UiTree, root: types.NodeId, list: *PaintList) !void {
    var stats: PaintStats = .{};
    try buildPaintNode(tree, root, list, null, &stats);
}

pub fn buildPaintListMeasured(tree: *const tree_mod.UiTree, root: types.NodeId, list: *PaintList) !PaintStats {
    var stats: PaintStats = .{};
    try buildPaintNode(tree, root, list, null, &stats);
    return stats;
}

fn buildPaintNode(tree: *const tree_mod.UiTree, root: types.NodeId, list: *PaintList, inherited_clip: ?types.Rect, stats: *PaintStats) !void {
    const node = tree.getConst(root) orelse return;
    if (!node.flags.visible) return;
    stats.visited_nodes += 1;

    if (inherited_clip) |clip| {
        if (!rectsIntersect(node.layout.visual_bounds, clip)) {
            stats.culled_subtrees += 1;
            return;
        }
    }

    const clipped = node.flags.clipped or node.style.overflow_x == .scroll or node.style.overflow_y == .scroll;
    // Include the node's antialiased edge in its own clip. Its visual bounds
    // already reserve this one-pixel outset, so this keeps control borders
    // from losing their final edge at a clipping boundary.
    const effective_clip = if (clipped)
        if (inherited_clip) |clip| intersectRects(clip, outsetRect(node.bounds, 1)) else outsetRect(node.bounds, 1)
    else
        inherited_clip;
    if (effective_clip) |clip| {
        if (clip.isEmpty()) {
            stats.culled_subtrees += 1;
            return;
        }
    }
    if (clipped) try list.append(.{ .clip_push = node.bounds });

    var background = node.style.background;
    var border = node.style.border_color;
    if (node.kind == .button) {
        if (node.flags.pressed) {
            background = node.style.pressed_background orelse darken(background, 24);
            border = node.style.pressed_border_color orelse lighten(border, 36);
        } else if (node.flags.hovered) {
            background = node.style.hover_background orelse lighten(background, 20);
            border = node.style.hover_border_color orelse lighten(border, 20);
        }
    }

    if (background.a != 0 and commandVisible(node.bounds, 1, effective_clip, stats)) {
        try list.append(.{ .rect = .{
            .rect = node.bounds,
            .color = background,
            .radius = node.style.radius,
        } });
    }

    if (node.image) |image| {
        if (image.texture.isValid() and commandVisible(node.bounds, 1, effective_clip, stats)) {
            const image_rect = if (node.kind == .button) node.bounds.inset(node.style.padding) else node.bounds;
            const tint = if (node.kind == .button and node.flags.pressed)
                image.pressed_tint orelse image.tint
            else if (node.kind == .button and node.flags.hovered)
                image.hover_tint orelse image.tint
            else
                image.tint;
            try list.append(.{ .image = .{
                .rect = image_rect,
                .texture = image.texture,
                .uv0 = image.uv0,
                .uv1 = image.uv1,
                .tint = tint,
                .radius = node.style.radius,
            } });
        }
    }

    const border_widths = node.style.border_edges orelse style_mod.Edges.all(node.style.border_width);
    if (hasBorder(border_widths) and border.a != 0 and commandVisible(node.bounds, 1, effective_clip, stats)) {
        try list.append(.{ .border = .{
            .rect = node.bounds,
            .color = border,
            .widths = border_widths,
            .radius = node.style.radius,
        } });
    }

    if (node.text) |text| if (commandVisible(node.bounds, @max(@as(f32, 1), node.style.font_size * 0.25), effective_clip, stats)) {
        try list.append(.{ .text = .{
            .source_node = root,
            .text_revision = node.text_revision,
            .pos = .{
                .x = node.bounds.x + node.style.padding.left,
                .y = node.bounds.y + node.style.padding.top + node.style.font_size,
            },
            .text = text,
            .size = node.style.font_size,
            .color = node.style.foreground,
        } });
    };

    var child = node.first_child;
    while (child != types.invalid_node) {
        const child_node = tree.getConst(child) orelse break;
        try buildPaintNode(tree, child, list, effective_clip, stats);
        child = child_node.next_sibling;
    }

    if (clipped) try list.append(.clip_pop);
}

fn commandVisible(bounds: types.Rect, outset: f32, clip: ?types.Rect, stats: *PaintStats) bool {
    if (bounds.isEmpty()) return false;
    if (clip) |active| {
        if (!rectsIntersect(outsetRect(bounds, outset), active)) {
            stats.culled_commands += 1;
            return false;
        }
    }
    return true;
}

fn outsetRect(rect: types.Rect, amount: f32) types.Rect {
    return .{
        .x = rect.x - amount,
        .y = rect.y - amount,
        .w = rect.w + amount * 2,
        .h = rect.h + amount * 2,
    };
}

fn rectsIntersect(a: types.Rect, b: types.Rect) bool {
    return !a.isEmpty() and !b.isEmpty() and
        a.x < b.x + b.w and a.x + a.w > b.x and
        a.y < b.y + b.h and a.y + a.h > b.y;
}

fn intersectRects(a: types.Rect, b: types.Rect) types.Rect {
    const x0 = @max(a.x, b.x);
    const y0 = @max(a.y, b.y);
    const x1 = @min(a.x + a.w, b.x + b.w);
    const y1 = @min(a.y + a.h, b.y + b.h);
    return .{ .x = x0, .y = y0, .w = @max(0, x1 - x0), .h = @max(0, y1 - y0) };
}

fn lighten(color: types.Color, amount: u8) types.Color {
    return .{
        .r = color.r +| amount,
        .g = color.g +| amount,
        .b = color.b +| amount,
        .a = color.a,
    };
}

fn darken(color: types.Color, amount: u8) types.Color {
    return .{
        .r = color.r -| amount,
        .g = color.g -| amount,
        .b = color.b -| amount,
        .a = color.a,
    };
}

fn hasBorder(edges: style_mod.Edges) bool {
    return edges.left > 0 or edges.right > 0 or edges.top > 0 or edges.bottom > 0;
}

test "clipped containers skip offscreen subtrees" {
    const layout_mod = @import("layout.zig");

    var tree = tree_mod.UiTree.init(std.testing.allocator);
    defer tree.deinit();
    var list = PaintList.init(std.testing.allocator);
    defer list.deinit();

    const root = try tree.createNode(.root);
    const scroller = try tree.createNode(.panel);
    tree.get(root).?.style = .{ .width = .fill, .height = .fill };
    tree.get(scroller).?.style = .{
        .width = .fill,
        .height = .fill,
        .direction = .column,
        .overflow_y = .scroll,
    };
    try tree.appendChild(root, scroller);
    for (0..100) |_| {
        const row = try tree.createNode(.panel);
        tree.get(row).?.style = .{
            .width = .fill,
            .height = .{ .px = 10 },
            .background = types.Color.rgba(255, 255, 255, 255),
        };
        try tree.appendChild(scroller, row);
    }

    layout_mod.layoutTree(&tree, root, .{ .x = 100, .y = 100 }, null);
    const stats = try buildPaintListMeasured(&tree, root, &list);
    try std.testing.expect(stats.culled_subtrees >= 89);
    try std.testing.expect(list.commands.items.len < 20);
}
