const std = @import("std");
const types = @import("../core/types.zig");
const draw_data = @import("draw_data.zig");
const font_atlas_mod = @import("font_atlas.zig");
const renderer_mod = @import("renderer.zig");

const c = @cImport({
    @cInclude("glad/glad.h");
});

pub const ProcAddressFn = *const fn (name: [*:0]const u8) ?*const anyopaque;

var active_proc_address_fn: ?ProcAddressFn = null;

pub const OpenGlRenderer = struct {
    vao: c.GLuint = 0,
    vbo: c.GLuint = 0,
    ibo: c.GLuint = 0,
    program: c.GLuint = 0,
    white_texture: c.GLuint = 0,
    projection_location: c.GLint = -1,
    framebuffer_width: u32 = 0,
    framebuffer_height: u32 = 0,
    logical_width: f32 = 0,
    logical_height: f32 = 0,

    pub fn init(proc_address_fn: ProcAddressFn) !OpenGlRenderer {
        try loadGlad(proc_address_fn);
        c.glEnable(c.GL_MULTISAMPLE);

        var self: OpenGlRenderer = .{};
        self.program = try createProgram();
        self.projection_location = c.glGetUniformLocation(self.program, "u_projection");

        c.glGenVertexArrays(1, &self.vao);
        c.glGenBuffers(1, &self.vbo);
        c.glGenBuffers(1, &self.ibo);

        c.glBindVertexArray(self.vao);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, self.vbo);
        c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, self.ibo);

        const stride: c.GLsizei = @intCast(@sizeOf(draw_data.Vertex));
        c.glEnableVertexAttribArray(0);
        c.glVertexAttribPointer(0, 2, c.GL_FLOAT, c.GL_FALSE, stride, @ptrFromInt(@offsetOf(draw_data.Vertex, "pos")));
        c.glEnableVertexAttribArray(1);
        c.glVertexAttribPointer(1, 2, c.GL_FLOAT, c.GL_FALSE, stride, @ptrFromInt(@offsetOf(draw_data.Vertex, "uv")));
        c.glEnableVertexAttribArray(2);
        c.glVertexAttribPointer(2, 4, c.GL_UNSIGNED_BYTE, c.GL_TRUE, stride, @ptrFromInt(@offsetOf(draw_data.Vertex, "color")));

        c.glGenTextures(1, &self.white_texture);
        c.glBindTexture(c.GL_TEXTURE_2D, self.white_texture);
        const white = [_]u8{ 255, 255, 255, 255 };
        c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_RGBA, 1, 1, 0, c.GL_RGBA, c.GL_UNSIGNED_BYTE, &white);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
        c.glBindTexture(c.GL_TEXTURE_2D, 0);

        return self;
    }

    pub fn deinit(self: *OpenGlRenderer) void {
        if (self.white_texture != 0) c.glDeleteTextures(1, &self.white_texture);
        if (self.ibo != 0) c.glDeleteBuffers(1, &self.ibo);
        if (self.vbo != 0) c.glDeleteBuffers(1, &self.vbo);
        if (self.vao != 0) c.glDeleteVertexArrays(1, &self.vao);
        if (self.program != 0) c.glDeleteProgram(self.program);
        self.* = undefined;
    }

    pub fn renderer(self: *OpenGlRenderer) renderer_mod.Renderer {
        return .{
            .ptr = self,
            .beginFrameFn = beginFrameErased,
            .renderFn = renderErased,
            .endFrameFn = endFrameErased,
        };
    }

    pub fn beginFrame(self: *OpenGlRenderer, width: u32, height: u32) !void {
        try self.beginFrameLogical(width, height, @floatFromInt(width), @floatFromInt(height));
    }

    pub fn beginFrameLogical(self: *OpenGlRenderer, framebuffer_width: u32, framebuffer_height: u32, logical_width: f32, logical_height: f32) !void {
        self.framebuffer_width = framebuffer_width;
        self.framebuffer_height = framebuffer_height;
        self.logical_width = @max(1, logical_width);
        self.logical_height = @max(1, logical_height);
        c.glViewport(0, 0, @intCast(framebuffer_width), @intCast(framebuffer_height));
        c.glClearColor(0.055, 0.06, 0.075, 1.0);
        c.glClear(c.GL_COLOR_BUFFER_BIT);
    }

    pub fn render(self: *OpenGlRenderer, data: draw_data.DrawData) !void {
        if (data.vertices.len == 0 or data.indices.len == 0) return;

        c.glUseProgram(self.program);
        c.glBindVertexArray(self.vao);
        c.glEnable(c.GL_BLEND);
        c.glBlendEquation(c.GL_FUNC_ADD);
        c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
        c.glEnable(c.GL_MULTISAMPLE);
        c.glDisable(c.GL_DEPTH_TEST);
        c.glEnable(c.GL_SCISSOR_TEST);

        const projection = ortho(0, self.logical_width, self.logical_height, 0);
        c.glUniformMatrix4fv(self.projection_location, 1, c.GL_FALSE, &projection);

        c.glBindBuffer(c.GL_ARRAY_BUFFER, self.vbo);
        c.glBufferData(
            c.GL_ARRAY_BUFFER,
            @intCast(data.vertices.len * @sizeOf(draw_data.Vertex)),
            data.vertices.ptr,
            c.GL_STREAM_DRAW,
        );
        c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, self.ibo);
        c.glBufferData(
            c.GL_ELEMENT_ARRAY_BUFFER,
            @intCast(data.indices.len * @sizeOf(u32)),
            data.indices.ptr,
            c.GL_STREAM_DRAW,
        );

        for (data.batches) |batch| {
            if (batch.index_count == 0) continue;
            const scissor = scissorRect(batch.clip_rect, self.logical_width, self.logical_height, self.framebuffer_width, self.framebuffer_height);
            c.glScissor(scissor.x, scissor.y, scissor.w, scissor.h);
            c.glBindTexture(c.GL_TEXTURE_2D, if (batch.texture_id == 0) self.white_texture else batch.texture_id);
            c.glDrawElements(
                c.GL_TRIANGLES,
                @intCast(batch.index_count),
                c.GL_UNSIGNED_INT,
                @ptrFromInt(@as(usize, batch.index_offset) * @sizeOf(u32)),
            );
        }

        c.glDisable(c.GL_SCISSOR_TEST);
        c.glBindVertexArray(0);
        c.glUseProgram(0);
    }

    pub fn createTextureRgba(self: *OpenGlRenderer, width: u32, height: u32, pixels: []const u8) !u32 {
        _ = self;
        try validateTexturePixels(width, height, pixels);

        var texture: c.GLuint = 0;
        c.glGenTextures(1, &texture);
        if (texture == 0) return error.OpenGlTextureCreateFailed;

        c.glBindTexture(c.GL_TEXTURE_2D, texture);
        c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, 1);
        c.glTexImage2D(
            c.GL_TEXTURE_2D,
            0,
            c.GL_RGBA,
            @intCast(width),
            @intCast(height),
            0,
            c.GL_RGBA,
            c.GL_UNSIGNED_BYTE,
            pixels.ptr,
        );
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
        c.glBindTexture(c.GL_TEXTURE_2D, 0);
        return texture;
    }

    pub fn uploadTextureRgba(self: *OpenGlRenderer, texture_id: u32, width: u32, height: u32, pixels: []const u8) !void {
        _ = self;
        if (texture_id == 0) return error.InvalidTexture;
        try validateTexturePixels(width, height, pixels);

        c.glBindTexture(c.GL_TEXTURE_2D, texture_id);
        c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, 1);
        c.glTexImage2D(
            c.GL_TEXTURE_2D,
            0,
            c.GL_RGBA,
            @intCast(width),
            @intCast(height),
            0,
            c.GL_RGBA,
            c.GL_UNSIGNED_BYTE,
            pixels.ptr,
        );
        c.glBindTexture(c.GL_TEXTURE_2D, 0);
    }

    pub fn syncFontAtlas(self: *OpenGlRenderer, font_atlas: *font_atlas_mod.FontAtlas) !void {
        if (font_atlas.texture_id == 0) {
            font_atlas.texture_id = try self.createTextureRgba(font_atlas.width, font_atlas.height, font_atlas.pixels);
            font_atlas.markClean();
            return;
        }

        if (font_atlas.dirty or font_atlas.full_upload) {
            try self.uploadTextureRgba(font_atlas.texture_id, font_atlas.width, font_atlas.height, font_atlas.pixels);
            font_atlas.markClean();
        }
    }

    pub fn endFrame(self: *OpenGlRenderer) !void {
        _ = self;
    }

    pub fn versionString() []const u8 {
        const ptr = c.glGetString(c.GL_VERSION) orelse return "unknown";
        return std.mem.span(@as([*:0]const u8, @ptrCast(ptr)));
    }

    fn beginFrameErased(ptr: *anyopaque, width: u32, height: u32) anyerror!void {
        const self: *OpenGlRenderer = @ptrCast(@alignCast(ptr));
        try self.beginFrame(width, height);
    }

    fn renderErased(ptr: *anyopaque, data: draw_data.DrawData) anyerror!void {
        const self: *OpenGlRenderer = @ptrCast(@alignCast(ptr));
        try self.render(data);
    }

    fn endFrameErased(ptr: *anyopaque) anyerror!void {
        const self: *OpenGlRenderer = @ptrCast(@alignCast(ptr));
        try self.endFrame();
    }
};

