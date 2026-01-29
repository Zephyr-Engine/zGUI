const builtin = @import("builtin");
const std = @import("std");
const GuiContext = @import("../context.zig").GuiContext;
const ActiveInputState = @import("../context.zig").ActiveInputState;
const shapes = @import("../shapes.zig");
const window = @import("../window.zig");
const Key = window.Key;
const theme_mod = @import("../theme.zig");

pub const InputOptions = struct {
    font_size: f32 = 24,
    color: ?shapes.Color = null,
    text_color: ?shapes.Color = null,
    border_radius: f32 = 8.0,
    border_thickness: f32 = 2.0,
    width: f32 = 200.0,
    height: f32 = 40.0,
    label: ?[]const u8 = null,
    label_font_size: f32 = 16,
    label_color: ?shapes.Color = null,
};

fn isWordBoundary(char: u8) bool {
    return char == ' ' or char == '\t' or char == '\n' or char == '.' or char == ',' or
        char == ';' or char == ':' or char == '!' or char == '?' or char == '(' or
        char == ')' or char == '[' or char == ']' or char == '{' or char == '}' or
        char == '-' or char == '_' or char == '/' or char == '\\';
}

fn findPreviousWordBoundary(buffer: []const u8, cursor_pos: usize) usize {
    if (cursor_pos == 0) return 0;

    var pos = cursor_pos;

    // Skip any whitespace/punctuation at current position
    while (pos > 0 and isWordBoundary(buffer[pos - 1])) {
        pos -= 1;
    }

    // Move back to the start of the word
    while (pos > 0 and !isWordBoundary(buffer[pos - 1])) {
        pos -= 1;
    }

    return pos;
}

fn findNextWordBoundary(buffer: []const u8, len: usize, cursor_pos: usize) usize {
    if (cursor_pos >= len) return len;

    var pos = cursor_pos;

    // Skip any whitespace/punctuation at current position
    while (pos < len and isWordBoundary(buffer[pos])) {
        pos += 1;
    }

    // Move forward to the end of the word
    while (pos < len and !isWordBoundary(buffer[pos])) {
        pos += 1;
    }

    return pos;
}

fn hasSelection(state: *const ActiveInputState, cursor_pos: usize) bool {
    return state.selection_start != null and state.selection_start.? != cursor_pos;
}

fn getSelectionRange(state: *const ActiveInputState, cursor_pos: usize, buffer_len: usize) ?struct { start: usize, end: usize } {
    if (state.selection_start) |sel_start| {
        if (sel_start != cursor_pos) {
            const start = @min(@min(sel_start, cursor_pos), buffer_len);
            const end = @min(@max(sel_start, cursor_pos), buffer_len);
            return .{ .start = start, .end = end };
        }
    }
    return null;
}

pub fn inputText(ctx: *GuiContext, buffer: []u8, buffer_len: *usize, opts: InputOptions) !bool {
    const layout_mod = @import("../layout.zig");

    // If there's a label, create a vertical layout to stack label and input
    if (opts.label) |label| {
        const label_metrics = try ctx.measureText(label, opts.label_font_size);
        const label_width = @max(label_metrics.width, opts.width);
        const label_spacing: f32 = 6; // Space between label and input
        const total_height = opts.label_font_size + label_spacing + opts.height;
        layout_mod.beginLayout(ctx, layout_mod.vLayout(ctx, .{ .margin = layout_mod.Spacing.all(0), .padding = layout_mod.Spacing.all(0), .width = label_width, .height = total_height }));
    }

    const layout = ctx.getCurrentLayout();

    if (opts.label) |label| {
        const label_metrics = try ctx.measureText(label, opts.label_font_size);
        const label_spacing: f32 = 6;
        const label_rect = layout.allocateSpace(ctx, label_metrics.width, opts.label_font_size + label_spacing);
        const label_color = theme_mod.getColor(ctx.theme, opts.label_color, "text_secondary", 0x9d9d9dFF);
        try ctx.addText(label_rect.x, label_rect.y + 5, label, opts.label_font_size, label_color);
    }

    const rect = layout.allocateSpace(ctx, opts.width, opts.height);
    const id = @intFromPtr(buffer.ptr);
    const result = try inputInternal(ctx, rect, id, buffer, buffer_len, opts, null);

    // End the vertical layout if we created one
    if (opts.label != null) {
        layout_mod.endLayout(ctx);
    }

    return result;
}

