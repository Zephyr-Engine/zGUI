const std = @import("std");
const types = @import("../core/types.zig");
const app = @import("../core/ui_context.zig");

pub const Options = struct {
    item_count: usize,
    row_height: f32,
    overscan: usize = 2,
};

pub const Range = struct {
    first: usize,
    last: usize,
    offset_y: f32,
    total_height: f32,

    pub fn count(self: Range) usize {
        return self.last - self.first;
    }
};

pub fn visibleRange(ui: *const app.Ui, scroll_node: types.NodeId, options: Options) Range {
    const node = ui.tree.getConst(scroll_node) orelse return emptyRange(options.item_count, options.row_height);
    if (options.item_count == 0 or !std.math.isFinite(options.row_height) or options.row_height <= 0) {
        return emptyRange(options.item_count, options.row_height);
    }

    const first_visible: usize = @intFromFloat(@floor(@max(0, node.scroll_offset.y) / options.row_height));
    const visible_count: usize = @intFromFloat(@ceil(@max(0, node.bounds.h) / options.row_height));
    const first = first_visible -| options.overscan;
    const last = @min(options.item_count, first_visible + visible_count + options.overscan);
    return .{
        .first = @min(first, last),
        .last = last,
        .offset_y = @as(f32, @floatFromInt(first)) * options.row_height,
        .total_height = @as(f32, @floatFromInt(options.item_count)) * options.row_height,
    };
}

fn emptyRange(item_count: usize, row_height: f32) Range {
    const height = if (std.math.isFinite(row_height) and row_height > 0)
        @as(f32, @floatFromInt(item_count)) * row_height
    else
        0;
    return .{ .first = 0, .last = 0, .offset_y = 0, .total_height = height };
}

test "visible range includes overscan and remains bounded" {
    var ui_state = try app.Ui.init(std.testing.allocator);
    defer ui_state.deinit();

    const list = try ui_state.tree.createNode(.panel);
    try ui_state.tree.appendChild(ui_state.root, list);
    const node = ui_state.tree.get(list).?;
    node.bounds = .{ .w = 200, .h = 100 };
    node.scroll_offset.y = 250;

    const range = visibleRange(&ui_state, list, .{
        .item_count = 100_000,
        .row_height = 20,
        .overscan = 2,
    });
    try std.testing.expectEqual(@as(usize, 10), range.first);
    try std.testing.expectEqual(@as(usize, 19), range.last);
    try std.testing.expectEqual(@as(usize, 9), range.count());
    try std.testing.expectEqual(@as(f32, 2_000_000), range.total_height);
}
