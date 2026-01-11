const std = @import("std");
const build_options = @import("build_options");

const btn = @import("gui/widgets/button.zig");
const textInput = @import("gui/widgets/input.zig");
const imageWidget = @import("gui/widgets/image.zig");
const dropdown = @import("gui/widgets/dropdown.zig");
const collapsible = @import("gui/widgets/collapsible.zig");
const utils = @import("gui/widgets/utils.zig");
const layout = @import("gui/layout.zig");
const opengl = @import("gui/renderers/opengl.zig");
const GuiContext = @import("gui/context.zig").GuiContext;
const shapes = @import("gui/shapes.zig");
const input = @import("gui/input.zig");
const DebugStats = @import("gui/debug_stats.zig").DebugStats;
const window_mod = @import("gui/window.zig");
const Window = window_mod.Window;
const DockingContext = @import("gui/docking/docking_context.zig").DockingContext;
const PanelInfo = @import("gui/docking/panel_info.zig").PanelInfo;
const WindowManager = @import("gui/window_manager.zig").WindowManager;

pub fn main() !void {
    try Window.init();
    defer Window.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create window manager
    var window_manager = WindowManager.init(allocator);
    defer window_manager.deinit();

    // Register all panels with centralized registry
    try window_manager.registerPanel(PanelInfo{
        .id = utils.id("scene"),
        .title = "Scene",
        .render_fn = renderScenePanel,
        .closable = false,
        .min_width = 300,
        .min_height = 300,
    });

    try window_manager.registerPanel(PanelInfo{
        .id = utils.id("hierarchy"),
        .title = "Hierarchy",
        .render_fn = renderHierarchyPanel,
        .closable = true,
        .min_width = 200,
        .min_height = 200,
    });

    try window_manager.registerPanel(PanelInfo{
        .id = utils.id("inspector"),
        .title = "Inspector",
        .render_fn = renderInspectorPanel,
        .closable = true,
        .min_width = 250,
        .min_height = 200,
    });

    try window_manager.registerPanel(PanelInfo{
        .id = utils.id("console"),
        .title = "Console",
        .render_fn = renderConsolePanel,
        .closable = true,
        .min_width = 200,
        .min_height = 100,
    });

    // Create main window
    const main_ctx = try window_manager.createMainWindow(1920, 1080, "zGUI - Docking Demo");

    // Load checkmark image for checkbox widget
    const checkmark_img = try imageWidget.Image.load(allocator, main_ctx.renderer, "assets/checkmark.png");
    main_ctx.gui.checkmark_image = checkmark_img;

    var debug_stats = if (comptime build_options.debug) DebugStats.init() else {};
    defer {
        if (comptime build_options.debug) {
            debug_stats.deinit();
        }
    }
    var stats_buffer: [128]u8 = undefined;

    const file_options = [_][]const u8{ "New", "Open", "Save", "Save As", "Exit" };
    const menu_options = [_][]const u8{ "Preferences", "Settings", "About" };
    const top_panel_height: f32 = 50;

    // Try to load multi-window layout
    const layout_file = "zgui_layout.txt";
    const layout_loaded = try window_manager.loadLayout(layout_file);

    if (!layout_loaded) {
        // No saved layout - add all panels to main window
        try main_ctx.docking_ctx.addPanel(utils.id("scene"));
        try main_ctx.docking_ctx.addPanel(utils.id("hierarchy"));
        try main_ctx.docking_ctx.addPanel(utils.id("inspector"));
        try main_ctx.docking_ctx.addPanel(utils.id("console"));
    }

    // Main event loop - poll ALL windows
    while (!main_ctx.window.shouldClose()) {
        if (comptime build_options.debug) {
            debug_stats.beginFrame(window_mod.getTime());
        }

        Window.pollEvents(); // Global event poll

        // Render each window
        var iter = window_manager.windows.iterator();
        while (iter.next()) |entry| {
            const window_ctx = entry.value_ptr.*;

            // Check if window should close
            if (window_ctx.window.shouldClose() and !window_ctx.metadata.is_main) {
                window_ctx.is_closing = true;
                continue;
            }

            // Make context current for this window
            window_ctx.window.makeContextCurrent();

            // Update GUI
            window_ctx.gui.newFrame();
            window_ctx.gui.updateInput(window_ctx.window);

            if (window_ctx.gui.is_resizing) continue;

            // Update dock bounds (for main window, leave space for menu; for child windows, use full window)
            const panel_y = if (window_ctx.metadata.is_main) top_panel_height else 0;
            const panel_h = if (window_ctx.metadata.is_main) window_ctx.gui.window_height - top_panel_height else window_ctx.gui.window_height;

            window_ctx.docking_ctx.dock_space.bounds = shapes.Rect{
                .x = 0,
                .y = panel_y,
                .w = window_ctx.gui.window_width,
                .h = panel_h,
            };

            // Render top menu bar (main window only)
            if (window_ctx.metadata.is_main) {
                const menu_bar_rect = shapes.Rect{
                    .x = 0,
                    .y = 0,
                    .w = window_ctx.gui.window_width,
                    .h = top_panel_height,
                };
                try window_ctx.gui.draw_list.addRect(menu_bar_rect, window_ctx.gui.theme.bg_secondary);

                layout.beginLayout(&window_ctx.gui, layout.hLayout(&window_ctx.gui, .{
                    .margin = layout.Spacing.all(10),
                    .padding = layout.Spacing.all(12),
                    .height = top_panel_height,
                }));

                if (try dropdown.dropdown(&window_ctx.gui, 1, "File", &file_options, .{
                    .font_size = 16,
                    .padding = layout.Spacing.symmetric(6, 12),
                    .border_radius = 4.0,
                })) |index| {
                    std.debug.print("File option selected: {s}\n", .{file_options[index]});
                }

                if (try dropdown.dropdown(&window_ctx.gui, 2, "Menu", &menu_options, .{
                    .font_size = 16,
                    .padding = layout.Spacing.symmetric(6, 12),
                    .border_radius = 4.0,
                })) |index| {
                    std.debug.print("Menu option selected: {s}\n", .{menu_options[index]});
                }

                layout.endLayout(&window_ctx.gui);
            }

            // Render docking system
            try window_ctx.docking_ctx.render(&window_ctx.gui);

            // Debug stats (main window only)
            if (comptime build_options.debug) {
                if (window_ctx.metadata.is_main) {
                    const stats_text = try debug_stats.format(&stats_buffer);
                    const stats_metrics = try window_ctx.gui.measureText(stats_text, 20);
                    const stats_x = window_ctx.gui.window_width - stats_metrics.width - 10;
                    const stats_y = 10;
                    try window_ctx.gui.addText(stats_x, stats_y, stats_text, 20, 0xFFFFFFFF);
                }
            }

            // Render frame
            var fb_width: i32 = 0;
            var fb_height: i32 = 0;
            window_ctx.window.getFramebufferSize(&fb_width, &fb_height);
            window_ctx.gui.render(window_ctx.renderer, fb_width, fb_height);
            window_ctx.window.swapBuffers();
        }

        if (comptime build_options.debug) {
            debug_stats.endFrame();
        }

        // Handle cross-window operations
        try window_manager.updateAllWindows();

        // Close any child windows marked for closing
        try window_manager.closeMarkedWindows();
    }

    // Save multi-window layout
    try window_manager.saveLayout(layout_file);

    // Process any remaining events
    Window.pollEvents();
}

