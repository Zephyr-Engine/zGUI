const std = @import("std");
const GuiContext = @import("../context.zig").GuiContext;
const shapes = @import("../shapes.zig");
const DockSpace = @import("dock_space.zig").DockSpace;
const DockNode = @import("dock_node.zig").DockNode;
const SplitDirection = @import("dock_node.zig").SplitDirection;
const PanelInfo = @import("panel_info.zig").PanelInfo;
const drop_zone = @import("drop_zone.zig");
const DropZone = drop_zone.DropZone;
const persistence = @import("layout_persistence.zig");

pub const DragState = struct {
    dragging: bool = false,
    panel_id: u64 = 0,
    source_node: ?*DockNode = null,
    initial_mouse_pos: [2]f32 = .{ 0, 0 },
    current_mouse_pos: [2]f32 = .{ 0, 0 },
    drag_threshold_met: bool = false,
    target_node: ?*DockNode = null,
    drop_zone: DropZone = .none,

    pub fn init() DragState {
        return .{};
    }

    pub fn reset(self: *DragState) void {
        self.* = init();
    }
};

pub const SplitterDragState = struct {
    node: *DockNode,
    initial_ratio: f32,
    initial_mouse_pos: f32,
};

pub const DockingContext = struct {
    dock_space: DockSpace,
    drag_state: DragState,
    splitter_drag: ?SplitterDragState = null,
    panel_registry: *std.AutoHashMap(u64, PanelInfo),
    allocator: std.mem.Allocator,
    window_id: u64 = 0,
    window_manager: ?*anyopaque = null, // Pointer to WindowManager (avoid circular dependency)
    owns_panel_registry: bool = false, // Track if we should deinit panel_registry

    pub fn init(allocator: std.mem.Allocator, bounds: shapes.Rect) !DockingContext {
        const panel_registry = try allocator.create(std.AutoHashMap(u64, PanelInfo));
        panel_registry.* = std.AutoHashMap(u64, PanelInfo).init(allocator);

        return .{
            .allocator = allocator,
            .dock_space = DockSpace.init(allocator, bounds),
            .drag_state = DragState.init(),
            .panel_registry = panel_registry,
            .owns_panel_registry = true,
        };
    }

    pub fn deinit(self: *DockingContext) void {
        self.dock_space.deinit();
        if (self.owns_panel_registry) {
            self.panel_registry.deinit();
            self.allocator.destroy(self.panel_registry);
        }
    }

    /// Register a panel with the docking system
    pub fn registerPanel(self: *DockingContext, panel: PanelInfo) !void {
        try self.panel_registry.*.put(panel.id, panel);
    }

    /// Unregister a panel
    pub fn unregisterPanel(self: *DockingContext, panel_id: u64) void {
        _ = self.panel_registry.*.remove(panel_id);
    }

    /// Add a panel to the dock space
    pub fn addPanel(self: *DockingContext, panel_id: u64) !void {
        try self.dock_space.addPanel(panel_id);
    }

    /// Remove a panel from the dock space
    pub fn removePanel(self: *DockingContext, panel_id: u64) !void {
        // Find node containing panel
        if (self.dock_space.root) |root| {
            if (root.findNodeContainingPanel(panel_id)) |node| {
                const should_remove = node.removePanel(panel_id);
                if (should_remove) {
                    try collapseEmptyNode(self, node);
                }
            }
        }
    }

    /// Save the current layout to a file
    pub fn saveLayout(self: *DockingContext, file_path: []const u8, io: std.Io) !void {
        try persistence.saveLayoutToFile(self.allocator, self.dock_space.root, file_path, io);
    }

    /// Load layout from a file
    /// Returns true if layout was loaded, false if file doesn't exist
    pub fn loadLayout(self: *DockingContext, file_path: []const u8, io: std.Io) !bool {
        const loaded_root = try persistence.loadLayoutFromFile(self.allocator, file_path, io);
        if (loaded_root) |root| {
            // Free existing root if any
            if (self.dock_space.root) |old_root| {
                old_root.deinit();
            }
            self.dock_space.root = root;
            return true;
        }
        return false;
    }

    /// Main render function - entry point
    pub fn render(self: *DockingContext, ctx: *GuiContext) !void {
        // Update layout
        try self.dock_space.updateLayout();

        // Update drag state
        try updateDragState(self, ctx);

        // Render the dock tree
        if (self.dock_space.root) |root| {
            try renderRecursive(self, ctx, root);
        }

        // Render dragged panel preview
        if (self.drag_state.dragging) {
            try renderDraggedPanelPreview(self, ctx);
        }
    }

    /// Begin a new frame (reset per-frame state)
    pub fn beginFrame(self: *DockingContext) void {
        _ = self;
        // Will be used in later steps
    }

    /// End frame cleanup
    pub fn endFrame(self: *DockingContext) void {
        _ = self;
        // Will be used in later steps
    }

    /// Check if current drag position is outside the window bounds
    pub fn isDragOutsideWindow(self: *DockingContext, ctx: *GuiContext) bool {
        if (!self.drag_state.dragging) return false;

        const mouse_x = @as(f32, @floatCast(ctx.input.cursor_x));
        const mouse_y = @as(f32, @floatCast(ctx.input.cursor_y));
        const bounds = self.dock_space.bounds;
        const threshold = 50.0; // Prevent accidental window creation

        return mouse_x < (bounds.x - threshold) or
            mouse_x > (bounds.x + bounds.w + threshold) or
            mouse_y < (bounds.y - threshold) or
            mouse_y > (bounds.y + bounds.h + threshold);
    }

    /// Get the cached rect of the panel being dragged (for sizing new window)
    pub fn getDraggedPanelRect(self: *DockingContext) ?shapes.Rect {
        if (!self.drag_state.dragging) return null;
        if (self.drag_state.source_node) |source| {
            return source.cached_rect;
        }
        return null;
    }
};

