const types = @import("core/types.zig");
const style_mod = @import("core/style.zig");

pub const ColorRole = enum {
    transparent,
    app,
    shell,
    panel,
    panel_soft,
    card,
    control,
    viewport,
    stroke,
    stroke_soft,
    text,
    text_dim,
    text_muted,
    accent,
    accent_soft,
    violet,
    violet_soft,
    success,
    success_soft,
    warning,
    warning_soft,
    danger,
    danger_soft,
};

pub const RadiusRole = enum {
    none,
    control,
    card,
    viewport,
    pill,
    round,
};

pub const Palette = struct {
    transparent: types.Color = types.Color.rgba(0, 0, 0, 0),

    app: types.Color = types.Color.rgba(13, 14, 17, 255),
    shell: types.Color = types.Color.rgba(20, 20, 24, 255),
    panel: types.Color = types.Color.rgba(25, 25, 30, 255),
    panel_soft: types.Color = types.Color.rgba(30, 30, 36, 255),
    card: types.Color = types.Color.rgba(35, 35, 42, 255),
    control: types.Color = types.Color.rgba(41, 41, 49, 255),
    viewport: types.Color = types.Color.rgba(18, 18, 22, 255),

    stroke: types.Color = types.Color.rgba(58, 58, 68, 255),
    stroke_soft: types.Color = types.Color.rgba(42, 42, 50, 255),

    text: types.Color = types.Color.rgba(245, 245, 246, 255),
    text_dim: types.Color = types.Color.rgba(177, 179, 187, 255),
    text_muted: types.Color = types.Color.rgba(123, 126, 136, 255),

    accent: types.Color = types.Color.rgba(139, 92, 246, 255),
    accent_soft: types.Color = types.Color.rgba(48, 36, 78, 255),
    violet: types.Color = types.Color.rgba(167, 139, 250, 255),
    violet_soft: types.Color = types.Color.rgba(48, 40, 82, 255),

    success: types.Color = types.Color.rgba(64, 190, 122, 255),
    success_soft: types.Color = types.Color.rgba(31, 58, 43, 255),
    warning: types.Color = types.Color.rgba(245, 158, 11, 255),
    warning_soft: types.Color = types.Color.rgba(69, 48, 19, 255),
    danger: types.Color = types.Color.rgba(239, 68, 68, 255),
    danger_soft: types.Color = types.Color.rgba(74, 32, 32, 255),
};

pub const Radius = struct {
    control: f32 = 10,
    card: f32 = 12,
    viewport: f32 = 14,
    pill: f32 = 12,
    round: f32 = 999,
};

pub const Space = struct {
    xxs: f32 = 2,
    xs: f32 = 4,
    sm: f32 = 6,
    md: f32 = 8,
    lg: f32 = 10,
    xl: f32 = 12,
    xxl: f32 = 16,
};

pub const Font = struct {
    tiny: f32 = 11,
    small: f32 = 12,
    body: f32 = 13,
    title: f32 = 16,
    brand: f32 = 18,
};

pub const StyleOptions = struct {
    width: style_mod.Size = .hug,
    height: style_mod.Size = .hug,
    min_width: f32 = 0,
    min_height: f32 = 0,
    padding: style_mod.Edges = .{},
    margin: style_mod.Edges = .{},
    gap: f32 = 0,
    direction: style_mod.LayoutDirection = .column,
    background: ColorRole = .transparent,
    foreground: ColorRole = .text,
    border: ColorRole = .transparent,
    border_width: f32 = 0,
    border_edges: ?style_mod.Edges = null,
    radius: RadiusRole = .none,
    radius_px: ?f32 = null,
    font_size: f32 = 16,
};

pub const TextOptions = struct {
    width: style_mod.Size = .hug,
    height: style_mod.Size = .hug,
    min_width: f32 = 0,
    min_height: f32 = 0,
    padding: style_mod.Edges = .{},
    margin: style_mod.Edges = .{},
    color: ColorRole = .text,
    size: f32 = 13,
};

pub const Theme = struct {
    palette: Palette = .{},
    radius_tokens: Radius = .{},
    space: Space = .{},
    font: Font = .{},

    pub fn color(self: Theme, role: ColorRole) types.Color {
        return switch (role) {
            .transparent => self.palette.transparent,
            .app => self.palette.app,
            .shell => self.palette.shell,
            .panel => self.palette.panel,
            .panel_soft => self.palette.panel_soft,
            .card => self.palette.card,
            .control => self.palette.control,
            .viewport => self.palette.viewport,
            .stroke => self.palette.stroke,
            .stroke_soft => self.palette.stroke_soft,
            .text => self.palette.text,
            .text_dim => self.palette.text_dim,
            .text_muted => self.palette.text_muted,
            .accent => self.palette.accent,
            .accent_soft => self.palette.accent_soft,
            .violet => self.palette.violet,
            .violet_soft => self.palette.violet_soft,
            .success => self.palette.success,
            .success_soft => self.palette.success_soft,
            .warning => self.palette.warning,
            .warning_soft => self.palette.warning_soft,
            .danger => self.palette.danger,
            .danger_soft => self.palette.danger_soft,
        };
    }

    pub fn radius(self: Theme, role: RadiusRole) f32 {
        return switch (role) {
            .none => 0,
            .control => self.radius_tokens.control,
            .card => self.radius_tokens.card,
            .viewport => self.radius_tokens.viewport,
            .pill => self.radius_tokens.pill,
            .round => self.radius_tokens.round,
        };
    }

    pub fn style(self: Theme, options: StyleOptions) style_mod.Style {
        return .{
            .width = options.width,
            .height = options.height,
            .min_width = options.min_width,
            .min_height = options.min_height,
            .padding = options.padding,
            .margin = options.margin,
            .gap = options.gap,
            .direction = options.direction,
            .background = self.color(options.background),
            .foreground = self.color(options.foreground),
            .border_color = self.color(options.border),
            .border_width = options.border_width,
            .border_edges = options.border_edges,
            .radius = options.radius_px orelse self.radius(options.radius),
            .font_size = options.font_size,
        };
    }

    pub fn textStyle(self: Theme, options: TextOptions) style_mod.Style {
        return self.style(.{
            .width = options.width,
            .height = options.height,
            .min_width = options.min_width,
            .min_height = options.min_height,
            .padding = options.padding,
            .margin = options.margin,
            .foreground = options.color,
            .font_size = options.size,
        });
    }
};

pub const zephyr_dark = Theme{};
