const ResizeBorder = @import("../context.zig").ResizeBorder;
const GuiContext = @import("../context.zig").GuiContext;
const PanelSize = @import("../context.zig").PanelSize;
const id = @import("utils.zig").id;
const shapes = @import("../shapes.zig");
const window = @import("../window.zig");
const Cursor = window.Cursor;
const theme_mod = @import("../theme.zig");

const border_width: f32 = 10.0;

pub const Options = struct {
    color: ?shapes.Color = null,
    border_radius: f32 = 0.0,
    resizable: bool = false,
};

pub const PanelResult = struct {
    width: f32,
    height: f32,
};

fn getStoredSize(ctx: *GuiContext, panel_id: u64) PanelSize {
    return ctx.panel_sizes.get(panel_id) orelse PanelSize{
        .width = null,
        .height = null,
        .min_width = 100.0,
        .min_height = 100.0,
    };
}

fn checkBorderHover(
    mouse_x: f32,
    mouse_y: f32,
    rect: shapes.Rect,
    border: ResizeBorder,
) bool {
    return switch (border) {
        .right => mouse_x >= rect.x + rect.w - border_width and
            mouse_x <= rect.x + rect.w and
            mouse_y >= rect.y and mouse_y <= rect.y + rect.h,
        .left => mouse_x >= rect.x and
            mouse_x <= rect.x + border_width and
            mouse_y >= rect.y and mouse_y <= rect.y + rect.h,
        .bottom => mouse_y >= rect.y + rect.h - border_width and
            mouse_y <= rect.y + rect.h and
            mouse_x >= rect.x and mouse_x <= rect.x + rect.w,
        .top => mouse_y >= rect.y and
            mouse_y <= rect.y + border_width and
            mouse_x >= rect.x and mouse_x <= rect.x + rect.w,
    };
}

fn getHighlightRect(rect: shapes.Rect, border: ResizeBorder) shapes.Rect {
    return switch (border) {
        .right => .{ .x = rect.x + rect.w - 2.0, .y = rect.y, .w = 2.0, .h = rect.h },
        .left => .{ .x = rect.x, .y = rect.y, .w = 2.0, .h = rect.h },
        .bottom => .{ .x = rect.x, .y = rect.y + rect.h - 2.0, .w = rect.w, .h = 2.0 },
        .top => .{ .x = rect.x, .y = rect.y, .w = rect.w, .h = 2.0 },
    };
}

fn getCursor(ctx: *GuiContext, border: ResizeBorder) ?*Cursor {
    return switch (border) {
        .left, .right => ctx.hresize_cursor,
        .top, .bottom => ctx.vresize_cursor,
    };
}

fn handleResize(
    ctx: *GuiContext,
    panel_id: u64,
    rect: shapes.Rect,
    border: ResizeBorder,
    mouse_x: f32,
    mouse_y: f32,
    current_layout: anytype,
) !void {
    const stored_size = getStoredSize(ctx, panel_id);

    if (!ctx.resize_state.dragging) {
        // Start dragging
        ctx.resize_state.dragging = true;
        ctx.resize_state.panel_id = panel_id;
        ctx.resize_state.border = border;
        ctx.resize_state.initial_mouse_pos = switch (border) {
            .left, .right => mouse_x,
            .top, .bottom => mouse_y,
        };
        ctx.resize_state.panel_rect = rect;
        return;
    }

    // Continue dragging
    if (ctx.resize_state.panel_id != panel_id or !ctx.input.mouse_left_pressed) {
        ctx.resize_state.dragging = false;
        return;
    }

    const current_pos = switch (border) {
        .left, .right => mouse_x,
        .top, .bottom => mouse_y,
    };
    const delta = current_pos - ctx.resize_state.initial_mouse_pos;

    switch (border) {
        .right => {
            const new_width = ctx.resize_state.panel_rect.w + delta;
            if (new_width >= stored_size.min_width) {
                current_layout.width = new_width;
                try ctx.panel_sizes.put(panel_id, .{
                    .width = new_width,
                    .height = current_layout.height,
                    .min_width = stored_size.min_width,
                    .min_height = stored_size.min_height,
                });
            }
        },
        .left => {
            const new_width = ctx.resize_state.panel_rect.w - delta;
            if (new_width >= stored_size.min_width) {
                current_layout.width = new_width;
                try ctx.panel_sizes.put(panel_id, .{
                    .width = new_width,
                    .height = current_layout.height,
                    .min_width = stored_size.min_width,
                    .min_height = stored_size.min_height,
                });
            }
        },
        .bottom => {
            const new_height = ctx.resize_state.panel_rect.h + delta;
            if (new_height >= stored_size.min_height) {
                current_layout.height = new_height;
                try ctx.panel_sizes.put(panel_id, .{
                    .width = current_layout.width,
                    .height = new_height,
                    .min_width = stored_size.min_width,
                    .min_height = stored_size.min_height,
                });
            }
        },
        .top => {
            const new_height = ctx.resize_state.panel_rect.h - delta;
            if (new_height >= stored_size.min_height) {
                current_layout.height = new_height;
                try ctx.panel_sizes.put(panel_id, .{
                    .width = current_layout.width,
                    .height = new_height,
                    .min_width = stored_size.min_width,
                    .min_height = stored_size.min_height,
                });
            }
        },
    }
}

