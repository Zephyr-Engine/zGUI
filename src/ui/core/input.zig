const std = @import("std");
const types = @import("types.zig");
const tree_mod = @import("tree.zig");
const events = @import("../platform/events.zig");
const dirty = @import("dirty.zig");

pub const InputState = struct {
    mouse_pos: types.Vec2 = .{},
    prev_mouse_pos: types.Vec2 = .{},

    mouse_down: [3]bool = .{ false, false, false },
    mouse_pressed: [3]bool = .{ false, false, false },
    mouse_released: [3]bool = .{ false, false, false },

    scroll_delta: types.Vec2 = .{},
    hovered: types.NodeId = types.invalid_node,
    active: types.NodeId = types.invalid_node,
    focused: types.NodeId = types.invalid_node,

    key_down: [events.key_count]bool = @splat(false),
    key_down_at_frame_start: [events.key_count]bool = @splat(false),
    /// Press-or-repeat semantics: every key_down event marks this bit. This
    /// makes navigation/deletion repeat naturally; shortcut users that want
    /// edge-only behavior should also track their own command latch.
    key_pressed: [events.key_count]bool = @splat(false),
    key_released: [events.key_count]bool = @splat(false),
    text_input: [4096]u8 = undefined,
    text_input_len: usize = 0,
    text_overflowed: bool = false,
    ordered_events: [4096]OrderedEvent = undefined,
    ordered_events_len: usize = 0,
    event_overflowed: bool = false,

    pub fn beginFrame(self: *InputState) void {
        self.prev_mouse_pos = self.mouse_pos;
        self.mouse_pressed = .{ false, false, false };
        self.mouse_released = .{ false, false, false };
        self.scroll_delta = .{};
        self.key_down_at_frame_start = self.key_down;
        self.key_pressed = @splat(false);
        self.key_released = @splat(false);
        self.text_input_len = 0;
        self.text_overflowed = false;
        self.ordered_events_len = 0;
        self.event_overflowed = false;
    }

    pub fn orderedEvents(self: *const InputState) []const OrderedEvent {
        return self.ordered_events[0..self.ordered_events_len];
    }
};

pub const TextRange = struct { offset: usize, len: usize };

/// Ordered keyboard/text stream for focused controls. Text ranges point into
/// InputState.text_input and remain valid until the next beginFrame.
pub const OrderedEvent = union(enum) {
    key_down: events.Key,
    key_up: events.Key,
    text_input: TextRange,
};

pub fn applyEvent(input: *InputState, event: events.PlatformEvent) void {
    switch (event) {
        .mouse_move => |pos| input.mouse_pos = pos,
        .mouse_down => |button| {
            const idx = buttonIndex(button);
            input.mouse_down[idx] = true;
            input.mouse_pressed[idx] = true;
        },
        .mouse_up => |button| {
            const idx = buttonIndex(button);
            input.mouse_down[idx] = false;
            input.mouse_released[idx] = true;
        },
        .scroll => |delta| {
            input.scroll_delta.x += delta.x;
            input.scroll_delta.y += delta.y;
        },
        .key_down => |key| {
            const index = keyIndex(key);
            input.key_down[index] = true;
            input.key_pressed[index] = true;
            appendOrdered(input, .{ .key_down = key });
        },
        .key_up => |key| {
            const index = keyIndex(key);
            input.key_down[index] = false;
            input.key_released[index] = true;
            appendOrdered(input, .{ .key_up = key });
        },
        .text_input => |text| appendText(input, text),
        else => {},
    }
}

fn appendText(input: *InputState, text: []const u8) void {
    if (text.len == 0 or !std.unicode.utf8ValidateSlice(text)) return;
    if (text.len > input.text_input.len - input.text_input_len) {
        input.text_overflowed = true;
        return;
    }
    const start = input.text_input_len;
    @memcpy(input.text_input[start .. start + text.len], text);
    input.text_input_len += text.len;
    appendOrdered(input, .{ .text_input = .{ .offset = start, .len = text.len } });
}

fn appendOrdered(input: *InputState, event: OrderedEvent) void {
    if (input.ordered_events_len == input.ordered_events.len) {
        input.event_overflowed = true;
        return;
    }
    input.ordered_events[input.ordered_events_len] = event;
    input.ordered_events_len += 1;
}

/// Applies and routes one platform event before the next event is observed.
/// Returning a node signals a semantic primary-button activation.
pub fn routeEvent(tree: *tree_mod.UiTree, root: types.NodeId, input: *InputState, event: events.PlatformEvent) ?types.NodeId {
    applyEvent(input, event);

    switch (event) {
        .mouse_move => updateHovered(tree, root, input),
        .mouse_down => |button| {
            updateHovered(tree, root, input);
            if (button == .left) pressPrimary(tree, input);
        },
        .mouse_up => |button| {
            updateHovered(tree, root, input);
            if (button == .left) return releasePrimary(tree, input);
        },
        else => {},
    }
    return null;
}

