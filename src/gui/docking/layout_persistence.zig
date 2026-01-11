const std = @import("std");
const DockNode = @import("dock_node.zig").DockNode;
const DockNodeType = @import("dock_node.zig").DockNodeType;
const SplitDirection = @import("dock_node.zig").SplitDirection;

/// Serialize a dock tree to a string
pub fn serializeLayout(allocator: std.mem.Allocator, root: ?*DockNode) ![]u8 {
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 256);
    errdefer buffer.deinit(allocator);

    if (root) |node| {
        try serializeNode(allocator, &buffer, node, 0);
    }

    return buffer.toOwnedSlice(allocator);
}

/// Recursively serialize a node with indentation
fn serializeNode(allocator: std.mem.Allocator, buffer: *std.ArrayList(u8), node: *DockNode, depth: usize) !void {
    // Add indentation
    var i: usize = 0;
    while (i < depth) : (i += 1) {
        try buffer.append(allocator, ' ');
        try buffer.append(allocator, ' ');
    }

    switch (node.node_type) {
        .split => {
            if (node.split) |split_info| {
                // Write "split <direction> <ratio>\n"
                const direction_str = if (split_info.direction == .horizontal) "horizontal" else "vertical";
                const line = try std.fmt.allocPrint(
                    allocator,
                    "split {s} {d:.6}\n",
                    .{ direction_str, split_info.ratio },
                );
                defer allocator.free(line);
                try buffer.appendSlice(allocator, line);

                // Recursively serialize children
                try serializeNode(allocator, buffer, split_info.first, depth + 1);
                try serializeNode(allocator, buffer, split_info.second, depth + 1);
            }
        },
        .tab_group => {
            if (node.tab_group) |group| {
                // Write "tabgroup <active_index> <panel_id1> <panel_id2> ...\n"
                try buffer.appendSlice(allocator, "tabgroup ");
                const active_str = try std.fmt.allocPrint(allocator, "{d}", .{group.active_index});
                defer allocator.free(active_str);
                try buffer.appendSlice(allocator, active_str);

                for (group.panel_ids.items) |panel_id| {
                    const id_str = try std.fmt.allocPrint(allocator, " {d}", .{panel_id});
                    defer allocator.free(id_str);
                    try buffer.appendSlice(allocator, id_str);
                }
                try buffer.append(allocator, '\n');
            }
        },
    }
}

/// Deserialize a dock tree from a string
pub fn deserializeLayout(allocator: std.mem.Allocator, data: []const u8) !?*DockNode {
    var lines = try std.ArrayList([]const u8).initCapacity(allocator, 16);
    defer lines.deinit(allocator);

    // Split into lines
    var iter = std.mem.splitScalar(u8, data, '\n');
    while (iter.next()) |line| {
        if (line.len > 0) {
            try lines.append(allocator, line);
        }
    }

    if (lines.items.len == 0) {
        return null;
    }

    var index: usize = 0;
    return try deserializeNode(allocator, lines.items, &index);
}