pub fn loadGlad(proc_address_fn: ProcAddressFn) !void {
    active_proc_address_fn = proc_address_fn;
    if (c.gladLoadGLLoader(gladLoader) == 0) return error.GladLoadFailed;
}

fn gladLoader(name: [*c]const u8) callconv(.c) ?*anyopaque {
    const loader = active_proc_address_fn orelse return null;
    const sentinel_name: [*:0]const u8 = @ptrCast(name);
    const ptr = loader(sentinel_name) orelse return null;
    return @ptrCast(@constCast(ptr));
}

fn createProgram() !c.GLuint {
    const vertex = try compileShader(c.GL_VERTEX_SHADER, vertex_shader_source);
    defer c.glDeleteShader(vertex);
    const fragment = try compileShader(c.GL_FRAGMENT_SHADER, fragment_shader_source);
    defer c.glDeleteShader(fragment);

    const program = c.glCreateProgram();
    c.glAttachShader(program, vertex);
    c.glAttachShader(program, fragment);
    c.glLinkProgram(program);

    var ok: c.GLint = 0;
    c.glGetProgramiv(program, c.GL_LINK_STATUS, &ok);
    if (ok == 0) {
        c.glDeleteProgram(program);
        return error.OpenGlProgramLinkFailed;
    }
    return program;
}

