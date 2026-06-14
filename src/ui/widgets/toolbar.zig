const types = @import("../core/types.zig");
const style_mod = @import("../core/style.zig");
const app = @import("../core/ui_context.zig");
const panel_mod = @import("panel.zig");

pub fn toolbar(ui: *app.Ui, parent: types.NodeId, style: style_mod.Style) !types.NodeId {
    var next = style;
    next.direction = .row;
    return panel_mod.panel(ui, parent, next);
}