/// Recursively render a dock node and its children
fn renderRecursive(docking_ctx: *DockingContext, ctx: *GuiContext, node: *DockNode) !void {
    const bounds = node.cached_rect;

    switch (node.node_type) {
        .tab_group => {
            if (node.tab_group) |*group| {
                try renderTabGroup(docking_ctx, ctx, node, group, bounds);
            }
        },
        .split => {
            if (node.split) |*split_info| {
                // Render children first
                try renderRecursive(docking_ctx, ctx, split_info.first);
                try renderRecursive(docking_ctx, ctx, split_info.second);

                // Render splitter on top
                try renderSplitter(docking_ctx, ctx, node, split_info, bounds);
            }
        },
    }

    // Render drop zone overlay if this is the target node
    if (docking_ctx.drag_state.dragging and docking_ctx.drag_state.target_node == node) {
        const mouse_x = @as(f32, @floatCast(ctx.input.cursor_x));
        const mouse_y = @as(f32, @floatCast(ctx.input.cursor_y));

        if (drop_zone.calculateDropZone(bounds, mouse_x, mouse_y)) |zone_info| {
            try drop_zone.renderDropZoneOverlay(ctx, zone_info);
        }
    }
}

/// Render a tab group (tabs + active panel content)
fn renderTabGroup(
    docking_ctx: *DockingContext,
    ctx: *GuiContext,
    node: *DockNode,
    group: *@import("dock_node.zig").TabGroup,
    bounds: shapes.Rect,
) !void {
    const tab_bar_height = 35.0;
    const tab_font_size = 16.0;

    // Tab bar background
    const tab_bar_rect = shapes.Rect{
        .x = bounds.x,
        .y = bounds.y,
        .w = bounds.w,
        .h = tab_bar_height,
    };
    try ctx.draw_list.addRect(tab_bar_rect, ctx.theme.bg_elevated);

    // Render tabs
    var tab_x = bounds.x + 4.0; // Small left padding
    const tab_width = 150.0;
    const tab_padding = 2.0;

    for (group.panel_ids.items, 0..) |panel_id, i| {
        const panel_info = docking_ctx.panel_registry.*.get(panel_id) orelse continue;

        const is_active = (i == group.active_index);

        const tab_rect = shapes.Rect{
            .x = tab_x,
            .y = bounds.y + 4.0,
            .w = tab_width,
            .h = tab_bar_height - 8.0,
        };

        // Tab background
        const tab_color = if (is_active) ctx.theme.bg_secondary else ctx.theme.bg_primary;
        try ctx.draw_list.addRoundedRect(tab_rect, 4.0, tab_color);

        // Tab text
        const text_metrics = try ctx.measureText(panel_info.title, tab_font_size);
        const text_x = tab_x + (tab_width - text_metrics.width) * 0.5;
        const text_y = bounds.y + (tab_bar_height - text_metrics.height) * 0.5;
        try ctx.addText(text_x, text_y, panel_info.title, tab_font_size, ctx.theme.text_primary);

        // Handle tab interaction (click to activate, drag to move)
        if (ctx.input.isMouseInRect(tab_rect) and !ctx.click_consumed) {
            if (ctx.input.mouse_left_clicked and !docking_ctx.drag_state.dragging) {
                // Simple click - activate tab
                group.active_index = i;
                // Store initial position for potential drag
                docking_ctx.drag_state.initial_mouse_pos = .{
                    @floatCast(ctx.input.cursor_x),
                    @floatCast(ctx.input.cursor_y),
                };
                docking_ctx.drag_state.panel_id = panel_id;
                docking_ctx.drag_state.source_node = node;
                ctx.click_consumed = true;
            } else if (ctx.input.mouse_left_pressed and !docking_ctx.drag_state.dragging) {
                // Check if drag threshold exceeded
                const dx = @abs(@as(f32, @floatCast(ctx.input.cursor_x)) - docking_ctx.drag_state.initial_mouse_pos[0]);
                const dy = @abs(@as(f32, @floatCast(ctx.input.cursor_y)) - docking_ctx.drag_state.initial_mouse_pos[1]);

                if ((dx > 5.0 or dy > 5.0) and docking_ctx.drag_state.panel_id == panel_id) {
                    // Start dragging
                    docking_ctx.drag_state.dragging = true;
                    docking_ctx.drag_state.drag_threshold_met = true;
                    ctx.click_consumed = true;
                }
            }
        }

        tab_x += tab_width + tab_padding;
    }

    // Content area background
    const content_bounds = shapes.Rect{
        .x = bounds.x,
        .y = bounds.y + tab_bar_height,
        .w = bounds.w,
        .h = bounds.h - tab_bar_height,
    };
    try ctx.draw_list.addRect(content_bounds, ctx.theme.bg_secondary);

    // Render active panel content
    if (group.panel_ids.items.len > 0) {
        const active_panel_id = group.panel_ids.items[group.active_index];
        if (docking_ctx.panel_registry.*.get(active_panel_id)) |panel_info| {
            // Call user's render function
            try panel_info.render_fn(ctx, content_bounds);
        }
    }
}

