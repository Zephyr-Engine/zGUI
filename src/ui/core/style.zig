const types = @import("types.zig");

pub const Size = union(enum) {
    px: f32,
    percent: f32,
    fill,
    hug,
};

pub const LayoutDirection = enum {
    row,
    column,
    absolute,
};

pub const Edges = struct {
    left: f32 = 0,
    right: f32 = 0,
    top: f32 = 0,
    bottom: f32 = 0,

    pub fn all(v: f32) Edges {
        return .{ .left = v, .right = v, .top = v, .bottom = v };
    }

    pub fn horizontal(self: Edges) f32 {
        return self.left + self.right;
    }

    pub fn vertical(self: Edges) f32 {
        return self.top + self.bottom;
    }
};

pub const Style = struct {
    width: Size = .hug,
    height: Size = .hug,

    min_width: f32 = 0,
    min_height: f32 = 0,

    padding: Edges = .{},
    margin: Edges = .{},
    gap: f32 = 0,

    direction: LayoutDirection = .column,

    background: types.Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    foreground: types.Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },

    border_color: types.Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    border_width: f32 = 0,
    border_edges: ?Edges = null,
    radius: f32 = 0,

    font_size: f32 = 16,
};
