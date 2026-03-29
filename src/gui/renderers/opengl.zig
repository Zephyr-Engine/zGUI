const std = @import("std");
const gl = @import("../c.zig").glad;
const GuiContext = @import("../context.zig").GuiContext;
const Vertex = @import("../shapes.zig").Vertex;
const DrawList = @import("../draw_list.zig").DrawList;
const build_options = @import("build_options");
const Renderer = @import("../renderer.zig").Renderer;
const TextureHandle = @import("../renderer.zig").TextureHandle;
const TextureFormat = @import("../renderer.zig").TextureFormat;

pub const GLRenderer = struct {
    shader: u32,
    vbo: u32,
    ibo: u32,
    vao: u32,
    fallback_texture: u32,
    allocator: std.mem.Allocator,
    proj_loc: i32,
    tex_loc: i32,
    embedded_mode: bool,

    pub fn init(allocator: std.mem.Allocator) GLRenderer {
        return initWithOptions(allocator, false);
    }

    pub fn initEmbedded(allocator: std.mem.Allocator) GLRenderer {
        return initWithOptions(allocator, true);
    }

    fn initWithOptions(allocator: std.mem.Allocator, embedded: bool) GLRenderer {
        var self = GLRenderer{
            .shader = 0,
            .vbo = 0,
            .ibo = 0,
            .vao = 0,
            .fallback_texture = 0,
            .proj_loc = 0,
            .tex_loc = 0,
            .allocator = allocator,
            .embedded_mode = embedded,
        };

        self.shader = createShader();
        setupBuffers(&self);
        self.fallback_texture = createFallbackTexture();
        return self;
    }

    pub fn deinit(self: *GLRenderer) void {
        gl.glDeleteProgram(self.shader);
        gl.glDeleteBuffers(1, &self.vbo);
        gl.glDeleteBuffers(1, &self.ibo);
        gl.glDeleteVertexArrays(1, &self.vao);
        gl.glDeleteTextures(1, &self.fallback_texture);
    }

    pub fn render(self: *GLRenderer, ctx: *GuiContext, width: i32, height: i32) void {
        const dl = &ctx.draw_list;
        const vertices = dl.getVertices();
        const indices = dl.getIndices();
        const commands = dl.getCommands();

        if (vertices.len == 0 or commands.len == 0) {
            return;
        }

        // In embedded mode, save current GL state
        var prev_blend: i32 = undefined;
        var prev_depth_test: i32 = undefined;
        var prev_multisample: i32 = undefined;
        if (self.embedded_mode) {
            gl.glGetIntegerv(gl.GL_BLEND, &prev_blend);
            gl.glGetIntegerv(gl.GL_DEPTH_TEST, &prev_depth_test);
            gl.glGetIntegerv(gl.GL_MULTISAMPLE, &prev_multisample);
            gl.glEnable(gl.GL_BLEND);
            gl.glBlendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE_MINUS_SRC_ALPHA);
            gl.glDisable(gl.GL_DEPTH_TEST);
            gl.glEnable(gl.GL_MULTISAMPLE);
        } else {
            // Clear the screen (standalone mode only)
            gl.glClear(gl.GL_COLOR_BUFFER_BIT);
        }

        gl.glUseProgram(self.shader);
        checkGlError("glUseProgram");

        // Use framebuffer size for viewport (physical pixels for crisp rendering)
        gl.glViewport(0, 0, width, height);
        checkGlError("glViewport");

        // Use logical coordinates for projection (divided by content scale)
        // This ensures UI elements maintain consistent physical size across different DPI displays
        const logical_width = @as(f32, @floatFromInt(width)) / ctx.content_scale_x;
        const logical_height = @as(f32, @floatFromInt(height)) / ctx.content_scale_y;

        var proj: [16]f32 = ortho(0, logical_width, logical_height, 0, -1, 1);
        gl.glUniformMatrix4fv(self.proj_loc, 1, gl.GL_FALSE, &proj);
        checkGlError("glUniformMatrix4fv");

        gl.glUniform1i(self.tex_loc, 0);
        checkGlError("glUniform1i");

        // Bind VAO first, then upload vertex and index data
        gl.glBindVertexArray(self.vao);
        checkGlError("glBindVertexArray render");

        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo);
        checkGlError("glBindBuffer vbo render");
        gl.glBufferData(gl.GL_ARRAY_BUFFER, @intCast(vertices.len * @sizeOf(Vertex)), vertices.ptr, gl.GL_DYNAMIC_DRAW);
        checkGlError("glBufferData vbo");

        gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.ibo);
        checkGlError("glBindBuffer ibo render");
        gl.glBufferData(gl.GL_ELEMENT_ARRAY_BUFFER, @intCast(indices.len * @sizeOf(u32)), indices.ptr, gl.GL_DYNAMIC_DRAW);
        checkGlError("glBufferData ibo");

        gl.glActiveTexture(gl.GL_TEXTURE0);

        for (commands) |cmd| {
            if (cmd.elem_count == 0) continue;

            if (cmd.texture != 0) {
                const tex_id: u32 = @intCast(cmd.texture);
                gl.glBindTexture(gl.GL_TEXTURE_2D, tex_id);
                checkGlError("glBindTexture");
            } else {
                // Bind fallback texture so the sampler has a valid texture on all drivers
                gl.glBindTexture(gl.GL_TEXTURE_2D, self.fallback_texture);
            }

            const offset_ptr: ?*const anyopaque = @ptrFromInt(cmd.index_offset * @sizeOf(u32));
            gl.glDrawElements(gl.GL_TRIANGLES, @intCast(cmd.elem_count), gl.GL_UNSIGNED_INT, offset_ptr);
            checkGlError("glDrawElements");
        }

        // In embedded mode, restore previous GL state
        if (self.embedded_mode) {
            if (prev_blend == 0) gl.glDisable(gl.GL_BLEND);
            if (prev_depth_test != 0) gl.glEnable(gl.GL_DEPTH_TEST);
            if (prev_multisample != 0) gl.glEnable(gl.GL_MULTISAMPLE);
        }
    }
};

