const std = @import("std");
const ui = @import("zGUI");

const node_count = 10_000;
const iterations = 200;

pub fn main(init: std.process.Init) !void {
    try benchmarkIncrementalLayout(init);
    try benchmarkClippedPaint(init);
    try benchmarkTextReuse(init);
    try benchmarkInputBurst(init);
}

fn benchmarkIncrementalLayout(init: std.process.Init) !void {
    var state = try ui.Ui.init(init.gpa);
    defer state.deinit();
    const root = state.rootNode();
    try state.setStyle(root, .{ .width = .fill, .height = .fill, .direction = .column });

    var changed = ui.invalid_node;
    for (0..node_count) |index| {
        const node = try state.createNode(.panel);
        try state.setStyle(node, .{ .width = .{ .px = 1 }, .height = .{ .px = 1 } });
        try state.tree.appendChild(root, node);
        if (index == node_count / 2) changed = node;
    }
    try state.beginFrame(.{ .window_size = .{ .x = 1200, .y = 800 } });
    try state.endFrame();

    const started: std.Io.Clock.Timestamp = .now(init.io, .awake);
    var measured_total: u64 = 0;
    for (0..iterations) |iteration| {
        try state.beginFrame(.{ .window_size = .{ .x = 1200, .y = 800 } });
        var style = state.nodeStyle(changed).?;
        style.width = .{ .px = if (iteration & 1 == 0) 2 else 1 };
        try state.setStyle(changed, style);
        try state.endFrame();
        measured_total += state.statsSnapshot().layout_measured_count;
    }
    const elapsed_ns: u64 = @intCast(started.untilNow(init.io).raw.toNanoseconds());
    std.debug.print(
        "incremental-layout nodes={d} iterations={d} avg_ns={d} avg_measured={d}\n",
        .{ node_count, iterations, elapsed_ns / iterations, measured_total / iterations },
    );
}

fn benchmarkClippedPaint(init: std.process.Init) !void {
    var state = try ui.Ui.init(init.gpa);
    defer state.deinit();
    const root = state.rootNode();
    try state.setStyle(root, .{
        .width = .fill,
        .height = .fill,
        .direction = .column,
        .overflow_y = .scroll,
    });
    for (0..node_count) |_| {
        const node = try state.createNode(.panel);
        try state.setStyle(node, .{
            .width = .fill,
            .height = .{ .px = 2 },
            .background = ui.Color.rgba(255, 255, 255, 255),
        });
        try state.tree.appendChild(root, node);
    }
    try state.beginFrame(.{ .window_size = .{ .x = 1200, .y = 800 } });
    try state.endFrame();

    try state.beginFrame(.{ .window_size = .{ .x = 1200, .y = 800 } });
    var style = state.nodeStyle(root).?;
    style.background = ui.Color.rgba(1, 1, 1, 1);
    try state.setStyle(root, style);
    const started: std.Io.Clock.Timestamp = .now(init.io, .awake);
    try state.endFrame();
    const elapsed_ns: u64 = @intCast(started.untilNow(init.io).raw.toNanoseconds());
    const stats = state.statsSnapshot();
    std.debug.print(
        "clipped-paint nodes={d} ns={d} visited={d} culled_subtrees={d} commands={d} vertices={d}\n",
        .{ node_count, elapsed_ns, stats.paint_visited_count, stats.paint_culled_subtree_count, stats.paint_command_count, stats.vertex_count },
    );
}

fn benchmarkInputBurst(init: std.process.Init) !void {
    var state = try ui.Ui.init(init.gpa);
    defer state.deinit();
    const button = try state.createNode(.button);
    try state.setStyle(button, .{ .width = .{ .px = 200 }, .height = .{ .px = 40 } });
    try state.tree.appendChild(state.rootNode(), button);
    try state.beginFrame(.{ .window_size = .{ .x = 400, .y = 200 } });
    try state.endFrame();

    var events: [4096]ui.PlatformEvent = undefined;
    for (&events, 0..) |*event, index| event.* = .{ .mouse_move = .{ .x = @floatFromInt(index % 200), .y = 10 } };
    const started: std.Io.Clock.Timestamp = .now(init.io, .awake);
    try state.beginFrame(.{ .events = &events, .window_size = .{ .x = 400, .y = 200 } });
    try state.endFrame();
    const elapsed_ns: u64 = @intCast(started.untilNow(init.io).raw.toNanoseconds());
    std.debug.print("input-burst events={d} ns={d}\n", .{ events.len, elapsed_ns });
}

fn benchmarkTextReuse(init: std.process.Init) !void {
    const font_bytes = @embedFile("benchmark_font");
    var atlas = try ui.FontAtlas.init(init.gpa, font_bytes, 1024, 1024);
    defer atlas.deinit();
    atlas.texture = .fromParts(0, 1);
    try atlas.prewarmAscii(&.{13}, 1);

    var state = try ui.Ui.init(init.gpa);
    defer state.deinit();
    state.setFontAtlas(&atlas);
    const root = state.rootNode();
    try state.setStyle(root, .{ .width = .fill, .height = .fill, .direction = .column });
    for (0..1000) |_| {
        const label = try state.createNode(.label);
        try state.setStyle(label, .{
            .width = .fill,
            .height = .{ .px = 18 },
            .font_size = 13,
            .background = ui.Color.rgba(24, 24, 24, 255),
        });
        try state.setText(label, "Transform position rotation scale");
        try state.tree.appendChild(root, label);
    }

    const first_started: std.Io.Clock.Timestamp = .now(init.io, .awake);
    try state.beginFrame(.{ .window_size = .{ .x = 1200, .y = 18_000 } });
    try state.endFrame();
    const first_ns: u64 = @intCast(first_started.untilNow(init.io).raw.toNanoseconds());
    const first_stats = state.statsSnapshot();

    var root_style = state.nodeStyle(root).?;
    root_style.background = ui.Color.rgba(1, 1, 1, 1);
    try state.setStyle(root, root_style);
    const cached_started: std.Io.Clock.Timestamp = .now(init.io, .awake);
    try state.beginFrame(.{ .window_size = .{ .x = 1200, .y = 18_000 } });
    try state.endFrame();
    const cached_ns: u64 = @intCast(cached_started.untilNow(init.io).raw.toNanoseconds());
    const cached_stats = state.statsSnapshot();

    std.debug.print(
        "text-reuse labels=1000 first_ns={d} cached_ns={d} shaped={d} reused={d} batches={d}\n",
        .{ first_ns, cached_ns, first_stats.shaped_glyph_count, cached_stats.reused_glyph_count, cached_stats.batch_count },
    );
}