/// Render a splitter between split nodes
fn renderSplitter(
    docking_ctx: *DockingContext,
    ctx: *GuiContext,
    node: *DockNode,
    split_info: *@import("dock_node.zig").Split,
    bounds: shapes.Rect,
) !void {
    const thickness = 4.0;

    const splitter_rect = switch (split_info.direction) {
        .horizontal => shapes.Rect{
            .x = bounds.x + (bounds.w * split_info.ratio),
            .y = bounds.y,
            .w = thickness,
            .h = bounds.h,
        },
        .vertical => shapes.Rect{
            .x = bounds.x,
            .y = bounds.y + (bounds.h * split_info.ratio),
            .w = bounds.w,
            .h = thickness,
        },
    };

    const is_hovered = ctx.input.isMouseInRect(splitter_rect);
    const is_dragging = if (docking_ctx.splitter_drag) |drag|
        drag.node == node
    else
        false;

    // Render splitter
    const splitter_color = if (is_hovered or is_dragging) ctx.theme.accent_primary else ctx.theme.bg_elevated;
    try ctx.draw_list.addRect(splitter_rect, splitter_color);

    // Handle splitter drag
    if (is_hovered and ctx.input.mouse_left_clicked and !ctx.click_consumed and !docking_ctx.drag_state.dragging) {
        docking_ctx.splitter_drag = SplitterDragState{
            .node = node,
            .initial_ratio = split_info.ratio,
            .initial_mouse_pos = switch (split_info.direction) {
                .horizontal => @as(f32, @floatCast(ctx.input.cursor_x)),
                .vertical => @as(f32, @floatCast(ctx.input.cursor_y)),
            },
        };
        ctx.click_consumed = true;
    }

    if (is_dragging and ctx.input.mouse_left_pressed) {
        const current_pos = switch (split_info.direction) {
            .horizontal => @as(f32, @floatCast(ctx.input.cursor_x)),
            .vertical => @as(f32, @floatCast(ctx.input.cursor_y)),
        };

        const delta = current_pos - docking_ctx.splitter_drag.?.initial_mouse_pos;
        const size = switch (split_info.direction) {
            .horizontal => bounds.w,
            .vertical => bounds.h,
        };

        const delta_ratio = delta / size;
        var new_ratio = docking_ctx.splitter_drag.?.initial_ratio + delta_ratio;

        // Clamp to min/max values
        new_ratio = std.math.clamp(new_ratio, 0.1, 0.9);

        split_info.ratio = new_ratio;
    }

    if (!ctx.input.mouse_left_pressed) {
        docking_ctx.splitter_drag = null;
    }

    // Set cursor on hover or drag
    if (is_hovered or is_dragging) {
        const cursor = switch (split_info.direction) {
            .horizontal => ctx.hresize_cursor,
            .vertical => ctx.vresize_cursor,
        };
        ctx.setCursor(cursor);
    }
}

