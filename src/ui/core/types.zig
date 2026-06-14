const std = @import("std");

pub const Vec2 = struct {
    x: f32 = 0,
    y: f32 = 0,

    pub fn splat(v: f32) Vec2 {
        return .{ .x = v, .y = v };
    }
};

pub const Rect = struct {
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,

    pub fn contains(self: Rect, p: Vec2) bool {
        return p.x >= self.x and p.x <= self.x + self.w and
            p.y >= self.y and p.y <= self.y + self.h;
    }

    pub fn isEmpty(self: Rect) bool {
        return self.w <= 0 or self.h <= 0;
    }

    pub fn inset(self: Rect, edges: anytype) Rect {
        return .{
            .x = self.x + edges.left,
            .y = self.y + edges.top,
            .w = @max(0, self.w - edges.left - edges.right),
            .h = @max(0, self.h - edges.top - edges.bottom),
        };
    }
};

pub const Color = packed struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 255,

    pub fn rgba(r: u8, g: u8, b: u8, a: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn toU32(self: Color) u32 {
        return (@as(u32, self.a) << 24) |
            (@as(u32, self.b) << 16) |
            (@as(u32, self.g) << 8) |
            @as(u32, self.r);
    }
};

pub const NodeId = u32;
pub const WindowId = u32;
pub const DockNodeId = u32;

pub const invalid_node: NodeId = std.math.maxInt(NodeId);
pub const invalid_window: WindowId = std.math.maxInt(WindowId);
pub const invalid_dock_node: DockNodeId = std.math.maxInt(DockNodeId);

test "rect hit testing includes edges" {
    const rect: Rect = .{ .x = 10, .y = 20, .w = 30, .h = 40 };
    try std.testing.expect(rect.contains(.{ .x = 10, .y = 20 }));
    try std.testing.expect(rect.contains(.{ .x = 40, .y = 60 }));
    try std.testing.expect(!rect.contains(.{ .x = 41, .y = 60 }));
    try std.testing.expect(!rect.contains(.{ .x = 40, .y = 61 }));
}
