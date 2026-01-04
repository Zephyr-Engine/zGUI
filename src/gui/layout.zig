const std = @import("std");
const GuiContext = @import("context.zig").GuiContext;
const shapes = @import("shapes.zig");

pub const Direction = enum {
    HORIZONTAL,
    VERTICAL,
};

pub const Alignment = enum {
    LEFT,
    CENTER,
    RIGHT,
    TOP,
    BOTTOM,
};

pub const Spacing = struct {
    top: f32,
    right: f32,
    bottom: f32,
    left: f32,

    pub fn all(value: f32) Spacing {
        return .{ .top = value, .right = value, .bottom = value, .left = value };
    }

    pub fn symmetric(vertical: f32, horizontal: f32) Spacing {
        return .{ .top = vertical, .right = horizontal, .bottom = vertical, .left = horizontal };
    }

    pub fn only(comptime args: anytype) Spacing {
        var spacing = Spacing{ .top = 0, .right = 0, .bottom = 0, .left = 0 };
        if (@hasField(@TypeOf(args), "top")) spacing.top = args.top;
        if (@hasField(@TypeOf(args), "right")) spacing.right = args.right;
        if (@hasField(@TypeOf(args), "bottom")) spacing.bottom = args.bottom;
        if (@hasField(@TypeOf(args), "left")) spacing.left = args.left;
        return spacing;
    }
};

pub const LayoutOptions = struct {
    margin: Spacing = Spacing.all(0.0),
    padding: Spacing = Spacing.all(0.0),
    width: ?f32 = null, // Fixed width (null = auto)
    height: ?f32 = null, // Fixed height (null = auto)
    align_horizontal: ?Alignment = null, // Horizontal alignment (LEFT, CENTER, RIGHT)
    align_vertical: ?Alignment = null, // Vertical alignment (TOP, CENTER, BOTTOM)
};

pub const Layout = struct {
    direction: Direction,
    x: f32,
    y: f32,
    current_x: f32,
    current_y: f32,
    margin: Spacing,
    padding: Spacing,
    max_cross_size: f32, // max height for horizontal, max width for vertical
    width: ?f32, // Fixed width (null = auto)
    height: ?f32, // Fixed height (null = auto)
    align_horizontal: ?Alignment, // Horizontal alignment
    align_vertical: ?Alignment, // Vertical alignment

    pub fn init(direction: Direction, x: f32, y: f32, opts: LayoutOptions) Layout {
        return Layout{
            .direction = direction,
            .x = x,
            .y = y,
            .current_x = x + opts.padding.left,
            .current_y = y + opts.padding.top,
            .margin = opts.margin,
            .padding = opts.padding,
            .max_cross_size = 0.0,
            .width = opts.width,
            .height = opts.height,
            .align_horizontal = opts.align_horizontal,
            .align_vertical = opts.align_vertical,
        };
    }

    pub fn allocateSpace(self: *Layout, ctx: *const GuiContext, width: f32, height: f32) shapes.Rect {
        switch (self.direction) {
            .HORIZONTAL => self.current_x += self.margin.left,
            .VERTICAL => self.current_y += self.margin.top,
        }

        var x = self.current_x;
        var y = self.current_y;

        if (self.align_vertical) |v_align| {
            const available_height = (self.height orelse ctx.window_height) - (self.padding.top + self.padding.bottom);
            switch (v_align) {
                .TOP => {}, // Default, no adjustment
                .CENTER => y += (available_height - height) * 0.5,
                .BOTTOM => y += available_height - height,
                else => {}, // LEFT/RIGHT not applicable for vertical alignment
            }
        }

        if (self.align_horizontal) |h_align| {
            const available_width = (self.width orelse ctx.window_width) - (self.padding.left + self.padding.right);
            switch (h_align) {
                .LEFT => {}, // Default, no adjustment
                .CENTER => x += (available_width - width) * 0.5,
                .RIGHT => x += available_width - width,
                else => {}, // TOP/BOTTOM not applicable for horizontal alignment
            }
        }

        const rect = shapes.Rect{
            .x = x,
            .y = y,
            .w = width,
            .h = height,
        };

        switch (self.direction) {
            .HORIZONTAL => {
                self.current_x += width + self.margin.right;
                self.max_cross_size = @max(self.max_cross_size, height);
            },
            .VERTICAL => {
                self.current_y += height + self.margin.bottom;
                self.max_cross_size = @max(self.max_cross_size, width);
            },
        }

        return rect;
    }

    pub fn getCurrentPos(self: *const Layout) struct { x: f32, y: f32 } {
        return .{ .x = self.current_x, .y = self.current_y };
    }

    pub fn skip(self: *Layout, amount: f32) void {
        switch (self.direction) {
            .HORIZONTAL => self.current_x += amount,
            .VERTICAL => self.current_y += amount,
        }
    }
};

