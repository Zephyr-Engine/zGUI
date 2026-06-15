const std = @import("std");
const types = @import("../core/types.zig");
const style_mod = @import("../core/style.zig");
const node_mod = @import("../core/node.zig");
const app = @import("../core/ui_context.zig");
const theme_mod = @import("../theme.zig");
const events = @import("../platform/events.zig");
const dock_node = @import("dock_node.zig");
const dock_manager_mod = @import("dock_manager.zig");
const window_manager_mod = @import("../windowing/window_manager.zig");
const window_mod = @import("../windowing/window.zig");

pub const DockWindowId = types.WindowId;

pub const DockSpaceOptions = struct {
    rect: types.Rect,
    handle_thickness: f32 = 4,
    tab_height: f32 = 30,
    gap: f32 = 0,
};

pub const DockSpaceResult = struct {
    changed: bool = false,
    cursor: events.CursorKind = .arrow,
    active_window: ?DockWindowId = null,

    pub fn contentRect(self: DockSpaceResult, dock_space: *const DockSpace, window: DockWindowId) ?types.Rect {
        _ = self;
        return dock_space.windowContentRect(window);
    }
};

const LeafNodes = struct {
    host: types.NodeId = types.invalid_node,
    tab_bar: types.NodeId = types.invalid_node,
    content: types.NodeId = types.invalid_node,
};

const SplitNodes = struct {
    handle: types.NodeId = types.invalid_node,
};

const FloatingNodes = struct {
    host: types.NodeId = types.invalid_node,
    title: types.NodeId = types.invalid_node,
    content: types.NodeId = types.invalid_node,
};

const OverlayNodes = struct {
    drop_preview: types.NodeId = types.invalid_node,
    drag_ghost: types.NodeId = types.invalid_node,
    drag_label: types.NodeId = types.invalid_node,
};

const WindowState = struct {
    content_rect: types.Rect = .{},
    tab: types.NodeId = types.invalid_node,
    tab_label: types.NodeId = types.invalid_node,
};

const DragState = struct {
    window: DockWindowId,
    source_leaf: ?types.DockNodeId = null,
    start_mouse: types.Vec2,
    dragging: bool = false,
    floating: bool = false,
};

pub const DropZone = enum {
    left,
    right,
    top,
    bottom,
    center_tab,
};

