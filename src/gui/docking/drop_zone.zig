const GuiContext = @import("../context.zig").GuiContext;
const shapes = @import("../shapes.zig");

pub const DropZone = enum {
    none,
    left,
    right,
    top,
    bottom,
    center, // Tab into existing group
};

pub const DropZoneInfo = struct {
    zone: DropZone,
    highlight_rect: shapes.Rect, // Small edge indicator
    preview_rect: shapes.Rect, // Where panel would appear after drop
};

/// Calculate drop zone based on mouse position within a target rect
/// Returns null if mouse is outside the rect
pub fn calculateDropZone(
    target_rect: shapes.Rect,
    mouse_x: f32,
    mouse_y: f32,
) ?DropZoneInfo {
    // Normalize mouse position to 0-1 range within rect
    const rel_x = (mouse_x - target_rect.x) / target_rect.w;
    const rel_y = (mouse_y - target_rect.y) / target_rect.h;

    // Check if outside rect
    if (rel_x < 0 or rel_x > 1 or rel_y < 0 or rel_y > 1) {
        return null;
    }

    const edge_threshold = 0.25; // 25% of dimensions for edge zones

    // Check edges (priority order matters!)
    // Left edge
    if (rel_x < edge_threshold) {
        return makeDropZoneInfo(target_rect, .left);
    }
    // Right edge
    if (rel_x > 1.0 - edge_threshold) {
        return makeDropZoneInfo(target_rect, .right);
    }
    // Top edge
    if (rel_y < edge_threshold) {
        return makeDropZoneInfo(target_rect, .top);
    }
    // Bottom edge
    if (rel_y > 1.0 - edge_threshold) {
        return makeDropZoneInfo(target_rect, .bottom);
    }

    // Center zone (tab)
    return makeDropZoneInfo(target_rect, .center);
}

fn makeDropZoneInfo(target_rect: shapes.Rect, zone: DropZone) DropZoneInfo {
    const highlight_thickness = 40.0; // Thickness of edge highlight

    var highlight_rect: shapes.Rect = undefined;
    var preview_rect: shapes.Rect = undefined;

    switch (zone) {
        .left => {
            highlight_rect = shapes.Rect{
                .x = target_rect.x,
                .y = target_rect.y,
                .w = highlight_thickness,
                .h = target_rect.h,
            };
            preview_rect = shapes.Rect{
                .x = target_rect.x,
                .y = target_rect.y,
                .w = target_rect.w * 0.5,
                .h = target_rect.h,
            };
        },
        .right => {
            highlight_rect = shapes.Rect{
                .x = target_rect.x + target_rect.w - highlight_thickness,
                .y = target_rect.y,
                .w = highlight_thickness,
                .h = target_rect.h,
            };
            preview_rect = shapes.Rect{
                .x = target_rect.x + target_rect.w * 0.5,
                .y = target_rect.y,
                .w = target_rect.w * 0.5,
                .h = target_rect.h,
            };
        },
        .top => {
            highlight_rect = shapes.Rect{
                .x = target_rect.x,
                .y = target_rect.y,
                .w = target_rect.w,
                .h = highlight_thickness,
            };
            preview_rect = shapes.Rect{
                .x = target_rect.x,
                .y = target_rect.y,
                .w = target_rect.w,
                .h = target_rect.h * 0.5,
            };
        },
        .bottom => {
            highlight_rect = shapes.Rect{
                .x = target_rect.x,
                .y = target_rect.y + target_rect.h - highlight_thickness,
                .w = target_rect.w,
                .h = highlight_thickness,
            };
            preview_rect = shapes.Rect{
                .x = target_rect.x,
                .y = target_rect.y + target_rect.h * 0.5,
                .w = target_rect.w,
                .h = target_rect.h * 0.5,
            };
        },
        .center => {
            // Center zone uses the whole rect for both highlight and preview
            highlight_rect = target_rect;
            preview_rect = target_rect;
        },
        .none => {
            highlight_rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 };
            preview_rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 };
        },
    }

    return .{
        .zone = zone,
        .highlight_rect = highlight_rect,
        .preview_rect = preview_rect,
    };
}

/// Render drop zone overlay with highlights and preview
pub fn renderDropZoneOverlay(ctx: *GuiContext, zone_info: DropZoneInfo) !void {
    // Don't render "none" zone
    if (zone_info.zone == .none) {
        return;
    }

    const highlight_color = ctx.theme.accent_primary; // Blue highlight
    const preview_color = blendColor(ctx.theme.accent_primary, 80); // Semi-transparent blue

    // Render preview area (where panel will go)
    try ctx.draw_list.addRect(zone_info.preview_rect, preview_color);

    // Render highlight (bright edge indicator)
    try ctx.draw_list.addRect(zone_info.highlight_rect, highlight_color);
}

/// Blend a color with alpha transparency (RGBA u32 format)
fn blendColor(color: u32, alpha: u8) u32 {
    // Extract RGB components, replace alpha
    const rgb = color & 0xFFFFFF00;
    return rgb | alpha;
}
