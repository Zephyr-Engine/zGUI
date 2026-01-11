const std = @import("std");
const GuiContext = @import("context.zig").GuiContext;

/// Opaque texture handle - interpretation depends on the renderer
/// For OpenGL: cast to u32 for texture ID
/// For Vulkan: cast to pointer for VkImage
/// For custom renderers: any 64-bit value
pub const TextureHandle = u64;

pub const TextureFormat = enum {
    /// Single channel (R) format - typically used for font atlases
    r8,
    /// RGBA format - used for color images
    rgba8,
};

/// Abstract renderer interface that allows different rendering backends
/// (OpenGL, Vulkan, custom game engine renderers, etc.)
pub const Renderer = struct {
    /// Opaque pointer to renderer-specific implementation data
    context: *anyopaque,

    /// Initialize the renderer and set up required resources
    /// Called once during renderer creation
    init_fn: *const fn (context: *anyopaque) void,

    /// Render a frame using the GuiContext's draw list
    /// Called every frame to render the GUI
    /// Parameters:
    ///   - context: Renderer-specific data
    ///   - gui_ctx: GUI context containing draw commands
    ///   - width: Framebuffer width in pixels
    ///   - height: Framebuffer height in pixels
    render_fn: *const fn (context: *anyopaque, gui_ctx: *GuiContext, width: i32, height: i32) void,

    /// Create a texture from bitmap data
    /// Parameters:
    ///   - context: Renderer-specific data
    ///   - width: Texture width in pixels
    ///   - height: Texture height in pixels
    ///   - format: Texture format
    ///   - data: Pointer to pixel data
    /// Returns: Opaque texture handle
    create_texture_fn: *const fn (context: *anyopaque, width: i32, height: i32, format: TextureFormat, data: [*]const u8) TextureHandle,

    /// Delete a texture
    /// Parameters:
    ///   - context: Renderer-specific data
    ///   - texture: Texture handle to delete
    delete_texture_fn: *const fn (context: *anyopaque, texture: TextureHandle) void,

    /// Wrap an existing texture ID (e.g., from a framebuffer)
    /// Parameters:
    ///   - context: Renderer-specific data
    ///   - texture_id: Native texture ID (e.g., OpenGL texture ID)
    ///   - width: Texture width in pixels
    ///   - height: Texture height in pixels
    /// Returns: Opaque texture handle
    /// Note: The texture is NOT owned by the renderer and will not be deleted
    wrap_texture_fn: *const fn (context: *anyopaque, texture_id: u32, width: i32, height: i32) TextureHandle,

    /// Clean up renderer resources
    /// Called when the renderer is being destroyed
    deinit_fn: *const fn (context: *anyopaque) void,

    /// Initialize the renderer interface
    pub fn init(
        context: *anyopaque,
        init_fn: *const fn (*anyopaque) void,
        render_fn: *const fn (*anyopaque, *GuiContext, i32, i32) void,
        create_texture_fn: *const fn (*anyopaque, i32, i32, TextureFormat, [*]const u8) TextureHandle,
        delete_texture_fn: *const fn (*anyopaque, TextureHandle) void,
        wrap_texture_fn: *const fn (*anyopaque, u32, i32, i32) TextureHandle,
        deinit_fn: *const fn (*anyopaque) void,
    ) Renderer {
        return Renderer{
            .context = context,
            .init_fn = init_fn,
            .render_fn = render_fn,
            .create_texture_fn = create_texture_fn,
            .delete_texture_fn = delete_texture_fn,
            .wrap_texture_fn = wrap_texture_fn,
            .deinit_fn = deinit_fn,
        };
    }

    /// Call the renderer's render function
    pub fn render(self: *Renderer, gui_ctx: *GuiContext, width: i32, height: i32) void {
        self.render_fn(self.context, gui_ctx, width, height);
    }

    /// Create a texture from bitmap data
    pub fn createTexture(self: *Renderer, width: i32, height: i32, format: TextureFormat, data: [*]const u8) TextureHandle {
        return self.create_texture_fn(self.context, width, height, format, data);
    }

    /// Delete a texture
    pub fn deleteTexture(self: *Renderer, texture: TextureHandle) void {
        self.delete_texture_fn(self.context, texture);
    }

    /// Wrap an existing texture ID (e.g., from a framebuffer)
    /// Note: The wrapped texture is NOT owned by the renderer and will not be deleted
    pub fn wrapTexture(self: *Renderer, texture_id: u32, width: i32, height: i32) TextureHandle {
        return self.wrap_texture_fn(self.context, texture_id, width, height);
    }

    /// Call the renderer's cleanup function
    pub fn deinit(self: *Renderer) void {
        self.deinit_fn(self.context);
    }
};