// Panel render callbacks

fn renderScenePanel(ctx: *GuiContext, bounds: shapes.Rect) !void {
    // Render centered image if available
    if (ctx.checkmark_image) |*img| {
        const img_x = bounds.x + (bounds.w - @as(f32, @floatFromInt(img.width))) * 0.5;
        const img_y = bounds.y + (bounds.h - @as(f32, @floatFromInt(img.height))) * 0.5;

        const img_rect = shapes.Rect{
            .x = img_x,
            .y = img_y,
            .w = @floatFromInt(img.width),
            .h = @floatFromInt(img.height),
        };
        try ctx.draw_list.setTexture(img.texture);
        try ctx.draw_list.addRectUV(img_rect, .{ 0, 0 }, .{ 1, 1 }, 0xFFFFFFFF);
    }

    // Label
    const label = "Scene Viewport";
    const label_x = bounds.x + 20;
    const label_y = bounds.y + 20;
    try ctx.addText(label_x, label_y, label, 20, ctx.theme.text_primary);
}

fn renderHierarchyPanel(ctx: *GuiContext, bounds: shapes.Rect) !void {
    var y = bounds.y + 16; // Start with padding
    const x = bounds.x + 16;

    try ctx.addText(x, y, "Scene Objects:", 18, ctx.theme.text_primary);
    y += 24; // Line height

    // Placeholder hierarchy
    const items = [_][]const u8{
        "  - Camera",
        "  - Directional Light",
        "  - Player",
        "  - Ground Plane",
        "  - Obstacles",
    };

    for (items) |item| {
        try ctx.addText(x, y, item, 16, ctx.theme.text_secondary);
        y += 20; // Line height
    }
}

fn renderInspectorPanel(ctx: *GuiContext, bounds: shapes.Rect) !void {
    var y = bounds.y + 16; // Start with padding
    const x = bounds.x + 16;

    try ctx.addText(x, y, "Inspector Panel", 18, ctx.theme.text_primary);
    y += 26; // Line height

    try ctx.addText(x, y, "Object Properties:", 16, ctx.theme.text_primary);
    y += 22; // Line height

    try ctx.addText(x, y, "  Position: (0, 0, 0)", 14, ctx.theme.text_secondary);
    y += 18;

    try ctx.addText(x, y, "  Rotation: (0, 0, 0)", 14, ctx.theme.text_secondary);
    y += 18;

    try ctx.addText(x, y, "  Scale: (1, 1, 1)", 14, ctx.theme.text_secondary);
}

fn renderConsolePanel(ctx: *GuiContext, bounds: shapes.Rect) !void {
    var y = bounds.y + 16; // Start with padding
    const x = bounds.x + 16;

    try ctx.addText(x, y, "Console Output", 18, ctx.theme.text_primary);
    y += 24; // Line height

    try ctx.addText(x, y, "> Application started", 14, 0x00FF00FF); // Green
    y += 18;

    try ctx.addText(x, y, "> Docking system initialized", 14, 0x00FF00FF);
    y += 18;

    try ctx.addText(x, y, "> Ready", 14, 0x00FF00FF);
}
