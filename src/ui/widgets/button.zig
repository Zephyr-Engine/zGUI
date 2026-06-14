const types = @import("../core/types.zig");
const style_mod = @import("../core/style.zig");
const input = @import("../core/input.zig");
const app = @import("../core/ui_context.zig");

pub fn button(ui: *app.Ui, parent: types.NodeId, text: []const u8, style: style_mod.Style) !types.NodeId {
    const id = try ui.tree.createNode(.button);
    const node = ui.tree.get(id).?;
    node.style = style;
    node.text = text;
    node.flags.visible = true;
    node.flags.interactive = true;
    try ui.tree.appendChild(parent, id);
    return id;
}

pub fn buttonClicked(ui: *const app.Ui, id: types.NodeId) bool {
    return input.buttonClicked(ui.input, id);
}
