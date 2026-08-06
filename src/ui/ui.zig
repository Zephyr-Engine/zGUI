const types = @import("core/types.zig");
const style = @import("core/style.zig");
const dirty = @import("core/dirty.zig");
const node = @import("core/node.zig");
const tree = @import("core/tree.zig");
const app = @import("core/ui_context.zig");
const text = @import("core/text.zig");
pub const theme = @import("theme.zig");

const platform_events = @import("platform/events.zig");

const draw_data = @import("render/draw_data.zig");
const batcher = @import("render/batcher.zig");
const font_atlas = @import("render/font_atlas.zig");
const opengl_renderer = @import("render/opengl_renderer.zig");

const dock_manager = @import("docking/dock_manager.zig");
const dock_space = @import("docking/dock_space.zig");

pub const widgets = @import("widgets/widgets.zig");

pub const Vec2 = types.Vec2;
pub const Rect = types.Rect;
pub const Color = types.Color;
pub const NodeId = types.NodeId;
pub const WindowId = types.WindowId;
pub const DockNodeId = types.DockNodeId;
pub const TextureHandle = types.TextureHandle;
pub const invalid_node = types.invalid_node;

pub const Size = style.Size;
pub const LayoutDirection = style.LayoutDirection;
pub const Overflow = style.Overflow;
pub const Edges = style.Edges;
pub const CornerRadii = style.CornerRadii;
pub const Style = style.Style;
pub const Theme = theme.Theme;
pub const Palette = theme.Palette;
pub const ColorRole = theme.ColorRole;
pub const RadiusRole = theme.RadiusRole;
pub const StyleOptions = theme.StyleOptions;
pub const TextOptions = theme.TextOptions;

pub const Ui = app.Ui;
pub const BeginFrame = app.BeginFrame;
pub const UiStats = app.UiStats;
pub const InputCapture = app.InputCapture;
pub const Interaction = app.Interaction;

pub const PlatformEvent = platform_events.PlatformEvent;
pub const MouseButton = platform_events.MouseButton;
pub const Key = platform_events.Key;

pub const TextMetrics = text.TextMetrics;
pub const FontAtlas = font_atlas.FontAtlas;
pub const OpenGlRenderer = opengl_renderer.OpenGlRenderer;
pub const DockManager = dock_manager.DockManager;
pub const DockSpace = dock_space.DockSpace;
pub const DockSpaceOptions = dock_space.DockSpaceOptions;
pub const DockSpaceResult = dock_space.DockSpaceResult;
pub const DockWindowId = dock_space.DockWindowId;
pub const CursorKind = platform_events.CursorKind;
