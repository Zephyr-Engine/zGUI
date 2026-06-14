const std = @import("std");
const types = @import("../core/types.zig");

pub const Axis = enum {
    x,
    y,
};

pub const DockPosition = enum {
    left,
    right,
    top,
    bottom,
    center_tab,
};

pub const DockNode = union(enum) {
    leaf: DockLeaf,
    split: DockSplit,

    pub fn deinit(self: *DockNode, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .leaf => |*leaf| leaf.tabs.deinit(allocator),
            .split => {},
        }
    }
};

pub const DockLeaf = struct {
    rect: types.Rect = .{},
    tabs: std.ArrayList(types.WindowId) = .empty,
    active_tab: usize = 0,
};

pub const DockSplit = struct {
    axis: Axis,
    ratio: f32 = 0.5,
    min_first_size: f32 = 0,
    min_second_size: f32 = 0,
    first: types.DockNodeId,
    second: types.DockNodeId,
    rect: types.Rect = .{},
};
