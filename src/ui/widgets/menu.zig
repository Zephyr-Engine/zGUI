const types = @import("../core/types.zig");
const std = @import("std");
const app = @import("../core/ui_context.zig");
const dock_space = @import("../docking/dock_space.zig");
const primitives = @import("primitives.zig");

/// A desktop-style menu bar that renders consistently on every zGUI host.
/// Popups are registered as dock overlays so they remain above application
/// content and consume pointer input before the docking system sees it.
pub const MenuBar = struct {
    root: types.NodeId,

    pub fn init(ui: *app.Ui, parent: types.NodeId) !MenuBar {
        const root = try primitives.row(ui, parent, .{
            .width = .fill,
            .height = .fill,
            .gap = 2,
        });
        return .{ .root = root };
    }

    pub fn deinit(self: *MenuBar, ui: *app.Ui) void {
        ui.destroySubtree(self.root);
        self.* = undefined;
    }
};

pub const MenuOptions = struct {
    popup_width: f32 = 232,
    popup_offset_x: f32 = 4,
};

/// Owns one top-level menu and its popup. The caller owns action dispatch and
/// can query its item node IDs with `itemActivated` during an update.
pub const Menu = struct {
    trigger: types.NodeId,
    popup: types.NodeId,
    open: bool = false,

    pub fn init(
        ui: *app.Ui,
        bar: *const MenuBar,
        overlay_host: types.NodeId,
        dock: *dock_space.DockSpace,
        label: []const u8,
        options: MenuOptions,
    ) !Menu {
        const trigger = try primitives.themedButton(ui, bar.root, label, .{
            .width = .{ .px = 48 },
            .height = .fill,
            .padding = .{ .left = 10, .right = 10, .top = 7, .bottom = 6 },
            .variant = .ghost,
            .border = .transparent,
            .font_size = ui.theme.font.body,
        });
        errdefer ui.destroySubtree(trigger);
        applyMenuButtonStyle(ui, trigger, false);

        const popup = try primitives.surface(ui, overlay_host, .{
            .width = .{ .px = options.popup_width },
            .height = .hug,
            .direction = .column,
            .padding = .{ .left = 4, .right = 4, .top = 4, .bottom = 4 },
            .gap = 2,
            .margin = .{ .left = options.popup_offset_x },
            .background = .panel,
            .border = .stroke,
            .border_width = 1,
            .radius = .none,
        });
        errdefer ui.destroySubtree(popup);

        try ui.setVisible(popup, false);
        try dock.registerOverlay(popup);

        return .{ .trigger = trigger, .popup = popup };
    }

    pub fn deinit(self: *Menu, ui: *app.Ui, dock: *dock_space.DockSpace) void {
        dock.unregisterOverlay(self.popup);
        ui.destroySubtree(self.popup);
        self.* = undefined;
    }

    pub fn addItem(self: *const Menu, ui: *app.Ui, label: []const u8) !types.NodeId {
        const item = try primitives.themedButton(ui, self.popup, label, .{
            .width = .fill,
            .height = .{ .px = 32 },
            .padding = .{ .left = 10, .right = 10, .top = 7, .bottom = 6 },
            .variant = .ghost,
            .foreground = .text,
            .border = .transparent,
            .font_size = ui.theme.font.body,
        });
        applyMenuButtonStyle(ui, item, false);
        return item;
    }

    pub fn update(self: *Menu, ui: *app.Ui) !void {
        if (ui.activated(self.trigger)) self.open = !self.open;
        applyMenuButtonStyle(ui, self.trigger, self.open);
        try ui.setVisible(self.popup, self.open);
    }

    pub fn close(self: *Menu, ui: *app.Ui) !void {
        self.open = false;
        applyMenuButtonStyle(ui, self.trigger, false);
        try ui.setVisible(self.popup, false);
    }

    pub fn itemActivated(self: *const Menu, ui: *const app.Ui, item: types.NodeId) bool {
        return self.open and ui.activated(item);
    }
};

fn applyMenuButtonStyle(ui: *app.Ui, id: types.NodeId, selected: bool) void {
    const current = ui.nodeStyle(id) orelse return;
    var next = current;
    next.background = ui.theme.color(if (selected) .control else .transparent);
    next.foreground = ui.theme.color(.text);
    next.hover_background = ui.theme.color(.panel_soft);
    next.pressed_background = ui.theme.color(.control);
    ui.setStyle(id, next) catch {};
}

test "menu owns an overlay popup and menu items" {
    var ui = try app.Ui.init(std.testing.allocator);
    defer ui.deinit();

    const menu_host = try primitives.surface(&ui, ui.rootNode(), .{
        .width = .fill,
        .height = .{ .px = 30 },
        .direction = .row,
    });
    const overlay_host = try primitives.surface(&ui, ui.rootNode(), .{
        .width = .fill,
        .height = .fill,
        .direction = .absolute,
    });
    var dock = try dock_space.DockSpace.init(std.testing.allocator);
    defer dock.deinit();

    var bar = try MenuBar.init(&ui, menu_host);
    var menu = try Menu.init(&ui, &bar, overlay_host, &dock, "File", .{});
    defer menu.deinit(&ui, &dock);
    defer bar.deinit(&ui);

    const item = try menu.addItem(&ui, "Open Project");
    try std.testing.expect(ui.nodeExists(item));
    try std.testing.expect(ui.nodeExists(menu.popup));
}
