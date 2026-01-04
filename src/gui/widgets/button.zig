const GuiContext = @import("../context.zig").GuiContext;
const shapes = @import("../shapes.zig");
const color_utils = @import("../color.zig");
const theme_mod = @import("../theme.zig");
const layout_mod = @import("../layout.zig");

pub const Variant = enum {
    FILLED,
    OUTLINED,
};

pub const Options = struct {
    font_size: f32 = 24,
    color: ?shapes.Color = null,
    font_color: ?shapes.Color = null,
    border_radius: f32 = 9.0,
    variant: Variant = .FILLED,
    border_thickness: f32 = 2.0,
    padding: layout_mod.Spacing = layout_mod.Spacing.symmetric(10.0, 20.0),
};

pub fn button(ctx: *GuiContext, label: []const u8, opts: Options) bool {
    const metrics = ctx.measureText(label, opts.font_size) catch {
        return false;
    };

    const layout = ctx.getCurrentLayout();
    const width = metrics.width + opts.padding.left + opts.padding.right;
    const height = metrics.height + opts.padding.top + opts.padding.bottom;
    const rect = layout.allocateSpace(ctx, width, height);

    const is_hovered = ctx.input.isMouseInRect(rect);
    const is_clicked = is_hovered and ctx.input.mouse_left_clicked and !ctx.click_consumed;

    if (is_hovered) {
        ctx.setCursor(ctx.hand_cursor);
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

    // Determine button color based on state
    var button_color = base_color;
    if (is_hovered and ctx.input.mouse_left_pressed) {
        // Use theme's pressed color if using theme, else darken custom color
        button_color = if (opts.color == null)
            ctx.theme.accent_pressed
        else
            color_utils.darken(base_color, 0.8);
    } else if (is_hovered) {
        // Use theme's hover color if using theme, else darken custom color
        button_color = if (opts.color == null)
            ctx.theme.accent_hover
        else
            color_utils.darken(base_color, 0.9);
    }

    switch (opts.variant) {
        .FILLED => ctx.draw_list.addRoundedRect(rect, opts.border_radius, button_color) catch {
            return false;
        },
        .OUTLINED => ctx.draw_list.addRoundedRectOutline(rect, opts.border_radius, opts.border_thickness, button_color) catch {
            return false;
        },
    }

    const tx = rect.x + opts.padding.left + (rect.w - opts.padding.left - opts.padding.right - metrics.width) * 0.5;
    const ty = rect.y + opts.padding.top + (rect.h - opts.padding.top - opts.padding.bottom - metrics.height) * 0.5;

    ctx.addText(tx, ty, label, opts.font_size, font_color) catch {
        return false;
    };

    return is_clicked;
}