pub const DockSpace = struct {
    allocator: std.mem.Allocator,
    dock: dock_manager_mod.DockManager,
    windows: window_manager_mod.WindowManager,
    leaf_nodes: std.ArrayList(LeafNodes) = .empty,
    split_nodes: std.ArrayList(SplitNodes) = .empty,
    floating_nodes: std.ArrayList(FloatingNodes) = .empty,
    window_state: std.ArrayList(WindowState) = .empty,
    overlays: OverlayNodes = .{},
    drag: ?DragState = null,

    pub fn init(allocator: std.mem.Allocator) !DockSpace {
        return .{
            .allocator = allocator,
            .dock = try dock_manager_mod.DockManager.init(allocator),
            .windows = window_manager_mod.WindowManager.init(allocator),
        };
    }

    pub fn deinit(self: *DockSpace) void {
        self.window_state.deinit(self.allocator);
        self.floating_nodes.deinit(self.allocator);
        self.split_nodes.deinit(self.allocator);
        self.leaf_nodes.deinit(self.allocator);
        self.windows.deinit();
        self.dock.deinit();
        self.* = undefined;
    }

    pub fn createWindow(
        self: *DockSpace,
        title: []const u8,
        root_node: types.NodeId,
        min_size: types.Vec2,
        flags: window_mod.WindowFlags,
    ) !DockWindowId {
        const id = try self.windows.createWindow(title, .{}, root_node, flags);
        self.windows.get(id).?.min_size = min_size;
        try self.ensureWindowCapacity(id + 1);
        return id;
    }

    pub fn splitNode(
        self: *DockSpace,
        target: types.DockNodeId,
        position: dock_node.DockPosition,
        ratio: f32,
    ) !dock_manager_mod.DockManager.SplitResult {
        return self.dock.splitNode(target, position, ratio);
    }

    pub fn dockWindow(
        self: *DockSpace,
        window: DockWindowId,
        target: types.DockNodeId,
        position: dock_node.DockPosition,
    ) !void {
        try self.dock.dockWindow(window, target, position);
    }

    pub fn setSplitMinimums(self: *DockSpace, split_id: types.DockNodeId, min_first_size: f32, min_second_size: f32) !void {
        try self.dock.setSplitMinimums(split_id, min_first_size, min_second_size);
    }

    pub fn windowContentRect(self: *const DockSpace, window: DockWindowId) ?types.Rect {
        if (window == types.invalid_window or window >= self.window_state.items.len) return null;
        return self.window_state.items[window].content_rect;
    }

    pub fn run(self: *DockSpace, ui: *app.Ui, parent: types.NodeId, options: DockSpaceOptions) !DockSpaceResult {
        try self.ensureNodeCapacity(ui, parent);
        self.dock.layout(options.rect);

        var result: DockSpaceResult = .{};
        result.changed = self.updateResize(ui, options);
        if (self.updateTabsAndDrops(ui, options)) result.changed = true;
        try self.ensureNodeCapacity(ui, parent);
        try self.ensureOverlayNodes(ui, parent);

        self.hideDockSupportNodes(ui);
        self.syncDockNode(ui, parent, self.dock.root, options);
        try self.syncFloatingNodes(ui, parent, options);
        self.syncDragFeedback(ui, parent, options);

        if (self.dock.hitTestResizeHandle(ui.input.mouse_pos, options.handle_thickness)) |split| {
            result.cursor = cursorForSplit(self.dock.splitAxis(split) orelse .x);
        }
        if (self.dock.activeResizeSplit()) |split| {
            result.cursor = cursorForSplit(self.dock.splitAxis(split) orelse .x);
        }
        if (result.cursor != .arrow) ui.requestCursor(result.cursor);

        result.active_window = self.firstActiveWindow();
        return result;
    }

    fn updateResize(self: *DockSpace, ui: *app.Ui, options: DockSpaceOptions) bool {
        const hovered_split = self.dock.hitTestResizeHandle(ui.input.mouse_pos, options.handle_thickness);
        if (mousePressed(ui)) {
            if (hovered_split) |split| {
                self.dock.beginResize(split, ui.input.mouse_pos) catch {};
            }
        }

        const changed = if (mouseDown(ui))
            self.dock.updateResize(ui.input.mouse_pos)
        else
            false;

        if (mouseReleased(ui)) self.dock.endResize();
        return changed;
    }

    fn updateTabsAndDrops(self: *DockSpace, ui: *app.Ui, options: DockSpaceOptions) bool {
        var changed = false;
        if (mousePressed(ui)) {
            if (self.tabAt(ui.input.mouse_pos, options)) |hit| {
                _ = self.dock.setActiveWindow(hit.leaf, hit.window);
                self.drag = .{
                    .window = hit.window,
                    .source_leaf = hit.leaf,
                    .start_mouse = ui.input.mouse_pos,
                };
                changed = true;
            } else if (self.floatingTitleAt(ui.input.mouse_pos)) |window| {
                self.windows.bringToFront(window);
                self.drag = .{
                    .window = window,
                    .start_mouse = ui.input.mouse_pos,
                    .floating = true,
                };
            }
        }

        if (mouseDown(ui)) {
            if (self.drag) |*drag| {
                const dx = ui.input.mouse_pos.x - drag.start_mouse.x;
                const dy = ui.input.mouse_pos.y - drag.start_mouse.y;
                if (@abs(dx) + @abs(dy) > 4) drag.dragging = true;
                if (drag.floating and drag.dragging) {
                    if (self.windows.get(drag.window)) |window| {
                        window.rect.x += ui.input.mouse_pos.x - ui.input.prev_mouse_pos.x;
                        window.rect.y += ui.input.mouse_pos.y - ui.input.prev_mouse_pos.y;
                        changed = true;
                    }
                }
            }
        }

        if (mouseReleased(ui)) {
            if (self.drag) |drag| {
                if (drag.dragging) {
                    changed = self.finishDrag(ui.input.mouse_pos, drag, options) or changed;
                }
                self.drag = null;
            }
        }
        return changed;
    }

    fn finishDrag(self: *DockSpace, mouse_pos: types.Vec2, drag: DragState, options: DockSpaceOptions) bool {
        if (self.dock.hitTestLeaf(mouse_pos)) |target_leaf| {
            const zone = dropZoneFor(self.dock.nodeRect(target_leaf) orelse return false, mouse_pos, options);
            if (drag.source_leaf) |source| {
                if (source == target_leaf and zone == .center_tab) return false;
                if (source == target_leaf and self.leafTabCount(source) <= 1) return false;
            }
            if (zone == .center_tab) {
                self.dock.moveWindowToLeaf(drag.window, target_leaf) catch return false;
            } else {
                self.dock.dockWindow(drag.window, target_leaf, @enumFromInt(@intFromEnum(zone))) catch return false;
            }
            return true;
        }

        if (!drag.floating) {
            self.dock.undockWindow(drag.window) catch {};
            if (self.windows.get(drag.window)) |window| {
                window.rect = .{ .x = mouse_pos.x - 120, .y = mouse_pos.y - 14, .w = @max(240, window.min_size.x), .h = @max(180, window.min_size.y) };
            }
            return true;
        }
        return false;
    }

    fn syncDockNode(self: *DockSpace, ui: *app.Ui, parent: types.NodeId, id: types.DockNodeId, options: DockSpaceOptions) void {
        if (id == types.invalid_dock_node or id >= self.dock.nodes.items.len) return;
        switch (self.dock.nodes.items[id]) {
            .leaf => |leaf| self.syncLeaf(ui, parent, id, leaf, options),
            .split => |split| {
                self.syncSplit(ui, parent, id, split, options);
                self.syncDockNode(ui, parent, split.first, options);
                self.syncDockNode(ui, parent, split.second, options);
            },
        }
    }

    fn hideDockSupportNodes(self: *DockSpace, ui: *app.Ui) void {
        for (self.leaf_nodes.items) |nodes| {
            hideNode(ui, nodes.host);
            hideNode(ui, nodes.tab_bar);
            hideNode(ui, nodes.content);
        }
        for (self.split_nodes.items) |nodes| {
            hideNode(ui, nodes.handle);
        }
    }

    fn syncLeaf(self: *DockSpace, ui: *app.Ui, parent: types.NodeId, id: types.DockNodeId, leaf: anytype, options: DockSpaceOptions) void {
        const parent_origin = nodeOrigin(ui, parent);
        const nodes = self.leaf_nodes.items[id];
        const active = if (leaf.tabs.items.len == 0) null else leaf.tabs.items[@min(leaf.active_tab, leaf.tabs.items.len - 1)];
        setPanel(ui, nodes.host, leaf.rect, parent_origin, .panel, false);
        setPanel(ui, nodes.tab_bar, .{ .x = leaf.rect.x, .y = leaf.rect.y, .w = leaf.rect.w, .h = options.tab_height }, .{ .x = leaf.rect.x, .y = leaf.rect.y }, .shell, false);
        const content_rect: types.Rect = .{
            .x = leaf.rect.x,
            .y = leaf.rect.y + options.tab_height,
            .w = leaf.rect.w,
            .h = @max(0, leaf.rect.h - options.tab_height),
        };
        setPanel(ui, nodes.content, content_rect, .{ .x = leaf.rect.x, .y = leaf.rect.y }, .transparent, false);

        for (leaf.tabs.items, 0..) |window_id, tab_index| {
            if (self.windows.get(window_id)) |window| {
                self.ensureWindowTab(ui, nodes.tab_bar, window_id) catch {};
                const tab_rect: types.Rect = .{
                    .x = leaf.rect.x + @as(f32, @floatFromInt(tab_index)) * 116,
                    .y = leaf.rect.y,
                    .w = @min(116, @max(40, leaf.rect.w)),
                    .h = options.tab_height,
                };
                const is_active = active != null and active.? == window_id;
                if (window_id < self.window_state.items.len) {
                    const tab = self.window_state.items[window_id].tab;
                    const label = self.window_state.items[window_id].tab_label;
                    const is_hovered = tab_rect.contains(ui.input.mouse_pos);
                    const is_dragged = if (self.drag) |drag| drag.window == window_id else false;
                    ensureRootParent(ui, tab, nodes.tab_bar);
                    const tab_background: theme_mod.ColorRole = if (is_dragged)
                        .accent_soft
                    else if (is_active)
                        .control
                    else if (is_hovered)
                        .panel_soft
                    else
                        .transparent;
                    const tab_border: theme_mod.ColorRole = if (is_dragged or is_hovered) .accent else .transparent;
                    setPanelStyled(ui, tab, tab_rect, .{ .x = leaf.rect.x, .y = leaf.rect.y }, tab_background, tab_border, if (is_dragged or is_hovered) 1 else 0, true, 6);
                    setLabel(ui, label, window.title, is_active);
                }
                ensureRootParent(ui, window.root_node, if (active != null and active.? == window_id) nodes.content else types.invalid_node);
                if (active != null and active.? == window_id) {
                    setContentRoot(ui, window.root_node);
                    if (window_id < self.window_state.items.len) self.window_state.items[window_id].content_rect = content_rect;
                }
            }
        }
    }

    fn syncSplit(self: *DockSpace, ui: *app.Ui, parent: types.NodeId, id: types.DockNodeId, split: anytype, options: DockSpaceOptions) void {
        const parent_origin = nodeOrigin(ui, parent);
        const nodes = self.split_nodes.items[id];
        const hit_rect = self.dock.resizeHandleRect(id, options.handle_thickness) orelse return;
        const active = if (self.dock.activeResizeSplit()) |active_split| active_split == id else false;
        const hovered = !active and hit_rect.contains(ui.input.mouse_pos);
        const visual_rect = if (active or hovered)
            resizeHandleVisualRect(hit_rect, split.axis, options.handle_thickness)
        else
            hit_rect;
        ui.tree.appendChild(parent, nodes.handle) catch {};
        setPanel(ui, nodes.handle, visual_rect, parent_origin, if (active or hovered) .accent else .transparent, true);
    }

    fn syncFloatingNodes(self: *DockSpace, ui: *app.Ui, parent: types.NodeId, options: DockSpaceOptions) !void {
        _ = options;
        const parent_origin = nodeOrigin(ui, parent);
        for (self.windows.windows.items, 0..) |*window, i| {
            const window_id: DockWindowId = @intCast(i);
            if (!window.open or self.dock.leafForWindow(window_id) != null) continue;
            try self.ensureFloatingCapacity(ui, parent, window_id + 1);
            const nodes = self.floating_nodes.items[window_id];
            if (window.rect.w <= 0 or window.rect.h <= 0) {
                window.rect.w = @max(260, window.min_size.x);
                window.rect.h = @max(190, window.min_size.y);
            }
            setPanel(ui, nodes.host, window.rect, parent_origin, .panel, false);
            setPanel(ui, nodes.title, .{ .x = window.rect.x, .y = window.rect.y, .w = window.rect.w, .h = 30 }, .{ .x = window.rect.x, .y = window.rect.y }, .shell, true);
            const content_rect: types.Rect = .{ .x = window.rect.x, .y = window.rect.y + 30, .w = window.rect.w, .h = @max(0, window.rect.h - 30) };
            setPanel(ui, nodes.content, content_rect, .{ .x = window.rect.x, .y = window.rect.y }, .transparent, false);
            ensureRootParent(ui, window.root_node, nodes.content);
            setContentRoot(ui, window.root_node);
            if (window_id < self.window_state.items.len) self.window_state.items[window_id].content_rect = content_rect;
        }
    }

    fn tabAt(self: *const DockSpace, mouse_pos: types.Vec2, options: DockSpaceOptions) ?struct { leaf: types.DockNodeId, window: DockWindowId } {
        for (self.dock.nodes.items, 0..) |node, i| {
            switch (node) {
                .leaf => |leaf| {
                    const leaf_id: types.DockNodeId = @intCast(i);
                    for (leaf.tabs.items, 0..) |window_id, tab_index| {
                        const rect: types.Rect = .{
                            .x = leaf.rect.x + @as(f32, @floatFromInt(tab_index)) * 116,
                            .y = leaf.rect.y,
                            .w = @min(116, @max(40, leaf.rect.w)),
                            .h = options.tab_height,
                        };
                        if (rect.contains(mouse_pos)) return .{ .leaf = leaf_id, .window = window_id };
                    }
                },
                .split => {},
            }
        }
        return null;
    }

    fn floatingTitleAt(self: *const DockSpace, mouse_pos: types.Vec2) ?DockWindowId {
        for (self.windows.windows.items, 0..) |window, i| {
            const window_id: DockWindowId = @intCast(i);
            if (!window.open or self.dock.leafForWindow(window_id) != null) continue;
            const title_rect: types.Rect = .{ .x = window.rect.x, .y = window.rect.y, .w = window.rect.w, .h = 30 };
            if (title_rect.contains(mouse_pos)) return window_id;
        }
        return null;
    }

    fn firstActiveWindow(self: *const DockSpace) ?DockWindowId {
        for (self.dock.nodes.items, 0..) |node, i| {
            switch (node) {
                .leaf => if (self.dock.activeWindow(@intCast(i))) |window| return window,
                .split => {},
            }
        }
        return null;
    }

    fn leafTabCount(self: *const DockSpace, leaf_id: types.DockNodeId) usize {
        if (leaf_id == types.invalid_dock_node or leaf_id >= self.dock.nodes.items.len) return 0;
        return switch (self.dock.nodes.items[leaf_id]) {
            .leaf => |leaf| leaf.tabs.items.len,
            .split => 0,
        };
    }

    fn ensureNodeCapacity(self: *DockSpace, ui: *app.Ui, parent: types.NodeId) !void {
        while (self.leaf_nodes.items.len < self.dock.nodes.items.len) {
            const host = try createPanel(ui, parent);
            const tab_bar = try createPanel(ui, host);
            const content = try createPanel(ui, host);
            try self.leaf_nodes.append(self.allocator, .{ .host = host, .tab_bar = tab_bar, .content = content });
        }
        while (self.split_nodes.items.len < self.dock.nodes.items.len) {
            const handle = try createPanel(ui, parent);
            try self.split_nodes.append(self.allocator, .{ .handle = handle });
        }
    }

    fn ensureFloatingCapacity(self: *DockSpace, ui: *app.Ui, parent: types.NodeId, count: usize) !void {
        while (self.floating_nodes.items.len < count) {
            const host = try createPanel(ui, parent);
            const title = try createPanel(ui, host);
            const content = try createPanel(ui, host);
            try self.floating_nodes.append(self.allocator, .{ .host = host, .title = title, .content = content });
        }
    }

    fn ensureWindowCapacity(self: *DockSpace, count: usize) !void {
        while (self.window_state.items.len < count) {
            try self.window_state.append(self.allocator, .{});
        }
    }

    fn ensureWindowTab(self: *DockSpace, ui: *app.Ui, parent: types.NodeId, window: DockWindowId) !void {
        try self.ensureWindowCapacity(window + 1);
        if (self.window_state.items[window].tab != types.invalid_node) return;
        const tab = try createPanel(ui, parent);
        const label = try ui.tree.createNode(.label);
        try ui.tree.appendChild(tab, label);
        self.window_state.items[window].tab = tab;
        self.window_state.items[window].tab_label = label;
    }

    fn ensureOverlayNodes(self: *DockSpace, ui: *app.Ui, parent: types.NodeId) !void {
        if (self.overlays.drop_preview == types.invalid_node) {
            self.overlays.drop_preview = try createPanel(ui, parent);
        }
        if (self.overlays.drag_ghost == types.invalid_node) {
            self.overlays.drag_ghost = try createPanel(ui, parent);
            self.overlays.drag_label = try ui.tree.createNode(.label);
            try ui.tree.appendChild(self.overlays.drag_ghost, self.overlays.drag_label);
        }

        ui.tree.appendChild(parent, self.overlays.drop_preview) catch {};
        ui.tree.appendChild(parent, self.overlays.drag_ghost) catch {};
    }

    fn syncDragFeedback(self: *DockSpace, ui: *app.Ui, parent: types.NodeId, options: DockSpaceOptions) void {
        const parent_origin = nodeOrigin(ui, parent);
        const drag = self.drag orelse {
            hideNode(ui, self.overlays.drop_preview);
            hideNode(ui, self.overlays.drag_ghost);
            return;
        };
        if (!drag.dragging) {
            hideNode(ui, self.overlays.drop_preview);
            hideNode(ui, self.overlays.drag_ghost);
            return;
        }

        if (self.dock.hitTestLeaf(ui.input.mouse_pos)) |target_leaf| {
            if (self.dock.nodeRect(target_leaf)) |leaf_rect| {
                const zone = dropZoneFor(leaf_rect, ui.input.mouse_pos, options);
                const preview_rect = dropPreviewRect(leaf_rect, zone);
                setPanelStyled(ui, self.overlays.drop_preview, preview_rect, parent_origin, .accent_soft, .accent, 2, false, 8);
            } else {
                hideNode(ui, self.overlays.drop_preview);
            }
        } else {
            hideNode(ui, self.overlays.drop_preview);
        }

        const title = if (self.windows.get(drag.window)) |window| window.title else "Window";
        const ghost_rect: types.Rect = .{
            .x = ui.input.mouse_pos.x + 14,
            .y = ui.input.mouse_pos.y + 16,
            .w = @max(128, @min(220, 24 + @as(f32, @floatFromInt(title.len)) * 8)),
            .h = 30,
        };
        setPanelStyled(ui, self.overlays.drag_ghost, ghost_rect, parent_origin, .control, .accent, 1, false, 8);
        setLabel(ui, self.overlays.drag_label, title, true);
    }
};

