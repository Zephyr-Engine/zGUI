/// Platform abstraction callbacks for embedded mode (game engine integration)
/// These callbacks allow zGUI to run without GLFW by delegating platform-specific
/// functionality to the host application.

pub const CursorShape = enum {
    arrow,
    ibeam,
    hand,
    hresize,
    vresize,
    crosshair,
};

/// Platform callbacks for embedded mode
/// All callbacks are optional except getTime which is required for animations
pub const PlatformCallbacks = struct {
    /// Get current time in seconds (REQUIRED)
    /// Used for cursor blinking, animations, and frame timing
    getTime: *const fn () f64,

    /// Get clipboard text content (optional)
    /// Returns null if clipboard is empty or unavailable
    getClipboard: ?*const fn () ?[]const u8 = null,

    /// Set clipboard text content (optional)
    setClipboard: ?*const fn ([]const u8) void = null,

    /// Set cursor shape (optional)
    /// Called when cursor should change (e.g., over text input, resize handles)
    setCursor: ?*const fn (CursorShape) void = null,
};
