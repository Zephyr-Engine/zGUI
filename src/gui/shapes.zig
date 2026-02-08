// Color is a 32-bit hex value in RGBA format
// Example: 0xFFFFFFFF = white, 0xFF0000FF = red, 0x00FF00FF = green
pub const Color = u32;

// Convert Color (u32 hex) to RGBA bytes for OpenGL
pub fn colorToRGBA(color: Color) [4]u8 {
    return .{
        @intCast((color >> 24) & 0xFF), // R
        @intCast((color >> 16) & 0xFF), // G
        @intCast((color >> 8) & 0xFF),  // B
        @intCast(color & 0xFF),         // A
    };
}

pub const Vertex = struct {
    pos: [2]f32,
    uv: [2]f32 = .{ -1.0, -1.0 },
    color: [4]u8 = .{ 255, 255, 255, 255 }, // Keep as [4]u8 for OpenGL memory layout
};

pub const Rect = struct { x: f32, y: f32, w: f32, h: f32 };
