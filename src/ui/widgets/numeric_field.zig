const std = @import("std");
const types = @import("../core/types.zig");
const app = @import("../core/ui_context.zig");
const text_field = @import("text_field.zig");

pub const Options = struct {
    min: ?f32 = null,
    max: ?f32 = null,
    step: ?f32 = null,
    max_bytes: usize = 64,
    width: @import("../core/style.zig").Size = .fill,
};

pub const NumericResult = struct { changed: bool = false, committed: bool = false, invalid: bool = false };

pub const NumericField = struct {
    text: text_field.TextField,
    kind: Kind,
    invalid: bool = false,

    const Kind = enum { i32, u32, f32 };

    pub fn initI32(allocator: std.mem.Allocator, ui: *app.Ui, parent: types.NodeId, value: i32, options: Options) !NumericField {
        return initFormatted(allocator, ui, parent, .i32, value, options);
    }
    pub fn initU32(allocator: std.mem.Allocator, ui: *app.Ui, parent: types.NodeId, value: u32, options: Options) !NumericField {
        return initFormatted(allocator, ui, parent, .u32, value, options);
    }
    pub fn initF32(allocator: std.mem.Allocator, ui: *app.Ui, parent: types.NodeId, value: f32, options: Options) !NumericField {
        return initFormatted(allocator, ui, parent, .f32, value, options);
    }

    fn initFormatted(allocator: std.mem.Allocator, ui: *app.Ui, parent: types.NodeId, kind: Kind, value: anytype, options: Options) !NumericField {
        var buf: [64]u8 = undefined;
        const formatted = switch (kind) {
            .i32, .u32 => try std.fmt.bufPrint(&buf, "{d}", .{value}),
            .f32 => try std.fmt.bufPrint(&buf, "{d}", .{value}),
        };
        return .{ .text = try text_field.TextField.init(allocator, ui, parent, .{ .text = formatted, .max_bytes = options.max_bytes, .width = options.width }), .kind = kind };
    }

    pub fn deinit(self: *NumericField, ui: *app.Ui) void {
        self.text.deinit(ui);
        self.* = undefined;
    }

    pub fn updateI32(self: *NumericField, ui: *app.Ui, value: *i32, options: Options) !NumericResult {
        const event = try self.text.update(ui, fieldOptions(options, self.invalid));
        if (!event.committed) return .{ .changed = event.changed, .invalid = self.invalid };
        const parsed = std.fmt.parseInt(i32, self.text.text(), 10) catch {
            self.invalid = true;
            try self.syncValue(ui, value.*, options);
            return .{ .committed = true, .invalid = true };
        };
        var next: f32 = @floatFromInt(parsed);
        next = try applyHints(next, options);
        value.* = @intFromFloat(std.math.clamp(@round(next), @as(f32, @floatFromInt(std.math.minInt(i32))), @as(f32, @floatFromInt(std.math.maxInt(i32)))));
        self.invalid = false;
        try self.syncValue(ui, value.*, options);
        return .{ .changed = true, .committed = true };
    }

    pub fn updateU32(self: *NumericField, ui: *app.Ui, value: *u32, options: Options) !NumericResult {
        const event = try self.text.update(ui, fieldOptions(options, self.invalid));
        if (!event.committed) return .{ .changed = event.changed, .invalid = self.invalid };
        const parsed = std.fmt.parseInt(u32, self.text.text(), 10) catch {
            self.invalid = true;
            try self.syncValue(ui, value.*, options);
            return .{ .committed = true, .invalid = true };
        };
        var next: f32 = @floatFromInt(parsed);
        next = try applyHints(next, options);
        value.* = @intFromFloat(std.math.clamp(@round(next), 0, @as(f32, @floatFromInt(std.math.maxInt(u32)))));
        self.invalid = false;
        try self.syncValue(ui, value.*, options);
        return .{ .changed = true, .committed = true };
    }

    pub fn updateF32(self: *NumericField, ui: *app.Ui, value: *f32, options: Options) !NumericResult {
        const event = try self.text.update(ui, fieldOptions(options, self.invalid));
        if (!event.committed) return .{ .changed = event.changed, .invalid = self.invalid };
        const parsed = std.fmt.parseFloat(f32, self.text.text()) catch {
            self.invalid = true;
            try self.syncValue(ui, value.*, options);
            return .{ .committed = true, .invalid = true };
        };
        const next = applyHints(parsed, options) catch {
            self.invalid = true;
            try self.syncValue(ui, value.*, options);
            return .{ .committed = true, .invalid = true };
        };
        value.* = next;
        self.invalid = false;
        try self.syncValue(ui, value.*, options);
        return .{ .changed = true, .committed = true };
    }

    fn syncValue(self: *NumericField, ui: *app.Ui, value: anytype, options: Options) !void {
        var buf: [64]u8 = undefined;
        const formatted = try std.fmt.bufPrint(&buf, "{d}", .{value});
        try self.text.setTextContent(ui, formatted, options.max_bytes);
    }
};

fn fieldOptions(options: Options, invalid: bool) text_field.Options {
    return .{ .max_bytes = options.max_bytes, .width = options.width, .invalid = invalid };
}

pub fn commitFloat(text: []const u8, options: Options) !f32 {
    return applyHints(try std.fmt.parseFloat(f32, text), options);
}

fn applyHints(input: f32, options: Options) !f32 {
    if (!std.math.isFinite(input)) return error.NonFiniteValue;
    var value = input;
    if (options.min) |minimum| value = @max(minimum, value);
    if (options.max) |maximum| value = @min(maximum, value);
    if (options.step) |step| {
        if (step <= 0 or !std.math.isFinite(step)) return error.InvalidStep;
        value = @round(value / step) * step;
        if (options.min) |minimum| value = @max(minimum, value);
        if (options.max) |maximum| value = @min(maximum, value);
    }
    return value;
}

test "float commit is strict, finite, clamped, and stepped" {
    try std.testing.expectError(error.InvalidCharacter, commitFloat("1,5", .{}));
    try std.testing.expectError(error.NonFiniteValue, commitFloat("nan", .{}));
    try std.testing.expectEqual(@as(f32, 1.5), try commitFloat("1.6", .{ .min = 0, .max = 2, .step = 0.5 }));
    try std.testing.expectEqual(@as(f32, 2), try commitFloat("9", .{ .min = 0, .max = 2 }));
}

test "invalid numeric text rolls back without changing committed value" {
    var ui = try app.Ui.init(std.testing.allocator);
    defer ui.deinit();
    var field = try NumericField.initI32(std.testing.allocator, &ui, ui.rootNode(), 42, .{});
    defer field.deinit(&ui);
    try field.text.setTextContent(&ui, "not-a-number", 64);
    ui.requestFocus(field.text.root_node);
    var value: i32 = 42;
    try ui.beginFrame(.{ .window_size = .{ .x = 200, .y = 50 } });
    _ = try field.updateI32(&ui, &value, .{});
    try ui.beginFrame(.{ .events = &.{.{ .key_down = .enter }}, .window_size = .{ .x = 200, .y = 50 } });
    const result = try field.updateI32(&ui, &value, .{});
    try std.testing.expect(result.invalid);
    try std.testing.expectEqual(@as(i32, 42), value);
    try std.testing.expectEqualStrings("42", field.text.text());
}