pub fn getBounds(layout: *const Layout) shapes.Rect {
    const auto_width = switch (layout.direction) {
        .HORIZONTAL => layout.current_x - layout.x + layout.padding.right,
        .VERTICAL => layout.max_cross_size + layout.padding.left + layout.padding.right,
    };
    const auto_height = switch (layout.direction) {
        .HORIZONTAL => layout.max_cross_size + layout.padding.top + layout.padding.bottom,
        .VERTICAL => layout.current_y - layout.y + layout.padding.bottom,
    };

    return shapes.Rect{
        .x = layout.x,
        .y = layout.y,
        .w = layout.width orelse auto_width,
        .h = layout.height orelse auto_height,
    };
}

pub fn hLayout(ctx: *GuiContext, opts: LayoutOptions) Layout {
    return layoutHelper(ctx, .HORIZONTAL, opts);
}

pub fn vLayout(ctx: *GuiContext, opts: LayoutOptions) Layout {
    return layoutHelper(ctx, .VERTICAL, opts);
}

fn layoutHelper(ctx: *GuiContext, direction: Direction, opts: LayoutOptions) Layout {
    const width: f32 = opts.width orelse ctx.window_width;
    const height: f32 = opts.height orelse ctx.window_height;
    const rect = ctx.getCurrentLayout().allocateSpace(ctx, width, height);

    return Layout.init(direction, rect.x, rect.y, opts);
}

pub fn beginLayout(ctx: *GuiContext, layout: Layout) void {
    ctx.layout_stack.append(ctx.allocator, layout) catch {};
}

pub fn endLayout(ctx: *GuiContext) void {
    const finished_layout = ctx.layout_stack.pop().?;
    const bounds = getBounds(&finished_layout);

    // Update parent layout's position if there is one
    if (ctx.layout_stack.items.len > 0) {
        const parent_layout = ctx.getCurrentLayout();
        // Ensure parent's position is at least at the end of the finished layout
        // This handles manually positioned nested layouts (like collapsible content)
        switch (parent_layout.direction) {
            .VERTICAL => parent_layout.current_y = @max(parent_layout.current_y, bounds.y + bounds.h),
            .HORIZONTAL => parent_layout.current_x = @max(parent_layout.current_x, bounds.x + bounds.w),
        }
    }

    if (ctx.current_panel_id) |panel_id| {
        const content_width = switch (finished_layout.direction) {
            .HORIZONTAL => finished_layout.current_x - finished_layout.x + finished_layout.padding.right,
            .VERTICAL => finished_layout.max_cross_size + finished_layout.padding.left + finished_layout.padding.right,
        };
        const content_height = switch (finished_layout.direction) {
            .HORIZONTAL => finished_layout.max_cross_size + finished_layout.padding.top + finished_layout.padding.bottom,
            .VERTICAL => finished_layout.current_y - finished_layout.y + finished_layout.padding.bottom,
        };

        if (ctx.panel_sizes.getPtr(panel_id)) |panel_size| {
            panel_size.min_width = content_width;
            panel_size.min_height = content_height;
        } else {
            ctx.panel_sizes.put(panel_id, .{
                .width = null,
                .height = null,
                .min_width = content_width,
                .min_height = content_height,
            }) catch {};
        }
        ctx.current_panel_id = null;
    }

    ctx.updateLayoutPos(bounds);
}
