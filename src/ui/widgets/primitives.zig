const types = @import("../core/types.zig");
const style_mod = @import("../core/style.zig");
const theme_mod = @import("../theme.zig");
const app = @import("../core/ui_context.zig");
const panel_mod = @import("panel.zig");
const label_mod = @import("label.zig");
const button_mod = @import("button.zig");

pub const CardOptions = struct {
    width: style_mod.Size = .fill,
    height: style_mod.Size = .hug,
    direction: style_mod.LayoutDirection = .column,
    gap: f32 = 6,
    padding: style_mod.Edges = style_mod.Edges.all(10),
    surface: theme_mod.ColorRole = .card,
    border: theme_mod.ColorRole = .stroke_soft,
    border_width: f32 = 1,
    radius: theme_mod.RadiusRole = .card,
};

pub const PillOptions = struct {
    width: f32,
    height: f32 = 24,
    foreground: theme_mod.ColorRole = .text,
    background: theme_mod.ColorRole = .control,
    border: theme_mod.ColorRole = .stroke,
    font_size: f32 = 11,
};

pub const ButtonVariant = enum {
    neutral,
    primary,
    ghost,
};

pub const ButtonOptions = struct {
    width: style_mod.Size = .hug,
    height: style_mod.Size = .{ .px = 34 },
    padding: style_mod.Edges = .{ .left = 14, .right = 14, .top = 9, .bottom = 8 },
    variant: ButtonVariant = .neutral,
    foreground: ?theme_mod.ColorRole = null,
    background: ?theme_mod.ColorRole = null,
    border: ?theme_mod.ColorRole = null,
    border_width: f32 = 1,
    radius: theme_mod.RadiusRole = .control,
    font_size: f32 = 12,
};

const ButtonRoles = struct {
    foreground: theme_mod.ColorRole,
    background: theme_mod.ColorRole,
    border: theme_mod.ColorRole,
};

pub fn surface(ui: *app.Ui, parent: types.NodeId, options: theme_mod.StyleOptions) !types.NodeId {
    return panel_mod.panel(ui, parent, ui.theme.style(options));
}

pub fn row(ui: *app.Ui, parent: types.NodeId, options: theme_mod.StyleOptions) !types.NodeId {
    var next = options;
    next.direction = .row;
    return surface(ui, parent, next);
}

pub fn column(ui: *app.Ui, parent: types.NodeId, options: theme_mod.StyleOptions) !types.NodeId {
    var next = options;
    next.direction = .column;
    return surface(ui, parent, next);
}

pub fn card(ui: *app.Ui, parent: types.NodeId, options: CardOptions) !types.NodeId {
    return surface(ui, parent, .{
        .width = options.width,
        .height = options.height,
        .direction = options.direction,
        .gap = options.gap,
        .padding = options.padding,
        .background = options.surface,
        .border = options.border,
        .border_width = options.border_width,
        .radius = options.radius,
    });
}

pub fn text(ui: *app.Ui, parent: types.NodeId, bytes: []const u8, options: theme_mod.TextOptions) !types.NodeId {
    return label_mod.label(ui, parent, bytes, ui.theme.textStyle(options));
}

pub fn sectionLabel(ui: *app.Ui, parent: types.NodeId, bytes: []const u8) !types.NodeId {
    return text(ui, parent, bytes, .{
        .width = .fill,
        .height = .{ .px = 18 },
        .padding = .{ .top = 3 },
        .color = .text_muted,
        .size = ui.theme.font.tiny,
    });
}

pub fn divider(ui: *app.Ui, parent: types.NodeId) !types.NodeId {
    return surface(ui, parent, .{
        .width = .fill,
        .height = .{ .px = 1 },
        .background = .stroke_soft,
    });
}

pub fn spacer(ui: *app.Ui, parent: types.NodeId) !types.NodeId {
    return surface(ui, parent, .{
        .width = .fill,
        .height = .fill,
    });
}

pub fn dot(ui: *app.Ui, parent: types.NodeId, color: theme_mod.ColorRole, size: f32) !types.NodeId {
    return surface(ui, parent, .{
        .width = .{ .px = size },
        .height = .{ .px = size },
        .background = color,
        .radius_px = size * 0.5,
    });
}

pub fn pill(ui: *app.Ui, parent: types.NodeId, bytes: []const u8, options: PillOptions) !types.NodeId {
    const container = try surface(ui, parent, .{
        .width = .{ .px = options.width },
        .height = .{ .px = options.height },
        .padding = .{ .left = 8, .right = 8, .top = 5, .bottom = 5 },
        .background = options.background,
        .border = options.border,
        .border_width = 1,
        .radius = .pill,
    });
    _ = try text(ui, container, bytes, .{
        .width = .fill,
        .height = .fill,
        .color = options.foreground,
        .size = options.font_size,
    });
    return container;
}

pub fn themedButton(ui: *app.Ui, parent: types.NodeId, bytes: []const u8, options: ButtonOptions) !types.NodeId {
    const roles = buttonRoles(options);
    return button_mod.button(ui, parent, bytes, ui.theme.style(.{
        .width = options.width,
        .height = options.height,
        .padding = options.padding,
        .background = roles.background,
        .foreground = roles.foreground,
        .border = roles.border,
        .border_width = options.border_width,
        .radius = options.radius,
        .font_size = options.font_size,
    }));
}

pub fn toolbarButton(ui: *app.Ui, parent: types.NodeId, bytes: []const u8, width: f32, variant: ButtonVariant) !types.NodeId {
    return themedButton(ui, parent, bytes, .{
        .width = .{ .px = width },
        .height = .{ .px = 32 },
        .padding = .{ .left = 14, .right = 14, .top = 8, .bottom = 7 },
        .variant = variant,
    });
}

pub fn primaryButton(ui: *app.Ui, parent: types.NodeId, bytes: []const u8) !types.NodeId {
    return themedButton(ui, parent, bytes, .{
        .width = .fill,
        .variant = .primary,
    });
}

fn buttonRoles(options: ButtonOptions) ButtonRoles {
    const defaults: ButtonRoles = switch (options.variant) {
        .neutral => .{
            .foreground = theme_mod.ColorRole.text_dim,
            .background = theme_mod.ColorRole.control,
            .border = theme_mod.ColorRole.stroke,
        },
        .primary => .{
            .foreground = theme_mod.ColorRole.text,
            .background = theme_mod.ColorRole.accent,
            .border = theme_mod.ColorRole.accent,
        },
        .ghost => .{
            .foreground = theme_mod.ColorRole.text_muted,
            .background = theme_mod.ColorRole.transparent,
            .border = theme_mod.ColorRole.stroke_soft,
        },
    };

    return .{
        .foreground = options.foreground orelse defaults.foreground,
        .background = options.background orelse defaults.background,
        .border = options.border orelse defaults.border,
    };
}
