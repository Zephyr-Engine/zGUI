const std = @import("std");
const types = @import("../core/types.zig");
const app = @import("../core/ui_context.zig");
const primitives = @import("primitives.zig");
const dirty = @import("../core/dirty.zig");

pub const Options = struct {
    min: f32,
    max: f32,
    step: f32 = 0,
    width: @import("../core/style.zig").Size = .fill,
};

pub const Slider = struct {
    root_node: types.NodeId,
    fill_node: types.NodeId,
    knob_node: types.NodeId,
    dragging: bool = false,

    pub fn init(ui: *app.Ui, parent: types.NodeId, options: Options) !Slider {
        if (!validOptions(options)) return error.InvalidSliderBounds;
        const root = try primitives.surface(ui, parent, .{
            .width = options.width,
            .height = .{ .px = 24 },
            .direction = .absolute,
            .padding = .{ .top = 9, .bottom = 9 },
        });
        errdefer ui.destroySubtree(root);
        const node = ui.tree.get(root).?;
        node.flags.interactive = true;
        node.flags.focusable = true;
        const track = try primitives.surface(ui, root, .{ .width = .fill, .height = .{ .px = 6 }, .background = .stroke, .radius = .pill });
        const fill = try primitives.surface(ui, track, .{ .width = .{ .px = 0 }, .height = .fill, .background = .accent, .radius = .pill });
        const knob = try primitives.surface(ui, root, .{ .width = .{ .px = 14 }, .height = .{ .px = 14 }, .margin = .{ .top = -4 }, .background = .text, .border = .accent, .border_width = 2, .radius = .round });
        return .{ .root_node = root, .fill_node = fill, .knob_node = knob };
    }

    pub fn deinit(self: *Slider, ui: *app.Ui) void {
        ui.destroySubtree(self.root_node);
        self.* = undefined;
    }

    pub fn update(self: *Slider, ui: *app.Ui, value: *f32, options: Options) !bool {
        if (!validOptions(options)) return error.InvalidSliderBounds;
        var changed = false;
        if (ui.mousePressed(.left) and ui.input.hovered == self.root_node) {
            self.dragging = true;
            ui.requestFocus(self.root_node);
        }
        if (self.dragging and ui.mouseDown(.left)) {
            const bounds = ui.bounds(self.root_node) orelse return false;
            const ratio = std.math.clamp((ui.mousePosition().x - bounds.x) / @max(1, bounds.w), 0, 1);
            const next = quantize(options.min + ratio * (options.max - options.min), options);
            if (next != value.*) {
                value.* = next;
                changed = true;
            }
            ui.capturePointer();
        }
        if (ui.mouseReleased(.left)) self.dragging = false;
        if (ui.isFocused(self.root_node)) {
            const amount = if (options.step > 0) options.step else (options.max - options.min) / 100;
            if (ui.keyPressed(.left) or ui.keyPressed(.down)) {
                const next = quantize(value.* - amount, options);
                if (next != value.*) {
                    value.* = next;
                    changed = true;
                }
            }
            if (ui.keyPressed(.right) or ui.keyPressed(.up)) {
                const next = quantize(value.* + amount, options);
                if (next != value.*) {
                    value.* = next;
                    changed = true;
                }
            }
            if (ui.keyPressed(.home) and value.* != options.min) {
                value.* = options.min;
                changed = true;
            }
            if (ui.keyPressed(.end) and value.* != options.max) {
                value.* = options.max;
                changed = true;
            }
        }
        value.* = quantize(value.*, options);
        const ratio = (value.* - options.min) / (options.max - options.min);
        const bounds = ui.bounds(self.root_node) orelse types.Rect{};
        const fill = ui.tree.get(self.fill_node).?;
        const knob = ui.tree.get(self.knob_node).?;
        const width = @max(0, bounds.w * ratio);
        if (!std.meta.eql(fill.style.width, @as(@TypeOf(fill.style.width), .{ .px = width }))) {
            fill.style.width = .{ .px = width };
            knob.style.margin.left = @max(0, width - 7);
            dirty.markLayoutDirty(&ui.tree, self.root_node);
        }
        return changed;
    }
};

fn validOptions(options: Options) bool {
    return std.math.isFinite(options.min) and std.math.isFinite(options.max) and options.min < options.max and options.step >= 0;
}

fn quantize(value: f32, options: Options) f32 {
    var result = std.math.clamp(value, options.min, options.max);
    if (options.step > 0) result = options.min + @round((result - options.min) / options.step) * options.step;
    return std.math.clamp(result, options.min, options.max);
}

test "slider quantization is deterministic" {
    try std.testing.expectEqual(@as(f32, 0.25), quantize(0.26, .{ .min = 0, .max = 1, .step = 0.25 }));
    try std.testing.expectEqual(@as(f32, 1), quantize(2, .{ .min = 0, .max = 1 }));
}
