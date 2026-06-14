const std = @import("std");
const types = @import("types.zig");
const style_mod = @import("style.zig");
const tree_mod = @import("tree.zig");
const text_mod = @import("text.zig");

pub const Layout = struct {
    intrinsic: types.Vec2 = .{},
};

const Axis = enum { x, y };

pub fn layoutTree(tree: *tree_mod.UiTree, root: types.NodeId, available: types.Vec2, text_measurer: ?text_mod.TextMeasurer) void {
    const root_node = tree.get(root) orelse return;
    root_node.bounds = .{ .x = 0, .y = 0, .w = available.x, .h = available.y };
    _ = measureNode(tree, root, text_measurer);
    layoutChildren(tree, root);
}

fn measureNode(tree: *tree_mod.UiTree, id: types.NodeId, text_measurer: ?text_mod.TextMeasurer) types.Vec2 {
    const node = tree.get(id) orelse return .{};
    var measured: types.Vec2 = .{};

    if (node.text) |bytes| {
        const metrics = if (text_measurer) |measurer|
            measurer.measure(bytes, node.style.font_size)
        else
            text_mod.measureFallback(bytes, node.style.font_size);
        measured = metrics.size;
    }

    var child = node.first_child;
    var child_count: usize = 0;
    while (child != types.invalid_node) {
        const child_size = measureNode(tree, child, text_measurer);
        const child_node = tree.get(child) orelse break;
        child_count += 1;
        switch (node.style.direction) {
            .row => {
                measured.x += child_size.x + child_node.style.margin.horizontal();
                measured.y = @max(measured.y, child_size.y + child_node.style.margin.vertical());
            },
            .column, .absolute => {
                measured.x = @max(measured.x, child_size.x + child_node.style.margin.horizontal());
                measured.y += child_size.y + child_node.style.margin.vertical();
            },
        }
        child = child_node.next_sibling;
    }

    if (child_count > 1 and node.style.direction != .absolute) {
        const gaps = @as(f32, @floatFromInt(child_count - 1)) * node.style.gap;
        if (node.style.direction == .row) measured.x += gaps else measured.y += gaps;
    }

    measured.x += node.style.padding.horizontal();
    measured.y += node.style.padding.vertical();
    measured.x = @max(measured.x, node.style.min_width);
    measured.y = @max(measured.y, node.style.min_height);
    node.layout.intrinsic = measured;
    return measured;
}

fn layoutChildren(tree: *tree_mod.UiTree, id: types.NodeId) void {
    const parent = tree.get(id) orelse return;
    const direction = parent.style.direction;
    const padding = parent.style.padding;
    const gap = parent.style.gap;
    const content: types.Rect = parent.bounds.inset(padding);

    switch (direction) {
        .absolute => layoutAbsolute(tree, parent.first_child, content),
        .row => layoutLinear(tree, parent.first_child, content, gap, .x),
        .column => layoutLinear(tree, parent.first_child, content, gap, .y),
    }
}

fn layoutAbsolute(tree: *tree_mod.UiTree, first_child: types.NodeId, content: types.Rect) void {
    var child = first_child;
    while (child != types.invalid_node) {
        const child_node = tree.get(child) orelse break;
        const margin = child_node.style.margin;
        const width = resolveSize(child_node.style.width, .x, content, child_node.layout.intrinsic);
        const height = resolveSize(child_node.style.height, .y, content, child_node.layout.intrinsic);
        child_node.bounds = .{
            .x = content.x + margin.left,
            .y = content.y + margin.top,
            .w = @max(width, child_node.style.min_width),
            .h = @max(height, child_node.style.min_height),
        };
        const next = child_node.next_sibling;
        layoutChildren(tree, child);
        child = next;
    }
}