pub fn dockSpace(ui: *app.Ui, parent: types.NodeId, dock_space: *DockSpace, options: DockSpaceOptions) !DockSpaceResult {
    return dock_space.run(ui, parent, options);
}

fn createPanel(ui: *app.Ui, parent: types.NodeId) !types.NodeId {
    const id = try ui.tree.createNode(.panel);
    try ui.tree.appendChild(parent, id);
    if (ui.tree.get(id)) |node| {
        node.style.direction = .absolute;
        node.flags.visible = true;
    }
    return id;
}

fn setPanel(ui: *app.Ui, id: types.NodeId, rect: types.Rect, origin: types.Vec2, background: theme_mod.ColorRole, interactive: bool) void {
    setPanelStyled(ui, id, rect, origin, background, .transparent, 0, interactive, 0);
}

fn setPanelStyled(
    ui: *app.Ui,
    id: types.NodeId,
    rect: types.Rect,
    origin: types.Vec2,
    background: theme_mod.ColorRole,
    border: theme_mod.ColorRole,
    border_width: f32,
    interactive: bool,
    radius: f32,
) void {
    if (ui.tree.get(id)) |node| {
        node.style.width = .{ .px = @max(0, rect.w) };
        node.style.height = .{ .px = @max(0, rect.h) };
        node.style.margin = style_mod.Edges{ .left = rect.x - origin.x, .top = rect.y - origin.y };
        node.style.background = ui.theme.color(background);
        node.style.border_color = ui.theme.color(border);
        node.style.border_width = border_width;
        node.style.radius = style_mod.CornerRadii.all(radius);
        node.style.direction = .absolute;
        node.flags.visible = rect.w > 0 and rect.h > 0;
        node.flags.interactive = interactive;
        node.dirty.layout = true;
        node.dirty.paint = true;
    }
}

