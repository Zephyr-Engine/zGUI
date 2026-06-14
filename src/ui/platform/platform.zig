const types = @import("../core/types.zig");
const events = @import("events.zig");

pub const Platform = struct {
    ptr: *anyopaque,

    pollEventsFn: *const fn (*anyopaque) []const events.PlatformEvent,
    getWindowSizeFn: *const fn (*anyopaque) types.Vec2,
    setCursorFn: *const fn (*anyopaque, events.CursorKind) void,
    getClipboardFn: *const fn (*anyopaque) []const u8,
    setClipboardFn: *const fn (*anyopaque, []const u8) void,

    pub fn pollEvents(self: Platform) []const events.PlatformEvent {
        return self.pollEventsFn(self.ptr);
    }

    pub fn getWindowSize(self: Platform) types.Vec2 {
        return self.getWindowSizeFn(self.ptr);
    }

    pub fn setCursor(self: Platform, cursor: events.CursorKind) void {
        self.setCursorFn(self.ptr, cursor);
    }

    pub fn getClipboard(self: Platform) []const u8 {
        return self.getClipboardFn(self.ptr);
    }

    pub fn setClipboard(self: Platform, text: []const u8) void {
        self.setClipboardFn(self.ptr, text);
    }
};