fn createFallbackTexture() u32 {
    var tex: u32 = 0;
    gl.glGenTextures(1, &tex);
    gl.glBindTexture(gl.GL_TEXTURE_2D, tex);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
    const pixel = [_]u8{ 255, 255, 255, 255 };
    gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, gl.GL_RGBA, 1, 1, 0, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, &pixel);
    return tex;
}

fn setupBuffers(r: *GLRenderer) void {
    gl.glGenVertexArrays(1, &r.vao);
    checkGlError("glGenVertexArrays");
    gl.glGenBuffers(1, &r.vbo);
    checkGlError("glGenBuffers vbo");
    gl.glGenBuffers(1, &r.ibo);
    checkGlError("glGenBuffers ibo");

    gl.glBindVertexArray(r.vao);
    checkGlError("glBindVertexArray");
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, r.vbo);
    checkGlError("glBindBuffer vbo");
    gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, r.ibo);
    checkGlError("glBindBuffer ibo");

    const stride = @sizeOf(Vertex);

    gl.glEnableVertexAttribArray(0);
    checkGlError("glEnableVertexAttribArray 0");
    gl.glVertexAttribPointer(0, 2, gl.GL_FLOAT, gl.GL_FALSE, stride, @ptrFromInt(0));
    checkGlError("glVertexAttribPointer 0");

    gl.glEnableVertexAttribArray(1);
    checkGlError("glEnableVertexAttribArray 1");
    gl.glVertexAttribPointer(1, 2, gl.GL_FLOAT, gl.GL_FALSE, stride, @ptrFromInt(8));
    checkGlError("glVertexAttribPointer 1");

    gl.glEnableVertexAttribArray(2);
    checkGlError("glEnableVertexAttribArray 2");
    gl.glVertexAttribPointer(2, 4, gl.GL_UNSIGNED_BYTE, gl.GL_TRUE, stride, @ptrFromInt(16));
    checkGlError("glVertexAttribPointer 2");

    r.*.proj_loc = gl.glGetUniformLocation(r.shader, "u_projection");
    checkGlError("glGetUniformLocation");

    r.*.tex_loc = gl.glGetUniformLocation(r.shader, "uTexture");
    checkGlError("glGetUniformLocation");
}

