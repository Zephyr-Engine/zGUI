const std = @import("std");
const types = @import("../core/types.zig");
const text_mod = @import("../core/text.zig");

const c = @cImport({
    @cInclude("stb_truetype.h");
});

pub const GlyphKey = struct {
    codepoint: u21,
    px_size: u16,
};

pub const DirtyRect = struct {
    x: u32,
    y: u32,
    w: u32,
    h: u32,
};

pub const Glyph = struct {
    codepoint: u21,
    px_size: u16,
    advance: f32,
    offset: types.Vec2 = .{},
    size: types.Vec2 = .{},
    uv0: types.Vec2 = .{},
    uv1: types.Vec2 = .{},
    atlas_x: u32 = 0,
    atlas_y: u32 = 0,
    atlas_w: u32 = 0,
    atlas_h: u32 = 0,
};

pub const FontAtlas = struct {
    allocator: std.mem.Allocator,
    font_bytes: []u8,
    font_info: c.stbtt_fontinfo,
    pixels: []u8,
    width: u32,
    height: u32,
    texture_id: u32 = 0,
    glyphs: std.AutoHashMap(GlyphKey, Glyph),
    shelf_x: u32 = 1,
    shelf_y: u32 = 1,
    shelf_height: u32 = 0,
    dirty: bool = true,
    full_upload: bool = true,
    dirty_rect: ?DirtyRect = null,

    pub fn init(allocator: std.mem.Allocator, font_bytes: []const u8, atlas_width: u32, atlas_height: u32) !FontAtlas {
        if (atlas_width == 0 or atlas_height == 0) return error.InvalidAtlasSize;

        const owned_font = try allocator.dupe(u8, font_bytes);
        errdefer allocator.free(owned_font);

        var info: c.stbtt_fontinfo = undefined;
        const offset = c.stbtt_GetFontOffsetForIndex(owned_font.ptr, 0);
        if (offset < 0) return error.InvalidFont;
        if (c.stbtt_InitFont(&info, owned_font.ptr, offset) == 0) return error.InvalidFont;

        const pixel_count = try std.math.mul(usize, @intCast(atlas_width), @intCast(atlas_height));
        const byte_count = try std.math.mul(usize, pixel_count, 4);
        const pixels = try allocator.alloc(u8, byte_count);
        errdefer allocator.free(pixels);
        clearPixels(pixels);

        return .{
            .allocator = allocator,
            .font_bytes = owned_font,
            .font_info = info,
            .pixels = pixels,
            .width = atlas_width,
            .height = atlas_height,
            .glyphs = std.AutoHashMap(GlyphKey, Glyph).init(allocator),
            .dirty_rect = .{ .x = 0, .y = 0, .w = atlas_width, .h = atlas_height },
        };
    }

    pub fn deinit(self: *FontAtlas) void {
        self.glyphs.deinit();
        self.allocator.free(self.pixels);
        self.allocator.free(self.font_bytes);
        self.* = undefined;
    }

    pub fn measure(self: *const FontAtlas, bytes: []const u8, size: f32) text_mod.TextMetrics {
        const line_height = self.lineHeight(size);
        var current_width: f32 = 0;
        var max_width: f32 = 0;
        var line_count: u32 = 1;
        var previous: ?u21 = null;

        var it = text_mod.Utf8Iterator.init(bytes);
        while (it.next()) |raw_codepoint| {
            switch (raw_codepoint) {
                '\n' => {
                    max_width = @max(max_width, current_width);
                    current_width = 0;
                    line_count += 1;
                    previous = null;
                },
                '\t' => {
                    current_width += self.spaceAdvance(size) * 4;
                    previous = null;
                },
                else => {
                    const codepoint = self.renderableCodepoint(raw_codepoint);
                    if (previous) |left| current_width += self.kerning(left, codepoint, size);
                    current_width += self.advanceForCodepoint(codepoint, size);
                    previous = codepoint;
                },
            }
        }

        max_width = @max(max_width, current_width);
        return .{
            .size = .{
                .x = max_width,
                .y = line_height * @as(f32, @floatFromInt(line_count)),
            },
            .line_height = line_height,
        };
    }

    pub fn textMeasurer(self: *FontAtlas) text_mod.TextMeasurer {
        return .{
            .ptr = self,
            .measureFn = measureErased,
        };
    }

    pub fn getGlyph(self: *FontAtlas, codepoint: u21, size: f32) !Glyph {
        return self.getGlyphForPixelSize(codepoint, quantizeSize(size));
    }

    pub fn getGlyphScaled(self: *FontAtlas, codepoint: u21, size: f32, raster_scale: f32) !Glyph {
        const safe_scale = sanitizeRasterScale(raster_scale);
        var glyph = try self.getGlyphForPixelSize(codepoint, quantizeSize(size * safe_scale));
        scaleGlyphToLogical(&glyph, safe_scale);
        return glyph;
    }

    pub fn lineHeightScaled(self: *const FontAtlas, size: f32, raster_scale: f32) f32 {
        const safe_scale = sanitizeRasterScale(raster_scale);
        return self.lineHeight(@floatFromInt(quantizeSize(size * safe_scale))) / safe_scale;
    }

    pub fn spaceAdvanceScaled(self: *const FontAtlas, size: f32, raster_scale: f32) f32 {
        const safe_scale = sanitizeRasterScale(raster_scale);
        return self.spaceAdvance(@floatFromInt(quantizeSize(size * safe_scale))) / safe_scale;
    }

    pub fn kerningScaled(self: *const FontAtlas, left: u21, right: u21, size: f32, raster_scale: f32) f32 {
        const safe_scale = sanitizeRasterScale(raster_scale);
        return self.kerning(left, right, @floatFromInt(quantizeSize(size * safe_scale))) / safe_scale;
    }

    fn getGlyphForPixelSize(self: *FontAtlas, codepoint: u21, px_size: u16) !Glyph {
        const resolved = self.renderableCodepoint(codepoint);
        const key: GlyphKey = .{ .codepoint = resolved, .px_size = px_size };
        if (self.glyphs.get(key)) |glyph| return glyph;

        const glyph = self.createGlyph(key) catch |err| switch (err) {
            error.AtlasFull => {
                if (resolved != '?') return self.getGlyphForPixelSize('?', px_size);
                return emptyGlyph(key, self.advanceForCodepoint('?', @floatFromInt(px_size)));
            },
            else => return err,
        };
        try self.glyphs.put(key, glyph);
        return glyph;
    }

    pub fn glyphCount(self: *const FontAtlas) usize {
        return self.glyphs.count();
    }

    pub fn lineHeight(self: *const FontAtlas, size: f32) f32 {
        const scale = self.scaleForSize(size);
        var ascent: c_int = 0;
        var descent: c_int = 0;
        var line_gap: c_int = 0;
        c.stbtt_GetFontVMetrics(&self.font_info, &ascent, &descent, &line_gap);
        const height = @as(f32, @floatFromInt(ascent - descent + line_gap)) * scale;
        return if (height > 0) height else size * 1.25;
    }

    pub fn spaceAdvance(self: *const FontAtlas, size: f32) f32 {
        return self.advanceForCodepoint(' ', size);
    }

    pub fn kerning(self: *const FontAtlas, left: u21, right: u21, size: f32) f32 {
        const scale = self.scaleForSize(size);
        const kern = c.stbtt_GetCodepointKernAdvance(&self.font_info, @intCast(left), @intCast(right));
        return @as(f32, @floatFromInt(kern)) * scale;
    }

    pub fn markClean(self: *FontAtlas) void {
        self.dirty = false;
        self.full_upload = false;
        self.dirty_rect = null;
    }

    fn createGlyph(self: *FontAtlas, key: GlyphKey) !Glyph {
        const size = @as(f32, @floatFromInt(key.px_size));
        const scale = self.scaleForSize(size);
        const advance = self.advanceForCodepoint(key.codepoint, size);

        var x0: c_int = 0;
        var y0: c_int = 0;
        var x1: c_int = 0;
        var y1: c_int = 0;
        c.stbtt_GetCodepointBitmapBox(&self.font_info, @intCast(key.codepoint), scale, scale, &x0, &y0, &x1, &y1);

        const bitmap_w_i = @max(0, x1 - x0);
        const bitmap_h_i = @max(0, y1 - y0);
        if (bitmap_w_i == 0 or bitmap_h_i == 0) {
            return emptyGlyph(key, advance);
        }

        const bitmap_w: u32 = @intCast(bitmap_w_i);
        const bitmap_h: u32 = @intCast(bitmap_h_i);
        const padding: u32 = 1;
        const allocation = self.allocate(bitmap_w + padding * 2, bitmap_h + padding * 2) orelse return error.AtlasFull;

        const coverage = try self.allocator.alloc(u8, @as(usize, bitmap_w) * @as(usize, bitmap_h));
        defer self.allocator.free(coverage);
        c.stbtt_MakeCodepointBitmap(
            &self.font_info,
            coverage.ptr,
            @intCast(bitmap_w),
            @intCast(bitmap_h),
            @intCast(bitmap_w),
            scale,
            scale,
            @intCast(key.codepoint),
        );

        const dst_x = allocation.x + padding;
        const dst_y = allocation.y + padding;
        var row: u32 = 0;
        while (row < bitmap_h) : (row += 1) {
            var col: u32 = 0;
            while (col < bitmap_w) : (col += 1) {
                const src_index = @as(usize, row) * @as(usize, bitmap_w) + @as(usize, col);
                const dst_index = ((@as(usize, dst_y + row) * @as(usize, self.width)) + @as(usize, dst_x + col)) * 4;
                self.pixels[dst_index + 0] = 255;
                self.pixels[dst_index + 1] = 255;
                self.pixels[dst_index + 2] = 255;
                self.pixels[dst_index + 3] = coverage[src_index];
            }
        }

        self.markDirty(allocation);

        return .{
            .codepoint = key.codepoint,
            .px_size = key.px_size,
            .advance = advance,
            .offset = .{
                .x = @floatFromInt(x0),
                .y = @floatFromInt(y0),
            },
            .size = .{
                .x = @floatFromInt(bitmap_w),
                .y = @floatFromInt(bitmap_h),
            },
            .uv0 = .{
                .x = @as(f32, @floatFromInt(dst_x)) / @as(f32, @floatFromInt(self.width)),
                .y = @as(f32, @floatFromInt(dst_y)) / @as(f32, @floatFromInt(self.height)),
            },
            .uv1 = .{
                .x = @as(f32, @floatFromInt(dst_x + bitmap_w)) / @as(f32, @floatFromInt(self.width)),
                .y = @as(f32, @floatFromInt(dst_y + bitmap_h)) / @as(f32, @floatFromInt(self.height)),
            },
            .atlas_x = dst_x,
            .atlas_y = dst_y,
            .atlas_w = bitmap_w,
            .atlas_h = bitmap_h,
        };
    }

    fn allocate(self: *FontAtlas, w: u32, h: u32) ?DirtyRect {
        if (w > self.width or h > self.height) return null;
        if (self.shelf_x + w > self.width) {
            self.shelf_x = 1;
            self.shelf_y += self.shelf_height;
            self.shelf_height = 0;
        }
        if (self.shelf_y + h > self.height) return null;

        const rect: DirtyRect = .{ .x = self.shelf_x, .y = self.shelf_y, .w = w, .h = h };
        self.shelf_x += w;
        self.shelf_height = @max(self.shelf_height, h);
        return rect;
    }

    fn markDirty(self: *FontAtlas, rect: DirtyRect) void {
        self.dirty = true;
        if (self.dirty_rect) |existing| {
            const min_x = @min(existing.x, rect.x);
            const min_y = @min(existing.y, rect.y);
            const max_x = @max(existing.x + existing.w, rect.x + rect.w);
            const max_y = @max(existing.y + existing.h, rect.y + rect.h);
            self.dirty_rect = .{ .x = min_x, .y = min_y, .w = max_x - min_x, .h = max_y - min_y };
        } else {
            self.dirty_rect = rect;
        }
    }

    fn advanceForCodepoint(self: *const FontAtlas, codepoint: u21, size: f32) f32 {
        const scale = self.scaleForSize(size);
        var advance_width: c_int = 0;
        var left_side_bearing: c_int = 0;
        c.stbtt_GetCodepointHMetrics(&self.font_info, @intCast(codepoint), &advance_width, &left_side_bearing);
        return @as(f32, @floatFromInt(advance_width)) * scale;
    }

    fn renderableCodepoint(self: *const FontAtlas, codepoint: u21) u21 {
        if (codepoint == '\n' or codepoint == '\t') return codepoint;
        if (c.stbtt_FindGlyphIndex(&self.font_info, @intCast(codepoint)) != 0) return codepoint;
        return '?';
    }

    fn scaleForSize(self: *const FontAtlas, size: f32) f32 {
        const px_size = quantizeSize(size);
        return c.stbtt_ScaleForPixelHeight(&self.font_info, @floatFromInt(px_size));
    }

    fn measureErased(ptr: *anyopaque, bytes: []const u8, size: f32) text_mod.TextMetrics {
        const self: *FontAtlas = @ptrCast(@alignCast(ptr));
        return self.measure(bytes, size);
    }
};