pub fn moveMousePosition(ctx: *GuiContext, state: *ActiveInputState, buffer: []u8, buffer_len: usize, rect: shapes.Rect, opts: InputOptions) !void {
    if (buffer_len == 0) {
        return;
    }

    const padding = 8.0;
    const text_x = rect.x + padding;
    const mouse_x: f32 = @floatCast(ctx.input.cursor_x);
    const relative_x = mouse_x - text_x + state.scroll_offset;

    // Find the character position closest to the mouse
    var closest_pos: usize = 0;
    var closest_dist: f32 = std.math.floatMax(f32);

    // Check position before first character
    if (relative_x < 0) {
        state.cursor_pos = 0;
        return;
    }

    // Check each character position
    for (0..buffer_len + 1) |i| {
        const text_slice = buffer[0..i];
        const metrics = try ctx.measureText(text_slice, opts.font_size);
        const dist = @abs(metrics.width - relative_x);

        if (dist < closest_dist) {
            closest_dist = dist;
            closest_pos = i;
        }
    }

    state.cursor_pos = closest_pos;
    state.cursor_blink_time = window.getTime();
}

fn inputInternal(
    ctx: *GuiContext,
    rect: shapes.Rect,
    id: u64,
    buffer: []u8,
    buffer_len: *usize,
    opts: InputOptions,
    comptime charValidationFn: ?fn (char: u8, buffer: []const u8, buffer_len: usize, cursor_pos: usize) bool,
) !bool {
    const is_hovered = ctx.input.isMouseInRect(rect);
    const is_clicked = is_hovered and ctx.input.mouse_left_clicked and !ctx.click_consumed;
    if (is_hovered) {
        ctx.setCursor(ctx.ibeam_cursor);
    }

    const is_active = if (ctx.active_input_id) |active_id| active_id == id else false;

    // click away(becomes inactive)
    if (ctx.input.mouse_left_clicked and !ctx.click_consumed and !is_hovered and is_active) {
        ctx.active_input_id = null;
        ctx.active_input_state = null;
        return false;
    }

    var state = if (is_active and ctx.active_input_state != null)
        ctx.active_input_state.?
    else
        ActiveInputState.init();

    if (is_clicked) {
        ctx.active_input_id = id;
        try moveMousePosition(ctx, &state, buffer, buffer_len.*, rect, opts);

        state.selection_start = state.cursor_pos;
    }

    // handle mouse drag selection
    if (is_active and is_hovered and ctx.input.mouse_left_pressed and !is_clicked) {
        try moveMousePosition(ctx, &state, buffer, buffer_len.*, rect, opts);
    }

    // Get colors from theme with option overrides
    const base_border_color = theme_mod.getColor(ctx.theme, opts.color, "border_subtle", 0x3e3e42FF);
    const text_color = theme_mod.getColor(ctx.theme, opts.text_color, "text_primary", 0xccccccFF);

    // Border color - stronger when active
    const box_color = if (is_active)
        theme_mod.getColor(ctx.theme, opts.color, "border_strong", 0x454545FF)
    else
        base_border_color;

    try ctx.draw_list.addRoundedRectOutline(rect, opts.border_radius, opts.border_thickness, box_color);

    var text_changed = false;
    if (is_active) {
        for (0..ctx.input.chars_count) |i| {
            const char = ctx.input.chars_buffer[i];
            const char_u8: u8 = @intCast(char);

            const is_valid = if (charValidationFn) |validationFn|
                validationFn(char_u8, buffer[0..buffer_len.*], buffer_len.*, state.cursor_pos)
            else
                char >= 32 and char < 127;

            if (is_valid and buffer_len.* < buffer.len) {
                if (hasSelection(&state, state.cursor_pos)) {
                    if (getSelectionRange(&state, state.cursor_pos, buffer_len.*)) |range| {
                        const bytes_to_remove = range.end - range.start;
                        std.mem.copyForwards(u8, buffer[range.start .. buffer_len.* - bytes_to_remove], buffer[range.end..buffer_len.*]);
                        buffer_len.* -= bytes_to_remove;
                        state.cursor_pos = range.start;
                        state.selection_start = null;
                        text_changed = true;
                    }
                }

                if (state.cursor_pos < buffer_len.*) {
                    std.mem.copyBackwards(u8, buffer[state.cursor_pos + 1 .. buffer_len.* + 1], buffer[state.cursor_pos..buffer_len.*]);
                }
                buffer[state.cursor_pos] = char_u8;
                state.cursor_pos += 1;
                buffer_len.* += 1;
                text_changed = true;
                state.cursor_blink_time = window.getTime();
            }
        }

        if (ctx.input.isKeyJustPressed(@intFromEnum(Key.backspace))) {
            if (hasSelection(&state, state.cursor_pos)) {
                if (getSelectionRange(&state, state.cursor_pos, buffer_len.*)) |range| {
                    const bytes_to_remove = range.end - range.start;
                    std.mem.copyForwards(u8, buffer[range.start .. buffer_len.* - bytes_to_remove], buffer[range.end..buffer_len.*]);
                    buffer_len.* -= bytes_to_remove;
                    state.cursor_pos = range.start;
                    state.selection_start = null;
                    text_changed = true;
                    state.cursor_blink_time = window.getTime();
                }
            } else if (state.cursor_pos > 0) {
                std.mem.copyForwards(u8, buffer[state.cursor_pos - 1 .. buffer_len.* - 1], buffer[state.cursor_pos..buffer_len.*]);
                state.cursor_pos -= 1;
                buffer_len.* -= 1;
                text_changed = true;
                state.cursor_blink_time = window.getTime();
            }
        }

        if (ctx.input.isKeyJustPressed(@intFromEnum(Key.delete))) {
            if (hasSelection(&state, state.cursor_pos)) {
                if (getSelectionRange(&state, state.cursor_pos, buffer_len.*)) |range| {
                    const bytes_to_remove = range.end - range.start;
                    std.mem.copyForwards(u8, buffer[range.start .. buffer_len.* - bytes_to_remove], buffer[range.end..buffer_len.*]);
                    buffer_len.* -= bytes_to_remove;
                    state.cursor_pos = range.start;
                    state.selection_start = null;
                    text_changed = true;
                    state.cursor_blink_time = window.getTime();
                }
            } else if (state.cursor_pos < buffer_len.*) {
                std.mem.copyForwards(u8, buffer[state.cursor_pos .. buffer_len.* - 1], buffer[state.cursor_pos + 1 .. buffer_len.*]);
                buffer_len.* -= 1;
                text_changed = true;
                state.cursor_blink_time = window.getTime();
            }
        }

        if (ctx.input.isKeyJustPressed(@intFromEnum(Key.left))) {
            if (ctx.input.shift_pressed and state.selection_start == null) {
                state.selection_start = state.cursor_pos;
            }

            var new_pos: usize = state.cursor_pos;
            if (ctx.input.super_pressed) {
                new_pos = 0;
            } else if (ctx.input.alt_pressed or ctx.input.ctrl_pressed) {
                new_pos = findPreviousWordBoundary(buffer[0..buffer_len.*], state.cursor_pos);
            } else {
                if (hasSelection(&state, state.cursor_pos) and !ctx.input.shift_pressed) {
                    if (getSelectionRange(&state, state.cursor_pos, buffer_len.*)) |range| {
                        new_pos = range.start;
                    }
                } else if (state.cursor_pos > 0) {
                    new_pos = state.cursor_pos - 1;
                }
            }

            state.cursor_pos = new_pos;
            state.cursor_blink_time = window.getTime();

            if (!ctx.input.shift_pressed) {
                state.selection_start = null;
            }
        }

        if (ctx.input.isKeyJustPressed(@intFromEnum(Key.right))) {
            if (ctx.input.shift_pressed and state.selection_start == null) {
                state.selection_start = state.cursor_pos;
            }

            var new_pos: usize = state.cursor_pos;
            if (ctx.input.super_pressed) {
                new_pos = buffer_len.*;
            } else if (ctx.input.alt_pressed or ctx.input.ctrl_pressed) {
                new_pos = findNextWordBoundary(buffer[0..buffer_len.*], buffer_len.*, state.cursor_pos);
            } else {
                if (hasSelection(&state, state.cursor_pos) and !ctx.input.shift_pressed) {
                    if (getSelectionRange(&state, state.cursor_pos, buffer_len.*)) |range| {
                        new_pos = range.end;
                    }
                } else if (state.cursor_pos < buffer_len.*) {
                    new_pos = state.cursor_pos + 1;
                }
            }

            state.cursor_pos = new_pos;
            state.cursor_blink_time = window.getTime();

            if (!ctx.input.shift_pressed) {
                state.selection_start = null;
            }
        }

        if (ctx.input.isKeyJustPressed(@intFromEnum(Key.home))) {
            if (ctx.input.shift_pressed and state.selection_start == null) {
                state.selection_start = state.cursor_pos;
            }
            state.cursor_pos = 0;
            state.cursor_blink_time = window.getTime();
            if (!ctx.input.shift_pressed) {
                state.selection_start = null;
            }
        }

        if (ctx.input.isKeyJustPressed(@intFromEnum(Key.end))) {
            if (ctx.input.shift_pressed and state.selection_start == null) {
                state.selection_start = state.cursor_pos;
            }
            state.cursor_pos = buffer_len.*;
            state.cursor_blink_time = window.getTime();
            if (!ctx.input.shift_pressed) {
                state.selection_start = null;
            }
        }

        if (ctx.input.isKeyJustPressed(@intFromEnum(Key.v)) and ctx.input.primary_pressed) {
            // Only paste if we have a window with clipboard access
            if (ctx.window) |win| {
                const content = win.getClipboardString();
                const len = std.mem.len(content);
                const slice = content[0..len];

                if (hasSelection(&state, state.cursor_pos)) {
                    if (getSelectionRange(&state, state.cursor_pos, buffer_len.*)) |range| {
                        const bytes_to_remove = range.end - range.start;
                        std.mem.copyForwards(u8, buffer[range.start .. buffer_len.* - bytes_to_remove], buffer[range.end..buffer_len.*]);
                        buffer_len.* -= bytes_to_remove;
                        state.cursor_pos = range.start;
                        state.selection_start = null;
                        text_changed = true;
                    }
                }

                if (buffer_len.* + len <= buffer.len) {
                    if (state.cursor_pos < buffer_len.*) {
                        std.mem.copyBackwards(
                            u8,
                            buffer[state.cursor_pos + len .. buffer_len.* + len],
                            buffer[state.cursor_pos..buffer_len.*],
                        );
                    }

                    std.mem.copyForwards(
                        u8,
                        buffer[state.cursor_pos .. state.cursor_pos + len],
                        slice,
                    );

                    state.cursor_pos += len;
                    buffer_len.* += len;
                    text_changed = true;
                    state.cursor_blink_time = window.getTime();
                }
            }
        }

        if (ctx.input.isKeyJustPressed(@intFromEnum(Key.c)) and ctx.input.primary_pressed and hasSelection(&state, state.cursor_pos)) {
            if (getSelectionRange(&state, state.cursor_pos, buffer_len.*)) |range| {
                // Only copy if we have a window with clipboard access
                if (ctx.window) |win| {
                    const content = buffer[range.start..range.end];

                    var buf: [4096:0]u8 = undefined;
                    const copy_len = @min(content.len, buf.len - 1);
                    @memcpy(buf[0..copy_len], content[0..copy_len]);
                    buf[copy_len] = 0;

                    win.setClipboardString(&buf);
                }
            }
        }

        if (ctx.input.isKeyJustPressed(@intFromEnum(Key.x)) and ctx.input.primary_pressed and hasSelection(&state, state.cursor_pos)) {
            if (getSelectionRange(&state, state.cursor_pos, buffer_len.*)) |range| {
                // Only cut (copy to clipboard) if we have a window with clipboard access
                if (ctx.window) |win| {
                    const content = buffer[range.start..range.end];

                    var buf: [4096:0]u8 = undefined;
                    const copy_len = @min(content.len, buf.len - 1);
                    @memcpy(buf[0..copy_len], content[0..copy_len]);
                    buf[copy_len] = 0;

                    win.setClipboardString(&buf);
                }

                const bytes_to_remove = range.end - range.start;
                std.mem.copyForwards(u8, buffer[range.start .. buffer_len.* - bytes_to_remove], buffer[range.end..buffer_len.*]);
                buffer_len.* -= bytes_to_remove;
                state.cursor_pos = range.start;
                state.selection_start = null;
                text_changed = true;
                state.cursor_blink_time = window.getTime();
            }
        }

        if (ctx.input.isKeyJustPressed(@intFromEnum(Key.a)) and ctx.input.primary_pressed) {
            if (buffer_len.* > 0) {
                state.selection_start = 0;
                state.cursor_pos = buffer_len.*;
                state.cursor_blink_time = window.getTime();
            }
        }
    }

    const padding = 8.0;
    const text_x = rect.x + padding;
    const font_metrics = try ctx.measureText("Ag", opts.font_size);
    const text_y = rect.y + (rect.h - font_metrics.height) * 0.5;
    const available_width = rect.w - (padding * 2.0);

    if (buffer_len.* > 0) {
        const text_before_cursor = buffer[0..state.cursor_pos];
        const metrics_to_cursor = try ctx.measureText(text_before_cursor, opts.font_size);
        const cursor_x_unscrolled = metrics_to_cursor.width;

        const cursor_margin = 10.0;
        if (cursor_x_unscrolled - state.scroll_offset > available_width - cursor_margin) {
            state.scroll_offset = cursor_x_unscrolled - available_width + cursor_margin;
        } else if (cursor_x_unscrolled - state.scroll_offset < cursor_margin) {
            state.scroll_offset = @max(0.0, cursor_x_unscrolled - cursor_margin);
        }
    } else {
        state.scroll_offset = 0.0;
    }

    if (buffer_len.* > 0) {
        const full_text = buffer[0..buffer_len.*];

        var visible_start: usize = 0;
        var visible_end: usize = buffer_len.*;
        var current_x: f32 = 0.0;

        for (0..buffer_len.*) |i| {
            const char_text = buffer[0 .. i + 1];
            const metrics = try ctx.measureText(char_text, opts.font_size);
            if (metrics.width >= state.scroll_offset) {
                visible_start = i;
                if (i > 0) {
                    const prev_metrics = try ctx.measureText(buffer[0..i], opts.font_size);
                    current_x = prev_metrics.width;
                }
                break;
            }
        }

        for (visible_start..buffer_len.*) |i| {
            const char_text = buffer[0 .. i + 1];
            const metrics = try ctx.measureText(char_text, opts.font_size);
            if (metrics.width - state.scroll_offset > available_width) {
                visible_end = i;
                break;
            }
        }

        if (getSelectionRange(&state, state.cursor_pos, buffer_len.*)) |sel_range| {
            const text_before_sel_start = buffer[0..sel_range.start];
            const text_before_sel_end = buffer[0..sel_range.end];

            const metrics_start = try ctx.measureText(text_before_sel_start, opts.font_size);
            const metrics_end = try ctx.measureText(text_before_sel_end, opts.font_size);

            const sel_x_start = text_x + metrics_start.width - state.scroll_offset;
            const sel_x_end = text_x + metrics_end.width - state.scroll_offset;

            if (sel_x_end >= text_x and sel_x_start <= text_x + available_width) {
                const highlight_x = @max(sel_x_start, rect.x);
                const highlight_w = @min(sel_x_end, rect.x + rect.w - padding) - highlight_x;

                if (highlight_w > 0) {
                    const selection_color = ctx.theme.input_selection;
                    const selection_rect = shapes.Rect{
                        .x = highlight_x,
                        .y = text_y,
                        .w = highlight_w,
                        .h = opts.font_size,
                    };
                    try ctx.draw_list.addRect(selection_rect, selection_color);
                }
            }
        }

        if (visible_start < visible_end) {
            const visible_text = full_text[visible_start..visible_end];
            const render_x = text_x - (state.scroll_offset - current_x);
            try ctx.addText(render_x, text_y, visible_text, opts.font_size, text_color);
        }
    }

    if (is_active) {
        const current_time = window.getTime();
        const elapsed = current_time - state.cursor_blink_time;
        const blink_cycle = @mod(elapsed, 1.0);

        if (blink_cycle < 0.5) {
            var cursor_x = text_x;
            if (state.cursor_pos > 0) {
                const text_before_cursor = buffer[0..state.cursor_pos];
                const metrics = try ctx.measureText(text_before_cursor, opts.font_size);
                cursor_x = text_x + metrics.width - state.scroll_offset;
            }

            const cursor_height = opts.font_size;
            const cursor_y = rect.y + (rect.h - cursor_height) * 0.5;
            const cursor_rect = shapes.Rect{
                .x = cursor_x,
                .y = cursor_y,
                .w = 2.0,
                .h = cursor_height,
            };
            try ctx.draw_list.addRect(cursor_rect, text_color);
        }
    }

    if (is_active) {
        ctx.active_input_state = state;
    }

    return text_changed;
}