fn hideNode(ui: *app.Ui, id: types.NodeId) void {
    if (ui.tree.get(id)) |node| {
        node.flags.visible = false;
        node.flags.interactive = false;
        node.dirty.layout = true;
        node.dirty.paint = true;
    }
}

fn nodeOrigin(ui: *const app.Ui, id: types.NodeId) types.Vec2 {
    if (ui.tree.getConst(id)) |node| return .{ .x = node.bounds.x, .y = node.bounds.y };
    return .{};
}

fn setContentRoot(ui: *app.Ui, id: types.NodeId) void {
    if (ui.tree.get(id)) |node| {
        node.style.width = .fill;
        node.style.height = .fill;
        node.style.margin = .{};
        node.style.overflow_x = .scroll;
        node.style.overflow_y = .scroll;
        node.flags.visible = true;
        node.dirty.layout = true;
        node.dirty.paint = true;
    }
}

fn resizeHandleVisualRect(rect: types.Rect, axis: dock_node.Axis, thickness: f32) types.Rect {
    return switch (axis) {
        .x => .{
            .x = rect.x + rect.w * 0.5 - thickness * 0.5,
            .y = rect.y,
            .w = thickness,
            .h = rect.h,
        },
        .y => .{
            .x = rect.x,
            .y = rect.y + rect.h * 0.5 - thickness * 0.5,
            .w = rect.w,
            .h = thickness,
        },
    };
}

