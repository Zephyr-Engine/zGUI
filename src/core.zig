pub const types = @import("ui/core/types.zig");
pub const style = @import("ui/core/style.zig");
pub const theme = @import("ui/theme.zig");
pub const widgets = @import("ui/widgets/widgets.zig");
pub const events = @import("ui/platform/events.zig");

pub const Ui = @import("ui/core/ui_context.zig").Ui;
pub const BeginFrame = @import("ui/core/ui_context.zig").BeginFrame;
pub const UiStats = @import("ui/core/ui_context.zig").UiStats;
pub const InputCapture = @import("ui/core/ui_context.zig").InputCapture;
pub const Interaction = @import("ui/core/ui_context.zig").Interaction;
pub const Event = events.Event;
pub const EventHandler = events.EventHandler;
pub const Activation = events.Activation;
pub const ActivationSource = events.ActivationSource;
pub const NodeId = types.NodeId;
pub const TextureHandle = types.TextureHandle;
pub const Vec2 = types.Vec2;
pub const Rect = types.Rect;
pub const Color = types.Color;

test {
    _ = @import("ui/core/types.zig");
    _ = @import("ui/core/tree.zig");
    _ = @import("ui/core/layout.zig");
    _ = @import("ui/core/input.zig");
    _ = @import("ui/core/ui_context.zig");
    _ = @import("ui/widgets/virtual_list.zig");
    _ = @import("ui/docking/dock_view.zig");
}
