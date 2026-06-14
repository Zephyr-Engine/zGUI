const types = @import("../core/types.zig");

pub const Vertex = extern struct {
    pos: [2]f32,
    uv: [2]f32,
    color: u32,
};

pub const DrawBatch = struct {
    texture_id: u32 = 0,
    clip_rect: types.Rect = .{},
    index_offset: u32 = 0,
    index_count: u32 = 0,
};

pub const DrawData = struct {
    vertices: []const Vertex,
    indices: []const u32,
    batches: []const DrawBatch,

    pub const empty: DrawData = .{
        .vertices = &.{},
        .indices = &.{},
        .batches = &.{},
    };
};
