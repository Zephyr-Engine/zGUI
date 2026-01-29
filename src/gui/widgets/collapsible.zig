const std = @import("std");
const GuiContext = @import("../context.zig").GuiContext;
const shapes = @import("../shapes.zig");
const layout = @import("../layout.zig");
const imageWidget = @import("image.zig");
const theme_mod = @import("../theme.zig");

pub const Options = struct {
    font_size: f32 = 20.0,
    header_color: ?shapes.Color = null,
    text_color: ?shapes.Color = null,
    chevron_color: ?shapes.Color = null,
    border_radius: f32 = 4.0,
    header_height: f32 = 40.0,
    chevron_size: f32 = 16.0,
    padding: f32 = 4.0,
    margin: f32 = 8.0,
};

pub fn collapsibleSection(
    ctx: *GuiContext,
    label: []const u8,
    is_open: *bool,
    opts: Options,
) !bool {
    const current_layout = ctx.getCurrentLayout();

    const available_width = if (current_layout.width) |w|
        w - (current_layout.padding.left + current_layout.padding.right)
    else
        ctx.window_width - (current_layout.padding.left + current_layout.padding.right);

    const header_rect = current_layout.allocateSpace(ctx, available_width, opts.header_height);
    const is_hovered = ctx.input.isMouseInRect(header_rect);
    const is_clicked = is_hovered and ctx.input.mouse_left_clicked and !ctx.click_consumed;

    if (is_hovered) {
        ctx.setCursor(ctx.hand_cursor);
    }

    if (is_clicked) {
        is_open.* = !is_open.*;
    }

    // Get colors from theme with option overrides
    const header_color = theme_mod.getColor(ctx.theme, opts.header_color, "bg_hover", 0x2a2d2eFF);
    const text_color = theme_mod.getColor(ctx.theme, opts.text_color, "text_primary", 0xccccccFF);
    const chevron_color = theme_mod.getColor(ctx.theme, opts.chevron_color, "text_secondary", 0x9d9d9dFF);

    try ctx.draw_list.addRoundedRect(header_rect, opts.border_radius, header_color);

    const chevron_x = header_rect.x + 12;
    const chevron_y = header_rect.y + (opts.header_height - opts.chevron_size) * 0.5;

    const chevron_center_x = chevron_x + opts.chevron_size * 0.5;
    const chevron_center_y = chevron_y + opts.chevron_size * 0.5;
    const triangle_size = opts.chevron_size * 0.4;

    if (is_open.*) {
        const v1_x = chevron_center_x;
        const v1_y = chevron_center_y + triangle_size * 0.6;
        const v2_x = chevron_center_x - triangle_size * 0.8;
        const v2_y = chevron_center_y - triangle_size * 0.4;
        const v3_x = chevron_center_x + triangle_size * 0.8;
        const v3_y = chevron_center_y - triangle_size * 0.4;

        const rgba = shapes.colorToRGBA(chevron_color);
        const v1 = shapes.Vertex{ .pos = .{ v1_x, v1_y }, .color = rgba };
        const v2 = shapes.Vertex{ .pos = .{ v2_x, v2_y }, .color = rgba };
        const v3 = shapes.Vertex{ .pos = .{ v3_x, v3_y }, .color = rgba };

        try ctx.draw_list.addTriangle(v1, v2, v3);
    } else {
        const v1_x = chevron_center_x + triangle_size * 0.6;
        const v1_y = chevron_center_y;
        const v2_x = chevron_center_x - triangle_size * 0.4;
        const v2_y = chevron_center_y - triangle_size * 0.8;
        const v3_x = chevron_center_x - triangle_size * 0.4;
        const v3_y = chevron_center_y + triangle_size * 0.8;

        const rgba = shapes.colorToRGBA(chevron_color);
        const v1 = shapes.Vertex{ .pos = .{ v1_x, v1_y }, .color = rgba };
        const v2 = shapes.Vertex{ .pos = .{ v2_x, v2_y }, .color = rgba };
        const v3 = shapes.Vertex{ .pos = .{ v3_x, v3_y }, .color = rgba };

        try ctx.draw_list.addTriangle(v1, v2, v3);
    }

    const text_x = chevron_x + opts.chevron_size + opts.padding;
    const label_metrics = try ctx.measureText(label, opts.font_size);
    const text_y = header_rect.y + (opts.header_height - label_metrics.height) * 0.5;
    try ctx.addText(text_x, text_y, label, opts.font_size, text_color);

    if (is_open.*) {
        const content_layout = layout.Layout.init(.VERTICAL, header_rect.x, header_rect.y + header_rect.h, .{
            .margin = layout.Spacing.all(opts.margin),
            .padding = layout.Spacing.all(opts.padding),
            .width = header_rect.w,
        });
        layout.beginLayout(ctx, content_layout);
        return true;
    }

    return false;
}
