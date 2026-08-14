const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const glfw_dep = b.dependency("glfw_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const glad_dep = b.dependency("zig_glad", .{
        .target = target,
        .optimize = optimize,
    });

    const mod = b.addModule("zGUI", .{
        .root_source_file = b.path("src/ui/ui.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addIncludePath(b.path("third_party/stb"));
    mod.addCSourceFile(.{ .file = b.path("src/ui/render/stb_truetype_impl.c") });
    mod.linkSystemLibrary("c", .{});
    mod.linkLibrary(glad_dep.artifact("glad"));

    const glfw_mod = b.addModule("zGUI_glfw", .{
        .root_source_file = b.path("src/glfw.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zGUI", .module = mod }},
    });
    glfw_mod.linkLibrary(glfw_dep.artifact("glfw"));

    const native_menu_mod = b.addModule("zGUI_native", .{
        .root_source_file = b.path("src/native_menu.zig"),
        .target = target,
        .optimize = optimize,
    });
    native_menu_mod.linkSystemLibrary("c", .{});
    if (target.result.os.tag == .linux) {
        native_menu_mod.addCSourceFile(.{ .file = b.path("src/native_menu_linux.c") });
    }
    if (target.result.os.tag == .macos) {
        native_menu_mod.addCSourceFile(.{ .file = b.path("src/native_menu_macos.m") });
        native_menu_mod.linkFramework("AppKit", .{});
    }
    if (target.result.os.tag == .windows) {
        native_menu_mod.addCSourceFile(.{ .file = b.path("src/native_menu_windows.c") });
        native_menu_mod.linkSystemLibrary("user32", .{});
    }

    const core_mod = b.addModule("zGUI_core", .{
        .root_source_file = b.path("src/core.zig"),
        .target = target,
        .optimize = optimize,
    });
    core_mod.addIncludePath(b.path("third_party/stb"));
    core_mod.addCSourceFile(.{ .file = b.path("src/ui/render/stb_truetype_impl.c") });
    core_mod.linkSystemLibrary("c", .{});

    const demo = b.addExecutable(.{
        .name = "editor_demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/editor_demo.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zGUI", .module = mod },
                .{ .name = "zGUI_glfw", .module = glfw_mod },
            },
        }),
    });
    b.installArtifact(demo);

    const run_demo = b.addRunArtifact(demo);
    const run_step = b.step("run", "Run the editor demo");
    run_step.dependOn(&run_demo.step);

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);
    const core_tests = b.addTest(.{ .root_module = core_mod });
    const run_core_tests = b.addRunArtifact(core_tests);
    const native_menu_tests = b.addTest(.{ .root_module = native_menu_mod });
    const run_native_menu_tests = b.addRunArtifact(native_menu_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_core_tests.step);
    test_step.dependOn(&run_native_menu_tests.step);

    const check_step = b.step("check", "Compile the library, demo, and tests");
    check_step.dependOn(&demo.step);
    check_step.dependOn(&mod_tests.step);
    check_step.dependOn(&core_tests.step);
    check_step.dependOn(&native_menu_tests.step);
}
