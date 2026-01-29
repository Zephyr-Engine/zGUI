const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add debug option (use -Ddebug=true to enable)
    const debug = b.option(bool, "debug", "Enable debug features (FPS counter, etc)") orelse false;

    // Get zGUI dependency
    const zgui_dep = b.dependency("zgui", .{
        .target = target,
        .optimize = optimize,
        .debug = debug,
    });

    const exe = b.addExecutable(.{
        .name = "docking_demo",
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

    const run_step = b.step("run", "Run the docking demo");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
}
