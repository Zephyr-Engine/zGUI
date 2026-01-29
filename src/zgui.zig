// zGUI - Immediate-mode GUI library for Zig
// Main library entry point

// Build options (re-exported for consumer convenience)
pub const build_options = @import("build_options");

// Core components
pub const GuiContext = @import("gui/context.zig").GuiContext;
pub const DrawList = @import("gui/draw_list.zig").DrawList;

// Shapes and primitives
pub const shapes = @import("gui/shapes.zig");
pub const Vertex = shapes.Vertex;
pub const Rect = shapes.Rect;

// Color and theming
pub const color = @import("gui/color.zig");
pub const Color = color.Color;
pub const theme = @import("gui/theme.zig");
pub const Theme = theme.Theme;

// Input handling
pub const input = @import("gui/input.zig");
pub const Input = input.Input;

// Layout system
pub const layout = @import("gui/layout.zig");

// Widgets
pub const button = @import("gui/widgets/button.zig");
pub const checkbox = @import("gui/widgets/checkbox.zig");
pub const textInput = @import("gui/widgets/input.zig");
pub const dropdown = @import("gui/widgets/dropdown.zig");
pub const collapsible = @import("gui/widgets/collapsible.zig");
pub const image = @import("gui/widgets/image.zig");
pub const panel = @import("gui/widgets/panel.zig");
pub const utils = @import("gui/widgets/utils.zig");

// Renderer interface and types
pub const renderer = @import("gui/renderer.zig");
pub const Renderer = renderer.Renderer;
pub const TextureHandle = renderer.TextureHandle;
pub const TextureFormat = renderer.TextureFormat;

// OpenGL renderer implementation
pub const opengl = @import("gui/renderers/opengl.zig");
pub const GLRenderer = opengl.GLRenderer;

// Text rendering
pub const font = @import("gui/text/font.zig");
pub const Font = font.Font;
pub const font_cache = @import("gui/text/font_cache.zig");
pub const FontCache = font_cache.FontCache;

// Windowing (re-export for convenience)
pub const window = @import("gui/window.zig");
pub const Window = window.Window;
pub const WindowManager = @import("gui/window_manager.zig").WindowManager;

// Platform abstraction for embedded mode
pub const platform = @import("gui/platform.zig");
pub const PlatformCallbacks = platform.PlatformCallbacks;
pub const CursorShape = platform.CursorShape;

// Docking system
pub const docking = struct {
    pub const DockingContext = @import("gui/docking/docking_context.zig").DockingContext;
    pub const PanelInfo = @import("gui/docking/panel_info.zig").PanelInfo;
    pub const DockNode = @import("gui/docking/dock_node.zig").DockNode;
    pub const DropZone = @import("gui/docking/drop_zone.zig").DropZone;
};

// Debug utilities (conditional compilation)
pub const debug_stats = @import("gui/debug_stats.zig");
pub const DebugStats = debug_stats.DebugStats;

// C bindings (for users who need direct access)
pub const c = @import("gui/c.zig");