/// Recursively deserialize a node
fn deserializeNode(allocator: std.mem.Allocator, lines: [][]const u8, index: *usize) !?*DockNode {
    if (index.* >= lines.len) {
        return null;
    }

    const line = lines[index.*];
    index.* += 1;

    // Count leading spaces to determine depth
    var indent: usize = 0;
    while (indent < line.len and line[indent] == ' ') : (indent += 1) {}

    const trimmed = std.mem.trim(u8, line, " ");

    if (std.mem.startsWith(u8, trimmed, "split")) {
        // Parse: "split <direction> <ratio>"
        var parts = std.mem.splitScalar(u8, trimmed, ' ');
        _ = parts.next(); // Skip "split"

        const direction_str = parts.next() orelse return error.InvalidFormat;
        const ratio_str = parts.next() orelse return error.InvalidFormat;

        const direction: SplitDirection = if (std.mem.eql(u8, direction_str, "horizontal"))
            .horizontal
        else if (std.mem.eql(u8, direction_str, "vertical"))
            .vertical
        else
            return error.InvalidFormat;

        const ratio = try std.fmt.parseFloat(f32, ratio_str);

        // Recursively parse children (they should be at greater indentation)
        const first = try deserializeNode(allocator, lines, index) orelse return error.InvalidFormat;
        errdefer first.deinit();

        const second = try deserializeNode(allocator, lines, index) orelse {
            first.deinit();
            return error.InvalidFormat;
        };
        errdefer second.deinit();

        return try DockNode.initSplit(allocator, direction, ratio, first, second);
    } else if (std.mem.startsWith(u8, trimmed, "tabgroup")) {
        // Parse: "tabgroup <active_index> <panel_id1> <panel_id2> ..."
        var parts = std.mem.splitScalar(u8, trimmed, ' ');
        _ = parts.next(); // Skip "tabgroup"

        const active_index_str = parts.next() orelse return error.InvalidFormat;
        const active_index = try std.fmt.parseInt(usize, active_index_str, 10);

        // Parse panel IDs
        var panel_ids = try std.ArrayList(u64).initCapacity(allocator, 4);
        errdefer panel_ids.deinit(allocator);

        while (parts.next()) |id_str| {
            const panel_id = try std.fmt.parseInt(u64, id_str, 10);
            try panel_ids.append(allocator, panel_id);
        }

        if (panel_ids.items.len == 0) {
            return error.InvalidFormat;
        }

        // Create tab group node
        const node = try allocator.create(DockNode);
        errdefer allocator.destroy(node);

        node.* = .{
            .node_type = .tab_group,
            .tab_group = .{
                .panel_ids = panel_ids,
                .active_index = if (active_index < panel_ids.items.len) active_index else 0,
            },
            .allocator = allocator,
        };

        return node;
    }

    return error.InvalidFormat;
}

/// Save layout to a file
pub fn saveLayoutToFile(allocator: std.mem.Allocator, root: ?*DockNode, file_path: []const u8) !void {
    const data = try serializeLayout(allocator, root);
    defer allocator.free(data);

    const file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();

    try file.writeAll(data);
}

/// Load layout from a file
pub fn loadLayoutFromFile(allocator: std.mem.Allocator, file_path: []const u8) !?*DockNode {
    const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            return null;
        }
        return err;
    };
    defer file.close();

    const data = try file.readToEndAlloc(allocator, 1024 * 1024); // Max 1MB
    defer allocator.free(data);

    return try deserializeLayout(allocator, data);
}

// ===== Multi-Window Persistence =====

pub const MultiWindowLayout = struct {
    windows: []WindowLayoutData,
};

pub const WindowLayoutData = struct {
    window_id: u64,
    is_main: bool,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    dock_tree: ?*DockNode,
};

/// Save multi-window layout to file
pub fn saveMultiWindowLayout(
    allocator: std.mem.Allocator,
    manager: *anyopaque, // WindowManager pointer
    file_path: []const u8,
) !void {
    const WindowManager = @import("../window_manager.zig").WindowManager;
    const window_manager: *WindowManager = @ptrCast(@alignCast(manager));

    var buffer = try std.ArrayList(u8).initCapacity(allocator, 1024);
    defer buffer.deinit(allocator);

    const header = try std.fmt.allocPrint(allocator, "multiwindow {d}\n", .{window_manager.windows.count()});
    defer allocator.free(header);
    try buffer.appendSlice(allocator, header);

    // Serialize each window
    var iter = window_manager.windows.iterator();
    while (iter.next()) |entry| {
        const window_ctx = entry.value_ptr.*;

        // Window metadata line
        const meta = try std.fmt.allocPrint(
            allocator,
            "window {d} {d} {d} {d} {d} {}\n",
            .{
                window_ctx.id,
                window_ctx.metadata.x,
                window_ctx.metadata.y,
                window_ctx.metadata.width,
                window_ctx.metadata.height,
                window_ctx.metadata.is_main,
            },
        );
        defer allocator.free(meta);
        try buffer.appendSlice(allocator, meta);

        // Serialize dock tree (indented)
        if (window_ctx.docking_ctx.dock_space.root) |root| {
            const tree_data = try serializeLayout(allocator, root);
            defer allocator.free(tree_data);

            var tree_iter = std.mem.splitScalar(u8, tree_data, '\n');
            while (tree_iter.next()) |line| {
                if (line.len > 0) {
                    try buffer.appendSlice(allocator, "  ");
                    try buffer.appendSlice(allocator, line);
                    try buffer.append(allocator, '\n');
                }
            }
        }
        try buffer.appendSlice(allocator, "endwindow\n");
    }

    // Write to file
    const file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();
    try file.writeAll(buffer.items);
}

