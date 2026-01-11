const std = @import("std");
const DockNode = @import("dock_node.zig").DockNode;
const SplitDirection = @import("dock_node.zig").SplitDirection;
const shapes = @import("../shapes.zig");

pub const DockSpace = struct {
    root: ?*DockNode = null,
    bounds: shapes.Rect,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, bounds: shapes.Rect) DockSpace {
        return .{
            .allocator = allocator,
            .bounds = bounds,
        };
    }

    pub fn deinit(self: *DockSpace) void {
        if (self.root) |root| {
            root.deinit();
        }
    }

    /// Add a panel to the dock space
    /// If root is null, creates a tab group as root
    /// Otherwise, appends to root if it's a tab group, or finds first tab group in tree
    pub fn addPanel(self: *DockSpace, panel_id: u64) !void {
        if (self.root == null) {
            // Create root tab group
            self.root = try DockNode.initTabGroup(self.allocator, panel_id);
        } else if (self.root.?.node_type == .tab_group) {
            // Add to existing root tab group
            if (self.root.?.tab_group) |*group| {
                try group.panel_ids.append(self.allocator, panel_id);
            }
        } else {
            // Root is a split - find the first tab group leaf node
            if (findFirstTabGroup(self.root.?)) |tab_group_node| {
                if (tab_group_node.tab_group) |*group| {
                    try group.panel_ids.append(self.allocator, panel_id);
                }
            } else {
                // No tab groups exist - this shouldn't happen in a valid tree
                return error.NoTabGroupFound;
            }
        }
    }

    /// Calculate layout for all nodes (sets cached_rect on all nodes)
    pub fn updateLayout(self: *DockSpace) !void {
        if (self.root) |root| {
            updateLayoutRecursive(root, self.bounds);
        }
    }

    /// Find the leaf node at a screen position
    pub fn findLeafAtPosition(self: *DockSpace, x: f32, y: f32) ?*DockNode {
        if (self.root) |root| {
            return root.findNodeAtPosition(x, y);
        }
        return null;
    }
};

/// Recursive layout calculation
fn updateLayoutRecursive(node: *DockNode, bounds: shapes.Rect) void {
    node.cached_rect = bounds;

    switch (node.node_type) {
        .tab_group => {
            // Leaf node, layout is just the bounds
        },
        .split => {
            if (node.split) |*split_info| {
                const splitter_thickness = 4.0;

                switch (split_info.direction) {
                    .horizontal => {
                        const first_width = (bounds.w - splitter_thickness) * split_info.ratio;
                        const second_width = bounds.w - first_width - splitter_thickness;

                        const first_bounds = shapes.Rect{
                            .x = bounds.x,
                            .y = bounds.y,
                            .w = first_width,
                            .h = bounds.h,
                        };

                        const second_bounds = shapes.Rect{
                            .x = bounds.x + first_width + splitter_thickness,
                            .y = bounds.y,
                            .w = second_width,
                            .h = bounds.h,
                        };

                        updateLayoutRecursive(split_info.first, first_bounds);
                        updateLayoutRecursive(split_info.second, second_bounds);
                    },
                    .vertical => {
                        const first_height = (bounds.h - splitter_thickness) * split_info.ratio;
                        const second_height = bounds.h - first_height - splitter_thickness;

                        const first_bounds = shapes.Rect{
                            .x = bounds.x,
                            .y = bounds.y,
                            .w = bounds.w,
                            .h = first_height,
                        };

                        const second_bounds = shapes.Rect{
                            .x = bounds.x,
                            .y = bounds.y + first_height + splitter_thickness,
                            .w = bounds.w,
                            .h = second_height,
                        };

                        updateLayoutRecursive(split_info.first, first_bounds);
                        updateLayoutRecursive(split_info.second, second_bounds);
                    },
                }
            }
        },
    }
}

/// Find the first tab group node in the tree (depth-first search)
fn findFirstTabGroup(node: *DockNode) ?*DockNode {
    switch (node.node_type) {
        .tab_group => return node,
        .split => {
            if (node.split) |split_info| {
                // Search left subtree first
                if (findFirstTabGroup(split_info.first)) |found| {
                    return found;
                }
                // Then search right subtree
                if (findFirstTabGroup(split_info.second)) |found| {
                    return found;
                }
            }
            return null;
        },
    }
}
