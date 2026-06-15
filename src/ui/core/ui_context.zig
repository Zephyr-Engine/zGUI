const std = @import("std");
const types = @import("types.zig");
const tree_mod = @import("tree.zig");
const layout_mod = @import("layout.zig");
const text_mod = @import("text.zig");
const input_mod = @import("input.zig");
const paint_mod = @import("paint.zig");
const theme_mod = @import("../theme.zig");
const platform_events = @import("../platform/events.zig");
const batcher_mod = @import("../render/batcher.zig");
const draw_data_mod = @import("../render/draw_data.zig");

const scroll_wheel_scale: f32 = 46;
const scroll_animation_rate: f32 = 18;

pub const BeginFrame = struct {
    events: []const platform_events.PlatformEvent = &.{},
    window_size: types.Vec2,
    dt: f32 = 0,
};

pub const UiStats = struct {
    node_count: u32 = 0,
    dirty_layout_count: u32 = 0,
    dirty_paint_count: u32 = 0,
    paint_command_count: u32 = 0,
    vertex_count: u32 = 0,
    index_count: u32 = 0,
    batch_count: u32 = 0,
    draw_call_count: u32 = 0,
    frame_alloc_count: u32 = 0,
};

pub const Ui = struct {
    allocator: std.mem.Allocator,
    tree: tree_mod.UiTree,
    paint_list: paint_mod.PaintList,
    batcher: batcher_mod.Batcher,
    input: input_mod.InputState = .{},
    root: types.NodeId = types.invalid_node,
    window_size: types.Vec2 = .{},
    dt: f32 = 0,
    stats: UiStats = .{},
    current_draw_data: draw_data_mod.DrawData = .empty,
    text_measurer: ?text_mod.TextMeasurer = null,
    font_atlas: ?*batcher_mod.FontAtlas = null,
    text_raster_scale: f32 = 1,
    theme: theme_mod.Theme = theme_mod.zephyr_dark,
    requested_cursor: platform_events.CursorKind = .arrow,

    pub fn init(allocator: std.mem.Allocator) !Ui {
        var tree = tree_mod.UiTree.init(allocator);
        errdefer tree.deinit();

        const root = try tree.createNode(.root);
        if (tree.get(root)) |node| {
            node.style.width = .fill;
            node.style.height = .fill;
            node.flags.visible = true;
        }

        return .{
            .allocator = allocator,
            .tree = tree,
            .paint_list = paint_mod.PaintList.init(allocator),
            .batcher = batcher_mod.Batcher.init(allocator),
            .root = root,
        };
    }

    pub fn deinit(self: *Ui) void {
        self.batcher.deinit();
        self.paint_list.deinit();
        self.tree.deinit();
        self.* = undefined;
    }

    pub fn beginFrame(self: *Ui, frame: BeginFrame) !void {
        self.window_size = frame.window_size;
        self.dt = frame.dt;
        self.requested_cursor = .arrow;
        self.input.beginFrame();
        for (frame.events) |event| {
            input_mod.applyEvent(&self.input, event);
        }
        input_mod.routePointerState(&self.tree, self.root, &self.input);
    }

    pub fn endFrame(self: *Ui) !void {
        layout_mod.layoutTree(&self.tree, self.root, self.window_size, self.text_measurer);
        const clamped_scroll = self.clampScrollOffsets(self.root);
        const input_scroll = self.applyScrollInput();
        const animated_scroll = self.animateScrollOffsets(self.root);
        if (clamped_scroll or input_scroll or animated_scroll) {
            layout_mod.layoutTree(&self.tree, self.root, self.window_size, self.text_measurer);
        }
        self.paint_list.clearRetainingCapacity();
        try paint_mod.buildPaintList(&self.tree, self.root, &self.paint_list);
        self.current_draw_data = try self.batcher.build(self.paint_list.commands.items, self.font_atlas, self.text_raster_scale);
        self.updateStats();
        self.clearDirty();
    }

    pub fn setTextMeasurer(self: *Ui, text_measurer: ?text_mod.TextMeasurer) void {
        self.text_measurer = text_measurer;
    }

    pub fn setFontAtlas(self: *Ui, font_atlas: ?*batcher_mod.FontAtlas) void {
        self.font_atlas = font_atlas;
        self.text_measurer = if (font_atlas) |atlas| atlas.textMeasurer() else null;
    }

    pub fn setTextRasterScale(self: *Ui, raster_scale: f32) void {
        if (!std.math.isFinite(raster_scale)) {
            self.text_raster_scale = 1;
            return;
        }
        self.text_raster_scale = @max(0.25, raster_scale);
    }

    pub fn setTheme(self: *Ui, theme: theme_mod.Theme) void {
        self.theme = theme;
    }

    pub fn drawData(self: *const Ui) draw_data_mod.DrawData {
        return self.current_draw_data;
    }

    pub fn requestCursor(self: *Ui, cursor: platform_events.CursorKind) void {
        self.requested_cursor = cursor;
    }

    pub fn requestedCursor(self: *const Ui) platform_events.CursorKind {
        return self.requested_cursor;
    }

    pub fn processPlatformEvent(self: *Ui, event: platform_events.PlatformEvent) void {
        input_mod.applyEvent(&self.input, event);
    }

    fn updateStats(self: *Ui) void {
        var dirty_layout_count: u32 = 0;
        var dirty_paint_count: u32 = 0;
        for (self.tree.nodes.items) |node| {
            if (node.generation == 0) continue;
            if (node.dirty.layout) dirty_layout_count += 1;
            if (node.dirty.paint) dirty_paint_count += 1;
        }

        self.stats = .{
            .node_count = @intCast(self.tree.nodes.items.len - self.tree.free_list.items.len),
            .dirty_layout_count = dirty_layout_count,
            .dirty_paint_count = dirty_paint_count,
            .paint_command_count = @intCast(self.paint_list.commands.items.len),
            .vertex_count = @intCast(self.batcher.vertices.items.len),
            .index_count = @intCast(self.batcher.indices.items.len),
            .batch_count = @intCast(self.batcher.batches.items.len),
            .draw_call_count = @intCast(self.batcher.batches.items.len),
        };
    }

    fn clearDirty(self: *Ui) void {
        for (self.tree.nodes.items) |*node| {
            if (node.generation != 0) node.dirty = .{};
        }
    }

    fn applyScrollInput(self: *Ui) bool {
        if (self.input.scroll_delta.x == 0 and self.input.scroll_delta.y == 0) return false;
        const target = scrollTargetAt(&self.tree, self.root, self.input.mouse_pos, self.input.scroll_delta) orelse return false;
        const node = self.tree.get(target) orelse return false;
        const before = node.scroll_target_offset;

        if (node.style.overflow_x == .scroll) {
            node.scroll_target_offset.x -= self.input.scroll_delta.x * scroll_wheel_scale;
        }
        if (node.style.overflow_y == .scroll) {
            node.scroll_target_offset.y -= self.input.scroll_delta.y * scroll_wheel_scale;
        }

        clampScroll(node);
        const changed = before.x != node.scroll_target_offset.x or before.y != node.scroll_target_offset.y;
        if (changed) {
            node.dirty.layout = true;
            node.dirty.paint = true;
        }
        return changed;
    }

    fn animateScrollOffsets(self: *Ui, id: types.NodeId) bool {
        const node = self.tree.get(id) orelse return false;
        if (!node.flags.visible) return false;

        var changed = animateNodeScroll(node, self.dt);
        if (changed) {
            node.dirty.layout = true;
            node.dirty.paint = true;
        }

        var child = node.first_child;
        while (child != types.invalid_node) {
            const next = if (self.tree.getConst(child)) |child_node| child_node.next_sibling else types.invalid_node;
            changed = self.animateScrollOffsets(child) or changed;
            child = next;
        }
        return changed;
    }

    fn clampScrollOffsets(self: *Ui, id: types.NodeId) bool {
        const node = self.tree.get(id) orelse return false;
        if (!node.flags.visible) return false;

        const before = node.scroll_offset;
        const before_target = node.scroll_target_offset;
        clampScroll(node);
        var changed = before.x != node.scroll_offset.x or
            before.y != node.scroll_offset.y or
            before_target.x != node.scroll_target_offset.x or
            before_target.y != node.scroll_target_offset.y;
        if (changed) {
            node.dirty.layout = true;
            node.dirty.paint = true;
        }

        var child = node.first_child;
        while (child != types.invalid_node) {
            const next = if (self.tree.getConst(child)) |child_node| child_node.next_sibling else types.invalid_node;
            changed = self.clampScrollOffsets(child) or changed;
            child = next;
        }
        return changed;
    }
};