/// Update drag state - find target node and calculate drop zone
fn updateDragState(docking_ctx: *DockingContext, ctx: *GuiContext) !void {
    // If dragging and mouse released, handle drop
    if (docking_ctx.drag_state.dragging and !ctx.input.mouse_left_pressed) {
        // Check if dropped outside window
        if (docking_ctx.isDragOutsideWindow(ctx)) {
            try handleDragOutsideWindow(docking_ctx, ctx);
        } else {
            try handleDrop(docking_ctx);
        }
        docking_ctx.drag_state.reset();
        return;
    }

    // If not dragging, reset state
    if (!ctx.input.mouse_left_pressed) {
        docking_ctx.drag_state.reset();
        return;
    }

    // If dragging, update target and drop zone
    if (docking_ctx.drag_state.dragging) {
        const mouse_x = @as(f32, @floatCast(ctx.input.cursor_x));
        const mouse_y = @as(f32, @floatCast(ctx.input.cursor_y));

        // Store current mouse position
        docking_ctx.drag_state.current_mouse_pos = .{ mouse_x, mouse_y };

        // Find target node at cursor position
        docking_ctx.drag_state.target_node = docking_ctx.dock_space.findLeafAtPosition(mouse_x, mouse_y);

        // Calculate drop zone
        if (docking_ctx.drag_state.target_node) |target| {
            const zone_info = drop_zone.calculateDropZone(target.cached_rect, mouse_x, mouse_y);
            if (zone_info) |info| {
                docking_ctx.drag_state.drop_zone = info.zone;
            } else {
                docking_ctx.drag_state.drop_zone = .none;
            }
        } else {
            docking_ctx.drag_state.drop_zone = .none;
        }
    }
}

/// Handle drag ending outside window bounds - creates new window
fn handleDragOutsideWindow(docking_ctx: *DockingContext, ctx: *GuiContext) !void {
    // Import WindowManager dynamically to avoid circular dependency
    const WindowManager = @import("../window_manager.zig").WindowManager;
    const window_manager: *WindowManager = @ptrCast(@alignCast(docking_ctx.window_manager orelse return));

    const panel_id = docking_ctx.drag_state.panel_id;

    // Get panel size for new window
    const panel_rect = docking_ctx.getDraggedPanelRect() orelse
        shapes.Rect{ .x = 0, .y = 0, .w = 800, .h = 600 };

    // Calculate position near cursor
    const mouse_x: i32 = @intFromFloat(ctx.input.cursor_x);
    const mouse_y: i32 = @intFromFloat(ctx.input.cursor_y);
    const width: i32 = @intFromFloat(@max(panel_rect.w, 400));
    const height: i32 = @intFromFloat(@max(panel_rect.h, 300));

    // Create new window and transfer panel
    const new_window = try window_manager.createChildWindow(
        width,
        height,
        mouse_x - 200,
        mouse_y - 150,
    );
    try window_manager.transferPanel(panel_id, docking_ctx.window_id, new_window.id);
}

