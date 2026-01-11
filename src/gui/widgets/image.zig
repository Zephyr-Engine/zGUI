const std = @import("std");
const c = @import("../c.zig");
const stb_image = c.image;
const GuiContext = @import("../context.zig").GuiContext;
const shapes = @import("../shapes.zig");
const Renderer = @import("../renderer.zig").Renderer;
const TextureHandle = @import("../renderer.zig").TextureHandle;
const TextureFormat = @import("../renderer.zig").TextureFormat;

pub const LoadError = error{
    InvalidImage,
    FileNotFound,
};

pub const Image = struct {
    texture: TextureHandle,
    width: i32,
    height: i32,
    channels: i32,
    /// Whether this Image owns the texture (if false, deinit will not delete it)
    owns_texture: bool,

    pub fn load(allocator: std.mem.Allocator, renderer: *Renderer, path: []const u8) !Image {
        const path_z = try allocator.dupeZ(u8, path);
        defer allocator.free(path_z);

        var width: c_int = 0;
        var height: c_int = 0;
        var channels: c_int = 0;

        const data = stb_image.stbi_load(path_z.ptr, &width, &height, &channels, 4);
        if (data == null) {
            return LoadError.InvalidImage;
        }
        defer stb_image.stbi_image_free(data);

        // Create texture using the renderer (RGBA format for images)
        const tex = renderer.createTexture(width, height, .rgba8, data);

        return Image{
            .texture = tex,
            .width = width,
            .height = height,
            .channels = 4,
            .owns_texture = true,
        };
    }

    /// Create an Image from an existing texture ID (e.g., from a framebuffer)
    /// The texture is NOT owned by the Image and will NOT be deleted when deinit is called
    /// Use this when you want to display framebuffer contents or other externally-managed textures
    ///
    /// Example usage with OpenGL framebuffer:
    /// ```zig
    /// const gl = @import("c.zig").glad;
    ///
    /// // Create framebuffer and texture (in your game engine)
    /// var fbo: u32 = 0;
    /// var fbo_texture: u32 = 0;
    /// gl.glGenFramebuffers(1, &fbo);
    /// gl.glGenTextures(1, &fbo_texture);
    ///
    /// // Set up framebuffer texture
    /// gl.glBindTexture(gl.GL_TEXTURE_2D, fbo_texture);
    /// gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, gl.GL_RGBA, 800, 600, 0, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, null);
    /// gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR);
    /// gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
    ///
    /// // Attach texture to framebuffer
    /// gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, fbo);
    /// gl.glFramebufferTexture2D(gl.GL_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, gl.GL_TEXTURE_2D, fbo_texture, 0);
    /// gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, 0);
    ///
    /// // Later, render your game to the framebuffer
    /// gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, fbo);
    /// // ... render your game scene here ...
    /// gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, 0);
    ///
    /// // Create an Image from the framebuffer texture to display in GUI
    /// const img = imageWidget.Image.fromTexture(renderer, fbo_texture, 800, 600);
    /// defer img.deinit(renderer); // Won't delete the framebuffer texture
    ///
    /// // Display the framebuffer in your GUI
    /// try imageWidget.image(&gui_ctx, &img, .{});
    /// ```
    pub fn fromTexture(renderer: *Renderer, texture_id: u32, width: i32, height: i32) Image {
        const tex = renderer.wrapTexture(texture_id, width, height);
        return Image{
            .texture = tex,
            .width = width,
            .height = height,
            .channels = 4,
            .owns_texture = false,
        };
    }

    pub fn deinit(self: *Image, renderer: *Renderer) void {
        if (self.owns_texture) {
            renderer.deleteTexture(self.texture);
        }
    }
};

pub const Options = struct {
    /// Width to render the image (if null, uses image's natural width)
    width: ?f32 = null,
    /// Height to render the image (if null, uses image's natural height)
    height: ?f32 = null,
    /// Color tint to apply to the image (default: white = no tint)
    tint: shapes.Color = 0xFFFFFFFF,
};

pub fn image(ctx: *GuiContext, img: *const Image, opts: Options) !void {
    const width = opts.width orelse @as(f32, @floatFromInt(img.width));
    const height = opts.height orelse @as(f32, @floatFromInt(img.height));

    const layout = ctx.getCurrentLayout();
    const rect = layout.allocateSpace(ctx, width, height);

    try ctx.draw_list.setTexture(img.texture);
    try ctx.draw_list.addRectUV(
        rect,
        .{ 0.0, 0.0 }, // UV min (top-left)
        .{ 1.0, 1.0 }, // UV max (bottom-right)
        opts.tint,
    );
}

// Internal helper for widgets that need to position images manually (like checkbox)
pub fn imageAt(ctx: *GuiContext, x: f32, y: f32, img: *const Image, opts: Options) !void {
    const width = opts.width orelse @as(f32, @floatFromInt(img.width));
    const height = opts.height orelse @as(f32, @floatFromInt(img.height));

    const rect = shapes.Rect{
        .x = x,
        .y = y,
        .w = width,
        .h = height,
    };

    try ctx.draw_list.setTexture(img.texture);
    try ctx.draw_list.addRectUV(
        rect,
        .{ 0.0, 0.0 }, // UV min (top-left)
        .{ 1.0, 1.0 }, // UV max (bottom-right)
        opts.tint,
    );
}