fn scrollTargetAt(tree: *const tree_mod.UiTree, id: types.NodeId, pos: types.Vec2, delta: types.Vec2) ?types.NodeId {
    const node = tree.getConst(id) orelse return null;
    if (!node.flags.visible or !node.bounds.contains(pos)) return null;

    var child = node.last_child;
    while (child != types.invalid_node) {
        if (scrollTargetAt(tree, child, pos, delta)) |hit| return hit;
        const child_node = tree.getConst(child) orelse break;
        child = child_node.prev_sibling;
    }

    if (canScrollForDelta(node, delta)) return id;
    return null;
}

fn canScrollForDelta(node: anytype, delta: types.Vec2) bool {
    if (delta.x != 0 and node.style.overflow_x == .scroll and maxScroll(node, .x) > 0) return true;
    if (delta.y != 0 and node.style.overflow_y == .scroll and maxScroll(node, .y) > 0) return true;
    return false;
}

fn clampScroll(node: anytype) void {
    const max_x = maxScroll(node, .x);
    const max_y = maxScroll(node, .y);
    if (node.style.overflow_x == .scroll) {
        node.scroll_offset.x = clamp(node.scroll_offset.x, 0, max_x);
        node.scroll_target_offset.x = clamp(node.scroll_target_offset.x, 0, max_x);
    } else {
        node.scroll_offset.x = 0;
        node.scroll_target_offset.x = 0;
    }
    if (node.style.overflow_y == .scroll) {
        node.scroll_offset.y = clamp(node.scroll_offset.y, 0, max_y);
        node.scroll_target_offset.y = clamp(node.scroll_target_offset.y, 0, max_y);
    } else {
        node.scroll_offset.y = 0;
        node.scroll_target_offset.y = 0;
    }
}