fn isValidFloatChar(char: u8, buffer: []const u8, buffer_len: usize, cursor_pos: usize) bool {
    if (char >= '0' and char <= '9') return true;

    if (char == '.') {
        for (buffer[0..buffer_len]) |ch| {
            if (ch == '.') return false;
        }
        return true;
    }

    if (char == '-') {
        return cursor_pos == 0 and (buffer_len == 0 or buffer[0] != '-');
    }

    return false;
}

fn isValidIntChar(char: u8, buffer: []const u8, buffer_len: usize, cursor_pos: usize) bool {
    if (char >= '0' and char <= '9') return true;

    if (char == '-') {
        return cursor_pos == 0 and (buffer_len == 0 or buffer[0] != '-');
    }

    return false;
}

fn inputNumberGeneric(
    ctx: *GuiContext,
    rect: shapes.Rect,
    value_ptr: *anyopaque,
    comptime T: type,
    opts: InputOptions,
    comptime validationFn: fn (char: u8, buffer: []const u8, buffer_len: usize, cursor_pos: usize) bool,
) !bool {
    var temp_buffer: [32]u8 = undefined;
    var temp_len: usize = 0;

    const value: *T = @ptrCast(@alignCast(value_ptr));
    const id = @intFromPtr(value) ^ 0x4e554d42;
    const is_active = if (ctx.active_input_id) |active_id| active_id == id else false;

    // If already active and we have a preserved buffer, use it
    if (is_active and ctx.active_input_state != null) {
        if (ctx.active_input_state.?.number_buffer) |buf| {
            temp_buffer = buf;
            temp_len = ctx.active_input_state.?.number_buffer_len;
        } else {
            // First frame after activation, initialize from value
            temp_len = (try std.fmt.bufPrint(&temp_buffer, "{d}", .{value.*})).len;
        }
    } else {
        // Not active, format the current value
        temp_len = (try std.fmt.bufPrint(&temp_buffer, "{d}", .{value.*})).len;
    }

    const changed = try inputInternal(ctx, rect, id, &temp_buffer, &temp_len, opts, validationFn);

    // Save the buffer back to state if active
    if (ctx.active_input_id != null and ctx.active_input_id.? == id) {
        if (ctx.active_input_state) |*state| {
            state.number_buffer = temp_buffer;
            state.number_buffer_len = temp_len;
        }
    }

    if (changed) {
        if (temp_len > 0) {
            const info = @typeInfo(T);
            switch (info) {
                .float => value.* = std.fmt.parseFloat(T, temp_buffer[0..temp_len]) catch value.*,
                .int => value.* = std.fmt.parseInt(T, temp_buffer[0..temp_len], 10) catch value.*,
                else => unreachable,
            }
        } else {
            value.* = 0;
        }
    }

    return changed;
}