fn setLabel(ui: *app.Ui, id: types.NodeId, text: []const u8, active: bool) void {
    if (ui.tree.get(id)) |node| {
        node.text = text;
        node.style.width = .fill;
        node.style.height = .fill;
        node.style.padding = .{ .left = 10, .right = 8, .top = 7, .bottom = 5 };
        node.style.foreground = ui.theme.color(if (active) .text else .text_muted);
        node.style.font_size = ui.theme.font.small;
        node.flags.visible = true;
        node.dirty.layout = true;
        node.dirty.paint = true;
    }
}

fn ensureRootParent(ui: *app.Ui, node_id: types.NodeId, parent: types.NodeId) void {
    const node = ui.tree.get(node_id) orelse return;
    if (parent == types.invalid_node) {
        if (node.parent != types.invalid_node) ui.tree.removeChild(node.parent, node_id);
        node.flags.visible = false;
        return;
    }
    if (node.parent != parent) ui.tree.appendChild(parent, node_id) catch {};
}

fn cursorForSplit(axis: dock_node.Axis) events.CursorKind {
    return switch (axis) {
        .x => .resize_x,
        .y => .resize_y,
    };
}

fn dropZoneFor(rect: types.Rect, mouse_pos: types.Vec2, options: DockSpaceOptions) DropZone {
    _ = options;
    const edge = @min(80, @min(rect.w, rect.h) * 0.28);
    if (mouse_pos.x < rect.x + edge) return .left;
    if (mouse_pos.x > rect.x + rect.w - edge) return .right;
    if (mouse_pos.y < rect.y + edge) return .top;
    if (mouse_pos.y > rect.y + rect.h - edge) return .bottom;
    return .center_tab;
}