fn renderPanel(
    ctx: *GuiContext,
    panel_id: u64,
    opts: Options,
    allowed_border: ?ResizeBorder,
) !PanelResult {
    const current_layout = ctx.getCurrentLayout();

    // Apply stored size (but not position offsets - sticky panels don't move)
    if (ctx.panel_sizes.get(panel_id)) |stored_size| {
        if (stored_size.width) |w| {
            current_layout.width = w;
        }
        if (stored_size.height) |h| {
            current_layout.height = h;
        }
    }

    const full_height = current_layout.height orelse ctx.window_height;
    const full_width = current_layout.width orelse ctx.window_width;
    const final_rect = shapes.Rect{
        .x = current_layout.x,
        .y = current_layout.y,
        .w = full_width,
        .h = full_height,
    };

    // Get colors from theme with option overrides
    const panel_color = theme_mod.getColor(ctx.theme, opts.color, "bg_secondary", 0x252526FF);

    // Render background
    if (opts.border_radius > 0.0) {
        try ctx.draw_list.addRoundedRect(final_rect, opts.border_radius, panel_color);
    } else {
        try ctx.draw_list.addRect(final_rect, panel_color);
    }

    // Handle resizing
    if (opts.resizable and allowed_border != null) {
        const mouse_x: f32 = @floatCast(ctx.input.cursor_x);
        const mouse_y: f32 = @floatCast(ctx.input.cursor_y);
        const border = allowed_border.?;

        const is_hovering = checkBorderHover(mouse_x, mouse_y, final_rect, border);
        const is_active = ctx.resize_state.dragging and ctx.resize_state.panel_id == panel_id;

        if (is_hovering and ctx.input.mouse_left_clicked and !ctx.click_consumed) {
            try handleResize(ctx, panel_id, final_rect, border, mouse_x, mouse_y, current_layout);
        }

        if (is_active) {
            try handleResize(ctx, panel_id, final_rect, border, mouse_x, mouse_y, current_layout);
        }

        if ((is_hovering or is_active) and (!ctx.resize_state.dragging or is_active)) {
            ctx.setCursor(getCursor(ctx, border));
            const highlight_rect = getHighlightRect(final_rect, border);
            try ctx.draw_list.addRect(highlight_rect, ctx.theme.resize_border);
        }
    }

    return PanelResult{
        .width = full_width,
        .height = full_height,
    };
}

pub fn leftPanel(ctx: *GuiContext, label: []const u8, opts: Options) !PanelResult {
    const panel_id = id(label);

    if (opts.resizable) {
        ctx.current_panel_id = panel_id;
    }

    return renderPanel(ctx, panel_id, opts, if (opts.resizable) .right else null);
}

pub fn rightPanel(ctx: *GuiContext, label: []const u8, opts: Options) !PanelResult {
    const panel_id = id(label);

    if (opts.resizable) {
        ctx.current_panel_id = panel_id;
    }

    return renderPanel(ctx, panel_id, opts, if (opts.resizable) .left else null);
}

pub fn topPanel(ctx: *GuiContext, label: []const u8, opts: Options) !PanelResult {
    const panel_id = id(label);

    if (opts.resizable) {
        ctx.current_panel_id = panel_id;
    }

    return renderPanel(ctx, panel_id, opts, if (opts.resizable) .bottom else null);
}

pub fn bottomPanel(ctx: *GuiContext, label: []const u8, opts: Options) !PanelResult {
    const panel_id = id(label);

    if (opts.resizable) {
        ctx.current_panel_id = panel_id;
    }

    return renderPanel(ctx, panel_id, opts, if (opts.resizable) .top else null);
}

pub fn centerPanel(ctx: *GuiContext, label: []const u8, opts: Options) !PanelResult {
    const panel_id = id(label);

    return renderPanel(ctx, panel_id, opts, null);
}
