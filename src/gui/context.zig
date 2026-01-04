const builtin = @import("builtin");
const std = @import("std");

const Renderer = @import("renderer.zig").Renderer;
const TextureHandle = @import("renderer.zig").TextureHandle;
const FontCache = @import("text/font_cache.zig").FontCache;
const TextMetrics = @import("text/font.zig").TextMetrics;
const DrawList = @import("draw_list.zig").DrawList;
const Image = @import("widgets/image.zig").Image;
const Input = @import("input.zig").Input;
const layout = @import("layout.zig");
const shapes = @import("shapes.zig");
const Direction = layout.Direction;
const Layout = layout.Layout;
const dropdown = @import("widgets/dropdown.zig");
const DropdownOverlay = dropdown.DropdownOverlay;
const window = @import("window.zig");
const Window = window.Window;
const Cursor = window.Cursor;

pub const ActiveInputState = struct {
    cursor_pos: usize,
    scroll_offset: f32,
    selection_start: ?usize,
    cursor_blink_time: f64,
    number_buffer: ?[32]u8,
    number_buffer_len: usize,

    pub fn init() ActiveInputState {
        return .{
            .cursor_pos = 0,
            .scroll_offset = 0.0,
            .selection_start = null,
            .cursor_blink_time = 0.0,
            .number_buffer = null,
            .number_buffer_len = 0,
        };
    }
};

pub const ResizeBorder = enum {
    left,
    right,
    top,
    bottom,
};

pub const ResizeState = struct {
    dragging: bool,
    panel_id: u64,
    border: ResizeBorder,
    initial_mouse_pos: f32,
    panel_rect: shapes.Rect,
    initial_x_offset: f32,
    initial_y_offset: f32,

    pub fn init() ResizeState {
        return .{
            .dragging = false,
            .panel_id = 0,
            .border = .right,
            .initial_mouse_pos = 0.0,
            .panel_rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
            .initial_x_offset = 0.0,
            .initial_y_offset = 0.0,
        };
    }
};

pub const PanelSize = struct {
    width: ?f32,
    height: ?f32,
    min_width: f32 = 0.0,
    min_height: f32 = 0.0,
    x_offset: f32 = 0.0,
    y_offset: f32 = 0.0,
};