fn animateNodeScroll(node: anytype, dt: f32) bool {
    const t = scrollStep(dt);
    const before = node.scroll_offset;
    node.scroll_offset.x = approach(node.scroll_offset.x, node.scroll_target_offset.x, t);
    node.scroll_offset.y = approach(node.scroll_offset.y, node.scroll_target_offset.y, t);
    return before.x != node.scroll_offset.x or before.y != node.scroll_offset.y;
}

fn scrollStep(dt: f32) f32 {
    if (!std.math.isFinite(dt) or dt <= 0) return 1;
    return 1 - @exp(-scroll_animation_rate * @min(dt, 0.05));
}

fn approach(current: f32, target: f32, t: f32) f32 {
    if (@abs(target - current) < 0.25) return target;
    return current + (target - current) * t;
}

fn maxScroll(node: anytype, axis: enum { x, y }) f32 {
    const viewport = node.bounds.inset(node.style.padding);
    return switch (axis) {
        .x => @max(0, node.layout.content_size.x - viewport.w),
        .y => @max(0, node.layout.content_size.y - viewport.h),
    };
}

fn clamp(v: f32, lo: f32, hi: f32) f32 {
    return @min(hi, @max(lo, v));
}

test "scroll input updates both overflow axes and clamps to content" {
    var ui_state = try Ui.init(std.testing.allocator);
    defer ui_state.deinit();

    const scroller = try ui_state.tree.createNode(.panel);
    const child = try ui_state.tree.createNode(.panel);
    ui_state.tree.get(scroller).?.style = .{
        .width = .fill,
        .height = .fill,
        .overflow_x = .scroll,
        .overflow_y = .scroll,
    };
    ui_state.tree.get(child).?.style = .{
        .width = .{ .px = 180 },
        .height = .{ .px = 140 },
    };
    try ui_state.tree.appendChild(ui_state.root, scroller);
    try ui_state.tree.appendChild(scroller, child);

    try ui_state.beginFrame(.{
        .events = &[_]platform_events.PlatformEvent{
            .{ .mouse_move = .{ .x = 10, .y = 10 } },
            .{ .scroll = .{ .x = -1, .y = -1 } },
        },
        .window_size = .{ .x = 100, .y = 80 },
        .dt = 1.0 / 60.0,
    });
    try ui_state.endFrame();

    try std.testing.expectEqual(@as(f32, scroll_wheel_scale), ui_state.tree.get(scroller).?.scroll_target_offset.x);
    try std.testing.expectEqual(@as(f32, scroll_wheel_scale), ui_state.tree.get(scroller).?.scroll_target_offset.y);
    try std.testing.expect(ui_state.tree.get(scroller).?.scroll_offset.x > 0);
    try std.testing.expect(ui_state.tree.get(scroller).?.scroll_offset.x < ui_state.tree.get(scroller).?.scroll_target_offset.x);
    try std.testing.expectEqual(-ui_state.tree.get(scroller).?.scroll_offset.x, ui_state.tree.get(child).?.bounds.x);
    try std.testing.expectEqual(-ui_state.tree.get(scroller).?.scroll_offset.y, ui_state.tree.get(child).?.bounds.y);

    try ui_state.beginFrame(.{
        .events = &[_]platform_events.PlatformEvent{
            .{ .scroll = .{ .x = -10, .y = -10 } },
        },
        .window_size = .{ .x = 100, .y = 80 },
        .dt = 1.0 / 60.0,
    });
    try ui_state.endFrame();

    try std.testing.expectEqual(@as(f32, 80), ui_state.tree.get(scroller).?.scroll_target_offset.x);
    try std.testing.expectEqual(@as(f32, 60), ui_state.tree.get(scroller).?.scroll_target_offset.y);
    try std.testing.expect(ui_state.tree.get(scroller).?.scroll_offset.x < ui_state.tree.get(scroller).?.scroll_target_offset.x);
    try std.testing.expect(ui_state.tree.get(scroller).?.scroll_offset.y < ui_state.tree.get(scroller).?.scroll_target_offset.y);

    try ui_state.beginFrame(.{
        .events = &.{},
        .window_size = .{ .x = 220, .y = 180 },
        .dt = 1.0 / 60.0,
    });
    try ui_state.endFrame();

    try std.testing.expectEqual(@as(f32, 0), ui_state.tree.get(scroller).?.scroll_offset.x);
    try std.testing.expectEqual(@as(f32, 0), ui_state.tree.get(scroller).?.scroll_offset.y);
    try std.testing.expectEqual(@as(f32, 0), ui_state.tree.get(scroller).?.scroll_target_offset.x);
    try std.testing.expectEqual(@as(f32, 0), ui_state.tree.get(scroller).?.scroll_target_offset.y);
}