fn dropPreviewRect(rect: types.Rect, zone: DropZone) types.Rect {
    const edge_w = @max(42, rect.w * 0.32);
    const edge_h = @max(36, rect.h * 0.32);
    return switch (zone) {
        .left => .{ .x = rect.x, .y = rect.y, .w = @min(edge_w, rect.w), .h = rect.h },
        .right => .{ .x = rect.x + @max(0, rect.w - edge_w), .y = rect.y, .w = @min(edge_w, rect.w), .h = rect.h },
        .top => .{ .x = rect.x, .y = rect.y, .w = rect.w, .h = @min(edge_h, rect.h) },
        .bottom => .{ .x = rect.x, .y = rect.y + @max(0, rect.h - edge_h), .w = rect.w, .h = @min(edge_h, rect.h) },
        .center_tab => rect.inset(style_mod.Edges.all(@min(18, @min(rect.w, rect.h) * 0.08))),
    };
}

fn mousePressed(ui: *const app.Ui) bool {
    return ui.input.mouse_pressed[0];
}

fn mouseDown(ui: *const app.Ui) bool {
    return ui.input.mouse_down[0];
}

fn mouseReleased(ui: *const app.Ui) bool {
    return ui.input.mouse_released[0];
}

fn reachableLeafCount(dock: *const dock_manager_mod.DockManager, id: types.DockNodeId) usize {
    if (id == types.invalid_dock_node or id >= dock.nodes.items.len) return 0;
    return switch (dock.nodes.items[id]) {
        .leaf => 1,
        .split => |split| reachableLeafCount(dock, split.first) + reachableLeafCount(dock, split.second),
    };
}

fn visibleLeafHostCount(ui: *const app.Ui, space: *const DockSpace) usize {
    var count: usize = 0;
    for (space.leaf_nodes.items) |nodes| {
        if (ui.tree.getConst(nodes.host)) |node| {
            if (node.flags.visible) count += 1;
        }
    }
    return count;
}