pub const GuiContext = struct {
    draw_list: DrawList,
    input: Input,
    font_cache: FontCache,
    current_font_texture: TextureHandle,
    renderer: *Renderer,
    window: ?Window,

    // Optional checkmark image for checkbox widget (can be set by user)
    checkmark_image: ?Image,

    // Active input widget state (only exists when an input is focused)
    active_input_id: ?u64,
    active_input_state: ?ActiveInputState,

    // Active dropdown widget (only one can be open at a time)
    active_dropdown_id: ?u64,
    active_dropdown_overlay: ?DropdownOverlay,
    dropdown_selection_changed: bool,
    dropdown_selection_id: u64,
    dropdown_selected_index: usize,

    // Click consumption for layered widgets
    click_consumed: bool,

    // Panel resize state
    resize_state: ResizeState,
    panel_sizes: std.AutoHashMap(u64, PanelSize),
    current_panel_id: ?u64, // Track which panel the current layout belongs to

    // Layout stack for managing nested layouts
    layout_stack: std.ArrayList(Layout),
    allocator: std.mem.Allocator,

    // Global layout position tracking for automatic positioning
    next_layout_x: f32,
    next_layout_y: f32,
    window_width: f32, // Current window width
    window_height: f32, // Current window height

    // Track if we're currently resizing to skip expensive UI rebuilding
    is_resizing: bool,
    last_resize_time: f64,

    // Cursor management
    arrow_cursor: ?*Cursor,
    hand_cursor: ?*Cursor,
    hresize_cursor: ?*Cursor,
    vresize_cursor: ?*Cursor,
    ibeam_cursor: ?*Cursor,
    current_cursor: ?*Cursor,

    pub fn init(allocator: std.mem.Allocator, renderer: *Renderer, win: ?Window) !GuiContext {
        // Only create cursors if we have a window
        const arrow_cursor = if (win) |_| window.createStandardCursor(.arrow) else null;
        const hand_cursor = if (win) |_| window.createStandardCursor(.hand) else null;
        const hresize_cursor = if (win) |_| window.createStandardCursor(.hresize) else null;
        const vresize_cursor = if (win) |_| window.createStandardCursor(.vresize) else null;
        const ibeam_cursor = if (win) |_| window.createStandardCursor(.ibeam) else null;

        const ctx = GuiContext{
            .allocator = allocator,
            .draw_list = DrawList.init(allocator),
            .input = Input.init(),
            .font_cache = FontCache.init(allocator, "assets/RobotoMono-Regular.ttf", renderer),
            .current_font_texture = 0,
            .renderer = renderer,
            .window = win,
            .checkmark_image = null,
            .window_width = 0.0,
            .window_height = 0.0,
            .active_input_id = null,
            .active_input_state = null,
            .active_dropdown_id = null,
            .active_dropdown_overlay = null,
            .dropdown_selection_changed = false,
            .dropdown_selection_id = 0,
            .dropdown_selected_index = 0,
            .click_consumed = false,
            .resize_state = ResizeState.init(),
            .panel_sizes = std.AutoHashMap(u64, PanelSize).init(allocator),
            .current_panel_id = null,
            .layout_stack = .empty,
            .next_layout_x = 0.0,
            .next_layout_y = 0.0,
            .is_resizing = false,
            .last_resize_time = 0.0,
            .arrow_cursor = arrow_cursor,
            .hand_cursor = hand_cursor,
            .hresize_cursor = hresize_cursor,
            .vresize_cursor = vresize_cursor,
            .ibeam_cursor = ibeam_cursor,
            .current_cursor = arrow_cursor,
        };
        return ctx;
    }

    pub fn newFrame(self: *GuiContext) void {
        self.input.beginFrame();
        self.draw_list.clear();
        self.layout_stack.clearRetainingCapacity();
        self.current_panel_id = null;
        self.next_layout_x = 0.0;
        self.next_layout_y = 0.0;
        self.click_consumed = false;

        // root layout
        self.layout_stack.append(self.allocator, Layout.init(Direction.HORIZONTAL, 0, 0, .{
            .height = self.window_height,
            .width = self.window_width,
        })) catch {};

        const current_time = window.getTime();
        if (self.is_resizing and (current_time - self.last_resize_time) > 0.05) {
            self.is_resizing = false;
        }

        self.setCursor(self.arrow_cursor);
    }

    /// Update input from a window (for GLFW-based applications)
    pub fn updateInput(self: *GuiContext, win: Window) void {
        self.input.update(win);

        // Consume clicks if they're over an active dropdown overlay
        self.consumeOverlayClicks();
    }

    /// Direct input injection methods for game engines

    /// Inject mouse movement
    pub fn injectMouseMove(self: *GuiContext, x: f64, y: f64) void {
        self.input.cursor_x = x;
        self.input.cursor_y = y;
    }

    /// Inject mouse button state
    pub fn injectMouseButton(self: *GuiContext, button: window.MouseButton, pressed: bool) void {
        switch (button) {
            .left => {
                if (pressed and !self.input.mouse_left_pressed) {
                    self.input.registerMouseClick();
                }
                self.input.mouse_left_pressed = pressed;
            },
            .right => {
                if (pressed and !self.input.mouse_right_pressed) {
                    self.input.registerRightClick();
                }
                self.input.mouse_right_pressed = pressed;
            },
            .middle => {
                if (pressed and !self.input.mouse_middle_pressed) {
                    self.input.registerMiddleClick();
                }
                self.input.mouse_middle_pressed = pressed;
            },
        }
    }

    /// Inject character input (for text entry)
    pub fn injectChar(self: *GuiContext, codepoint: u32) void {
        self.input.registerChar(codepoint);
    }

    /// Inject keyboard key
    pub fn injectKey(self: *GuiContext, key: c_int, action: window.KeyAction) void {
        self.input.registerKey(key, @intFromEnum(action));
    }

    /// Inject scroll wheel
    pub fn injectScroll(self: *GuiContext, xoffset: f64, yoffset: f64) void {
        self.input.registerScroll(xoffset, yoffset);
    }

    /// Inject modifier keys state
    pub fn injectModifiers(self: *GuiContext, ctrl: bool, alt: bool, shift: bool, super: bool) void {
        self.input.ctrl_pressed = ctrl;
        self.input.alt_pressed = alt;
        self.input.shift_pressed = shift;
        self.input.super_pressed = super;

        // Set primary modifier based on platform
        self.input.primary_pressed = if (builtin.os.tag == .macos) super else ctrl;
    }

    fn consumeOverlayClicks(self: *GuiContext) void {
        if (self.active_dropdown_overlay) |overlay| {
            const button_rect = overlay.button_rect;
            const dropdown_width = @max(200.0, button_rect.w);
            const dropdown_height = @as(f32, @floatFromInt(overlay.options.len)) * overlay.opts.item_height;

            const dropdown_rect = shapes.Rect{
                .x = button_rect.x,
                .y = button_rect.y + button_rect.h + 2.0,
                .w = dropdown_width,
                .h = dropdown_height,
            };

            const mouse_in_button = self.input.isMouseInRect(button_rect);
            const mouse_in_dropdown = self.input.isMouseInRect(dropdown_rect);

            if ((mouse_in_button or mouse_in_dropdown) and self.input.mouse_left_clicked) {
                self.click_consumed = true;
            }
        }
    }

    pub fn handleMouseButton(self: *GuiContext, button: c_int, action: c_int) void {
        if (action != @intFromEnum(window.KeyAction.press)) {
            return;
        }

        if (button == @intFromEnum(window.MouseButton.left)) {
            self.input.registerMouseClick();
        } else if (button == @intFromEnum(window.MouseButton.right)) {
            self.input.registerRightClick();
        } else if (button == @intFromEnum(window.MouseButton.middle)) {
            self.input.registerMiddleClick();
        }
    }

    pub fn handleChar(self: *GuiContext, codepoint: c_uint) void {
        self.input.registerChar(codepoint);
    }

    pub fn handleKey(self: *GuiContext, key: c_int, action: c_int) void {
        self.input.registerKey(key, action);
    }

    pub fn handleModifiers(self: *GuiContext, mods: c_int) void {
        self.input.ctrl_pressed = window.hasModifier(mods, .control);
        self.input.alt_pressed = window.hasModifier(mods, .alt);
        self.input.super_pressed = window.hasModifier(mods, .super);
        self.input.shift_pressed = window.hasModifier(mods, .shift);

        if (comptime builtin.target.os.tag == .macos) {
            self.input.primary_pressed = self.input.super_pressed;
        } else {
            self.input.primary_pressed = self.input.ctrl_pressed;
        }
    }

    pub fn handleScroll(self: *GuiContext, xoffset: f64, yoffset: f64) void {
        self.input.registerScroll(xoffset, yoffset);
    }

    pub fn render(self: *GuiContext, renderer: *Renderer, width: i32, height: i32) void {
        // Render dropdown overlays on top of everything
        dropdown.renderDropdownOverlays(self) catch {};

        renderer.render(self, width, height);
    }

    pub fn measureText(self: *GuiContext, text: []const u8, font_size: f32) !TextMetrics {
        const font = try self.font_cache.getFont(font_size);
        return font.measure(text);
    }

    pub fn addText(self: *GuiContext, x: f32, y: f32, text: []const u8, font_size: f32, color: shapes.Color) !void {
        const font = try self.font_cache.getFont(font_size);
        self.current_font_texture = font.texture;
        try self.draw_list.setTexture(font.texture);
        try self.draw_list.addText(font, x, y, text, color);
    }

    pub fn deinit(self: *GuiContext) void {
        self.draw_list.deinit();
        self.font_cache.deinit();
        self.layout_stack.deinit(self.allocator);
        self.panel_sizes.deinit();

        // Clean up optional checkmark image
        if (self.checkmark_image) |*img| {
            img.deinit(self.renderer);
        }

        // Only destroy cursors if we have a window
        if (self.window) |_| {
            window.destroyCursor(self.arrow_cursor);
            window.destroyCursor(self.hand_cursor);
            window.destroyCursor(self.hresize_cursor);
            window.destroyCursor(self.vresize_cursor);
            window.destroyCursor(self.ibeam_cursor);
        }
    }

    pub fn getCurrentLayout(self: *GuiContext) *Layout {
        return &self.layout_stack.items[self.layout_stack.items.len - 1];
    }

    pub fn getNextLayoutPos(self: *GuiContext) struct { x: f32, y: f32 } {
        return .{ .x = self.next_layout_x, .y = self.next_layout_y };
    }

    pub fn setWindowSize(self: *GuiContext, width: f32, height: f32) void {
        self.window_width = width;
        self.window_height = height;
        self.is_resizing = true;
        self.last_resize_time = window.getTime();
    }

    pub fn updateLayoutPos(self: *GuiContext, bounds: shapes.Rect) void {
        self.next_layout_x = 0.0;
        self.next_layout_y = bounds.y + bounds.h;
    }

    pub fn setCursor(self: *GuiContext, cursor: ?*Cursor) void {
        if (self.current_cursor != cursor) {
            if (self.window) |win| {
                win.setCursor(cursor);
            }
            self.current_cursor = cursor;
        }
    }
};
