const std = @import("std");
const builtin = @import("builtin");

const Scanner = @import("wayland").Scanner;

pub fn build(b: *std.Build) void {
    const options = b.addOptions();

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add protocol xml files
    const scanner = Scanner.create(b, .{});
    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
    scanner.addSystemProtocol("stable/tablet/tablet-v2.xml");
    scanner.addSystemProtocol("staging/cursor-shape/cursor-shape-v1.xml");
    scanner.addSystemProtocol("unstable/xdg-decoration/xdg-decoration-unstable-v1.xml");
    scanner.addSystemProtocol("unstable/pointer-constraints/pointer-constraints-unstable-v1.xml");
    scanner.addCustomProtocol(b.path("protocols/wlr-layer-shell-unstable-v1.xml"));
    scanner.addCustomProtocol(b.path("protocols/mez-remote-lua-unstable-v1.xml"));
    scanner.addCustomProtocol(b.path("protocols/wlr-output-power-management-unstable-v1.xml"));

    // Generate protocol code
    scanner.generate("zmez_remote_lua_manager_v1", 1);
    scanner.generate("wl_compositor", 6);
    scanner.generate("wl_subcompositor", 1);
    scanner.generate("wl_shm", 2);
    scanner.generate("wl_output", 4);
    scanner.generate("wl_seat", 10);
    scanner.generate("wl_data_device_manager", 3);
    scanner.generate("zxdg_decoration_manager_v1", 1);
    scanner.generate("xdg_wm_base", 7);
    scanner.generate("zwp_tablet_manager_v2", 2);
    scanner.generate("zwlr_layer_shell_v1", 5);
    scanner.generate("wp_cursor_shape_manager_v1", 1);
    scanner.generate("zwlr_output_power_manager_v1", 1);
    scanner.generate("zwp_pointer_constraints_v1", 1);

    const wayland = b.createModule(.{ .root_source_file = scanner.result });
    const xkbcommon = b.dependency("xkbcommon", .{}).module("xkbcommon");
    const pixman = b.dependency("pixman", .{}).module("pixman");
    const wlroots = b.dependency("wlroots", .{}).module("wlroots");
    const zlua = b.dependency("zlua", .{ .optimize = optimize, .target = target, .lang = .lua51 }).module("zlua");
    const clap = b.dependency("clap", .{ .optimize = optimize, .target = target }).module("clap");
    const xev = b.dependency("libxev", .{ .target = target, .optimize = optimize }).module("xev");

    wlroots.addImport("wayland", wayland);
    wlroots.addImport("xkbcommon", xkbcommon);
    wlroots.addImport("pixman", pixman);

    wlroots.resolved_target = target;
    wlroots.linkSystemLibrary("wlroots-0.19", .{});

    const mez = b.addExecutable(.{
        .name = "mez",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    mez.root_module.link_libc = true;

    mez.root_module.addImport("wayland", wayland);
    mez.root_module.addImport("xkbcommon", xkbcommon);
    mez.root_module.addImport("wlroots", wlroots);
    mez.root_module.addImport("zlua", zlua);
    mez.root_module.addImport("clap", clap);
    mez.root_module.addImport("xev", xev);

    mez.root_module.linkSystemLibrary("wayland-server", .{});
    mez.root_module.linkSystemLibrary("xkbcommon", .{});
    mez.root_module.linkSystemLibrary("pixman-1", .{});
    mez.root_module.linkSystemLibrary("libevdev", .{});

    var ret: u8 = undefined;
    const version = b.runAllowFail(
        &.{ "git", "-C", b.build_root.path orelse ".", "describe", "--tags", "--dirty" },
        &ret,
        .Inherit,
    ) catch "dev\n";

    const runtime_path_prefix = b.option([]const u8, "prefix", "Where mez looks for the runtime dir")
        orelse b.pathJoin(&.{b.install_prefix, "share"});
    options.addOption([]const u8, "runtime_path_prefix", runtime_path_prefix);

    options.addOption([]const u8, "version", version);
    mez.root_module.addOptions("config", options);

    // Installs a bin to prefix/bin/mez
    b.installArtifact(mez);

    // Installs runtime to prefix/share/mez
    b.installDirectory(.{
        .source_dir = b.path("runtime"),
        .install_dir = .prefix,
        .install_subdir = b.pathJoin(&.{"share", "mez", "runtime"}),
    });

    const run_step = b.step("run", "Run the compositor");
    const run_cmd = b.addRunArtifact(mez);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    // Test when zig build install is not broken
    // const uninstall_runtime = b.addSystemCommand(&.{
    //     "rm",
    //     "-rf",
    //     b.fmt("{s}/share/mez", .{b.install_prefix})
    // });
    // b.getUninstallStep().dependOn(&uninstall_runtime.step);

    const remove_step = b.step("remove", "Uninstall the zig binary");
    const uninstall_runtime = b.addSystemCommand(&.{
        "rm",
        "-rf",
        b.fmt("{s}/share/mez", .{b.install_prefix})
    });
    const uninstall_bin = b.addSystemCommand(&.{
        "rm",
        b.fmt("{s}/bin/mez", .{b.install_prefix})
    });
    remove_step.dependOn(&uninstall_runtime.step);
    remove_step.dependOn(&uninstall_bin.step);

    // const doc_gen_step = b.step("doc-gen", "Generate documentation for the lua api");
}
