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

const tab_nominal_width: f32 = 116;
const tab_min_width: f32 = 40;
const floating_title_height: f32 = 30;

const LeafNodes = struct {
    host: types.NodeId = types.invalid_node,
    tab_bar: types.NodeId = types.invalid_node,
    content: types.NodeId = types.invalid_node,
    last_sync: u32 = 0,
};

const SplitNodes = struct {
    handle: types.NodeId = types.invalid_node,
    last_sync: u32 = 0,
};

const FloatingNodes = struct {
    host: types.NodeId = types.invalid_node,
    title: types.NodeId = types.invalid_node,
    content: types.NodeId = types.invalid_node,
    last_sync: u32 = 0,
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
    last_sync: u32 = 0,
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
    // Frame counter used to detect support nodes that were not touched by
    // the current sync pass; those get hidden without a hide/show round trip
    // that would dirty the tree every frame.
    sync_stamp: u32 = 0,
    order_scratch: std.ArrayList(types.NodeId) = .empty,
    float_scratch: std.ArrayList(DockWindowId) = .empty,

    pub fn init(allocator: std.mem.Allocator) !DockSpace {
        return .{
            .allocator = allocator,
            .dock = try dock_manager_mod.DockManager.init(allocator),
            .windows = window_manager_mod.WindowManager.init(allocator),
        };
    }

    pub fn deinit(self: *DockSpace) void {
        self.float_scratch.deinit(self.allocator);
        self.order_scratch.deinit(self.allocator);
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
        self.sync_stamp +%= 1;
        try self.ensureNodeCapacity(ui, parent);
        self.dock.layout(options.rect);

        var result: DockSpaceResult = .{};
        result.changed = self.updateResize(ui, options);
        if (self.updateTabsAndDrops(ui, options)) result.changed = true;
        try self.ensureNodeCapacity(ui, parent);
        try self.ensureOverlayNodes(ui, parent);

        self.syncDockNode(ui, parent, self.dock.root, options);
        try self.syncFloatingNodes(ui, parent, options);
        self.hideStaleNodes(ui);
        try self.applyPaintOrder(ui, parent);
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

    /// Hides every support node the current sync pass did not touch:
    /// leaves/splits collapsed out of the dock tree, tabs of windows that
    /// left their leaf (including newly floating ones), and floating chrome
    /// of windows that were docked.
    fn hideStaleNodes(self: *DockSpace, ui: *app.Ui) void {
        for (self.leaf_nodes.items) |nodes| {
            if (nodes.last_sync == self.sync_stamp) continue;
            hideNode(ui, nodes.host);
            hideNode(ui, nodes.tab_bar);
            hideNode(ui, nodes.content);
        }
        for (self.split_nodes.items) |nodes| {
            if (nodes.last_sync == self.sync_stamp) continue;
            hideNode(ui, nodes.handle);
        }
        for (self.floating_nodes.items) |nodes| {
            if (nodes.last_sync == self.sync_stamp) continue;
            hideNode(ui, nodes.host);
            hideNode(ui, nodes.title);
            hideNode(ui, nodes.content);
        }
        for (self.window_state.items) |state| {
            if (state.last_sync == self.sync_stamp) continue;
            hideNode(ui, state.tab);
        }
    }

    /// Keeps overlay chrome painting in the right order: split handles above
    /// panels, floating windows above the docked layout in ascending z-index,
    /// and drag overlays on top. Re-appends only when the order is wrong, so
    /// the steady state leaves the tree untouched.
    fn applyPaintOrder(self: *DockSpace, ui: *app.Ui, parent: types.NodeId) !void {
        self.order_scratch.clearRetainingCapacity();
        try self.collectSplitHandles(self.dock.root);

        self.float_scratch.clearRetainingCapacity();
        for (self.windows.windows.items, 0..) |*window, i| {
            const window_id: DockWindowId = @intCast(i);
            if (!window.open or self.dock.leafForWindow(window_id) != null) continue;
            if (window_id >= self.floating_nodes.items.len) continue;
            try self.float_scratch.append(self.allocator, window_id);
        }
        std.mem.sort(DockWindowId, self.float_scratch.items, @as(*const window_manager_mod.WindowManager, &self.windows), floatZLessThan);
        for (self.float_scratch.items) |window_id| {
            try self.order_scratch.append(self.allocator, self.floating_nodes.items[window_id].host);
        }

        try self.order_scratch.append(self.allocator, self.overlays.drop_preview);
        try self.order_scratch.append(self.allocator, self.overlays.drag_ghost);
        ensureTailOrder(ui, parent, self.order_scratch.items);
    }

    fn collectSplitHandles(self: *DockSpace, id: types.DockNodeId) !void {
        if (id == types.invalid_dock_node or id >= self.dock.nodes.items.len) return;
        switch (self.dock.nodes.items[id]) {
            .leaf => {},
            .split => |split| {
                try self.order_scratch.append(self.allocator, self.split_nodes.items[id].handle);
                try self.collectSplitHandles(split.first);
                try self.collectSplitHandles(split.second);
            },
        }
    }

    fn syncLeaf(self: *DockSpace, ui: *app.Ui, parent: types.NodeId, id: types.DockNodeId, leaf: anytype, options: DockSpaceOptions) void {
        const parent_origin = nodeOrigin(ui, parent);
        self.leaf_nodes.items[id].last_sync = self.sync_stamp;
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
                const tab_rect = tabRect(leaf.rect, tab_index, leaf.tabs.items.len, options.tab_height);
                const is_active = active != null and active.? == window_id;
                if (window_id < self.window_state.items.len) {
                    self.window_state.items[window_id].last_sync = self.sync_stamp;
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
        self.split_nodes.items[id].last_sync = self.sync_stamp;
        const nodes = self.split_nodes.items[id];
        const hit_rect = self.dock.resizeHandleRect(id, options.handle_thickness) orelse return;
        const active = if (self.dock.activeResizeSplit()) |active_split| active_split == id else false;
        const hovered = !active and hit_rect.contains(ui.input.mouse_pos);
        const visual_rect = if (active or hovered)
            resizeHandleVisualRect(hit_rect, split.axis, options.handle_thickness)
        else
            hit_rect;
        setPanel(ui, nodes.handle, visual_rect, parent_origin, if (active or hovered) .accent else .transparent, true);
    }

    fn syncFloatingNodes(self: *DockSpace, ui: *app.Ui, parent: types.NodeId, options: DockSpaceOptions) !void {
        _ = options;
        const parent_origin = nodeOrigin(ui, parent);
        for (self.windows.windows.items, 0..) |*window, i| {
            const window_id: DockWindowId = @intCast(i);
            if (!window.open or self.dock.leafForWindow(window_id) != null) continue;
            try self.ensureFloatingCapacity(ui, parent, window_id + 1);
            self.floating_nodes.items[window_id].last_sync = self.sync_stamp;
            const nodes = self.floating_nodes.items[window_id];
            if (window.rect.w <= 0 or window.rect.h <= 0) {
                window.rect.w = @max(260, window.min_size.x);
                window.rect.h = @max(190, window.min_size.y);
            }
            setPanel(ui, nodes.host, window.rect, parent_origin, .panel, false);
            setPanel(ui, nodes.title, .{ .x = window.rect.x, .y = window.rect.y, .w = window.rect.w, .h = floating_title_height }, .{ .x = window.rect.x, .y = window.rect.y }, .shell, true);
            const content_rect: types.Rect = .{
                .x = window.rect.x,
                .y = window.rect.y + floating_title_height,
                .w = window.rect.w,
                .h = @max(0, window.rect.h - floating_title_height),
            };
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
                        const rect = tabRect(leaf.rect, tab_index, leaf.tabs.items.len, options.tab_height);
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
            const title_rect: types.Rect = .{ .x = window.rect.x, .y = window.rect.y, .w = window.rect.w, .h = floating_title_height };
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
        var next = node.style;
        next.width = .{ .px = @max(0, rect.w) };
        next.height = .{ .px = @max(0, rect.h) };
        next.margin = style_mod.Edges{ .left = rect.x - origin.x, .top = rect.y - origin.y };
        next.background = ui.theme.color(background);
        next.border_color = ui.theme.color(border);
        next.border_width = border_width;
        next.radius = style_mod.CornerRadii.all(radius);
        next.direction = .absolute;
        const visible = rect.w > 0 and rect.h > 0;
        if (std.meta.eql(node.style, next) and
            node.flags.visible == visible and
            node.flags.interactive == interactive) return;
        node.style = next;
        node.flags.visible = visible;
        node.flags.interactive = interactive;
        node.dirty.layout = true;
        node.dirty.paint = true;
    }
}

fn hideNode(ui: *app.Ui, id: types.NodeId) void {
    if (ui.tree.get(id)) |node| {
        if (!node.flags.visible and !node.flags.interactive) return;
        node.flags.visible = false;
        node.flags.interactive = false;
        node.dirty.layout = true;
        node.dirty.paint = true;
    }
}

/// Rect of the tab strip entry for `tab_index` inside a leaf. Tabs shrink
/// evenly when the nominal width would overflow the leaf and are clipped to
/// the leaf's right edge; shared by drawing and hit testing so they always
/// agree.
fn tabRect(leaf_rect: types.Rect, tab_index: usize, tab_count: usize, tab_height: f32) types.Rect {
    const count: f32 = @floatFromInt(@max(1, tab_count));
    const width = @min(tab_nominal_width, @max(tab_min_width, leaf_rect.w / count));
    const x = leaf_rect.x + @as(f32, @floatFromInt(tab_index)) * width;
    const right = @min(x + width, leaf_rect.x + leaf_rect.w);
    return .{ .x = x, .y = leaf_rect.y, .w = @max(0, right - x), .h = tab_height };
}

fn floatZLessThan(windows: *const window_manager_mod.WindowManager, a: DockWindowId, b: DockWindowId) bool {
    const za = if (windows.getConst(a)) |window| window.z_index else 0;
    const zb = if (windows.getConst(b)) |window| window.z_index else 0;
    return za < zb;
}

/// Ensures `desired` are the trailing children of `parent`, in order.
/// Re-appends (and therefore dirties the tree) only when the order differs.
fn ensureTailOrder(ui: *app.Ui, parent: types.NodeId, desired: []const types.NodeId) void {
    const parent_node = ui.tree.getConst(parent) orelse return;
    var current = parent_node.last_child;
    var i = desired.len;
    var matches = true;
    while (i > 0) : (i -= 1) {
        if (current != desired[i - 1]) {
            matches = false;
            break;
        }
        current = if (ui.tree.getConst(current)) |node| node.prev_sibling else types.invalid_node;
    }
    if (matches) return;
    for (desired) |id| {
        ui.tree.appendChild(parent, id) catch {};
    }
}

fn nodeOrigin(ui: *const app.Ui, id: types.NodeId) types.Vec2 {
    if (ui.tree.getConst(id)) |node| return .{ .x = node.bounds.x, .y = node.bounds.y };
    return .{};
}

fn setContentRoot(ui: *app.Ui, id: types.NodeId) void {
    if (ui.tree.get(id)) |node| {
        var next = node.style;
        next.width = .fill;
        next.height = .fill;
        next.margin = .{};
        next.overflow_x = .scroll;
        next.overflow_y = .scroll;
        if (std.meta.eql(node.style, next) and node.flags.visible) return;
        node.style = next;
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
    ui.tree.setText(id, text) catch {};
    if (ui.tree.get(id)) |node| {
        var next = node.style;
        next.width = .fill;
        next.height = .fill;
        next.padding = .{ .left = 10, .right = 8, .top = 7, .bottom = 5 };
        next.foreground = ui.theme.color(if (active) .text else .text_muted);
        next.font_size = ui.theme.font.small;
        if (std.meta.eql(node.style, next) and node.flags.visible) return;
        node.style = next;
        node.flags.visible = true;
        node.dirty.layout = true;
        node.dirty.paint = true;
    }
}

fn ensureRootParent(ui: *app.Ui, node_id: types.NodeId, parent: types.NodeId) void {
    const node = ui.tree.get(node_id) orelse return;
    if (parent == types.invalid_node) {
        if (node.parent != types.invalid_node) ui.tree.removeChild(node.parent, node_id);
        if (node.flags.visible) {
            node.flags.visible = false;
            node.dirty.layout = true;
            node.dirty.paint = true;
        }
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

fn siblingPosition(ui: *const app.Ui, parent: types.NodeId, id: types.NodeId) ?usize {
    const parent_node = ui.tree.getConst(parent) orelse return null;
    var child = parent_node.first_child;
    var index: usize = 0;
    while (child != types.invalid_node) : (index += 1) {
        if (child == id) return index;
        child = if (ui.tree.getConst(child)) |node| node.next_sibling else types.invalid_node;
    }
    return null;
}

test "floating windows paint in z order after bring to front" {
    var ui_state = try app.Ui.init(std.testing.allocator);
    defer ui_state.deinit();
    ui_state.tree.get(ui_state.root).?.style.direction = .absolute;

    const a_root = try createPanel(&ui_state, ui_state.root);
    const b_root = try createPanel(&ui_state, ui_state.root);

    var space = try DockSpace.init(std.testing.allocator);
    defer space.deinit();
    const a = try space.createWindow("A", a_root, .{ .x = 40, .y = 40 }, .{});
    const b = try space.createWindow("B", b_root, .{ .x = 40, .y = 40 }, .{});
    space.windows.get(a).?.rect = .{ .x = 20, .y = 20, .w = 200, .h = 150 };
    space.windows.get(b).?.rect = .{ .x = 60, .y = 60, .w = 200, .h = 150 };

    const opts = DockSpaceOptions{ .rect = .{ .x = 0, .y = 0, .w = 400, .h = 300 } };
    try ui_state.beginFrame(.{ .events = &.{}, .window_size = .{ .x = 400, .y = 300 } });
    _ = try space.run(&ui_state, ui_state.root, opts);

    const a_host = space.floating_nodes.items[a].host;
    const b_host = space.floating_nodes.items[b].host;
    var a_pos = siblingPosition(&ui_state, ui_state.root, a_host).?;
    var b_pos = siblingPosition(&ui_state, ui_state.root, b_host).?;
    try std.testing.expect(a_pos < b_pos);

    space.windows.bringToFront(a);
    try ui_state.beginFrame(.{ .events = &.{}, .window_size = .{ .x = 400, .y = 300 } });
    _ = try space.run(&ui_state, ui_state.root, opts);

    a_pos = siblingPosition(&ui_state, ui_state.root, a_host).?;
    b_pos = siblingPosition(&ui_state, ui_state.root, b_host).?;
    try std.testing.expect(b_pos < a_pos);
    try std.testing.expect(a_pos < siblingPosition(&ui_state, ui_state.root, space.overlays.drag_ghost).?);
}

test "docking a floating window hides its floating chrome" {
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
    space.windows.get(b).?.rect = .{ .x = 60, .y = 60, .w = 200, .h = 150 };

    const opts = DockSpaceOptions{ .rect = .{ .x = 0, .y = 0, .w = 400, .h = 300 } };
    try ui_state.beginFrame(.{ .events = &.{}, .window_size = .{ .x = 400, .y = 300 } });
    _ = try space.run(&ui_state, ui_state.root, opts);
    try std.testing.expect(ui_state.tree.get(space.floating_nodes.items[b].host).?.flags.visible);

    try space.dock.dockWindow(b, space.dock.root, .center_tab);
    try ui_state.beginFrame(.{ .events = &.{}, .window_size = .{ .x = 400, .y = 300 } });
    _ = try space.run(&ui_state, ui_state.root, opts);
    try std.testing.expect(!ui_state.tree.get(space.floating_nodes.items[b].host).?.flags.visible);
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
