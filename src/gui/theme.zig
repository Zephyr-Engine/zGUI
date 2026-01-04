const shapes = @import("shapes.zig");

/// Theme defines the color palette for the GUI
pub const Theme = struct {
    // Background colors
    bg_primary: shapes.Color, // Main background
    bg_secondary: shapes.Color, // Panels, sidebars
    bg_elevated: shapes.Color, // Dropdowns, modals, floating windows
    bg_hover: shapes.Color, // Subtle hover states

    // Border colors
    border_subtle: shapes.Color, // Panel dividers
    border_strong: shapes.Color, // Active/focused borders

    // Surface colors
    surface_highlight: shapes.Color, // Selected items in lists

    // Text hierarchy
    text_primary: shapes.Color, // Main text, labels
    text_secondary: shapes.Color, // Descriptions, metadata
    text_muted: shapes.Color, // Disabled states, hints
    text_bright: shapes.Color, // Headings, important labels

    // Accent colors (interactive elements)
    accent_primary: shapes.Color, // Primary buttons, links, active states
    accent_hover: shapes.Color, // Hover state for accent elements
    accent_pressed: shapes.Color, // Pressed state for accent elements

    // Semantic colors (for feedback)
    success: shapes.Color, // Success states, confirmations
    warning: shapes.Color, // Warnings, caution states
    err: shapes.Color, // Errors, delete actions
    info: shapes.Color, // Info messages

    // Widget-specific colors
    input_selection: shapes.Color, // Text selection highlight
    resize_border: shapes.Color, // Panel resize borders
};

/// VS Code-inspired dark theme with bright accent colors
pub const DARK_THEME = Theme{
    // Backgrounds
    .bg_primary = 0x1e1e1eFF, // #1e1e1e
    .bg_secondary = 0x252526FF, // #252526
    .bg_elevated = 0x2d2d30FF, // #2d2d30
    .bg_hover = 0x2a2d2eFF, // #2a2d2e

    // Borders
    .border_subtle = 0x3e3e42FF, // #3e3e42
    .border_strong = 0x454545FF, // #454545

    // Surface
    .surface_highlight = 0x37373dFF, // #37373d

    // Text
    .text_primary = 0xccccccFF, // #cccccc
    .text_secondary = 0x9d9d9dFF, // #9d9d9d
    .text_muted = 0x6e6e6eFF, // #6e6e6e
    .text_bright = 0xffffffFF, // #ffffff

    // Accents (purple-blue)
    .accent_primary = 0x546be7FF, // #546be7
    .accent_hover = 0x4c60d0FF, // 10% darker
    .accent_pressed = 0x4456b9FF, // 20% darker

    // Semantic colors
    .success = 0x81c784FF, // #81c784 (green)
    .warning = 0xffb74dFF, // #ffb74d (amber)
    .err = 0xe57373FF, // #e57373 (red)
    .info = 0x64b5f6FF, // #64b5f6 (blue)

    // Widget-specific
    .input_selection = 0x264f78AA, // #264f78 with alpha (VS Code selection)
    .resize_border = 0x546be7FF, // Use primary accent
};

/// Light theme with inverted colors
pub const LIGHT_THEME = Theme{
    // Backgrounds (light)
    .bg_primary = 0xf5f5f5FF, // #f5f5f5 (light gray)
    .bg_secondary = 0xeeeeeeFF, // #eeeeee (slightly darker)
    .bg_elevated = 0xffffffFF, // #ffffff (white for elevated)
    .bg_hover = 0xe0e0e0FF, // #e0e0e0 (hover state)

    // Borders
    .border_subtle = 0xe0e0e0FF, // #e0e0e0 (light borders)
    .border_strong = 0xc0c0c0FF, // #c0c0c0 (active borders)

    // Surface
    .surface_highlight = 0xd0d0d0FF, // #d0d0d0 (selected items)

    // Text (dark on light)
    .text_primary = 0x333333FF, // #333333 (dark gray)
    .text_secondary = 0x666666FF, // #666666 (medium gray)
    .text_muted = 0x999999FF, // #999999 (light gray for disabled)
    .text_bright = 0x000000FF, // #000000 (black for headings)

    // Accents (same as dark theme)
    .accent_primary = 0x546be7FF, // #546be7
    .accent_hover = 0x4c60d0FF, // 10% darker
    .accent_pressed = 0x4456b9FF, // 20% darker

    // Semantic colors (same as dark theme)
    .success = 0x81c784FF, // #81c784 (green)
    .warning = 0xffb74dFF, // #ffb74d (amber)
    .err = 0xe57373FF, // #e57373 (red)
    .info = 0x546be7FF, // #546be7 (same as primary accent)

    // Widget-specific
    .input_selection = 0xb3d4fcAA, // #b3d4fc with alpha (light blue selection)
    .resize_border = 0x546be7FF, // Use primary accent
};

/// Helper to get a color with fallback logic
/// Order: explicit_color > theme_color > default_color
pub fn getColor(
    theme: ?*const Theme,
    explicit_color: ?shapes.Color,
    comptime theme_field: []const u8,
    default_color: shapes.Color,
) shapes.Color {
    if (explicit_color) |c| return c;
    if (theme) |t| return @field(t, theme_field);
    return default_color;
}
