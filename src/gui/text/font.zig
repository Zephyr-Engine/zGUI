const std = @import("std");
const c = @import("../c.zig");
const stb = c.trueType;
const Renderer = @import("../renderer.zig").Renderer;
const TextureHandle = @import("../renderer.zig").TextureHandle;
const TextureFormat = @import("../renderer.zig").TextureFormat;

pub const TextMetrics = struct {
    width: f32,
    height: f32,
};

pub const Glyph = struct {
    x0: i32,
    y0: i32,
    x1: i32,
    y1: i32,
    x_off: f32,
    y_off: f32,
    x_advance: f32,
    uv0: [2]f32,
    uv1: [2]f32,
};

pub const LoadError = error{
    InvalidFont,
    PackFailed,
};

pub const Font = struct {
    tex_width: i32,
    tex_height: i32,
    texture: TextureHandle,
    scale: f32,
    ascent: f32,
    descent: f32,
    line_gap: f32,
    glyphs: [256]Glyph,

    /// Load font from in-memory data (e.g., @embedFile)
    pub fn loadFromMemory(allocator: std.mem.Allocator, renderer: *Renderer, font_data: []const u8, pixel_height: f32) !Font {
        return loadFromData(allocator, renderer, font_data, pixel_height);
    }

    pub fn load(allocator: std.mem.Allocator, renderer: *Renderer, path: []const u8, pixel_height: f32, io: std.Io) !Font {
        const data = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(4 * 1024 * 1024));
        defer allocator.free(data);

        return loadFromData(allocator, renderer, data, pixel_height);
    }

    fn loadFromData(allocator: std.mem.Allocator, renderer: *Renderer, data: []const u8, pixel_height: f32) !Font {
        var info: stb.stbtt_fontinfo = undefined;
        if (stb.stbtt_InitFont(&info, data.ptr, 0) == 0) {
            return LoadError.InvalidFont;
        }

        var ascent: c_int = 0;
        var descent: c_int = 0;
        var line_gap: c_int = 0;
        stb.stbtt_GetFontVMetrics(&info, &ascent, &descent, &line_gap);

        const scale = stb.stbtt_ScaleForPixelHeight(&info, pixel_height);

        // Calculate texture size based on font size to ensure all glyphs fit
        // Larger fonts need more space in the texture atlas
        const tex_size: i32 = if (pixel_height <= 20)
            512
        else if (pixel_height <= 48)
            1024
        else
            2048;

        const tex_width = tex_size;
        const tex_height = tex_size;

        const bitmap_size: usize = @intCast(tex_width * tex_height);
        var bitmap = try allocator.alloc(u8, bitmap_size);
        defer allocator.free(bitmap);
        @memset(bitmap[0..], 0);

        var packer: stb.stbtt_pack_context = undefined;
        if (stb.stbtt_PackBegin(&packer, bitmap.ptr, tex_width, tex_height, 0, 3, null) == 0) {
            return LoadError.PackFailed;
        }

        var range: stb.stbtt_pack_range = .{
            .font_size = pixel_height,
            .first_unicode_codepoint_in_range = 0,
            .num_chars = 256,
            .chardata_for_range = undefined,
        };

        const cd = try allocator.alloc(stb.stbtt_packedchar, 256);
        defer allocator.free(cd);
        range.chardata_for_range = cd.ptr;

        if (stb.stbtt_PackFontRanges(&packer, data.ptr, 0, &range, 1) == 0) {
            return LoadError.PackFailed;
        }

        stb.stbtt_PackEnd(&packer);

        // Create texture using the renderer
        const tex = renderer.createTexture(tex_width, tex_height, .r8, bitmap.ptr);

        const tex_width_f: f32 = @floatFromInt(tex_width);
        const tex_height_f: f32 = @floatFromInt(tex_height);

        var glyphs: [256]Glyph = undefined;
        for (0..256) |i| {
            const char = cd[i];
            glyphs[i] = Glyph{
                .x0 = char.x0,
                .y0 = char.y0,
                .x1 = char.x1,
                .y1 = char.y1,
                .x_off = char.xoff,
                .y_off = char.yoff,
                .x_advance = char.xadvance,
                .uv0 = .{ @as(f32, @floatFromInt(char.x0)) / tex_width_f, @as(f32, @floatFromInt(char.y0)) / tex_height_f },
                .uv1 = .{ @as(f32, @floatFromInt(char.x1)) / tex_width_f, @as(f32, @floatFromInt(char.y1)) / tex_height_f },
            };
        }

        return Font{
            .tex_width = tex_width,
            .tex_height = tex_height,
            .texture = tex,
            .scale = scale,
            .ascent = @as(f32, @floatFromInt(ascent)) * scale,
            .descent = @as(f32, @floatFromInt(descent)) * scale,
            .line_gap = @as(f32, @floatFromInt(line_gap)) * scale,
            .glyphs = glyphs,
        };
    }

    pub fn measure(self: *const Font, text: []const u8) TextMetrics {
        var width: f32 = 0.0;

        for (text) |char| {
            const idx: usize = @intCast(char);
            const g = self.glyphs[idx];
            width += g.x_advance;
        }

        const height = (self.ascent - self.descent + self.line_gap);
        return TextMetrics{
            .width = width,
            .height = height,
        };
    }

    pub fn deinit(self: *Font, renderer: *Renderer) void {
        renderer.deleteTexture(self.texture);
    }
};