fn compileShader(kind: c.GLenum, source: [:0]const u8) !c.GLuint {
    const shader = c.glCreateShader(kind);
    var source_ptr: [*c]const u8 = source.ptr;
    c.glShaderSource(shader, 1, &source_ptr, null);
    c.glCompileShader(shader);

    var ok: c.GLint = 0;
    c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &ok);
    if (ok == 0) {
        c.glDeleteShader(shader);
        return error.OpenGlShaderCompileFailed;
    }
    return shader;
}

fn ortho(left: f32, right: f32, bottom: f32, top: f32) [16]f32 {
    const near: f32 = -1;
    const far: f32 = 1;
    return .{
        2 / (right - left),               0,                                0,                            0,
        0,                                2 / (top - bottom),               0,                            0,
        0,                                0,                                -2 / (far - near),            0,
        -(right + left) / (right - left), -(top + bottom) / (top - bottom), -(far + near) / (far - near), 1,
    };
}

const Scissor = struct {
    x: c.GLint,
    y: c.GLint,
    w: c.GLsizei,
    h: c.GLsizei,
};

fn scissorRect(rect: types.Rect, logical_width: f32, logical_height: f32, framebuffer_width: u32, framebuffer_height: u32) Scissor {
    const fw: f32 = @floatFromInt(framebuffer_width);
    const fh: f32 = @floatFromInt(framebuffer_height);
    const scale_x = fw / @max(1, logical_width);
    const scale_y = fh / @max(1, logical_height);
    const min_x = clamp(rect.x * scale_x, 0, fw);
    const min_y = clamp(rect.y * scale_y, 0, fh);
    const max_x = clamp((rect.x + rect.w) * scale_x, 0, fw);
    const max_y = clamp((rect.y + rect.h) * scale_y, 0, fh);
    return .{
        .x = @intFromFloat(min_x),
        .y = @intFromFloat(fh - max_y),
        .w = @intFromFloat(@max(0, max_x - min_x)),
        .h = @intFromFloat(@max(0, max_y - min_y)),
    };
}

fn clamp(v: f32, lo: f32, hi: f32) f32 {
    return @min(hi, @max(lo, v));
}

fn validateTexturePixels(width: u32, height: u32, pixels: []const u8) !void {
    const pixel_count = try std.math.mul(usize, @intCast(width), @intCast(height));
    const byte_count = try std.math.mul(usize, pixel_count, 4);
    if (pixels.len < byte_count) return error.InvalidTextureData;
}

const vertex_shader_source =
    \\#version 330 core
    \\layout(location = 0) in vec2 in_pos;
    \\layout(location = 1) in vec2 in_uv;
    \\layout(location = 2) in vec4 in_color;
    \\uniform mat4 u_projection;
    \\out vec2 v_uv;
    \\out vec4 v_color;
    \\void main() {
    \\    v_uv = in_uv;
    \\    v_color = in_color;
    \\    gl_Position = u_projection * vec4(in_pos, 0.0, 1.0);
    \\}
;

const fragment_shader_source =
    \\#version 330 core
    \\in vec2 v_uv;
    \\in vec4 v_color;
    \\uniform sampler2D u_texture;
    \\out vec4 out_color;
    \\void main() {
    \\    out_color = v_color * texture(u_texture, v_uv);
    \\}
;
