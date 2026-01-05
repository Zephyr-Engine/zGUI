const std = @import("std");
const shapes = @import("../shapes.zig");

pub const DockNodeType = enum {
    split,
    tab_group,
};

pub const SplitDirection = enum {
    horizontal, // Left/right split
    vertical, // Top/bottom split
};

pub const Split = struct {
    direction: SplitDirection,
    ratio: f32, // 0.0 to 1.0, size of first child
    first: *DockNode,
    second: *DockNode,
};

pub const TabGroup = struct {
    panel_ids: std.ArrayList(u64),
    active_index: usize,
};

pub const DockNode = struct {
    node_type: DockNodeType,
    split: ?Split = null,
    tab_group: ?TabGroup = null,
    cached_rect: shapes.Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
    allocator: std.mem.Allocator,

    /// Create a split node
    pub fn initSplit(
        allocator: std.mem.Allocator,
        direction: SplitDirection,
        ratio: f32,
        first: *DockNode,
        second: *DockNode,
    ) !*DockNode {
        const node = try allocator.create(DockNode);
        node.* = .{
            .node_type = .split,
            .split = Split{
                .direction = direction,
                .ratio = ratio,
                .first = first,
                .second = second,
            },
            .allocator = allocator,
        };
        return node;
    }

    /// Create a tab group node
    pub fn initTabGroup(
        allocator: std.mem.Allocator,
        initial_panel_id: u64,
    ) !*DockNode {
        var panel_ids = try std.ArrayList(u64).initCapacity(allocator, 4);
        try panel_ids.append(allocator, initial_panel_id);

        const node = try allocator.create(DockNode);
        node.* = .{
            .node_type = .tab_group,
            .tab_group = TabGroup{
                .panel_ids = panel_ids,
                .active_index = 0,
            },
            .allocator = allocator,
        };
        return node;
    }

    /// Recursively free the node and all children
    pub fn deinit(self: *DockNode) void {
        switch (self.node_type) {
            .split => {
                if (self.split) |split_info| {
                    split_info.first.deinit();
                    split_info.second.deinit();
                }
            },
            .tab_group => {
                if (self.tab_group) |*group| {
                    group.panel_ids.deinit(self.allocator);
                }
            },
        }
        self.allocator.destroy(self);
    }

    /// Find the node containing a specific panel ID
    pub fn findNodeContainingPanel(self: *DockNode, panel_id: u64) ?*DockNode {
        switch (self.node_type) {
            .split => {
                if (self.split) |split_info| {
                    if (split_info.first.findNodeContainingPanel(panel_id)) |node| {
                        return node;
                    }
                    if (split_info.second.findNodeContainingPanel(panel_id)) |node| {
                        return node;
                    }
                }
            },
            .tab_group => {
                if (self.tab_group) |group| {
                    for (group.panel_ids.items) |id| {
                        if (id == panel_id) {
                            return self;
                        }
                    }
                }
            },
        }
        return null;
    }

    /// Find the leaf node at a screen position (for drop targeting)
    pub fn findNodeAtPosition(self: *DockNode, x: f32, y: f32) ?*DockNode {
        // Check if position is within this node's cached rect
        const rect = self.cached_rect;
        if (x < rect.x or x > rect.x + rect.w or y < rect.y or y > rect.y + rect.h) {
            return null;
        }

        switch (self.node_type) {
            .split => {
                if (self.split) |split_info| {
                    // Check children (they have more specific rects)
                    if (split_info.first.findNodeAtPosition(x, y)) |node| {
                        return node;
                    }
                    if (split_info.second.findNodeAtPosition(x, y)) |node| {
                        return node;
                    }
                }
            },
            .tab_group => {
                // This is a leaf, return it
                return self;
            },
        }
        return null;
    }

    /// Remove a panel from the tree
    /// Returns true if this node should be removed (empty tab group)
    pub fn removePanel(self: *DockNode, panel_id: u64) bool {
        if (self.node_type != .tab_group) {
            return false;
        }

        if (self.tab_group) |*group| {
            // Find and remove the panel
            for (group.panel_ids.items, 0..) |id, i| {
                if (id == panel_id) {
                    _ = group.panel_ids.orderedRemove(i);

                    // Adjust active index if needed
                    if (group.active_index >= group.panel_ids.items.len and group.panel_ids.items.len > 0) {
                        group.active_index = group.panel_ids.items.len - 1;
                    }

                    // Return true if tab group is now empty
                    return group.panel_ids.items.len == 0;
                }
            }
        }
        return false;
    }

    /// Clone a node (deep copy for tree manipulation)
    pub fn clone(self: *DockNode, allocator: std.mem.Allocator) !*DockNode {
        switch (self.node_type) {
            .split => {
                if (self.split) |split_info| {
                    const first_clone = try split_info.first.clone(allocator);
                    const second_clone = try split_info.second.clone(allocator);
                    return try initSplit(
                        allocator,
                        split_info.direction,
                        split_info.ratio,
                        first_clone,
                        second_clone,
                    );
                }
            },
            .tab_group => {
                if (self.tab_group) |group| {
                    var panel_ids = try std.ArrayList(u64).initCapacity(allocator, group.panel_ids.items.len);
                    try panel_ids.appendSlice(allocator, group.panel_ids.items);

                    const node = try allocator.create(DockNode);
                    node.* = .{
                        .node_type = .tab_group,
                        .tab_group = TabGroup{
                            .panel_ids = panel_ids,
                            .active_index = group.active_index,
                        },
                        .allocator = allocator,
                    };
                    return node;
                }
            },
        }
        unreachable;
    }
};
