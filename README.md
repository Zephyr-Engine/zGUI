# zGUI

A retained-mode GUI library written in Zig, featuring OpenGL rendering, TrueType text, and a dockable panel system.

## Features

- Retained node tree with dirty tracking: layout, paint-list, and vertex-buffer rebuilds are skipped on frames where nothing changed
- OpenGL 3.3 Core renderer with batched draw calls, scissor clipping, and antialiased rounded corners
- TrueType font rendering (stb_truetype) with a glyph atlas, cached metrics, and HiDPI-aware rasterization
- Widgets and primitives: panels, labels, buttons, images, cards, pills, toolbars, dividers, and themed button variants
- Docking system: splits with draggable resize handles, tabbed leaves, drag-and-drop redocking with drop previews, and floating windows with z-ordering
- Flexbox-like layout: row/column/absolute direction, px/percent/fill/hug sizing, min sizes, padding, margins, gaps, and animated scrolling
- Role-based theming (colors, radii, spacing, font scale)
- Platform backends: GLFW, plus a translation layer for the zephyr runtime

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

## Status

Early development. Not yet implemented: text-input widgets and keyboard focus routing, checkboxes/dropdowns, and multiple OS windows (floating windows live inside the main window's dock space).
