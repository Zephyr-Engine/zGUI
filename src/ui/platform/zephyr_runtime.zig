const std = @import("std");
const types = @import("../core/types.zig");
const ui_context = @import("../core/ui_context.zig");
const events = @import("events.zig");

pub const PixelSize = struct {
    width: u32,
    height: u32,
};

pub const Frame = struct {
    events: []const events.PlatformEvent,
    window_size: types.Vec2,
    framebuffer_size: PixelSize,
    text_raster_scale: f32,
    dt: f32,

    pub fn toBeginFrame(self: Frame) ui_context.BeginFrame {
        return .{
            .events = self.events,
            .window_size = self.window_size,
            .dt = self.dt,
        };
    }
};

pub const Backend = struct {
    allocator: std.mem.Allocator,
    events: std.ArrayList(events.PlatformEvent) = .empty,
    text_buffer: std.ArrayList(u8) = .empty,

    pub fn init(allocator: std.mem.Allocator) Backend {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Backend) void {
        self.events.deinit(self.allocator);
        self.text_buffer.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn beginFrame(self: *Backend, app: anytype, runtime_events: anytype) !Frame {
        const window_size = toUiSize(app.window.getWindowSize());
        const framebuffer_size = toPixelSize(app.window.getFramebufferSize());

        return .{
            .events = try self.translateEvents(runtime_events),
            .window_size = window_size,
            .framebuffer_size = framebuffer_size,
            .text_raster_scale = framebufferScale(window_size, framebuffer_size),
            .dt = app.time.delta_time,
        };
    }

    pub fn translateEvents(self: *Backend, runtime_events: anytype) ![]const events.PlatformEvent {
        self.events.clearRetainingCapacity();
        self.text_buffer.clearRetainingCapacity();
        try self.reserveTextInput(runtime_events);

        for (runtime_events) |event| {
            if (try self.toPlatformEvent(event)) |platform_event| {
                try self.events.append(self.allocator, platform_event);
            }
        }
        return self.events.items;
    }

    fn reserveTextInput(self: *Backend, runtime_events: anytype) !void {
        var max_text_bytes: usize = 0;
        for (runtime_events) |event| {
            switch (event) {
                .CharInput => max_text_bytes += 4,
                else => {},
            }
        }
        try self.text_buffer.ensureTotalCapacity(self.allocator, max_text_bytes);
    }

    fn toPlatformEvent(self: *Backend, event: anytype) !?events.PlatformEvent {
        return switch (event) {
            .MouseMove => |pos| .{ .mouse_move = .{ .x = pos.x, .y = pos.y } },
            .MousePressed => |button| .{ .mouse_down = mapMouseButton(button) orelse return null },
            .MouseReleased => |button| .{ .mouse_up = mapMouseButton(button) orelse return null },
            .MouseScroll => |scroll| .{ .scroll = .{ .x = scroll.x, .y = scroll.y } },
            .KeyPressed => |key| .{ .key_down = mapKey(key) },
            .KeyRepeated => |key| .{ .key_down = mapKey(key) },
            .KeyReleased => |key| .{ .key_up = mapKey(key) },
            .CharInput => |codepoint| try self.textInputEvent(codepoint),
            .WindowResize => |resize| .{ .window_resize = .{ .x = @floatFromInt(resize.width), .y = @floatFromInt(resize.height) } },
            .WindowClose => .window_close,
            .FramebufferResize, .ContentScaleChange => null,
        };
    }

    fn textInputEvent(self: *Backend, codepoint: anytype) !?events.PlatformEvent {
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(@intCast(codepoint), &buf) catch return null;
        const start = self.text_buffer.items.len;
        try self.text_buffer.appendSlice(self.allocator, buf[0..len]);
        return .{ .text_input = self.text_buffer.items[start .. start + len] };
    }
};

pub const SceneInputCapture = struct {
    active: bool = false,

    pub fn accepts(self: *SceneInputCapture, event: anytype, viewport_rect: types.Rect, mouse_pos: types.Vec2) bool {
        const mouse_in_viewport = viewport_rect.contains(mouse_pos);
        return switch (event) {
            .MouseMove => true,
            .MousePressed => pressed: {
                if (mouse_in_viewport) {
                    self.active = true;
                    break :pressed true;
                }
                break :pressed false;
            },
            .MouseReleased => released: {
                const was_active = self.active;
                self.active = false;
                break :released was_active or mouse_in_viewport;
            },
            .MouseScroll => self.active or mouse_in_viewport,
            .KeyPressed, .KeyReleased, .KeyRepeated => self.active or mouse_in_viewport,
            .WindowResize, .FramebufferResize, .ContentScaleChange, .WindowClose => true,
            .CharInput => false,
        };
    }
};

pub fn processSceneEvents(
    app: anytype,
    runtime_events: anytype,
    viewport_rect: types.Rect,
    mouse_pos: types.Vec2,
    capture: *SceneInputCapture,
) !void {
    for (runtime_events) |event| {
        if (capture.accepts(event, viewport_rect, mouse_pos)) {
            try app.processEvent(event);
        }
    }
}

pub fn setCursor(window: anytype, cursor: events.CursorKind) void {
    switch (cursor) {
        .arrow => window.setCursor(.arrow),
        .hand => window.setCursor(.hand),
        .text => window.setCursor(.text),
        .resize_x => window.setCursor(.resize_x),
        .resize_y => window.setCursor(.resize_y),
        .resize_diag_a, .resize_diag_b => window.setCursor(.arrow),
    }
}

pub fn toUiSize(size: anytype) types.Vec2 {
    return .{
        .x = @floatFromInt(size.width),
        .y = @floatFromInt(size.height),
    };
}

pub fn toPixelSize(size: anytype) PixelSize {
    return .{
        .width = size.width,
        .height = size.height,
    };
}

pub fn viewportSize(framebuffer: anytype) PixelSize {
    return .{
        .width = framebuffer.width,
        .height = framebuffer.height,
    };
}

pub fn renderSizeForRect(rect: types.Rect, scale: f32) PixelSize {
    return .{
        .width = @intFromFloat(@max(1, @round(rect.w * scale))),
        .height = @intFromFloat(@max(1, @round(rect.h * scale))),
    };
}

pub fn framebufferScale(window_size: types.Vec2, framebuffer_size: PixelSize) f32 {
    const framebuffer_width: f32 = @floatFromInt(framebuffer_size.width);
    const framebuffer_height: f32 = @floatFromInt(framebuffer_size.height);
    const x = framebuffer_width / @max(1, window_size.x);
    const y = framebuffer_height / @max(1, window_size.y);
    return @max(0.25, @max(x, y));
}

fn mapMouseButton(button: anytype) ?events.MouseButton {
    return switch (button) {
        .Left => .left,
        .Right => .right,
        .Middle => .middle,
        else => null,
    };
}

fn mapKey(key: anytype) events.Key {
    return switch (key) {
        .Escape => .escape,
        .Enter => .enter,
        .Tab => .tab,
        .Backspace => .backspace,
        .Delete => .delete,
        .Left => .left,
        .Right => .right,
        .Up => .up,
        .Down => .down,
        .A => .a,
        .B => .b,
        .C => .c,
        else => .unknown,
    };
}