fn clearPixels(pixels: []u8) void {
    var i: usize = 0;
    while (i < pixels.len) : (i += 4) {
        pixels[i + 0] = 255;
        pixels[i + 1] = 255;
        pixels[i + 2] = 255;
        pixels[i + 3] = 0;
    }
}

fn emptyGlyph(key: GlyphKey, advance: f32) Glyph {
    return .{
        .codepoint = key.codepoint,
        .px_size = key.px_size,
        .advance = advance,
    };
}

fn scaleGlyphToLogical(glyph: *Glyph, raster_scale: f32) void {
    const inv_scale = 1.0 / raster_scale;
    glyph.advance *= inv_scale;
    glyph.offset.x *= inv_scale;
    glyph.offset.y *= inv_scale;
    glyph.size.x *= inv_scale;
    glyph.size.y *= inv_scale;
}

fn quantizeSize(size: f32) u16 {
    const clamped = @min(@as(f32, @floatFromInt(std.math.maxInt(u16))), @max(1, size));
    return @intFromFloat(@round(clamped));
}

fn sanitizeRasterScale(raster_scale: f32) f32 {
    if (!std.math.isFinite(raster_scale)) return 1;
    return @max(0.25, raster_scale);
}

fn loadTestFont(allocator: std.mem.Allocator) ![]u8 {
    return try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "assets/fonts/Inter-Regular.ttf", allocator, .limited(4 * 1024 * 1024));
}

