const types = @import("../core/types.zig");
const style_mod = @import("../core/style.zig");
const node_mod = @import("../core/node.zig");
const input = @import("../core/input.zig");
const app = @import("../core/ui_context.zig");

pub const IconButtonOptions = struct {
    texture: types.TextureHandle,
    style: style_mod.Style,
    uv0: types.Vec2 = .{ .x = 0, .y = 0 },
    uv1: types.Vec2 = .{ .x = 1, .y = 1 },
    tint: types.Color = types.Color.rgba(255, 255, 255, 255),
};

pub fn button(ui: *app.Ui, parent: types.NodeId, text: []const u8, style: style_mod.Style) !types.NodeId {
    const id = try ui.tree.createNode(.button);
    const node = ui.tree.get(id).?;
    node.style = style;
    node.flags.visible = true;
    node.flags.interactive = true;
    try ui.tree.setText(id, text);
    try ui.tree.appendChild(parent, id);
    return id;
}

/// Creates a normal button whose face is rendered from a texture instead of text.
/// It participates in the same hover, press, focus, and click routing as `button`.
pub fn iconButton(ui: *app.Ui, parent: types.NodeId, options: IconButtonOptions) !types.NodeId {
    const id = try button(ui, parent, "", options.style);
    const node = ui.tree.get(id).?;
    node.image = node_mod.Image{
        .texture = options.texture,
        .uv0 = options.uv0,
        .uv1 = options.uv1,
        .tint = options.tint,
    };
    return id;
}

pub fn buttonClicked(ui: *const app.Ui, id: types.NodeId) bool {
    return input.buttonClicked(ui.input, id);
}
