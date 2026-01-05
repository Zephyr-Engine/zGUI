const GuiContext = @import("../context.zig").GuiContext;
const shapes = @import("../shapes.zig");

/// Function signature for rendering panel content
pub const PanelRenderFn = *const fn (ctx: *GuiContext, bounds: shapes.Rect) anyerror!void;

/// Panel metadata - describes a panel that can be docked
pub const PanelInfo = struct {
    id: u64,
    title: []const u8,
    render_fn: PanelRenderFn,
    closable: bool = true,
    min_width: f32 = 100.0,
    min_height: f32 = 100.0,

    pub fn init(id: u64, title: []const u8, render_fn: PanelRenderFn) PanelInfo {
        return .{
            .id = id,
            .title = title,
            .render_fn = render_fn,
        };
    }
};
