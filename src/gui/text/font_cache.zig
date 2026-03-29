const std = @import("std");
const Font = @import("font.zig").Font;
const Renderer = @import("../renderer.zig").Renderer;

pub const FontCache = struct {
    allocator: std.mem.Allocator,
    font_path: []const u8,
    font_data: ?[]const u8,
    renderer: *Renderer,
    cache: std.AutoHashMap(u32, Font),
    io: std.Io,

    pub fn init(allocator: std.mem.Allocator, font_path: []const u8, renderer: *Renderer, io: std.Io) FontCache {
        return FontCache{
            .allocator = allocator,
            .font_path = font_path,
            .font_data = null,
            .renderer = renderer,
            .cache = std.AutoHashMap(u32, Font).init(allocator),
            .io = io,
        };
    }

    /// Initialize with embedded font data (no file I/O)
    pub fn initFromMemory(allocator: std.mem.Allocator, data: []const u8, renderer: *Renderer, io: std.Io) FontCache {
        return FontCache{
            .allocator = allocator,
            .font_path = "",
            .font_data = data,
            .renderer = renderer,
            .cache = std.AutoHashMap(u32, Font).init(allocator),
            .io = io,
        };
    }

    pub fn getFont(self: *FontCache, pixel_height: f32) !*Font {
        const size_key: u32 = @intFromFloat(pixel_height);

        if (self.cache.getPtr(size_key)) |font| {
            return font;
        }

        const font = if (self.font_data) |data|
            try Font.loadFromMemory(self.allocator, self.renderer, data, pixel_height)
        else
            try Font.load(self.allocator, self.renderer, self.font_path, pixel_height, self.io);
        try self.cache.put(size_key, font);

        return self.cache.getPtr(size_key).?;
    }

    pub fn deinit(self: *FontCache) void {
        var it = self.cache.valueIterator();
        while (it.next()) |font| {
            font.deinit(self.renderer);
        }
        self.cache.deinit();
    }
};