/// Load multi-window layout from file
pub fn loadMultiWindowLayout(
    allocator: std.mem.Allocator,
    file_path: []const u8,
) !?MultiWindowLayout {
    const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
        if (err == error.FileNotFound) return null;
        return err;
    };
    defer file.close();

    const data = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(data);

    // Parse header
    var windows = try std.ArrayList(WindowLayoutData).initCapacity(allocator, 4);
    errdefer {
        for (windows.items) |*w| {
            if (w.dock_tree) |tree| tree.deinit();
        }
        windows.deinit(allocator);
    }

    var lines = std.mem.splitScalar(u8, data, '\n');
    const header = lines.next() orelse return error.InvalidFormat;
    if (!std.mem.startsWith(u8, header, "multiwindow")) return error.InvalidFormat;

    // Collect all lines first
    var all_lines = try std.ArrayList([]const u8).initCapacity(allocator, 16);
    defer all_lines.deinit(allocator);

    while (lines.next()) |line| {
        if (line.len > 0) {
            try all_lines.append(allocator, line);
        }
    }

    // Parse each window block
    var index: usize = 0;
    while (index < all_lines.items.len) {
        const line = all_lines.items[index];
        const trimmed = std.mem.trim(u8, line, " ");

        if (std.mem.startsWith(u8, trimmed, "window")) {
            const window_data = try parseWindowBlock(allocator, all_lines.items, &index);
            try windows.append(allocator, window_data);
        } else {
            index += 1;
        }
    }

    return MultiWindowLayout{
        .windows = try windows.toOwnedSlice(allocator),
    };
}

/// Parse a single window block
fn parseWindowBlock(
    allocator: std.mem.Allocator,
    lines: [][]const u8,
    index: *usize,
) !WindowLayoutData {
    const window_line = lines[index.*];
    index.* += 1;

    // Parse: "window <id> <x> <y> <width> <height> <is_main>"
    var parts = std.mem.splitScalar(u8, window_line, ' ');
    _ = parts.next(); // Skip "window"

    const id = try std.fmt.parseInt(u64, parts.next() orelse return error.InvalidFormat, 10);
    const x = try std.fmt.parseInt(i32, parts.next() orelse return error.InvalidFormat, 10);
    const y = try std.fmt.parseInt(i32, parts.next() orelse return error.InvalidFormat, 10);
    const width = try std.fmt.parseInt(i32, parts.next() orelse return error.InvalidFormat, 10);
    const height = try std.fmt.parseInt(i32, parts.next() orelse return error.InvalidFormat, 10);
    const is_main_str = parts.next() orelse return error.InvalidFormat;
    const is_main = std.mem.eql(u8, is_main_str, "true");

    // Collect indented tree lines
    var tree_lines = try std.ArrayList([]const u8).initCapacity(allocator, 16);
    defer tree_lines.deinit(allocator);

    while (index.* < lines.len) {
        const line = lines[index.*];
        if (std.mem.startsWith(u8, line, "endwindow")) {
            index.* += 1;
            break;
        }

        // Remove 2-space indent
        const unindented = if (std.mem.startsWith(u8, line, "  "))
            line[2..]
        else
            line;

        try tree_lines.append(allocator, unindented);
        index.* += 1;
    }

    // Reconstruct tree data and deserialize
    var tree_data = try std.ArrayList(u8).initCapacity(allocator, 256);
    defer tree_data.deinit(allocator);

    for (tree_lines.items) |line| {
        try tree_data.appendSlice(allocator, line);
        try tree_data.append(allocator, '\n');
    }

    const dock_tree = if (tree_data.items.len > 0)
        try deserializeLayout(allocator, tree_data.items)
    else
        null;

    return WindowLayoutData{
        .window_id = id,
        .is_main = is_main,
        .x = x,
        .y = y,
        .width = width,
        .height = height,
        .dock_tree = dock_tree,
    };
}
