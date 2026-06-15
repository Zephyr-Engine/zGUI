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
    pos: types.Vec2,
    text: []const u8,
    size: f32,
    color: types.Color,
};

pub const ImagePaint = struct {
    rect: types.Rect,
    texture_id: u32,
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

pub fn buildPaintList(tree: *const tree_mod.UiTree, root: types.NodeId, list: *PaintList) !void {
    const node = tree.getConst(root) orelse return;
    if (!node.flags.visible) return;

    const clipped = node.flags.clipped or node.style.overflow_x == .scroll or node.style.overflow_y == .scroll;
    if (clipped) try list.append(.{ .clip_push = node.bounds });

    var background = node.style.background;
    var border = node.style.border_color;
    if (node.kind == .button) {
        if (node.flags.pressed) {
            background = darken(background, 24);
            border = lighten(border, 36);
        } else if (node.flags.hovered) {
            background = lighten(background, 20);
            border = lighten(border, 20);
        }
    }

    if (background.a != 0 and !node.bounds.isEmpty()) {
        try list.append(.{ .rect = .{
            .rect = node.bounds,
            .color = background,
            .radius = node.style.radius,
        } });
    }

    if (node.image) |image| {
        if (image.texture_id != 0 and !node.bounds.isEmpty()) {
            try list.append(.{ .image = .{
                .rect = node.bounds,
                .texture_id = image.texture_id,
                .uv0 = image.uv0,
                .uv1 = image.uv1,
                .tint = image.tint,
                .radius = node.style.radius,
            } });
        }
    }

    const border_widths = node.style.border_edges orelse style_mod.Edges.all(node.style.border_width);
    if (hasBorder(border_widths) and border.a != 0 and !node.bounds.isEmpty()) {
        try list.append(.{ .border = .{
            .rect = node.bounds,
            .color = border,
            .widths = border_widths,
            .radius = node.style.radius,
        } });
    }

    if (node.text) |text| {
        try list.append(.{ .text = .{
            .pos = .{
                .x = node.bounds.x + node.style.padding.left,
                .y = node.bounds.y + node.style.padding.top + node.style.font_size,
            },
            .text = text,
            .size = node.style.font_size,
            .color = node.style.foreground,
        } });
    }

    var child = node.first_child;
    while (child != types.invalid_node) {
        const child_node = tree.getConst(child) orelse break;
        try buildPaintList(tree, child, list);
        child = child_node.next_sibling;
    }

    if (clipped) try list.append(.clip_pop);
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
