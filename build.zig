const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add debug option (use -Ddebug=true to enable)
    const debug = b.option(bool, "debug", "Enable debug features (FPS counter, etc)") orelse false;

    // Build zGUI as a static library
    const lib = b.addLibrary(.{
        .name = "zgui",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zgui.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Add build options to the library module
    const build_options = b.addOptions();
    build_options.addOption(bool, "debug", debug);
    lib.root_module.addOptions("build_options", build_options);

    // Link dependencies
    const glfw_dependency = b.dependency("glfw_zig", .{
        .target = target,
        .optimize = optimize,
    });
    lib.root_module.linkLibrary(glfw_dependency.artifact("glfw"));

    const glad_dependency = b.dependency("zig_glad", .{
        .target = target,
        .optimize = optimize,
    });
    lib.root_module.linkLibrary(glad_dependency.artifact("glad"));

    // Add C source files
    lib.root_module.addIncludePath(b.path("external/font"));
    lib.root_module.addCSourceFile(.{
        .file = b.path("external/font/stb_truetype.c"),
        .flags = &[_][]const u8{"-O3"},
    });

    lib.root_module.addIncludePath(b.path("external/image"));
    lib.root_module.addCSourceFile(.{
        .file = b.path("external/image/stb_image.c"),
        .flags = &[_][]const u8{"-O3"},
    });

    b.installArtifact(lib);

    // Export the module for use by other projects
    // Note: build_options should be provided by the consuming project
    const zgui_module = b.addModule("zgui", .{
        .root_source_file = b.path("src/zgui.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add all dependencies to the exported module (but NOT build_options)
    zgui_module.linkLibrary(glfw_dependency.artifact("glfw"));
    zgui_module.linkLibrary(glad_dependency.artifact("glad"));

    // Use b.path() which creates paths relative to this build.zig file
    zgui_module.addIncludePath(b.path("external/font"));
    zgui_module.addCSourceFile(.{
        .file = b.path("external/font/stb_truetype.c"),
        .flags = &[_][]const u8{"-O3"},
    });

    zgui_module.addIncludePath(b.path("external/image"));
    zgui_module.addCSourceFile(.{
        .file = b.path("external/image/stb_image.c"),
        .flags = &[_][]const u8{"-O3"},
    });
}