fn createShader() u32 {
    const vs_src =
        \\#version 330 core
        \\layout (location = 0) in vec2 in_pos;
        \\layout (location = 1) in vec2 in_uv;
        \\layout (location = 2) in vec4 in_color;
        \\
        \\uniform mat4 u_projection;
        \\
        \\out vec2 vUV;
        \\out vec4 vColor;
        \\
        \\void main() {
        \\    vUV = in_uv;
        \\    vColor = in_color;
        \\    gl_Position = u_projection * vec4(in_pos.xy, 0, 1);
        \\}
    ;

    const fs_src =
        \\#version 330 core
        \\in vec2 vUV;
        \\in vec4 vColor;
        \\
        \\uniform sampler2D uTexture;
        \\
        \\layout (location = 0) out vec4 out_color;
        \\
        \\void main() {
        \\    // Check if this is non-textured geometry (default UV is -1.0, -1.0)
        \\    if (vUV.x < 0.0) {
        \\        // Solid color rendering (for rectangles, shapes, etc.)
        \\        out_color = vColor;
        \\    } else {
        \\        vec4 texColor = texture(uTexture, vUV.st);
        \\        // If texture has color (G or B channels > 0.1), it's a full-color image
        \\        // Otherwise, it's text (single red channel used for alpha)
        \\        if (texColor.g > 0.1 || texColor.b > 0.1) {
        \\            // Full-color image rendering (use RGBA from texture)
        \\            out_color = texColor * vColor;
        \\        } else {
        \\            // Text rendering (use only red channel for alpha)
        \\            out_color = vec4(vColor.rgb, vColor.a * texColor.r);
        \\        }
        \\    }
        \\}
    ;

    const vs_ptrs = [_][*c]const u8{
        @ptrCast(vs_src),
    };

    const fs_ptrs = [_][*c]const u8{
        @ptrCast(fs_src),
    };

    const vs = gl.glCreateShader(gl.GL_VERTEX_SHADER);
    checkGlError("glCreateShader VS");
    const fs = gl.glCreateShader(gl.GL_FRAGMENT_SHADER);
    checkGlError("glCreateShader FS");

    gl.glShaderSource(vs, 1, &vs_ptrs, null);
    checkGlError("glShaderSource VS");
    gl.glCompileShader(vs);
    checkGlError("glCompileShader VS");

    var success: i32 = 0;
    gl.glGetShaderiv(vs, gl.GL_COMPILE_STATUS, &success);
    if (success == 0) {
        var log: [1024]u8 = undefined;
        gl.glGetShaderInfoLog(vs, 1024, null, &log);
        std.debug.print("Vertex shader compilation failed:\n{s}\n", .{log});
    }

    gl.glShaderSource(fs, 1, &fs_ptrs, null);
    checkGlError("glShaderSource FS");
    gl.glCompileShader(fs);
    checkGlError("glCompileShader FS");

    gl.glGetShaderiv(fs, gl.GL_COMPILE_STATUS, &success);
    if (success == 0) {
        var log: [1024]u8 = undefined;
        gl.glGetShaderInfoLog(fs, 1024, null, &log);
        std.debug.print("Fragment shader compilation failed:\n{s}\n", .{log});
    }

    const prog = gl.glCreateProgram();
    checkGlError("glCreateProgram");
    gl.glAttachShader(prog, vs);
    checkGlError("glAttachShader VS");
    gl.glAttachShader(prog, fs);
    checkGlError("glAttachShader FS");
    gl.glLinkProgram(prog);
    checkGlError("glLinkProgram");

    gl.glGetProgramiv(prog, gl.GL_LINK_STATUS, &success);
    if (success == 0) {
        var log: [1024]u8 = undefined;
        gl.glGetProgramInfoLog(prog, 1024, null, &log);
        std.debug.print("Shader program linking failed:\n{s}\n", .{log});
    }

    gl.glDeleteShader(vs);
    checkGlError("glDeleteShader VS");
    gl.glDeleteShader(fs);
    checkGlError("glDeleteShader FS");

    return prog;
}

pub fn checkGlError(location: []const u8) void {
    if (comptime build_options.debug) {
        return;
    }

    var e = gl.glGetError();
    while (e != gl.GL_NO_ERROR) {
        const error_str = switch (e) {
            gl.GL_INVALID_ENUM => "GL_INVALID_ENUM",
            gl.GL_INVALID_VALUE => "GL_INVALID_VALUE",
            gl.GL_INVALID_OPERATION => "GL_INVALID_OPERATION",
            gl.GL_STACK_OVERFLOW => "GL_STACK_OVERFLOW",
            gl.GL_STACK_UNDERFLOW => "GL_STACK_UNDERFLOW",
            gl.GL_OUT_OF_MEMORY => "GL_OUT_OF_MEMORY",
            gl.GL_INVALID_FRAMEBUFFER_OPERATION => "GL_INVALID_FRAMEFRAMEBUFFER_OPERATION",
            else => "UNKNOWN_GL_ERROR",
        };
        std.debug.print("OpenGL Error at {s}: {s}\n", .{ location, error_str });
        e = gl.glGetError();
    }
}

