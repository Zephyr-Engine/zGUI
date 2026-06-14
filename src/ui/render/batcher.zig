const std = @import("std");
const types = @import("../core/types.zig");
const text_mod = @import("../core/text.zig");
const paint = @import("../core/paint.zig");
const draw_data = @import("draw_data.zig");
const font_atlas_mod = @import("font_atlas.zig");

const white_texture_id: u32 = 0;
const default_clip: types.Rect = .{ .x = 0, .y = 0, .w = 100000, .h = 100000 };
const rounded_corner_segments: usize = 10;
const rounded_point_count: usize = 4 * (rounded_corner_segments + 1);
const max_antialias_width: f32 = 1;

pub const FontAtlas = font_atlas_mod.FontAtlas;

pub const Batcher = struct {
    allocator: std.mem.Allocator,
    vertices: std.ArrayList(draw_data.Vertex) = .empty,
    indices: std.ArrayList(u32) = .empty,
    batches: std.ArrayList(draw_data.DrawBatch) = .empty,
    clip_stack: std.ArrayList(types.Rect) = .empty,
    antialias_width: f32 = max_antialias_width,

    pub fn init(allocator: std.mem.Allocator) Batcher {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Batcher) void {
        self.vertices.deinit(self.allocator);
        self.indices.deinit(self.allocator);
        self.batches.deinit(self.allocator);
        self.clip_stack.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn clearRetainingCapacity(self: *Batcher) void {
        self.vertices.clearRetainingCapacity();
        self.indices.clearRetainingCapacity();
        self.batches.clearRetainingCapacity();
        self.clip_stack.clearRetainingCapacity();
    }

    pub fn build(self: *Batcher, commands: []const paint.PaintCommand, font_atlas: ?*FontAtlas, text_raster_scale: f32) !draw_data.DrawData {
        self.clearRetainingCapacity();
        self.antialias_width = antialiasWidth(text_raster_scale);

        for (commands) |command| {
            switch (command) {
                .rect => |rect| try self.addFilledRect(rect.rect, rect.color, rect.radius),
                .border => |border| try self.addBorder(border),
                .image => |image| try self.addImage(image),
                .text => |text| {
                    if (font_atlas) |atlas| {
                        try self.addText(text, atlas, text_raster_scale);
                    }
                },
                .clip_push => |clip| try self.clip_stack.append(self.allocator, clip),
                .clip_pop => _ = self.clip_stack.pop(),
            }
        }

        return .{
            .vertices = self.vertices.items,
            .indices = self.indices.items,
            .batches = self.batches.items,
        };
    }

    fn addFilledRect(self: *Batcher, rect: types.Rect, color: types.Color, radius: f32) !void {
        if (rect.isEmpty() or color.a == 0) return;
        if (clampedRadius(rect, radius) > 0) {
            try self.addRoundedTexturedRect(
                rect,
                .{ .x = 0, .y = 0 },
                .{ .x = 1, .y = 1 },
                color,
                white_texture_id,
                radius,
            );
            return;
        }

        try self.addTexturedRect(
            rect,
            .{ .x = 0, .y = 0 },
            .{ .x = 1, .y = 1 },
            color,
            white_texture_id,
        );
    }

    fn addBorder(self: *Batcher, border: paint.BorderPaint) !void {
        const r = border.rect;
        const widths = border.widths;
        if (uniformBorderWidth(widths)) |width| {
            if (width > 0 and clampedRadius(r, border.radius) > 0) {
                try self.addRoundedBorder(border, width);
                return;
            }
        }

        if (widths.top > 0) {
            try self.addFilledRect(.{ .x = r.x, .y = r.y, .w = r.w, .h = widths.top }, border.color, 0);
        }
        if (widths.bottom > 0) {
            try self.addFilledRect(.{ .x = r.x, .y = r.y + r.h - widths.bottom, .w = r.w, .h = widths.bottom }, border.color, 0);
        }

        const side_y = r.y + widths.top;
        const side_h = @max(0, r.h - widths.top - widths.bottom);
        if (widths.left > 0) {
            try self.addFilledRect(.{ .x = r.x, .y = side_y, .w = widths.left, .h = side_h }, border.color, 0);
        }
        if (widths.right > 0) {
            try self.addFilledRect(.{ .x = r.x + r.w - widths.right, .y = side_y, .w = widths.right, .h = side_h }, border.color, 0);
        }
    }

    fn addRoundedBorder(self: *Batcher, border: paint.BorderPaint, width: f32) !void {
        const outer = border.rect;
        if (outer.isEmpty() or border.color.a == 0) return;

        const border_width = @min(width, @min(outer.w, outer.h) * 0.5);
        const inner: types.Rect = .{
            .x = outer.x + border_width,
            .y = outer.y + border_width,
            .w = @max(0, outer.w - border_width * 2),
            .h = @max(0, outer.h - border_width * 2),
        };

        if (inner.isEmpty()) {
            try self.addRoundedTexturedRect(
                outer,
                .{ .x = 0, .y = 0 },
                .{ .x = 1, .y = 1 },
                border.color,
                white_texture_id,
                border.radius,
            );
            return;
        }

        var outer_points: [rounded_point_count]types.Vec2 = undefined;
        var inner_points: [rounded_point_count]types.Vec2 = undefined;
        const outer_count = roundedRectPoints(outer, border.radius, &outer_points);
        const inner_count = roundedRectPoints(inner, @max(0, border.radius - border_width), &inner_points);
        if (outer_count < 3 or inner_count != outer_count) return;

        try self.ensureBatch(white_texture_id, self.currentClip());
        const color = border.color.toU32();
        const base: u32 = @intCast(self.vertices.items.len);
        for (outer_points[0..outer_count]) |point| {
            try self.vertices.append(self.allocator, .{ .pos = .{ point.x, point.y }, .uv = .{ 0, 0 }, .color = color });
        }
        for (inner_points[0..inner_count]) |point| {
            try self.vertices.append(self.allocator, .{ .pos = .{ point.x, point.y }, .uv = .{ 0, 0 }, .color = color });
        }

        const offset_before = self.indices.items.len;
        var i: usize = 0;
        while (i < outer_count) : (i += 1) {
            const next = (i + 1) % outer_count;
            const outer_current = base + @as(u32, @intCast(i));
            const outer_next = base + @as(u32, @intCast(next));
            const inner_current = base + @as(u32, @intCast(outer_count + i));
            const inner_next = base + @as(u32, @intCast(outer_count + next));
            try self.indices.appendSlice(self.allocator, &.{
                outer_current, outer_next, inner_next,
                outer_current, inner_next, inner_current,
            });
        }
        self.batches.items[self.batches.items.len - 1].index_count += @intCast(self.indices.items.len - offset_before);

        if (self.antialias_width > 0) {
            var fringe_points: [rounded_point_count]types.Vec2 = undefined;
            const fringe_rect = outsetRect(outer, self.antialias_width);
            const fringe_count = roundedRectPoints(fringe_rect, border.radius + self.antialias_width, &fringe_points);
            if (fringe_count == outer_count) {
                try self.addTexturedRing(
                    outer,
                    .{ .x = 0, .y = 0 },
                    .{ .x = 1, .y = 1 },
                    white_texture_id,
                    outer_points[0..outer_count],
                    fringe_points[0..fringe_count],
                    border.color,
                    withAlpha(border.color, 0),
                );
            }
        }
    }

    fn addText(self: *Batcher, text: paint.TextPaint, atlas: *FontAtlas, text_raster_scale: f32) !void {
        if (text.color.a == 0 or text.size <= 0) return;

        const raster_scale = sanitizeRasterScale(text_raster_scale);
        const origin_x = text.pos.x;
        var x = origin_x;
        var baseline_y = text.pos.y;
        var previous: ?u21 = null;
        var it = text_mod.Utf8Iterator.init(text.text);

        while (it.next()) |codepoint| {
            switch (codepoint) {
                '\n' => {
                    x = origin_x;
                    baseline_y += atlas.lineHeightScaled(text.size, raster_scale);
                    previous = null;
                },
                '\t' => {
                    x += atlas.spaceAdvanceScaled(text.size, raster_scale) * 4;
                    previous = null;
                },
                ' ' => {
                    x += atlas.spaceAdvanceScaled(text.size, raster_scale);
                    previous = null;
                },
                else => {
                    const glyph = try atlas.getGlyphScaled(codepoint, text.size, raster_scale);
                    if (previous) |left| x += atlas.kerningScaled(left, glyph.codepoint, text.size, raster_scale);

                    if (glyph.size.x > 0 and glyph.size.y > 0) {
                        try self.addGlyphQuad(.{
                            .x = snapToRasterPixel(x + glyph.offset.x, raster_scale),
                            .y = snapToRasterPixel(baseline_y + glyph.offset.y, raster_scale),
                            .w = glyph.size.x,
                            .h = glyph.size.y,
                        }, glyph, text.color, atlas.texture_id);
                    }

                    x += glyph.advance;
                    previous = glyph.codepoint;
                },
            }
        }
    }

    fn addImage(self: *Batcher, image: paint.ImagePaint) !void {
        if (image.texture_id == 0 or image.tint.a == 0) return;
        if (clampedRadius(image.rect, image.radius) > 0) {
            try self.addRoundedTexturedRect(image.rect, image.uv0, image.uv1, image.tint, image.texture_id, image.radius);
            return;
        }
        try self.addTexturedRect(image.rect, image.uv0, image.uv1, image.tint, image.texture_id);
    }

    fn addGlyphQuad(self: *Batcher, rect: types.Rect, glyph: font_atlas_mod.Glyph, color: types.Color, texture_id: u32) !void {
        if (rect.isEmpty()) return;
        try self.addTexturedRect(
            rect,
            .{ .x = glyph.uv0.x, .y = glyph.uv0.y },
            .{ .x = glyph.uv1.x, .y = glyph.uv1.y },
            color,
            texture_id,
        );
    }

    fn addTexturedRect(
        self: *Batcher,
        rect: types.Rect,
        uv0: types.Vec2,
        uv1: types.Vec2,
        color: types.Color,
        texture_id: u32,
    ) !void {
        if (rect.isEmpty() or color.a == 0) return;
        try self.ensureBatch(texture_id, self.currentClip());

        const base: u32 = @intCast(self.vertices.items.len);
        try self.vertices.append(self.allocator, .{ .pos = .{ rect.x, rect.y }, .uv = .{ uv0.x, uv0.y }, .color = color.toU32() });
        try self.vertices.append(self.allocator, .{ .pos = .{ rect.x + rect.w, rect.y }, .uv = .{ uv1.x, uv0.y }, .color = color.toU32() });
        try self.vertices.append(self.allocator, .{ .pos = .{ rect.x + rect.w, rect.y + rect.h }, .uv = .{ uv1.x, uv1.y }, .color = color.toU32() });
        try self.vertices.append(self.allocator, .{ .pos = .{ rect.x, rect.y + rect.h }, .uv = .{ uv0.x, uv1.y }, .color = color.toU32() });

        const offset_before = self.indices.items.len;
        try self.indices.appendSlice(self.allocator, &.{
            base, base + 1, base + 2,
            base, base + 2, base + 3,
        });
        self.batches.items[self.batches.items.len - 1].index_count += @intCast(self.indices.items.len - offset_before);
    }

    fn addRoundedTexturedRect(
        self: *Batcher,
        rect: types.Rect,
        uv0: types.Vec2,
        uv1: types.Vec2,
        color: types.Color,
        texture_id: u32,
        radius: f32,
    ) !void {
        if (rect.isEmpty() or color.a == 0) return;
        const r = clampedRadius(rect, radius);
        if (r <= 0) {
            try self.addTexturedRect(rect, uv0, uv1, color, texture_id);
            return;
        }

        var points: [rounded_point_count]types.Vec2 = undefined;
        const count = roundedRectPoints(rect, r, &points);
        if (count < 3) return;

        try self.ensureBatch(texture_id, self.currentClip());
        const color_u32 = color.toU32();
        const base: u32 = @intCast(self.vertices.items.len);
        const center: types.Vec2 = .{ .x = rect.x + rect.w * 0.5, .y = rect.y + rect.h * 0.5 };
        const center_uv = uvForPoint(rect, uv0, uv1, center);
        try self.vertices.append(self.allocator, .{
            .pos = .{ center.x, center.y },
            .uv = .{ center_uv.x, center_uv.y },
            .color = color_u32,
        });

        for (points[0..count]) |point| {
            const uv = uvForPoint(rect, uv0, uv1, point);
            try self.vertices.append(self.allocator, .{
                .pos = .{ point.x, point.y },
                .uv = .{ uv.x, uv.y },
                .color = color_u32,
            });
        }

        const offset_before = self.indices.items.len;
        var i: usize = 0;
        while (i < count) : (i += 1) {
            const current = base + 1 + @as(u32, @intCast(i));
            const next = base + 1 + @as(u32, @intCast((i + 1) % count));
            try self.indices.appendSlice(self.allocator, &.{ base, current, next });
        }
        self.batches.items[self.batches.items.len - 1].index_count += @intCast(self.indices.items.len - offset_before);

        if (self.antialias_width > 0) {
            var fringe_points: [rounded_point_count]types.Vec2 = undefined;
            const fringe_rect = outsetRect(rect, self.antialias_width);
            const fringe_count = roundedRectPoints(fringe_rect, r + self.antialias_width, &fringe_points);
            if (fringe_count == count) {
                try self.addTexturedRing(
                    rect,
                    uv0,
                    uv1,
                    texture_id,
                    points[0..count],
                    fringe_points[0..fringe_count],
                    color,
                    withAlpha(color, 0),
                );
            }
        }
    }

    fn addTexturedRing(
        self: *Batcher,
        uv_rect: types.Rect,
        uv0: types.Vec2,
        uv1: types.Vec2,
        texture_id: u32,
        inner_points: []const types.Vec2,
        outer_points: []const types.Vec2,
        inner_color: types.Color,
        outer_color: types.Color,
    ) !void {
        if (inner_points.len < 3 or inner_points.len != outer_points.len) return;

        try self.ensureBatch(texture_id, self.currentClip());
        const base: u32 = @intCast(self.vertices.items.len);
        for (inner_points) |point| {
            const uv = uvForPoint(uv_rect, uv0, uv1, point);
            try self.vertices.append(self.allocator, .{
                .pos = .{ point.x, point.y },
                .uv = .{ uv.x, uv.y },
                .color = inner_color.toU32(),
            });
        }
        for (outer_points) |point| {
            const uv = uvForPoint(uv_rect, uv0, uv1, point);
            try self.vertices.append(self.allocator, .{
                .pos = .{ point.x, point.y },
                .uv = .{ uv.x, uv.y },
                .color = outer_color.toU32(),
            });
        }

        const offset_before = self.indices.items.len;
        var i: usize = 0;
        while (i < inner_points.len) : (i += 1) {
            const next = (i + 1) % inner_points.len;
            const inner_current = base + @as(u32, @intCast(i));
            const inner_next = base + @as(u32, @intCast(next));
            const outer_current = base + @as(u32, @intCast(inner_points.len + i));
            const outer_next = base + @as(u32, @intCast(inner_points.len + next));
            try self.indices.appendSlice(self.allocator, &.{
                inner_current, inner_next, outer_next,
                inner_current, outer_next, outer_current,
            });
        }
        self.batches.items[self.batches.items.len - 1].index_count += @intCast(self.indices.items.len - offset_before);
    }

    fn ensureBatch(self: *Batcher, texture_id: u32, clip: types.Rect) !void {
        if (self.batches.items.len > 0) {
            const last = &self.batches.items[self.batches.items.len - 1];
            if (last.texture_id == texture_id and rectEqual(last.clip_rect, clip)) return;
        }

        try self.batches.append(self.allocator, .{
            .texture_id = texture_id,
            .clip_rect = clip,
            .index_offset = @intCast(self.indices.items.len),
            .index_count = 0,
        });
    }

    fn currentClip(self: *const Batcher) types.Rect {
        if (self.clip_stack.items.len == 0) return default_clip;
        return self.clip_stack.items[self.clip_stack.items.len - 1];
    }
};

fn rectEqual(a: types.Rect, b: types.Rect) bool {
    return a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h;
}

fn uniformBorderWidth(widths: anytype) ?f32 {
    if (widths.top != widths.right or widths.top != widths.bottom or widths.top != widths.left) return null;
    return widths.top;
}

fn clampedRadius(rect: types.Rect, radius: f32) f32 {
    if (!std.math.isFinite(radius) or radius <= 0) return 0;
    return @min(radius, @min(rect.w, rect.h) * 0.5);
}

fn antialiasWidth(raster_scale: f32) f32 {
    const scale = sanitizeRasterScale(raster_scale);
    return @min(max_antialias_width, 1 / scale);
}

fn outsetRect(rect: types.Rect, amount: f32) types.Rect {
    return .{
        .x = rect.x - amount,
        .y = rect.y - amount,
        .w = rect.w + amount * 2,
        .h = rect.h + amount * 2,
    };
}

fn withAlpha(color: types.Color, alpha_factor: f32) types.Color {
    const alpha = clamp01(alpha_factor);
    return .{
        .r = color.r,
        .g = color.g,
        .b = color.b,
        .a = @intFromFloat(@round(@as(f32, @floatFromInt(color.a)) * alpha)),
    };
}

fn roundedRectPoints(rect: types.Rect, radius: f32, points: *[rounded_point_count]types.Vec2) usize {
    const r = clampedRadius(rect, radius);
    if (r <= 0) {
        points[0] = .{ .x = rect.x, .y = rect.y };
        points[1] = .{ .x = rect.x + rect.w, .y = rect.y };
        points[2] = .{ .x = rect.x + rect.w, .y = rect.y + rect.h };
        points[3] = .{ .x = rect.x, .y = rect.y + rect.h };
        return 4;
    }

    const pi = std.math.pi;
    const quarter_turn = pi * 0.5;
    const centers = [_]types.Vec2{
        .{ .x = rect.x + rect.w - r, .y = rect.y + r },
        .{ .x = rect.x + rect.w - r, .y = rect.y + rect.h - r },
        .{ .x = rect.x + r, .y = rect.y + rect.h - r },
        .{ .x = rect.x + r, .y = rect.y + r },
    };
    const starts = [_]f32{ -quarter_turn, 0, quarter_turn, pi };

    var count: usize = 0;
    var corner: usize = 0;
    while (corner < centers.len) : (corner += 1) {
        var segment: usize = 0;
        while (segment <= rounded_corner_segments) : (segment += 1) {
            const progress = @as(f32, @floatFromInt(segment)) / @as(f32, @floatFromInt(rounded_corner_segments));
            const angle = starts[corner] + quarter_turn * progress;
            points[count] = .{
                .x = centers[corner].x + @cos(angle) * r,
                .y = centers[corner].y + @sin(angle) * r,
            };
            count += 1;
        }
    }
    return count;
}

fn uvForPoint(rect: types.Rect, uv0: types.Vec2, uv1: types.Vec2, point: types.Vec2) types.Vec2 {
    const tx = clamp01((point.x - rect.x) / rect.w);
    const ty = clamp01((point.y - rect.y) / rect.h);
    return .{
        .x = uv0.x + (uv1.x - uv0.x) * tx,
        .y = uv0.y + (uv1.y - uv0.y) * ty,
    };
}

fn clamp01(v: f32) f32 {
    return @min(1, @max(0, v));
}

fn sanitizeRasterScale(raster_scale: f32) f32 {
    if (!std.math.isFinite(raster_scale)) return 1;
    return @max(0.25, raster_scale);
}

fn snapToRasterPixel(value: f32, raster_scale: f32) f32 {
    return @round(value * raster_scale) / raster_scale;
}

fn loadTestFont(allocator: std.mem.Allocator) ![]u8 {
    return try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "assets/fonts/Inter-Regular.ttf", allocator, .limited(4 * 1024 * 1024));
}

test "text commands emit atlas glyph quads" {
    const font_bytes = try loadTestFont(std.testing.allocator);
    defer std.testing.allocator.free(font_bytes);

    var atlas = try FontAtlas.init(std.testing.allocator, font_bytes, 256, 256);
    defer atlas.deinit();
    atlas.texture_id = 42;

    var batcher = Batcher.init(std.testing.allocator);
    defer batcher.deinit();

    const commands = [_]paint.PaintCommand{
        .{ .text = .{
            .pos = .{ .x = 10, .y = 20 },
            .text = "A B",
            .size = 16,
            .color = types.Color.rgba(255, 255, 255, 255),
        } },
    };

    const data = try batcher.build(&commands, &atlas, 1);
    try std.testing.expectEqual(@as(usize, 8), data.vertices.len);
    try std.testing.expectEqual(@as(usize, 12), data.indices.len);
    try std.testing.expectEqual(@as(usize, 1), data.batches.len);
    try std.testing.expectEqual(@as(u32, 42), data.batches[0].texture_id);
    try std.testing.expect(data.vertices[0].uv[0] > 0);
}