fn layoutLinear(tree: *tree_mod.UiTree, first_child: types.NodeId, content: types.Rect, gap: f32, axis: Axis) void {
    var fixed_major: f32 = 0;
    var fill_count: usize = 0;
    var child_count: usize = 0;

    var child = first_child;
    while (child != types.invalid_node) {
        const child_node = tree.get(child) orelse break;
        child_count += 1;
        const margin_major = if (axis == .x) child_node.style.margin.horizontal() else child_node.style.margin.vertical();
        if (sizeForAxis(child_node.style, axis) == .fill) {
            fill_count += 1;
            fixed_major += margin_major;
        } else {
            fixed_major += resolveSize(sizeForAxis(child_node.style, axis), axis, content, child_node.layout.intrinsic) + margin_major;
        }
        child = child_node.next_sibling;
    }

    if (child_count > 1) {
        fixed_major += @as(f32, @floatFromInt(child_count - 1)) * gap;
    }

    const available_major = if (axis == .x) content.w else content.h;
    const fill_major = if (fill_count == 0) 0 else @max(0, available_major - fixed_major) / @as(f32, @floatFromInt(fill_count));

    var cursor = if (axis == .x) content.x else content.y;
    child = first_child;
    while (child != types.invalid_node) {
        const child_node = tree.get(child) orelse break;
        const margin = child_node.style.margin;

        const width = if (axis == .x)
            resolveLinearSize(child_node.style.width, .x, content, child_node.layout.intrinsic, fill_major)
        else
            resolveSize(child_node.style.width, .x, content, child_node.layout.intrinsic);

        const height = if (axis == .y)
            resolveLinearSize(child_node.style.height, .y, content, child_node.layout.intrinsic, fill_major)
        else
            resolveSize(child_node.style.height, .y, content, child_node.layout.intrinsic);

        if (axis == .x) {
            cursor += margin.left;
            child_node.bounds = .{
                .x = cursor,
                .y = content.y + margin.top,
                .w = @max(width, child_node.style.min_width),
                .h = @max(height, child_node.style.min_height),
            };
            cursor += child_node.bounds.w + margin.right + gap;
        } else {
            cursor += margin.top;
            child_node.bounds = .{
                .x = content.x + margin.left,
                .y = cursor,
                .w = @max(width, child_node.style.min_width),
                .h = @max(height, child_node.style.min_height),
            };
            cursor += child_node.bounds.h + margin.bottom + gap;
        }

        const next = child_node.next_sibling;
        layoutChildren(tree, child);
        child = next;
    }
}

fn resolveLinearSize(size: style_mod.Size, axis: Axis, content: types.Rect, intrinsic: types.Vec2, fill_value: f32) f32 {
    return switch (size) {
        .fill => fill_value,
        else => resolveSize(size, axis, content, intrinsic),
    };
}

fn resolveSize(size: style_mod.Size, axis: Axis, content: types.Rect, intrinsic: types.Vec2) f32 {
    return switch (size) {
        .px => |v| v,
        .percent => |v| (if (axis == .x) content.w else content.h) * v,
        .fill => if (axis == .x) content.w else content.h,
        .hug => if (axis == .x) intrinsic.x else intrinsic.y,
    };
}

fn sizeForAxis(style: style_mod.Style, axis: Axis) style_mod.Size {
    return if (axis == .x) style.width else style.height;
}

test "column fill lays out remaining height" {
    var tree = tree_mod.UiTree.init(std.testing.allocator);
    defer tree.deinit();

    const root = try tree.createNode(.root);
    const top = try tree.createNode(.panel);
    const fill = try tree.createNode(.panel);
    tree.get(root).?.style = .{ .width = .fill, .height = .fill };
    tree.get(top).?.style = .{ .width = .fill, .height = .{ .px = 20 } };
    tree.get(fill).?.style = .{ .width = .fill, .height = .fill };
    try tree.appendChild(root, top);
    try tree.appendChild(root, fill);

    layoutTree(&tree, root, .{ .x = 100, .y = 80 }, null);
    try std.testing.expectEqual(@as(f32, 20), tree.get(top).?.bounds.h);
    try std.testing.expectEqual(@as(f32, 60), tree.get(fill).?.bounds.h);
}