pub fn hitTest(tree: *const tree_mod.UiTree, root: types.NodeId, pos: types.Vec2) ?types.NodeId {
    const root_node = tree.getConst(root) orelse return null;
    if (!root_node.flags.visible or !root_node.bounds.contains(pos)) return null;

    var child = root_node.last_child;
    while (child != types.invalid_node) {
        if (hitTest(tree, child, pos)) |hit| return hit;
        const child_node = tree.getConst(child) orelse break;
        child = child_node.prev_sibling;
    }

    if (root_node.flags.interactive) return root;
    return null;
}

pub fn updateHovered(tree: *tree_mod.UiTree, root: types.NodeId, input: *InputState) void {
    const next_hovered = hitTest(tree, root, input.mouse_pos) orelse types.invalid_node;
    if (next_hovered != input.hovered) {
        if (tree.get(input.hovered)) |old| {
            old.flags.hovered = false;
        }
        dirty.markPaintDirty(tree, input.hovered);
        if (tree.get(next_hovered)) |new| {
            new.flags.hovered = true;
        }
        dirty.markPaintDirty(tree, next_hovered);
        input.hovered = next_hovered;
    }
}

fn pressPrimary(tree: *tree_mod.UiTree, input: *InputState) void {
    input.active = input.hovered;

    if (input.focused != input.hovered) {
        if (tree.get(input.focused)) |old| old.flags.focused = false;
        dirty.markPaintDirty(tree, input.focused);
        input.focused = input.hovered;
    }

    if (tree.get(input.active)) |node| {
        node.flags.pressed = true;
        node.flags.focused = true;
    }
    dirty.markPaintDirty(tree, input.active);
}

pub fn keyDown(input_state: *const InputState, key: events.Key) bool {
    return input_state.key_down[keyIndex(key)];
}

pub fn keyPressed(input_state: *const InputState, key: events.Key) bool {
    return input_state.key_pressed[keyIndex(key)];
}

pub fn keyReleased(input_state: *const InputState, key: events.Key) bool {
    return input_state.key_released[keyIndex(key)];
}

fn keyIndex(key: events.Key) usize {
    return @intFromEnum(key);
}

fn releasePrimary(tree: *tree_mod.UiTree, input: *InputState) ?types.NodeId {
    const active = input.active;
    const activated = if (active != types.invalid_node and input.hovered == active) active else types.invalid_node;

    if (tree.get(active)) |node| node.flags.pressed = false;
    dirty.markPaintDirty(tree, active);
    input.active = types.invalid_node;

    if (activated == types.invalid_node) return null;
    return activated;
}

pub fn mouseDown(input_state: *const InputState, button: events.MouseButton) bool {
    return input_state.mouse_down[buttonIndex(button)];
}

pub fn mousePressed(input_state: *const InputState, button: events.MouseButton) bool {
    return input_state.mouse_pressed[buttonIndex(button)];
}

pub fn mouseReleased(input_state: *const InputState, button: events.MouseButton) bool {
    return input_state.mouse_released[buttonIndex(button)];
}

fn buttonIndex(button: events.MouseButton) usize {
    return switch (button) {
        .left => 0,
        .right => 1,
        .middle => 2,
    };
}

test "keyboard state uses press-or-repeat semantics and text is ordered" {
    var input: InputState = .{};
    input.beginFrame();
    applyEvent(&input, .{ .key_down = .left_control });
    applyEvent(&input, .{ .key_down = .v });
    applyEvent(&input, .{ .text_input = "é" });
    applyEvent(&input, .{ .key_down = .v });
    try std.testing.expect(keyDown(&input, .v));
    try std.testing.expect(keyPressed(&input, .v));
    try std.testing.expectEqual(@as(usize, 4), input.ordered_events_len);
    try std.testing.expectEqualStrings("é", input.text_input[0..input.text_input_len]);

    input.beginFrame();
    try std.testing.expect(keyDown(&input, .v));
    try std.testing.expect(!keyPressed(&input, .v));
    applyEvent(&input, .{ .key_up = .v });
    try std.testing.expect(!keyDown(&input, .v));
    try std.testing.expect(keyReleased(&input, .v));
}

test "invalid and overflowing text input is not appended" {
    var input: InputState = .{};
    input.beginFrame();
    applyEvent(&input, .{ .text_input = "\xff" });
    try std.testing.expectEqual(@as(usize, 0), input.text_input_len);
    var oversized: [4097]u8 = @splat('a');
    applyEvent(&input, .{ .text_input = &oversized });
    try std.testing.expect(input.text_overflowed);
    try std.testing.expectEqual(@as(usize, 0), input.text_input_len);
}
