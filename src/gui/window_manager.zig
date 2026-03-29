const std = @import("std");
const GuiContext = @import("context.zig").GuiContext;
const Window = @import("window.zig").Window;
const c = @import("c.zig");
const glfw = c.glfw;
const opengl = @import("renderers/opengl.zig");
const Renderer = @import("renderer.zig").Renderer;
const DockingContext = @import("docking/docking_context.zig").DockingContext;
const PanelInfo = @import("docking/panel_info.zig").PanelInfo;
const DockNode = @import("docking/dock_node.zig").DockNode;
const shapes = @import("shapes.zig");
const input = @import("input.zig");
const persistence = @import("docking/layout_persistence.zig");

pub const WindowId = u64;

pub const WindowMetadata = struct {
    id: WindowId,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    is_main: bool,
};

pub const WindowContext = struct {
    id: WindowId,
    window: Window,
    gui: GuiContext,
    renderer: *Renderer,
    docking_ctx: DockingContext,
    metadata: WindowMetadata,
    is_closing: bool,

    pub fn deinit(self: *WindowContext, allocator: std.mem.Allocator) void {
        self.docking_ctx.deinit();
        self.gui.deinit();
        self.renderer.deinit();
        allocator.destroy(self.renderer);
        self.window.destroy();
    }
};

