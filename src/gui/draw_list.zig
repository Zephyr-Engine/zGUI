const std = @import("std");
const shapes = @import("shapes.zig");
const Font = @import("text/font.zig").Font;
const TextureHandle = @import("renderer.zig").TextureHandle;

pub const DrawCmd = struct {
    texture: TextureHandle,
    elem_count: u32,
    index_offset: u32,
};

pub const DrawList = struct {
    allocator: std.mem.Allocator,

    // Dynamic slices - allocated from frame arena each frame
    vertices: []shapes.Vertex,
    vertex_count: usize,

    indices: []u32,
    index_count: usize,

    commands: []DrawCmd,
    command_count: usize,

    current_texture: TextureHandle,

    // Initial capacity estimates for frame allocation
    const INITIAL_VERTEX_CAPACITY = 4096;
    const INITIAL_INDEX_CAPACITY = 8192;
    const INITIAL_COMMAND_CAPACITY = 64;

    pub fn init(allocator: std.mem.Allocator) !DrawList {
        return DrawList{
            .allocator = allocator,
            .vertices = try allocator.alloc(shapes.Vertex, INITIAL_VERTEX_CAPACITY),
            .vertex_count = 0,
            .indices = try allocator.alloc(u32, INITIAL_INDEX_CAPACITY),
            .index_count = 0,
            .commands = try allocator.alloc(DrawCmd, INITIAL_COMMAND_CAPACITY),
            .command_count = 0,
            .current_texture = 0,
        };
    }

    // No clear() needed - we just reset counters and allocate fresh each frame
    // No deinit() needed - frame arena handles cleanup

    /// Get the currently used vertices slice
    pub fn getVertices(self: *const DrawList) []const shapes.Vertex {
        return self.vertices[0..self.vertex_count];
    }

    /// Get the currently used indices slice
    pub fn getIndices(self: *const DrawList) []const u32 {
        return self.indices[0..self.index_count];
    }

    /// Get the currently used commands slice
    pub fn getCommands(self: *const DrawList) []const DrawCmd {
        return self.commands[0..self.command_count];
    }

    fn ensureVertexCapacity(self: *DrawList, additional: usize) !void {
        const required = self.vertex_count + additional;
        if (required > self.vertices.len) {
            const new_capacity = @max(required, self.vertices.len * 2);
            const new_vertices = try self.allocator.alloc(shapes.Vertex, new_capacity);
            @memcpy(new_vertices[0..self.vertex_count], self.vertices[0..self.vertex_count]);
            self.vertices = new_vertices;
        }
    }

    fn ensureIndexCapacity(self: *DrawList, additional: usize) !void {
        const required = self.index_count + additional;
        if (required > self.indices.len) {
            const new_capacity = @max(required, self.indices.len * 2);
            const new_indices = try self.allocator.alloc(u32, new_capacity);
            @memcpy(new_indices[0..self.index_count], self.indices[0..self.index_count]);
            self.indices = new_indices;
        }
    }

    fn ensureCommandCapacity(self: *DrawList, additional: usize) !void {
        const required = self.command_count + additional;
        if (required > self.commands.len) {
            const new_capacity = @max(required, self.commands.len * 2);
            const new_commands = try self.allocator.alloc(DrawCmd, new_capacity);
            @memcpy(new_commands[0..self.command_count], self.commands[0..self.command_count]);
            self.commands = new_commands;
        }
    }

    pub fn setTexture(self: *DrawList, texture: TextureHandle) !void {
        if (texture != self.current_texture) {
            self.current_texture = texture;

            // Start a new draw command for this texture
            if (self.command_count > 0) {
                // Close the previous command
                const prev_cmd = &self.commands[self.command_count - 1];
                const current_index: u32 = @intCast(self.index_count);
                prev_cmd.elem_count = current_index - prev_cmd.index_offset;
            }
            // Add new command
            try self.ensureCommandCapacity(1);
            self.commands[self.command_count] = DrawCmd{
                .texture = texture,
                .elem_count = 0,
                .index_offset = @intCast(self.index_count),
            };
            self.command_count += 1;
        }
    }

    fn ensureDrawCmd(self: *DrawList) !void {
        if (self.command_count == 0) {
            try self.ensureCommandCapacity(1);
            self.commands[self.command_count] = DrawCmd{
                .texture = self.current_texture,
                .elem_count = 0,
                .index_offset = 0,
            };
            self.command_count += 1;
        }
    }

    fn updateCurrentCmd(self: *DrawList) void {
        if (self.command_count > 0) {
            const cmd = &self.commands[self.command_count - 1];
            const current_index: u32 = @intCast(self.index_count);
            cmd.elem_count = current_index - cmd.index_offset;
        }
    }

    pub fn addVertex(self: *DrawList, v: shapes.Vertex) !void {
        try self.ensureDrawCmd();
        const idx: u32 = @intCast(self.vertex_count);

        try self.ensureVertexCapacity(1);
        self.vertices[self.vertex_count] = v;
        self.vertex_count += 1;

        try self.ensureIndexCapacity(1);
        self.indices[self.index_count] = idx;
        self.index_count += 1;

        self.updateCurrentCmd();
    }

    pub fn addTriangle(self: *DrawList, v1: shapes.Vertex, v2: shapes.Vertex, v3: shapes.Vertex) !void {
        try self.ensureDrawCmd();
        try self.addVertex(v1);
        try self.addVertex(v2);
        try self.addVertex(v3);
    }

    pub fn addRect(self: *DrawList, rect: shapes.Rect, color: shapes.Color) !void {
        try self.ensureDrawCmd();
        const rgba = shapes.colorToRGBA(color);
        const v1 = shapes.Vertex{ .pos = .{ rect.x, rect.y }, .color = rgba };
        const v2 = shapes.Vertex{ .pos = .{ rect.x + rect.w, rect.y }, .color = rgba };
        const v3 = shapes.Vertex{ .pos = .{ rect.x + rect.w, rect.y + rect.h }, .color = rgba };
        const v4 = shapes.Vertex{ .pos = .{ rect.x, rect.y + rect.h }, .color = rgba };

        const base: u32 = @intCast(self.vertex_count);

        try self.ensureVertexCapacity(4);
        self.vertices[self.vertex_count] = v1;
        self.vertices[self.vertex_count + 1] = v2;
        self.vertices[self.vertex_count + 2] = v3;
        self.vertices[self.vertex_count + 3] = v4;
        self.vertex_count += 4;

        try self.ensureIndexCapacity(6);
        const idx_slice = self.indices[self.index_count..];
        idx_slice[0] = base;
        idx_slice[1] = base + 1;
        idx_slice[2] = base + 2;
        idx_slice[3] = base;
        idx_slice[4] = base + 2;
        idx_slice[5] = base + 3;
        self.index_count += 6;

        self.updateCurrentCmd();
    }

    pub fn addRoundedRect(self: *DrawList, rect: shapes.Rect, radius: f32, color: shapes.Color) !void {
        try self.ensureDrawCmd();

        const segments_per_corner = 8;
        const pi = std.math.pi;

        // Clamp radius to not exceed half of the smallest dimension
        const max_radius = @min(rect.w, rect.h) * 0.5;
        const r = @min(radius, max_radius);

        // Corner centers and their start angles (going clockwise from top-left)
        const corners = [4][2]f32{
            .{ rect.x + r, rect.y + r }, // Top-left
            .{ rect.x + rect.w - r, rect.y + r }, // Top-right
            .{ rect.x + rect.w - r, rect.y + rect.h - r }, // Bottom-right
            .{ rect.x + r, rect.y + rect.h - r }, // Bottom-left
        };

        const start_angles = [4]f32{
            pi, // Top-left: start at π (pointing left)
            1.5 * pi, // Top-right: start at 3π/2 (pointing up)
            0.0, // Bottom-right: start at 0 (pointing right)
            0.5 * pi, // Bottom-left: start at π/2 (pointing down)
        };

        const base: u32 = @intCast(self.vertex_count);
        const rgba = shapes.colorToRGBA(color);

        // Center vertex for triangle fan
        const center_x = rect.x + rect.w * 0.5;
        const center_y = rect.y + rect.h * 0.5;

        const vertex_count = 1 + 4 * (segments_per_corner + 1);
        try self.ensureVertexCapacity(vertex_count);

        self.vertices[self.vertex_count] = shapes.Vertex{
            .pos = .{ center_x, center_y },
            .color = rgba,
        };
        self.vertex_count += 1;

        // Generate vertices for each corner arc
        var i: usize = 0;
        while (i < 4) : (i += 1) {
            var seg: usize = 0;
            while (seg <= segments_per_corner) : (seg += 1) {
                const t = @as(f32, @floatFromInt(seg)) / @as(f32, @floatFromInt(segments_per_corner));
                const angle = start_angles[i] + t * pi * 0.5;
                const x = corners[i][0] + @cos(angle) * r;
                const y = corners[i][1] + @sin(angle) * r;

                self.vertices[self.vertex_count] = shapes.Vertex{
                    .pos = .{ x, y },
                    .color = rgba,
                };
                self.vertex_count += 1;
            }
        }

        // Generate indices for triangle fan
        const index_count = (vertex_count - 1) * 3;
        try self.ensureIndexCapacity(index_count);

        var idx: u32 = 1;
        while (idx < vertex_count - 1) : (idx += 1) {
            self.indices[self.index_count] = base;
            self.indices[self.index_count + 1] = base + idx;
            self.indices[self.index_count + 2] = base + idx + 1;
            self.index_count += 3;
        }

        // Close the loop
        self.indices[self.index_count] = base;
        self.indices[self.index_count + 1] = base + vertex_count - 1;
        self.indices[self.index_count + 2] = base + 1;
        self.index_count += 3;

        self.updateCurrentCmd();
    }

    pub fn addRoundedRectOutline(self: *DrawList, rect: shapes.Rect, radius: f32, thickness: f32, color: shapes.Color) !void {
        try self.ensureDrawCmd();

        const segments_per_corner = 8;
        const pi = std.math.pi;

        // Clamp radius to not exceed half of the smallest dimension
        const max_radius = @min(rect.w, rect.h) * 0.5;
        const r = @min(radius, max_radius);

        // Clamp thickness to not exceed radius
        const t = @min(thickness, r);
        const inner_radius = r - t;

        // Corner centers and their start angles (going clockwise from top-left)
        const corners = [4][2]f32{
            .{ rect.x + r, rect.y + r }, // Top-left
            .{ rect.x + rect.w - r, rect.y + r }, // Top-right
            .{ rect.x + rect.w - r, rect.y + rect.h - r }, // Bottom-right
            .{ rect.x + r, rect.y + rect.h - r }, // Bottom-left
        };

        const start_angles = [4]f32{
            pi, // Top-left: start at π (pointing left)
            1.5 * pi, // Top-right: start at 3π/2 (pointing up)
            0.0, // Bottom-right: start at 0 (pointing right)
            0.5 * pi, // Bottom-left: start at π/2 (pointing down)
        };

        const base: u32 = @intCast(self.vertex_count);
        const rgba = shapes.colorToRGBA(color);

        const vertices_per_corner = segments_per_corner + 1;
        const total_vertices = 4 * vertices_per_corner * 2; // 2 vertices per point (outer + inner)
        try self.ensureVertexCapacity(total_vertices);

        // Generate outer and inner vertices for each corner arc
        var i: usize = 0;
        while (i < 4) : (i += 1) {
            var seg: usize = 0;
            while (seg <= segments_per_corner) : (seg += 1) {
                const angle_t = @as(f32, @floatFromInt(seg)) / @as(f32, @floatFromInt(segments_per_corner));
                const angle = start_angles[i] + angle_t * pi * 0.5;

                // Outer vertex
                const outer_x = corners[i][0] + @cos(angle) * r;
                const outer_y = corners[i][1] + @sin(angle) * r;
                self.vertices[self.vertex_count] = shapes.Vertex{
                    .pos = .{ outer_x, outer_y },
                    .color = rgba,
                };
                self.vertex_count += 1;

                // Inner vertex
                const inner_x = corners[i][0] + @cos(angle) * inner_radius;
                const inner_y = corners[i][1] + @sin(angle) * inner_radius;
                self.vertices[self.vertex_count] = shapes.Vertex{
                    .pos = .{ inner_x, inner_y },
                    .color = rgba,
                };
                self.vertex_count += 1;
            }
        }

        // Generate indices to form triangles between outer and inner vertices
        const total_vertex_pairs = 4 * vertices_per_corner;
        const total_indices = total_vertex_pairs * 6; // 2 triangles per quad
        try self.ensureIndexCapacity(total_indices);

        var pair: u32 = 0;
        while (pair < total_vertex_pairs) : (pair += 1) {
            const next_pair = (pair + 1) % total_vertex_pairs;

            const outer_curr = base + pair * 2;
            const inner_curr = base + pair * 2 + 1;
            const outer_next = base + next_pair * 2;
            const inner_next = base + next_pair * 2 + 1;

            // Two triangles forming a quad between current and next pair
            self.indices[self.index_count] = outer_curr;
            self.indices[self.index_count + 1] = inner_curr;
            self.indices[self.index_count + 2] = outer_next;
            self.index_count += 3;

            self.indices[self.index_count] = inner_curr;
            self.indices[self.index_count + 1] = inner_next;
            self.indices[self.index_count + 2] = outer_next;
            self.index_count += 3;
        }

        self.updateCurrentCmd();
    }

    pub fn addRectUV(
        self: *DrawList,
        rect: shapes.Rect,
        uv_min: [2]f32,
        uv_max: [2]f32,
        color: shapes.Color,
    ) !void {
        try self.ensureDrawCmd();
        const x1 = rect.x;
        const y1 = rect.y;
        const x2 = rect.x + rect.w;
        const y2 = rect.y + rect.h;

        const uv1 = uv_min[0];
        const v1 = uv_min[1];
        const uv2 = uv_max[0];
        const v2 = uv_max[1];

        const rgba = shapes.colorToRGBA(color);
        const base: u32 = @intCast(self.vertex_count);

        try self.ensureVertexCapacity(4);
        self.vertices[self.vertex_count] = .{ .pos = .{ x1, y1 }, .uv = .{ uv1, v1 }, .color = rgba };
        self.vertices[self.vertex_count + 1] = .{ .pos = .{ x2, y1 }, .uv = .{ uv2, v1 }, .color = rgba };
        self.vertices[self.vertex_count + 2] = .{ .pos = .{ x2, y2 }, .uv = .{ uv2, v2 }, .color = rgba };
        self.vertices[self.vertex_count + 3] = .{ .pos = .{ x1, y2 }, .uv = .{ uv1, v2 }, .color = rgba };
        self.vertex_count += 4;

        try self.ensureIndexCapacity(6);
        const idx_slice = self.indices[self.index_count..];
        idx_slice[0] = base;
        idx_slice[1] = base + 1;
        idx_slice[2] = base + 2;
        idx_slice[3] = base;
        idx_slice[4] = base + 2;
        idx_slice[5] = base + 3;
        self.index_count += 6;

        self.updateCurrentCmd();
    }

    /// Add a textured rectangle with rotation around its center
    /// angle: rotation in radians (positive = counter-clockwise)
    pub fn addRectUVRotated(
        self: *DrawList,
        rect: shapes.Rect,
        uv_min: [2]f32,
        uv_max: [2]f32,
        color: shapes.Color,
        angle: f32,
    ) !void {
        try self.ensureDrawCmd();

        // Calculate center point
        const cx = rect.x + rect.w * 0.5;
        const cy = rect.y + rect.h * 0.5;

        // Half dimensions for corners relative to center
        const half_w = rect.w * 0.5;
        const half_h = rect.h * 0.5;

        // Precompute rotation
        const cos_a = @cos(angle);
        const sin_a = @sin(angle);

        // Apply 2D rotation matrix to each corner
        // [x'] = [cos(θ)  -sin(θ)] [x] + [cx]
        // [y']   [sin(θ)   cos(θ)] [y]   [cy]

        // Top-left: (-half_w, -half_h)
        const tl_x = cx + (-half_w * cos_a - (-half_h) * sin_a);
        const tl_y = cy + (-half_w * sin_a + (-half_h) * cos_a);

        // Top-right: (half_w, -half_h)
        const tr_x = cx + (half_w * cos_a - (-half_h) * sin_a);
        const tr_y = cy + (half_w * sin_a + (-half_h) * cos_a);

        // Bottom-right: (half_w, half_h)
        const br_x = cx + (half_w * cos_a - half_h * sin_a);
        const br_y = cy + (half_w * sin_a + half_h * cos_a);

        // Bottom-left: (-half_w, half_h)
        const bl_x = cx + (-half_w * cos_a - half_h * sin_a);
        const bl_y = cy + (-half_w * sin_a + half_h * cos_a);

        const rgba = shapes.colorToRGBA(color);
        const uv1 = uv_min[0];
        const v1 = uv_min[1];
        const uv2 = uv_max[0];
        const v2 = uv_max[1];

        const base: u32 = @intCast(self.vertex_count);

        try self.ensureVertexCapacity(4);
        self.vertices[self.vertex_count] = .{ .pos = .{ tl_x, tl_y }, .uv = .{ uv1, v1 }, .color = rgba };
        self.vertices[self.vertex_count + 1] = .{ .pos = .{ tr_x, tr_y }, .uv = .{ uv2, v1 }, .color = rgba };
        self.vertices[self.vertex_count + 2] = .{ .pos = .{ br_x, br_y }, .uv = .{ uv2, v2 }, .color = rgba };
        self.vertices[self.vertex_count + 3] = .{ .pos = .{ bl_x, bl_y }, .uv = .{ uv1, v2 }, .color = rgba };
        self.vertex_count += 4;

        try self.ensureIndexCapacity(6);
        const idx_slice = self.indices[self.index_count..];
        idx_slice[0] = base;
        idx_slice[1] = base + 1;
        idx_slice[2] = base + 2;
        idx_slice[3] = base;
        idx_slice[4] = base + 2;
        idx_slice[5] = base + 3;
        self.index_count += 6;

        self.updateCurrentCmd();
    }

    pub fn addText(self: *DrawList, font: *const Font, x: f32, y: f32, text: []const u8, color: shapes.Color) !void {
        try self.addTextScaled(font, x, y, text, color, 1.0);
    }

    /// Render text with content scale compensation.
    /// When fonts are rasterized at physical_size = logical_size * scale,
    /// glyph metrics must be divided by scale to produce logical coordinates.
    pub fn addTextScaled(self: *DrawList, font: *const Font, x: f32, y: f32, text: []const u8, color: shapes.Color, scale: f32) !void {
        const inv_scale = 1.0 / scale;

        // Pixel-snap the text origin so all text at the same logical Y
        // lands on the same pixel row. Glyph offsets are kept fractional
        // to preserve relative positioning within the string.
        var cursor_x = @round(x);
        const cursor_y = @round(y + font.ascent * inv_scale);

        for (text) |c| {
            const glyph_index: usize = @intCast(c);
            const g = font.glyphs[glyph_index];

            const gx0 = cursor_x + g.x_off * inv_scale;
            const gy0 = cursor_y + g.y_off * inv_scale;
            const gw = @as(f32, @floatFromInt(g.x1 - g.x0)) * inv_scale;
            const gh = @as(f32, @floatFromInt(g.y1 - g.y0)) * inv_scale;

            try self.addRectUV(.{ .x = gx0, .y = gy0, .w = gw, .h = gh }, g.uv0, g.uv1, color);

            cursor_x += g.x_advance * inv_scale;
        }
    }
};