test "dock space tab click selects active window" {
    var ui_state = try app.Ui.init(std.testing.allocator);
    defer ui_state.deinit();
    ui_state.tree.get(ui_state.root).?.style.direction = .absolute;

    const a_root = try createPanel(&ui_state, ui_state.root);
    const b_root = try createPanel(&ui_state, ui_state.root);

    var space = try DockSpace.init(std.testing.allocator);
    defer space.deinit();
    const a = try space.createWindow("A", a_root, .{ .x = 40, .y = 40 }, .{});
    const b = try space.createWindow("B", b_root, .{ .x = 40, .y = 40 }, .{});
    try space.dock.moveWindowToLeaf(a, space.dock.root);
    try space.dockWindow(b, space.dock.root, .center_tab);

    const frame_events = [_]events.PlatformEvent{
        .{ .mouse_move = .{ .x = 130, .y = 10 } },
        .{ .mouse_down = .left },
    };
    try ui_state.beginFrame(.{ .events = &frame_events, .window_size = .{ .x = 400, .y = 300 } });
    _ = try space.run(&ui_state, ui_state.root, .{ .rect = .{ .x = 0, .y = 0, .w = 400, .h = 300 } });

    try std.testing.expectEqual(b, space.dock.activeWindow(space.dock.root).?);
}

test "dock space dragging tab outside creates floating window" {
    var ui_state = try app.Ui.init(std.testing.allocator);
    defer ui_state.deinit();
    ui_state.tree.get(ui_state.root).?.style.direction = .absolute;

    const root_node = try createPanel(&ui_state, ui_state.root);
    var space = try DockSpace.init(std.testing.allocator);
    defer space.deinit();
    const window = try space.createWindow("A", root_node, .{ .x = 120, .y = 90 }, .{});
    try space.dock.moveWindowToLeaf(window, space.dock.root);

    try ui_state.beginFrame(.{
        .events = &[_]events.PlatformEvent{
            .{ .mouse_move = .{ .x = 20, .y = 10 } },
            .{ .mouse_down = .left },
        },
        .window_size = .{ .x = 400, .y = 300 },
    });
    _ = try space.run(&ui_state, ui_state.root, .{ .rect = .{ .x = 0, .y = 0, .w = 400, .h = 300 } });

    try ui_state.beginFrame(.{
        .events = &[_]events.PlatformEvent{
            .{ .mouse_move = .{ .x = 420, .y = 320 } },
            .{ .mouse_up = .left },
        },
        .window_size = .{ .x = 400, .y = 300 },
    });
    _ = try space.run(&ui_state, ui_state.root, .{ .rect = .{ .x = 0, .y = 0, .w = 400, .h = 300 } });

    try std.testing.expect(space.dock.leafForWindow(window) == null);
    try std.testing.expect(space.windows.get(window).?.rect.w >= 120);
}

test "dock space redock split allocates support nodes before syncing same frame" {
    var ui_state = try app.Ui.init(std.testing.allocator);
    defer ui_state.deinit();
    ui_state.tree.get(ui_state.root).?.style.direction = .absolute;

    const a_root = try createPanel(&ui_state, ui_state.root);
    const b_root = try createPanel(&ui_state, ui_state.root);

    var space = try DockSpace.init(std.testing.allocator);
    defer space.deinit();
    const a = try space.createWindow("A", a_root, .{ .x = 80, .y = 80 }, .{});
    const b = try space.createWindow("B", b_root, .{ .x = 80, .y = 80 }, .{});
    try space.dock.moveWindowToLeaf(a, space.dock.root);
    const split = try space.splitNode(space.dock.root, .right, 0.5);
    try space.dock.moveWindowToLeaf(b, split.new_leaf);

    const opts = DockSpaceOptions{ .rect = .{ .x = 0, .y = 0, .w = 400, .h = 300 } };
    try ui_state.beginFrame(.{ .events = &.{}, .window_size = .{ .x = 400, .y = 300 } });
    _ = try space.run(&ui_state, ui_state.root, opts);

    try ui_state.beginFrame(.{
        .events = &[_]events.PlatformEvent{
            .{ .mouse_move = .{ .x = 20, .y = 10 } },
            .{ .mouse_down = .left },
        },
        .window_size = .{ .x = 400, .y = 300 },
    });
    _ = try space.run(&ui_state, ui_state.root, opts);

    try ui_state.beginFrame(.{
        .events = &[_]events.PlatformEvent{
            .{ .mouse_move = .{ .x = 390, .y = 120 } },
            .{ .mouse_up = .left },
        },
        .window_size = .{ .x = 400, .y = 300 },
    });
    _ = try space.run(&ui_state, ui_state.root, opts);

    try std.testing.expect(space.leaf_nodes.items.len >= space.dock.nodes.items.len);
    try std.testing.expect(space.split_nodes.items.len >= space.dock.nodes.items.len);
    try std.testing.expect(space.dock.leafForWindow(a) != null);
    try std.testing.expectEqual(reachableLeafCount(&space.dock, space.dock.root), visibleLeafHostCount(&ui_state, &space));
}

