const types = @import("../core/types.zig");
const style_mod = @import("../core/style.zig");
const app = @import("../core/ui_context.zig");

pub fn resizeHandle(ui: *app.Ui, parent: types.NodeId, style: style_mod.Style) !types.NodeId {
    const id = try ui.tree.createNode(.panel);
    const node = ui.tree.get(id).?;
    node.style = style;
    node.flags.visible = true;
    node.flags.interactive = true;
    try ui.tree.appendChild(parent, id);
    return id;
}