pub const WindowManager = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    main_window_id: WindowId,
    windows: std.AutoHashMap(WindowId, *WindowContext),
    panel_registry: std.AutoHashMap(u64, PanelInfo),
    next_window_id: WindowId,

    // Cross-window drag tracking
    active_drag_window: ?WindowId,
    drag_panel_id: ?u64,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) WindowManager {
        return .{
            .allocator = allocator,
            .io = io,
            .main_window_id = 0,
            .windows = std.AutoHashMap(WindowId, *WindowContext).init(allocator),
            .panel_registry = std.AutoHashMap(u64, PanelInfo).init(allocator),
            .next_window_id = 1,
            .active_drag_window = null,
            .drag_panel_id = null,
        };
    }

    pub fn deinit(self: *WindowManager) void {
        // Clean up all windows
        var iter = self.windows.iterator();
        while (iter.next()) |entry| {
            const ctx = entry.value_ptr.*;
            ctx.deinit(self.allocator);
            self.allocator.destroy(ctx);
        }
        self.windows.deinit();
        self.panel_registry.deinit();
    }

    /// Register a panel with the centralized registry
    pub fn registerPanel(self: *WindowManager, panel: PanelInfo) !void {
        try self.panel_registry.put(panel.id, panel);
    }

    /// Get panel info from registry
    pub fn getPanel(self: *WindowManager, panel_id: u64) ?PanelInfo {
        return self.panel_registry.get(panel_id);
    }

    /// Create the main window
    pub fn createMainWindow(self: *WindowManager, width: i32, height: i32, title: [*c]const u8) !*WindowContext {
        const window = try Window.create(width, height, title);
        window.makeContextCurrent();
        Window.setSwapInterval(0); // VSync

        // Create renderer
        const renderer = try self.allocator.create(Renderer);
        renderer.* = try opengl.createRenderer(self.allocator, Window);

        // Create GUI context
        var gui = try GuiContext.init(self.allocator, renderer, window, self.io);

        // Set initial window size (in logical coordinates)
        var fb_width: i32 = 0;
        var fb_height: i32 = 0;
        window.getFramebufferSize(&fb_width, &fb_height);
        const logical_width = @as(f32, @floatFromInt(fb_width)) / gui.content_scale_x;
        const logical_height = @as(f32, @floatFromInt(fb_height)) / gui.content_scale_y;
        gui.setWindowSize(logical_width, logical_height);

        // Create docking context
        const dock_bounds = shapes.Rect{
            .x = 0,
            .y = 0,
            .w = @floatFromInt(width),
            .h = @floatFromInt(height),
        };
        var docking_ctx = try DockingContext.init(self.allocator, dock_bounds);
        docking_ctx.window_id = 0; // Main window always has ID 0
        docking_ctx.window_manager = self;

        // Share panel registry reference (don't own it)
        docking_ctx.panel_registry.deinit();
        self.allocator.destroy(docking_ctx.panel_registry);
        docking_ctx.panel_registry = &self.panel_registry;
        docking_ctx.owns_panel_registry = false;

        // Create window context
        const window_id: WindowId = 0;
        self.main_window_id = window_id;

        const ctx = try self.allocator.create(WindowContext);
        ctx.* = WindowContext{
            .id = window_id,
            .window = window,
            .gui = gui,
            .renderer = renderer,
            .docking_ctx = docking_ctx,
            .metadata = WindowMetadata{
                .id = window_id,
                .x = 0,
                .y = 0,
                .width = width,
                .height = height,
                .is_main = true,
            },
            .is_closing = false,
        };

        try self.windows.put(window_id, ctx);

        // Set up input callbacks (AFTER WindowContext is created)
        window.setUserPointer(&ctx.gui);
        window.setMouseButtonCallback(input.mouseButtonCallback);
        window.setCharCallback(input.charCallback);
        window.setKeyCallback(input.keyCallback);
        window.setScrollCallback(input.scrollCallback);
        window.setFramebufferSizeCallback(input.framebufferSizeCallback);
        window.setContentScaleCallback(input.contentScaleCallback);

        return ctx;
    }

    /// Create a child window at the specified position
    pub fn createChildWindow(self: *WindowManager, width: i32, height: i32, x: i32, y: i32) !*WindowContext {
        const window_id = self.next_window_id;
        self.next_window_id += 1;

        // Create GLFW window
        const window = try Window.create(width, height, "Panel Window");

        // Position the window
        glfw.glfwSetWindowPos(window.handle, x, y);
        window.makeContextCurrent();

        // Create renderer (each window needs its own OpenGL context)
        const renderer = try self.allocator.create(Renderer);
        renderer.* = try opengl.createRenderer(self.allocator, Window);

        // Create GuiContext
        var gui = try GuiContext.init(self.allocator, renderer, window, self.io);

        // Set initial window size (in logical coordinates)
        var fb_width: i32 = 0;
        var fb_height: i32 = 0;
        window.getFramebufferSize(&fb_width, &fb_height);
        const logical_width = @as(f32, @floatFromInt(fb_width)) / gui.content_scale_x;
        const logical_height = @as(f32, @floatFromInt(fb_height)) / gui.content_scale_y;
        gui.setWindowSize(logical_width, logical_height);

        // Create docking context for this window
        const dock_bounds = shapes.Rect{
            .x = 0,
            .y = 0,
            .w = @floatFromInt(width),
            .h = @floatFromInt(height),
        };
        var docking_ctx = try DockingContext.init(self.allocator, dock_bounds);
        docking_ctx.window_id = window_id;
        docking_ctx.window_manager = self;

        // Share panel registry reference (don't own it)
        docking_ctx.panel_registry.deinit();
        self.allocator.destroy(docking_ctx.panel_registry);
        docking_ctx.panel_registry = &self.panel_registry;
        docking_ctx.owns_panel_registry = false;

        // Create WindowContext
        const ctx = try self.allocator.create(WindowContext);
        ctx.* = WindowContext{
            .id = window_id,
            .window = window,
            .gui = gui,
            .renderer = renderer,
            .docking_ctx = docking_ctx,
            .metadata = WindowMetadata{
                .id = window_id,
                .x = x,
                .y = y,
                .width = width,
                .height = height,
                .is_main = false,
            },
            .is_closing = false,
        };

        try self.windows.put(window_id, ctx);

        // Set up input callbacks (AFTER WindowContext is created)
        window.setUserPointer(&ctx.gui);
        window.setMouseButtonCallback(input.mouseButtonCallback);
        window.setCharCallback(input.charCallback);
        window.setKeyCallback(input.keyCallback);
        window.setScrollCallback(input.scrollCallback);
        window.setFramebufferSizeCallback(input.framebufferSizeCallback);
        window.setContentScaleCallback(input.contentScaleCallback);

        return ctx;
    }

    /// Transfer a panel from one window to another
    pub fn transferPanel(self: *WindowManager, panel_id: u64, from_window: WindowId, to_window: WindowId) !void {
        const from_ctx = self.windows.get(from_window) orelse return error.WindowNotFound;
        const to_ctx = self.windows.get(to_window) orelse return error.WindowNotFound;

        // Remove panel from source window
        try from_ctx.docking_ctx.removePanel(panel_id);

        // Add panel to target window
        try to_ctx.docking_ctx.addPanel(panel_id);

        // Check if source window is now empty and is not main window
        if (!from_ctx.metadata.is_main and from_ctx.docking_ctx.dock_space.root == null) {
            from_ctx.is_closing = true;
        }
    }

    /// Return all panels from a window to the main window
    pub fn returnPanelsToMain(self: *WindowManager, from_window: WindowId) !void {
        const from_ctx = self.windows.get(from_window) orelse return;
        const main_ctx = self.windows.get(self.main_window_id) orelse return;

        // Collect all panel IDs from source window
        var panel_ids = try std.ArrayList(u64).initCapacity(self.allocator, 8);
        defer panel_ids.deinit(self.allocator);

        if (from_ctx.docking_ctx.dock_space.root) |root| {
            try collectAllPanelIds(root, &panel_ids, self.allocator);
        }

        // Transfer each panel to main window
        for (panel_ids.items) |panel_id| {
            // Remove from source
            try from_ctx.docking_ctx.removePanel(panel_id);
            // Add to main
            try main_ctx.docking_ctx.addPanel(panel_id);
        }
    }

    /// Close a window and return its panels to main
    pub fn closeWindow(self: *WindowManager, window_id: WindowId) !void {
        // Don't allow closing main window this way
        if (window_id == self.main_window_id) return error.CannotCloseMainWindow;

        const window_ctx = self.windows.get(window_id) orelse return error.WindowNotFound;
        const main_ctx = self.windows.get(self.main_window_id) orelse return error.MainWindowNotFound;

        // Transfer all panels back to main window BEFORE destroying context
        try self.returnPanelsToMain(window_id);

        // Make the window's OpenGL context current before cleanup
        // This is critical to avoid GL_INVALID_OPERATION errors
        window_ctx.window.makeContextCurrent();

        // Clean up GUI and renderer resources (but not the window yet)
        window_ctx.docking_ctx.deinit();
        window_ctx.gui.deinit();
        window_ctx.renderer.deinit();
        self.allocator.destroy(window_ctx.renderer);

        // Clear OpenGL context before destroying window
        // This prevents Wayland/GLFW state corruption
        glfw.glfwMakeContextCurrent(null);

        // Now destroy the GLFW window
        window_ctx.window.destroy();

        // Restore main window's OpenGL context after cleanup
        // This ensures the main window can continue rendering properly
        main_ctx.window.makeContextCurrent();

        // Remove from registry and free memory
        _ = self.windows.remove(window_id);
        self.allocator.destroy(window_ctx);
    }

    /// Update all windows and handle cross-window drag operations
    pub fn updateAllWindows(self: *WindowManager) !void {
        var iter = self.windows.iterator();
        while (iter.next()) |entry| {
            const window_ctx = entry.value_ptr.*;

            // Check if this window has an active drag
            if (window_ctx.docking_ctx.drag_state.dragging) {
                self.active_drag_window = window_ctx.id;
                self.drag_panel_id = window_ctx.docking_ctx.drag_state.panel_id;

                // Check if cursor is over another window
                try self.checkCrossWindowDrop(window_ctx);
            }
        }
    }

    /// Check if a drag operation should transfer to another window
    fn checkCrossWindowDrop(self: *WindowManager, source_ctx: *WindowContext) !void {
        // Get cursor position in source window
        var cursor_x: f64 = 0;
        var cursor_y: f64 = 0;
        source_ctx.window.getCursorPos(&cursor_x, &cursor_y);

        // Get source window position
        var src_win_x: i32 = 0;
        var src_win_y: i32 = 0;
        glfw.glfwGetWindowPos(source_ctx.window.handle, &src_win_x, &src_win_y);

        // Calculate global screen coordinates
        const global_x = @as(f64, @floatFromInt(src_win_x)) + cursor_x;
        const global_y = @as(f64, @floatFromInt(src_win_y)) + cursor_y;

        // Check each other window
        var iter = self.windows.iterator();
        while (iter.next()) |entry| {
            const target_ctx = entry.value_ptr.*;
            if (target_ctx.id == source_ctx.id) continue;

            // Get target window position and size
            var target_x: i32 = 0;
            var target_y: i32 = 0;
            var target_w: i32 = 0;
            var target_h: i32 = 0;
            glfw.glfwGetWindowPos(target_ctx.window.handle, &target_x, &target_y);
            target_ctx.window.getSize(&target_w, &target_h);

            // Check if cursor is within target window bounds
            const in_bounds = global_x >= @as(f64, @floatFromInt(target_x)) and
                global_x <= @as(f64, @floatFromInt(target_x + target_w)) and
                global_y >= @as(f64, @floatFromInt(target_y)) and
                global_y <= @as(f64, @floatFromInt(target_y + target_h));

            if (in_bounds) {
                // Cursor is over target window - prepare for transfer on mouse release
                if (!source_ctx.gui.input.mouse_left_pressed) {
                    const panel_id = self.drag_panel_id orelse return;
                    try self.transferPanel(panel_id, source_ctx.id, target_ctx.id);
                    source_ctx.docking_ctx.drag_state.reset();
                    self.active_drag_window = null;
                    self.drag_panel_id = null;
                }
                return;
            }
        }
    }

    /// Close all windows marked for closing
    pub fn closeMarkedWindows(self: *WindowManager) !void {
        // Collect windows to close
        var to_close = try std.ArrayList(WindowId).initCapacity(self.allocator, 4);
        defer to_close.deinit(self.allocator);

        var iter = self.windows.iterator();
        while (iter.next()) |entry| {
            const window_ctx = entry.value_ptr.*;
            if (window_ctx.is_closing and !window_ctx.metadata.is_main) {
                try to_close.append(self.allocator, window_ctx.id);
            }
        }

        // Close each window
        for (to_close.items) |window_id| {
            try self.closeWindow(window_id);
        }
    }

    /// Save multi-window layout to file
    pub fn saveLayout(self: *WindowManager, file_path: []const u8) !void {
        try persistence.saveMultiWindowLayout(self.allocator, self, file_path, self.io);
    }

    /// Load multi-window layout from file
    pub fn loadLayout(self: *WindowManager, file_path: []const u8) !bool {
        const layout = try persistence.loadMultiWindowLayout(self.allocator, file_path, self.io);
        if (layout) |multi_layout| {
            defer {
                for (multi_layout.windows) |*window_data| {
                    if (window_data.dock_tree) |tree| {
                        tree.deinit();
                    }
                }
                self.allocator.free(multi_layout.windows);
            }

            // Restore each window's layout
            for (multi_layout.windows) |window_data| {
                var window_ctx = self.windows.get(window_data.window_id) orelse blk: {
                    // If this is not the main window, create it
                    if (!window_data.is_main) {
                        const new_ctx = try self.createChildWindow(
                            window_data.width,
                            window_data.height,
                            window_data.x,
                            window_data.y,
                        );
                        // Set the correct window ID
                        _ = self.windows.remove(new_ctx.id);
                        new_ctx.id = window_data.window_id;
                        new_ctx.docking_ctx.window_id = window_data.window_id;
                        new_ctx.metadata.id = window_data.window_id;
                        try self.windows.put(window_data.window_id, new_ctx);

                        // Update next_window_id if needed
                        if (window_data.window_id >= self.next_window_id) {
                            self.next_window_id = window_data.window_id + 1;
                        }

                        // Return the newly created context for tree restoration
                        break :blk new_ctx;
                    } else {
                        // Main window should exist, skip this window if not found
                        continue;
                    }
                };

                // Restore dock tree for this window
                if (window_data.dock_tree) |tree| {
                    // Clone the tree for this window
                    const cloned_tree = try cloneDockTree(self.allocator, tree);

                    // Free existing tree if any
                    if (window_ctx.docking_ctx.dock_space.root) |old_root| {
                        old_root.deinit();
                    }

                    window_ctx.docking_ctx.dock_space.root = cloned_tree;
                }
            }

            return true;
        }
        return false;
    }
};