/// Render preview of dragged panel
fn renderDraggedPanelPreview(docking_ctx: *DockingContext, ctx: *GuiContext) !void {
    // Get panel info
    if (docking_ctx.panel_registry.*.get(docking_ctx.drag_state.panel_id)) |panel_info| {
        const mouse_x = @as(f32, @floatCast(ctx.input.cursor_x));
        const mouse_y = @as(f32, @floatCast(ctx.input.cursor_y));

        // Draw ghost panel following cursor
        const ghost_width = 120.0;
        const ghost_height = 30.0;
        const ghost_rect = shapes.Rect{
            .x = mouse_x - ghost_width * 0.5,
            .y = mouse_y - ghost_height * 0.5,
            .w = ghost_width,
            .h = ghost_height,
        };

        // Semi-transparent background
        const ghost_color = blendColor(ctx.theme.bg_secondary, 180);
        try ctx.draw_list.addRoundedRect(ghost_rect, 4.0, ghost_color);

        // Text
        const text_metrics = try ctx.measureText(panel_info.title, 14.0);
        const text_x = mouse_x - text_metrics.width * 0.5;
        const text_y = mouse_y - text_metrics.height * 0.5;
        try ctx.addText(text_x, text_y, panel_info.title, 14.0, ctx.theme.text_primary);
    }
}

/// Handle drop - manipulate tree based on drop zone
fn handleDrop(docking_ctx: *DockingContext) !void {
    var target = docking_ctx.drag_state.target_node orelse return;
    const zone = docking_ctx.drag_state.drop_zone;
    const panel_id = docking_ctx.drag_state.panel_id;
    const source = docking_ctx.drag_state.source_node;

    // Don't drop if no valid zone
    if (zone == .none) return;

    // Don't drop onto the same tab group in center zone (no-op)
    if (zone == .center and source == target) return;

    // Special case: if source == target and it's an edge drop
    // Only allow if the source has multiple panels (can split off one panel)
    if (source == target and zone != .center) {
        if (source) |src| {
            if (src.tab_group) |group| {
                if (group.panel_ids.items.len <= 1) {
                    // Can't split a single panel with itself
                    return;
                }
                // Multiple panels - we can proceed with the split
            }
        }
    }

    // Remove panel from source
    var target_invalidated = false;
    if (source) |src| {
        const should_remove = src.removePanel(panel_id);
        if (should_remove) {
            // Only collapse if source is not the root
            // Root can be empty temporarily (though this shouldn't happen if we checked above)
            if (docking_ctx.dock_space.root != src) {
                // WARNING: Collapsing can invalidate the target pointer!
                // We need to re-find the target after collapsing
                try collapseEmptyNode(docking_ctx, src);
                target_invalidated = true;
            }
        }
    }

    // If target was potentially invalidated, re-find it
    if (target_invalidated) {
        // Re-find target at current mouse position
        const mouse_x = docking_ctx.drag_state.current_mouse_pos[0];
        const mouse_y = docking_ctx.drag_state.current_mouse_pos[1];
        target = docking_ctx.dock_space.findLeafAtPosition(mouse_x, mouse_y) orelse return;
    }

    // Add panel to target based on drop zone
    switch (zone) {
        .center => {
            // Add as new tab in existing group
            if (target.tab_group) |*group| {
                // Check if panel already exists in this group (shouldn't happen but be safe)
                for (group.panel_ids.items) |existing_id| {
                    if (existing_id == panel_id) return; // Already here, nothing to do
                }
                try group.panel_ids.append(docking_ctx.allocator, panel_id);
                group.active_index = group.panel_ids.items.len - 1; // Activate new tab
            }
        },
        .left, .right, .top, .bottom => {
            // Create new split
            try splitNode(docking_ctx, target, zone, panel_id);
        },
        .none => {},
    }
}

