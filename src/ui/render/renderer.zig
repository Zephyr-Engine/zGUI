const draw_data = @import("draw_data.zig");

pub const Renderer = struct {
    ptr: *anyopaque,

    beginFrameFn: *const fn (*anyopaque, u32, u32) anyerror!void,
    renderFn: *const fn (*anyopaque, draw_data.DrawData) anyerror!void,
    endFrameFn: *const fn (*anyopaque) anyerror!void,

    pub fn beginFrame(self: Renderer, w: u32, h: u32) !void {
        try self.beginFrameFn(self.ptr, w, h);
    }

    pub fn render(self: Renderer, data: draw_data.DrawData) !void {
        try self.renderFn(self.ptr, data);
    }

    pub fn endFrame(self: Renderer) !void {
        try self.endFrameFn(self.ptr);
    }
};
