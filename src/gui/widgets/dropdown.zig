const GuiContext = @import("../context.zig").GuiContext;
const shapes = @import("../shapes.zig");
const layout_mod = @import("../layout.zig");
const std = @import("std");
const color_utils = @import("../color.zig");
const theme_mod = @import("../theme.zig");

pub const Options = struct {
    font_size: f32 = 16,
    color: ?shapes.Color = null,
    font_color: ?shapes.Color = null,
    border_radius: f32 = 4.0,
    padding: layout_mod.Spacing = layout_mod.Spacing.all(6.0),
    item_height: f32 = 32.0,
    dropdown_bg_color: ?shapes.Color = null,
    dropdown_hover_color: ?shapes.Color = null,
};

pub const DropdownOverlay = struct {
    id: u64,
    button_rect: shapes.Rect,
    options: []const []const u8,
    opts: Options,
};

/// Dropdown widget - displays a button that opens an overlay menu with selectable options
/// Returns the selected index if the selection changed this frame, null otherwise
pub fn dropdown(
    ctx: *GuiContext,
    id: u64,
    label: []const u8,
    options: []const []const u8,
    opts: Options,
) !?usize {
    const layout = ctx.getCurrentLayout();

    // Measure button dimensions
    const metrics = try ctx.measureText(label, opts.font_size);
    const button_width = metrics.width + opts.padding.left + opts.padding.right;
    const button_height = metrics.height + opts.padding.top + opts.padding.bottom;
    const button_rect = layout.allocateSpace(ctx, button_width, button_height);

    const is_open = ctx.active_dropdown_id != null and ctx.active_dropdown_id.? == id;
    const button_hovered = ctx.input.isMouseInRect(button_rect);
    const button_clicked = button_hovered and ctx.input.mouse_left_clicked;

    if (button_hovered) {
        ctx.setCursor(ctx.hand_cursor);
    }

    // Toggle dropdown on button click
    if (button_clicked) {
        if (is_open) {
            ctx.active_dropdown_id = null;
            ctx.active_dropdown_overlay = null;
        } else {
            ctx.active_dropdown_id = id;
            // Store overlay info for later rendering
            ctx.active_dropdown_overlay = DropdownOverlay{
                .id = id,
                .button_rect = button_rect,
                .options = options,
                .opts = opts,
            };
        }
    }

    // Get base colors from theme with option overrides
    const base_color = theme_mod.getColor(
        ctx.theme,
        opts.color,
        "accent_primary",
        0x4fc3f7FF,
    );

    const font_color = theme_mod.getColor(
        ctx.theme,
        opts.font_color,
        "text_bright",
        0xffffffFF,
    );

    // Render button
    var button_color = base_color;
    if (button_hovered and ctx.input.mouse_left_pressed) {
        button_color = if (opts.color == null)
            ctx.theme.accent_pressed
        else
            color_utils.darken(base_color, 0.8);
    } else if (button_hovered or is_open) {
        button_color = if (opts.color == null)
            ctx.theme.accent_hover
        else
            color_utils.darken(base_color, 0.9);
    }

    try ctx.draw_list.addRoundedRect(button_rect, opts.border_radius, button_color);

    const tx = button_rect.x + (button_rect.w - metrics.width) * 0.5;
    const ty = button_rect.y + (button_rect.h - metrics.height) * 0.5;
    try ctx.addText(tx, ty, label, opts.font_size, font_color);

    // Return the selected index if selection changed this frame
    if (ctx.dropdown_selection_changed and ctx.dropdown_selection_id == id) {
        const selected = ctx.dropdown_selected_index;
        ctx.dropdown_selection_changed = false; // Reset after returning
        return selected;
    }
    return null;
}

/// Renders all dropdown overlays - called internally by GuiContext
pub fn renderDropdownOverlays(ctx: *GuiContext) !void {
    if (ctx.active_dropdown_overlay) |overlay| {
        const button_rect = overlay.button_rect;
        const options = overlay.options;
        const opts = overlay.opts;
        const dropdown_id = overlay.id;

        // Calculate dropdown dimensions
        const dropdown_width = @max(200.0, button_rect.w);
        const dropdown_height = @as(f32, @floatFromInt(options.len)) * opts.item_height;

        // Position dropdown below button
        const dropdown_rect = shapes.Rect{
            .x = button_rect.x,
            .y = button_rect.y + button_rect.h + 2.0,
            .w = dropdown_width,
            .h = dropdown_height,
        };

        // Get dropdown colors from theme with option overrides
        const dropdown_bg_color = theme_mod.getColor(
            ctx.theme,
            opts.dropdown_bg_color,
            "bg_elevated",
            0x2d2d30FF,
        );

        const dropdown_hover_color = theme_mod.getColor(
            ctx.theme,
            opts.dropdown_hover_color,
            "bg_hover",
            0x2a2d2eFF,
        );

        const font_color = theme_mod.getColor(
            ctx.theme,
            opts.font_color,
            "text_bright",
            0xffffffFF,
        );

        // Render dropdown background
        try ctx.draw_list.addRoundedRect(dropdown_rect, opts.border_radius, dropdown_bg_color);

        var clicked_index: ?usize = null;

        // Render each option
        for (options, 0..) |option, i| {
            const item_y = dropdown_rect.y + @as(f32, @floatFromInt(i)) * opts.item_height;
            const item_rect = shapes.Rect{
                .x = dropdown_rect.x,
                .y = item_y,
                .w = dropdown_rect.w,
                .h = opts.item_height,
            };

            const item_hovered = ctx.input.isMouseInRect(item_rect);
            const item_clicked = item_hovered and ctx.input.mouse_left_clicked;

            // Highlight hovered item
            if (item_hovered) {
                ctx.setCursor(ctx.hand_cursor);
                try ctx.draw_list.addRect(item_rect, dropdown_hover_color);
            }

            // Render option text
            const item_metrics = try ctx.measureText(option, opts.font_size);
            const item_tx = item_rect.x + opts.padding.left;
            const item_ty = item_rect.y + (item_rect.h - item_metrics.height) * 0.5;
            try ctx.addText(item_tx, item_ty, option, opts.font_size, font_color);

            // Handle option click
            if (item_clicked) {
                clicked_index = i;
            }
        }

        // Close dropdown if clicked outside
        const mouse_in_button = ctx.input.isMouseInRect(button_rect);
        const mouse_in_dropdown = ctx.input.isMouseInRect(dropdown_rect);
        if (ctx.input.mouse_left_clicked and !mouse_in_button and !mouse_in_dropdown) {
            ctx.active_dropdown_id = null;
            ctx.active_dropdown_overlay = null;
        }

        // If an item was selected, store it in the context and close the dropdown
        if (clicked_index) |index| {
            ctx.dropdown_selected_index = index;
            ctx.dropdown_selection_changed = true;
            ctx.dropdown_selection_id = dropdown_id;
            ctx.active_dropdown_id = null;
            ctx.active_dropdown_overlay = null;
        }
    }
}
