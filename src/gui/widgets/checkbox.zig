const GuiContext = @import("../context.zig").GuiContext;
const shapes = @import("../shapes.zig");
const theme_mod = @import("../theme.zig");

pub const CheckboxOptions = struct {
    size: f32 = 24.0,
    color: ?shapes.Color = null,
    border_radius: f32 = 4.0,
    border_thickness: f32 = 2.0,
};

pub fn checkbox(ctx: *GuiContext, checked: *bool, opts: CheckboxOptions) !bool {
    const layout = ctx.getCurrentLayout();
    const rect = layout.allocateSpace(ctx, opts.size, opts.size);

    const is_hovered = ctx.input.isMouseInRect(rect);
    if (is_hovered) {
        ctx.setCursor(ctx.hand_cursor);
    }

    const is_clicked = is_hovered and ctx.input.mouse_left_clicked and !ctx.click_consumed;
    if (is_clicked) {
        checked.* = !checked.*;
    }

    // Get color from theme with option override
    const checkbox_color = theme_mod.getColor(ctx.theme, opts.color, "accent_primary", 0x4fc3f7FF);

    if (checked.*) {
        try ctx.draw_list.addRoundedRect(rect, opts.border_radius, checkbox_color);
    } else {
        try ctx.draw_list.addRoundedRectOutline(rect, opts.border_radius, opts.border_thickness, checkbox_color);
    }

    return is_clicked;
}