test "dock space shows drag ghost and drop preview while dragging over leaf" {
    var ui_state = try app.Ui.init(std.testing.allocator);
    defer ui_state.deinit();
    ui_state.tree.get(ui_state.root).?.style.direction = .absolute;

    const a_root = try createPanel(&ui_state, ui_state.root);
    const b_root = try createPanel(&ui_state, ui_state.root);

    var space = try DockSpace.init(std.testing.allocator);
    defer space.deinit();
    const a = try space.createWindow("A", a_root, .{ .x = 80, .y = 80 }, .{});
    const b = try space.createWindow("B", b_root, .{ .x = 80, .y = 80 }, .{});
    try space.dock.moveWindowToLeaf(a, space.dock.root);
    const split = try space.splitNode(space.dock.root, .right, 0.5);
    try space.dock.moveWindowToLeaf(b, split.new_leaf);

    const opts = DockSpaceOptions{ .rect = .{ .x = 0, .y = 0, .w = 400, .h = 300 } };
    try ui_state.beginFrame(.{ .events = &.{}, .window_size = .{ .x = 400, .y = 300 } });
    _ = try space.run(&ui_state, ui_state.root, opts);

    try ui_state.beginFrame(.{
        .events = &[_]events.PlatformEvent{
            .{ .mouse_move = .{ .x = 20, .y = 10 } },
            .{ .mouse_down = .left },
        },
        .window_size = .{ .x = 400, .y = 300 },
    });
    _ = try space.run(&ui_state, ui_state.root, opts);

    try ui_state.beginFrame(.{
        .events = &[_]events.PlatformEvent{
            .{ .mouse_move = .{ .x = 390, .y = 120 } },
        },
        .window_size = .{ .x = 400, .y = 300 },
    });
    _ = try space.run(&ui_state, ui_state.root, opts);

    try std.testing.expect(ui_state.tree.get(space.overlays.drag_ghost).?.flags.visible);
    try std.testing.expect(ui_state.tree.get(space.overlays.drop_preview).?.flags.visible);
    try std.testing.expectEqualStrings("A", ui_state.tree.get(space.overlays.drag_label).?.text.?);
}

test "dock space splits active tab from same leaf when dropped on edge" {
    var ui_state = try app.Ui.init(std.testing.allocator);
    defer ui_state.deinit();
    ui_state.tree.get(ui_state.root).?.style.direction = .absolute;

    const viewport_root = try createPanel(&ui_state, ui_state.root);
    const inspector_root = try createPanel(&ui_state, ui_state.root);

    var space = try DockSpace.init(std.testing.allocator);
    defer space.deinit();
    const viewport = try space.createWindow("Viewport", viewport_root, .{ .x = 80, .y = 80 }, .{});
    const inspector = try space.createWindow("Inspector", inspector_root, .{ .x = 80, .y = 80 }, .{});
    try space.dock.moveWindowToLeaf(viewport, space.dock.root);
    try space.dockWindow(inspector, space.dock.root, .center_tab);
    _ = space.dock.setActiveWindow(space.dock.root, inspector);
    space.dock.layout(.{ .x = 0, .y = 0, .w = 400, .h = 300 });

    const changed = space.finishDrag(.{ .x = 390, .y = 120 }, .{
        .window = inspector,
        .source_leaf = space.dock.root,
        .start_mouse = .{ .x = 130, .y = 10 },
        .dragging = true,
    }, .{ .rect = .{ .x = 0, .y = 0, .w = 400, .h = 300 } });

    try std.testing.expect(changed);
    space.dock.layout(.{ .x = 0, .y = 0, .w = 400, .h = 300 });
    try std.testing.expect(space.dock.leafForWindow(viewport) != null);
    try std.testing.expect(space.dock.leafForWindow(inspector) != null);
    try std.testing.expect(space.dock.leafForWindow(viewport).? != space.dock.leafForWindow(inspector).?);
    const viewport_rect = space.dock.nodeRect(space.dock.leafForWindow(viewport).?) orelse .{};
    const inspector_rect = space.dock.nodeRect(space.dock.leafForWindow(inspector).?) orelse .{};
    try std.testing.expect(inspector_rect.x > viewport_rect.x);
    try std.testing.expect(inspector_rect.w < viewport_rect.w);
    try std.testing.expect(inspector_rect.w > 80);
}

test "dock manager moving last tab cleans empty source leaf" {
    var dock = try dock_manager_mod.DockManager.init(std.testing.allocator);
    defer dock.deinit();

    const split = try dock.splitNode(dock.root, .right, 0.5);
    try dock.moveWindowToLeaf(1, split.old_node);
    try dock.moveWindowToLeaf(2, split.new_leaf);
    try dock.moveWindowToLeaf(1, split.new_leaf);

    try std.testing.expect(dock.leafForWindow(1) != null);
    try std.testing.expect(dock.leafForWindow(2) != null);
    try std.testing.expectEqual(dock.leafForWindow(2).?, dock.leafForWindow(1).?);
}
