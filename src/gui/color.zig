const shapes = @import("shapes.zig");

/// Darken a color by a factor (0.0 = black, 1.0 = unchanged)
/// Example: darken(color, 0.9) makes color 10% darker
pub fn darken(color: shapes.Color, factor: f32) shapes.Color {
    const r: f32 = @floatFromInt((color >> 24) & 0xFF);
    const g: f32 = @floatFromInt((color >> 16) & 0xFF);
    const b: f32 = @floatFromInt((color >> 8) & 0xFF);
    const a: u8 = @intCast(color & 0xFF);

    const new_r: u8 = @intFromFloat(@min(255.0, r * factor));
    const new_g: u8 = @intFromFloat(@min(255.0, g * factor));
    const new_b: u8 = @intFromFloat(@min(255.0, b * factor));

    return (@as(u32, new_r) << 24) | (@as(u32, new_g) << 16) | (@as(u32, new_b) << 8) | @as(u32, a);
}

/// Lighten/brighten a color by a factor (1.0 = unchanged, >1.0 = brighter)
/// Example: lighten(color, 1.2) makes color 20% brighter
pub fn lighten(color: shapes.Color, factor: f32) shapes.Color {
    const r: f32 = @floatFromInt((color >> 24) & 0xFF);
    const g: f32 = @floatFromInt((color >> 16) & 0xFF);
    const b: f32 = @floatFromInt((color >> 8) & 0xFF);
    const a: u8 = @intCast(color & 0xFF);

    const new_r: u8 = @intFromFloat(@min(255.0, r * factor));
    const new_g: u8 = @intFromFloat(@min(255.0, g * factor));
    const new_b: u8 = @intFromFloat(@min(255.0, b * factor));

    return (@as(u32, new_r) << 24) | (@as(u32, new_g) << 16) | (@as(u32, new_b) << 8) | @as(u32, a);
}

/// Set the alpha channel of a color
/// Example: withAlpha(color, 128) makes color 50% transparent
pub fn withAlpha(color: shapes.Color, alpha: u8) shapes.Color {
    return (color & 0xFFFFFF00) | @as(u32, alpha);
}

/// Mix two colors by a ratio (0.0 = color1, 1.0 = color2)
/// Example: mix(red, blue, 0.5) creates purple
pub fn mix(color1: shapes.Color, color2: shapes.Color, ratio: f32) shapes.Color {
    const r1: f32 = @floatFromInt((color1 >> 24) & 0xFF);
    const g1: f32 = @floatFromInt((color1 >> 16) & 0xFF);
    const b1: f32 = @floatFromInt((color1 >> 8) & 0xFF);
    const a1: f32 = @floatFromInt(color1 & 0xFF);

    const r2: f32 = @floatFromInt((color2 >> 24) & 0xFF);
    const g2: f32 = @floatFromInt((color2 >> 16) & 0xFF);
    const b2: f32 = @floatFromInt((color2 >> 8) & 0xFF);
    const a2: f32 = @floatFromInt(color2 & 0xFF);

    const t = @max(0.0, @min(1.0, ratio));
    const new_r: u8 = @intFromFloat(r1 + (r2 - r1) * t);
    const new_g: u8 = @intFromFloat(g1 + (g2 - g1) * t);
    const new_b: u8 = @intFromFloat(b1 + (b2 - b1) * t);
    const new_a: u8 = @intFromFloat(a1 + (a2 - a1) * t);

    return (@as(u32, new_r) << 24) | (@as(u32, new_g) << 16) | (@as(u32, new_b) << 8) | @as(u32, new_a);
}
