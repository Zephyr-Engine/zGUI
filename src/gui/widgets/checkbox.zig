const GuiContext = @import("../context.zig").GuiContext;
const shapes = @import("../shapes.zig");
const imageWidget = @import("image.zig");

pub const CheckboxOptions = struct {
    size: f32 = 24.0,
    color: shapes.Color = 0x000000FF,
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

    try ctx.draw_list.addRoundedRectOutline(rect, opts.border_radius, opts.border_thickness, opts.color);
    if (checked.*) {
        // Only render checkmark if image is available
        if (ctx.checkmark_image) |*img| {
            const padding = opts.size * 0.15;
            const checkmark_size = opts.size - (padding * 2);
            const checkmark_x = rect.x + padding;
            const checkmark_y = rect.y + padding;

            try imageWidget.imageAt(ctx, checkmark_x, checkmark_y, img, .{
                .width = checkmark_size,
                .height = checkmark_size,
            });
        }
    }

    return is_clicked;
}
