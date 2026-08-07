# zGUI

A retained-mode GUI library written in Zig, featuring OpenGL rendering, TrueType text, and a dockable panel system.

## Features

- Retained node tree with dirty tracking: layout, paint-list, and vertex-buffer rebuilds are skipped on frames where nothing changed
- OpenGL 3.3 Core renderer with retained GPU buffers, batched draw calls, scissor clipping, and antialiased rounded corners
- TrueType font rendering (stb_truetype) with a glyph atlas, cached metrics, and HiDPI-aware rasterization
- Widgets and primitives: panels, labels, buttons, images, cards, pills, toolbars, dividers, themed button variants, and virtual-list range calculation
- Docking system: splits with draggable resize handles, tabbed leaves, drag-and-drop redocking with drop previews, and floating windows with z-ordering
- Flexbox-like layout: row/column/absolute direction, px/percent/fill/hug sizing, min sizes, padding, margins, gaps, and animated scrolling
- Role-based theming (colors, radii, spacing, font scale)
- Generational texture handles with explicit renderer-owned and externally-owned lifetimes
- Optional GLFW integration; the core and primary zGUI modules do not link GLFW

## Requirements

- Zig 0.16.0 or later
- OpenGL 3.3 compatible graphics hardware

## Usage

Build and run the editor demo:

```sh
zig build run
```

Run the test suite:

```sh
zig build test
```

Compile the library, GLFW demo, and tests without running them:

```sh
zig build check
```

## Modules

- `zGUI` is the supported UI, docking, and OpenGL renderer API.
- `zGUI_core` is the headless retained-tree/widget API for tools and tests.
- `zGUI_glfw` is the optional GLFW event/window adapter used by the demo.

Runtime-specific event translation belongs in the consuming application. This
keeps zGUI independent of engine packages and gives adapters concrete event,
window, key, and mouse-button types.

## Interaction

Platform input is routed in order and converted into semantic frame events.
Buttons emit `activate` after the primary pointer button is pressed and released
over the same node. Applications can poll retained events:

```zig
if (state.activated(save_button)) save();
```

Or attach a callback without allocating a closure:

```zig
fn saveProject(controller: *Controller, _: zgui.Event) void {
    controller.save();
}

try state.setActivationHandler(
    save_button,
    zgui.EventHandler.bind(controller, saveProject),
);
```

`EventHandler` borrows its context. The context must remain at a stable address
until the handler is replaced, cleared, or its node is destroyed. Callbacks run
on the UI thread during `beginFrame`, after all platform events for that frame
have been routed. `clicked` remains as an alias for `activated`.

Buttons can bind the same handler during construction:

```zig
_ = try zgui.widgets.iconButton(&state, parent, .{
    .texture = save_icon,
    .style = button_style,
    .on_activate = zgui.EventHandler.bind(controller, saveProject),
});
```

## Ownership and lifecycle

The application owns every subtree it creates below `Ui.rootNode()`. Widget
constructors are transactional: a failed constructor removes any nodes it
created. Remove a mounted component with `Ui.destroySubtree`; this recursively
clears input state and callbacks before recycling its generational node slots.

```zig
const panel = try buildPanel(&state, state.rootNode());
defer state.destroySubtree(panel);
```

`DockSpace.createWindow` borrows the supplied root node. `closeWindow` removes
the docking/window state but deliberately leaves that root subtree alive for
its owner to destroy or reuse. Window handles are generational, so a handle
retained after close cannot address a later window that reuses the same slot.

## Status

Early development. Not yet implemented: text-input widgets and keyboard focus routing, checkboxes/dropdowns, and multiple OS windows (floating windows live inside the main window's dock space).