// orthographic projection - column-major order for OpenGL
fn ortho(l: f32, r: f32, b: f32, t: f32, n: f32, f: f32) [16]f32 {
    const rl = r - l;
    const tb = t - b;
    const fn_ = f - n;

    return .{
        // Column 0
        2.0 / rl,
        0.0,
        0.0,
        0.0,
        // Column 1
        0.0,
        2.0 / tb,
        0.0,
        0.0,
        // Column 2
        0.0,
        0.0,
        -2.0 / fn_,
        0.0,
        // Column 3
        -(r + l) / rl,
        -(t + b) / tb,
        -(f + n) / fn_,
        1.0,
    };
}

// Renderer interface wrapper functions
fn rendererInit(context: *anyopaque) void {
    _ = context;
}

fn rendererRender(context: *anyopaque, gui_ctx: *GuiContext, width: i32, height: i32) void {
    const self: *GLRenderer = @ptrCast(@alignCast(context));
    self.render(gui_ctx, width, height);
}

fn rendererCreateTexture(context: *anyopaque, width: i32, height: i32, format: TextureFormat, data: [*]const u8) TextureHandle {
    _ = context;

    var tex: u32 = 0;
    gl.glGenTextures(1, &tex);
    gl.glBindTexture(gl.GL_TEXTURE_2D, tex);

    // Use nearest-neighbor filtering for crisp rendering
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);

    const gl_format: c_uint = switch (format) {
        .r8 => gl.GL_RED,
        .rgba8 => gl.GL_RGBA,
    };

    gl.glTexImage2D(
        gl.GL_TEXTURE_2D,
        0,
        @intCast(gl_format),
        width,
        height,
        0,
        gl_format,
        gl.GL_UNSIGNED_BYTE,
        data,
    );

    return @intCast(tex);
}

fn rendererDeleteTexture(context: *anyopaque, texture: TextureHandle) void {
    _ = context;
    var tex: u32 = @intCast(texture);
    gl.glDeleteTextures(1, &tex);
}

fn rendererWrapTexture(context: *anyopaque, texture_id: u32, width: i32, height: i32) TextureHandle {
    _ = context;
    _ = width;
    _ = height;
    // Simply return the texture ID as a TextureHandle
    // The texture is NOT owned by the renderer and will not be deleted
    return @intCast(texture_id);
}

fn rendererDeinit(context: *anyopaque) void {
    const self: *GLRenderer = @ptrCast(@alignCast(context));
    const allocator = self.allocator;
    self.deinit();
    allocator.destroy(self);
}

/// Create a renderer interface from this OpenGL renderer
/// The allocator is used to allocate the GLRenderer instance
/// The window is used to load OpenGL function pointers via GLAD
pub fn createRenderer(allocator: std.mem.Allocator, window: anytype) !Renderer {
    // Load OpenGL function pointers
    const loader: gl.GLADloadproc = @ptrCast(window.getProcAddressFunction());
    if (gl.gladLoadGLLoader(loader) == 0) {
        return error.OpenGLLoadFailed;
    }

    // Set up OpenGL state
    gl.glEnable(gl.GL_BLEND);
    gl.glBlendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE_MINUS_SRC_ALPHA);
    gl.glEnable(gl.GL_MULTISAMPLE); // Enable MSAA for smooth edges
    gl.glClearColor(0.55, 0.55, 0.55, 1.0);

    const gl_renderer = try allocator.create(GLRenderer);
    gl_renderer.* = GLRenderer.init(allocator);

    return Renderer.init(
        gl_renderer,
        rendererInit,
        rendererRender,
        rendererCreateTexture,
        rendererDeleteTexture,
        rendererWrapTexture,
        rendererDeinit,
    );
}

/// Create a renderer interface for embedded mode
/// Use this when OpenGL is already loaded by another system (e.g., a game engine)
/// The renderer will save/restore GL state and won't clear the screen
pub fn createEmbeddedRenderer(allocator: std.mem.Allocator) !Renderer {
    // Set up OpenGL state for GUI rendering
    gl.glEnable(gl.GL_BLEND);
    gl.glBlendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE_MINUS_SRC_ALPHA);

    const gl_renderer = try allocator.create(GLRenderer);
    gl_renderer.* = GLRenderer.initEmbedded(allocator);

    return Renderer.init(
        gl_renderer,
        rendererInit,
        rendererRender,
        rendererCreateTexture,
        rendererDeleteTexture,
        rendererWrapTexture,
        rendererDeinit,
    );
}
