# zGUI

An immediate-mode GUI library written in Zig, featuring OpenGL rendering, text support, and a comprehensive docking system.

## Features

- Immediate-mode GUI with retained state
- OpenGL 3.3 Core renderer
- TrueType font rendering
- Comprehensive widget set (buttons, checkboxes, text inputs, dropdowns, etc.)
- Advanced docking system with multi-window support
- Layout system for automatic positioning
- Themeable interface

## Requirements

- Zig 0.15.2 or later
- OpenGL 3.3 compatible graphics hardware

## Building

Build the library:
```bash
zig build
```

This will produce `libzgui.a` in `zig-out/lib/`.

## Examples

See the `examples/` directory for sample projects demonstrating library usage.

To build and run the docking demo:
```bash
cd examples/docking_demo
zig build run
```

## Using as a Library

Add zGUI to your project by including it as a dependency in your `build.zig.zon`. See `examples/README.md` for detailed integration instructions.

## Documentation

For detailed documentation about the library architecture, API usage, and development guidelines, see `CLAUDE.md`.

## License

See LICENSE file for details.
