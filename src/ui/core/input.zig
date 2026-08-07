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

    pub fn beginFrame(self: *InputState) void {
        self.prev_mouse_pos = self.mouse_pos;
        self.mouse_pressed = .{ false, false, false };
        self.mouse_released = .{ false, false, false };
        self.scroll_delta = .{};
    }
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
        else => {},
    }
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

fn releasePrimary(tree: *tree_mod.UiTree, input: *InputState) ?types.NodeId {
    const active = input.active;
    const activated = if (active != types.invalid_node and input.hovered == active) active else types.invalid_node;

    if (tree.get(active)) |node| node.flags.pressed = false;
    dirty.markPaintDirty(tree, active);
    input.active = types.invalid_node;

    if (activated == types.invalid_node) return null;
    return activated;
}

pub fn mouseDelta(input_state: InputState) types.Vec2 {
    return .{
        .x = input_state.mouse_pos.x - input_state.prev_mouse_pos.x,
        .y = input_state.mouse_pos.y - input_state.prev_mouse_pos.y,
    };
}

pub fn mouseDown(input_state: InputState, button: events.MouseButton) bool {
    return input_state.mouse_down[buttonIndex(button)];
}

pub fn mousePressed(input_state: InputState, button: events.MouseButton) bool {
    return input_state.mouse_pressed[buttonIndex(button)];
}

pub fn mouseReleased(input_state: InputState, button: events.MouseButton) bool {
    return input_state.mouse_released[buttonIndex(button)];
}

pub fn nodeHovered(input_state: InputState, id: types.NodeId) bool {
    return input_state.hovered == id;
}

pub fn nodeActive(input_state: InputState, id: types.NodeId) bool {
    return input_state.active == id;
}

fn buttonIndex(button: events.MouseButton) usize {
    return switch (button) {
        .left => 0,
        .right => 1,
        .middle => 2,
    };
}