pub fn inputNumber(ctx: *GuiContext, value: anytype, opts: InputOptions) !bool {
    const layout_mod = @import("../layout.zig");

    // If there's a label, create a vertical layout to stack label and input
    if (opts.label) |label| {
        const label_metrics = try ctx.measureText(label, opts.label_font_size);
        const label_width = @max(label_metrics.width, opts.width);
        const label_spacing: f32 = 6; // Space between label and input
        const total_height = opts.label_font_size + label_spacing + opts.height;
        layout_mod.beginLayout(ctx, layout_mod.vLayout(ctx, .{ .margin = layout_mod.Spacing.all(0), .padding = layout_mod.Spacing.all(0), .width = label_width, .height = total_height }));
    }

    const layout = ctx.getCurrentLayout();

    // Render label if provided
    if (opts.label) |label| {
        const label_metrics = try ctx.measureText(label, opts.label_font_size);
        const label_spacing: f32 = 6;
        const label_rect = layout.allocateSpace(ctx, label_metrics.width, opts.label_font_size + label_spacing);
        const label_color = theme_mod.getColor(ctx.theme, opts.label_color, "text_secondary", 0x9d9d9dFF);
        try ctx.addText(label_rect.x, label_rect.y + 5, label, opts.label_font_size, label_color);
    }

    const rect = layout.allocateSpace(ctx, opts.width, opts.height);
    const T = @TypeOf(value);
    const type_info = @typeInfo(T);

    if (type_info != .pointer) {
        @compileError("value must be a pointer to a number type");
    }

    const ChildType = type_info.pointer.child;

    const result = switch (@typeInfo(ChildType)) {
        .float => try inputNumberGeneric(ctx, rect, value, ChildType, opts, isValidFloatChar),
        .int => try inputNumberGeneric(ctx, rect, value, ChildType, opts, isValidIntChar),
        else => @compileError("value must be a pointer to a number type (int or float)"),
    };

    // End the vertical layout if we created one
    if (opts.label != null) {
        layout_mod.endLayout(ctx);
    }

    return result;
}
