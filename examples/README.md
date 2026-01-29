# zGUI Examples

This directory contains example projects demonstrating how to use the zGUI library.

## Available Examples

### docking_demo

A comprehensive example showcasing the docking system with multiple panels:
- Scene viewport
- Hierarchy panel
- Inspector panel
- Console output panel
- Menu system with dropdowns

**Building:**
```bash
cd docking_demo
zig build
```

**Running:**
```bash
cd docking_demo
zig build run
```

**Debug mode:**
```bash
cd docking_demo
zig build run -Ddebug=true
```

## Using zGUI in Your Own Project

1. Add zGUI as a dependency in your `build.zig.zon`:
```zig
.{
    .name = .your_project,
    .version = "0.0.1",
    .dependencies = .{
        .zgui = .{
            .path = "path/to/zGUI",
        },
    },
    .minimum_zig_version = "0.15.2",
}
```

2. In your `build.zig`:
```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add debug option
    const debug = b.option(bool, "debug", "Enable debug features") orelse false;

    // Get zGUI dependency
    const zgui_dep = b.dependency("zgui", .{
        .target = target,
        .optimize = optimize,
        .debug = debug,
    });

    const exe = b.addExecutable(.{
        .name = "your_app",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Create build options
    const build_options = b.addOptions();
    build_options.addOption(bool, "debug", debug);

    // Import zGUI module and provide build_options to it
    const zgui_module = zgui_dep.module("zgui");
    zgui_module.addOptions("build_options", build_options);
    exe.root_module.addImport("zgui", zgui_module);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run your app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
}
```

3. In your `main.zig`:
```zig
const std = @import("std");
const zgui = @import("zgui");

// Import modules you need
const Window = zgui.Window;
const GuiContext = zgui.GuiContext;
const button = zgui.button;
const layout = zgui.layout;

// Optionally access build options through zgui
const build_options = zgui.build_options;

pub fn main() !void {
    // Your code here
}
```

## Available Modules

- `GuiContext` - Main GUI context and state
- `Window`, `WindowManager` - Window management
- `button`, `checkbox`, `textInput`, `dropdown`, `collapsible`, `image`, `panel` - Widgets
- `layout` - Layout system
- `shapes`, `color`, `theme` - Visual primitives
- `docking` - Docking system components
- `opengl`, `GLRenderer` - OpenGL renderer
- `font`, `FontCache` - Text rendering

See the main zGUI documentation for detailed API usage.
