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
        self.input.beginFrame();
        for (frame.events) |event| {
            input_mod.applyEvent(&self.input, event);
        }
        input_mod.routePointerState(&self.tree, self.root, &self.input);
    }

    pub fn endFrame(self: *Ui) !void {
        layout_mod.layoutTree(&self.tree, self.root, self.window_size, self.text_measurer);
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
};