test "font atlas measures ascii whitespace newlines and non-ascii" {
    const font_bytes = try loadTestFont(std.testing.allocator);
    defer std.testing.allocator.free(font_bytes);

    var atlas = try FontAtlas.init(std.testing.allocator, font_bytes, 256, 256);
    defer atlas.deinit();

    const ascii = atlas.measure("abc", 16);
    const spaced = atlas.measure("a a", 16);
    const tabbed = atlas.measure("a\tb", 16);
    const multiline = atlas.measure("abc\nde", 16);
    const non_ascii = atlas.measure("\xc3\xa9", 16);

    try std.testing.expect(ascii.size.x > 0);
    try std.testing.expect(spaced.size.x > atlas.measure("aa", 16).size.x);
    try std.testing.expect(tabbed.size.x > spaced.size.x);
    try std.testing.expect(multiline.size.y > ascii.size.y);
    try std.testing.expect(non_ascii.size.x > 0);
}

test "font atlas reuses cached glyphs" {
    const font_bytes = try loadTestFont(std.testing.allocator);
    defer std.testing.allocator.free(font_bytes);

    var atlas = try FontAtlas.init(std.testing.allocator, font_bytes, 256, 256);
    defer atlas.deinit();

    _ = try atlas.getGlyph('A', 16);
    const count = atlas.glyphCount();
    _ = try atlas.getGlyph('A', 16);
    try std.testing.expectEqual(count, atlas.glyphCount());
}