/// Helper to collect all panel IDs from a dock tree
fn collectAllPanelIds(node: *DockNode, list: *std.ArrayList(u64), allocator: std.mem.Allocator) !void {
    switch (node.node_type) {
        .tab_group => {
            if (node.tab_group) |group| {
                for (group.panel_ids.items) |panel_id| {
                    try list.append(allocator, panel_id);
                }
            }
        },
        .split => {
            if (node.split) |split_info| {
                try collectAllPanelIds(split_info.first, list, allocator);
                try collectAllPanelIds(split_info.second, list, allocator);
            }
        },
    }
}

/// Helper to clone a dock tree
fn cloneDockTree(allocator: std.mem.Allocator, node: *DockNode) !*DockNode {
    const cloned = try allocator.create(DockNode);
    cloned.* = DockNode{
        .allocator = allocator,
        .node_type = node.node_type,
        .split = null,
        .tab_group = null,
        .cached_rect = node.cached_rect,
    };

    switch (node.node_type) {
        .tab_group => {
            if (node.tab_group) |group| {
                var panel_ids = try std.ArrayList(u64).initCapacity(allocator, group.panel_ids.items.len);
                for (group.panel_ids.items) |panel_id| {
                    try panel_ids.append(allocator, panel_id);
                }
                cloned.tab_group = .{
                    .panel_ids = panel_ids,
                    .active_index = group.active_index,
                };
            }
        },
        .split => {
            if (node.split) |split_info| {
                const first_clone = try cloneDockTree(allocator, split_info.first);
                const second_clone = try cloneDockTree(allocator, split_info.second);
                cloned.split = .{
                    .direction = split_info.direction,
                    .ratio = split_info.ratio,
                    .first = first_clone,
                    .second = second_clone,
                };
            }
        },
    }

    return cloned;
}