/// Convert a node to a split node with the dragged panel
fn splitNode(
    docking_ctx: *DockingContext,
    target: *DockNode,
    zone: DropZone,
    panel_id: u64,
) !void {
    // Safety: target must be a tab group
    if (target.node_type != .tab_group) {
        return error.CannotSplitSplitNode;
    }

    // Determine split direction
    const direction: SplitDirection = switch (zone) {
        .left, .right => .horizontal,
        .top, .bottom => .vertical,
        else => return, // Should not happen
    };

    // Determine child order (new panel goes first or second)
    const new_first = switch (zone) {
        .left, .top => true,
        .right, .bottom => false,
        else => return,
    };

    // Create new tab group for dragged panel
    const new_group = try DockNode.initTabGroup(docking_ctx.allocator, panel_id);
    errdefer new_group.deinit(); // Clean up if we fail after this point

    // Clone target node (becomes one child of split)
    const target_clone = try target.clone(docking_ctx.allocator);
    errdefer target_clone.deinit(); // Clean up if we fail after this point

    // Set up children
    const first_child = if (new_first) new_group else target_clone;
    const second_child = if (new_first) target_clone else new_group;

    // Convert target to split node (in-place modification)
    // First, clean up old target data
    if (target.tab_group) |*group| {
        group.panel_ids.deinit(docking_ctx.allocator);
    }

    // Set new split data
    target.node_type = .split;
    target.tab_group = null;
    target.split = .{
        .direction = direction,
        .ratio = 0.5, // Default 50/50 split
        .first = first_child,
        .second = second_child,
    };
}

/// Collapse an empty tab group node from the tree
fn collapseEmptyNode(docking_ctx: *DockingContext, empty_node: *DockNode) !void {
    // If this is the root, just leave it empty for now
    // TODO: Could set root to null if completely empty
    if (docking_ctx.dock_space.root == empty_node) {
        return;
    }

    // Find parent node
    if (docking_ctx.dock_space.root) |root| {
        if (findParentOfNode(root, empty_node)) |parent_info| {
            const parent = parent_info.parent;
            const sibling = parent_info.sibling;

            // Copy sibling's data into parent (effectively removing one level)
            if (parent.split) |old_split| {
                // Clone sibling BEFORE freeing anything
                const sibling_clone = try sibling.clone(docking_ctx.allocator);

                // Free old parent split children (includes empty_node and sibling)
                // Note: Don't free empty_node separately - it's already one of these!
                old_split.first.deinit();
                old_split.second.deinit();

                // Replace parent with sibling data
                parent.node_type = sibling_clone.node_type;
                parent.split = sibling_clone.split;
                parent.tab_group = sibling_clone.tab_group;

                // Don't deinit sibling_clone itself since we stole its data
                docking_ctx.allocator.destroy(sibling_clone);
            }
        }
    }
}

const ParentInfo = struct {
    parent: *DockNode,
    sibling: *DockNode,
};

/// Find the parent of a node and return it with the sibling
fn findParentOfNode(node: *DockNode, target: *DockNode) ?ParentInfo {
    if (node.split) |*split_info| {
        if (split_info.first == target) {
            return ParentInfo{
                .parent = node,
                .sibling = split_info.second,
            };
        }
        if (split_info.second == target) {
            return ParentInfo{
                .parent = node,
                .sibling = split_info.first,
            };
        }

        // Recursively search children
        if (findParentOfNode(split_info.first, target)) |info| {
            return info;
        }
        if (findParentOfNode(split_info.second, target)) |info| {
            return info;
        }
    }
    return null;
}

/// Blend a color with alpha transparency (RGBA u32 format)
fn blendColor(color: u32, alpha: u8) u32 {
    const rgb = color & 0xFFFFFF00;
    return rgb | alpha;
}