test "font atlas scaled glyphs use larger physical pixels with logical metrics" {
    const font_bytes = try loadTestFont(std.testing.allocator);
    defer std.testing.allocator.free(font_bytes);

    var atlas = try FontAtlas.init(std.testing.allocator, font_bytes, 256, 256);
    defer atlas.deinit();

    const regular = try atlas.getGlyph('A', 16);
    const scaled = try atlas.getGlyphScaled('A', 16, 2);

    try std.testing.expectEqual(@as(u16, 32), scaled.px_size);
    try std.testing.expect(scaled.atlas_w > regular.atlas_w);
    try std.testing.expect(std.math.approxEqAbs(f32, regular.size.x, scaled.size.x, 3));
}

test "font atlas packs glyphs without overlap" {
    const font_bytes = try loadTestFont(std.testing.allocator);
    defer std.testing.allocator.free(font_bytes);

    var atlas = try FontAtlas.init(std.testing.allocator, font_bytes, 256, 256);
    defer atlas.deinit();

    const a = try atlas.getGlyph('A', 24);
    const b = try atlas.getGlyph('B', 24);
    const separated = a.atlas_x + a.atlas_w <= b.atlas_x or
        b.atlas_x + b.atlas_w <= a.atlas_x or
        a.atlas_y + a.atlas_h <= b.atlas_y or
        b.atlas_y + b.atlas_h <= a.atlas_y;
    try std.testing.expect(separated);
}

test "font atlas falls back to question mark for missing glyphs" {
    const font_bytes = try loadTestFont(std.testing.allocator);
    defer std.testing.allocator.free(font_bytes);

    var atlas = try FontAtlas.init(std.testing.allocator, font_bytes, 256, 256);
    defer atlas.deinit();

    const glyph = try atlas.getGlyph(0x10ffff, 16);
    try std.testing.expectEqual(@as(u21, '?'), glyph.codepoint);
}
