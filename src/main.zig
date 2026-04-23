const std = @import("std");
const config = @import("config");
const clap = @import("clap");
const wlr = @import("wlroots");

const Server = @import("Server.zig");
const Lua = @import("lua/Lua.zig");

const gpa = std.heap.c_allocator;

pub var server: Server = undefined;
pub var lua: Lua = undefined;
pub var env_map: std.process.EnvMap = undefined;

const usage =
    \\Usage: mez [options]
    \\
    \\Options:
++ "\n" ++ args ++ "\n";
const args =
    \\   -u <path>            Use this config
    \\   -c <command>         Runs this command at startup
    \\   -v, --version        Print the version and exit
    \\   -h, --help           Print this help and exit
    \\
    \\   --clean              "Factory defaults" (skip user config)
;

pub fn main() !void {
    const params = comptime clap.parseParamsComptime(args);
    var diag = clap.Diagnostic{};
    const parsers = comptime .{
        .path = clap.parsers.string,
        .command = clap.parsers.string,
    };
    var res = clap.parse(clap.Help, &params, parsers, .{
        .diagnostic = &diag,
        .allocator = gpa,
    }) catch |err| {
        try diag.reportToFile(.stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help == 1) {
        try @constCast(&std.fs.File.stdout().writer(&[_]u8{}).interface).writeAll(usage);
        std.process.exit(0);
    }
    if (res.args.version == 1) {
        try @constCast(&std.fs.File.stdout().writer(&[_]u8{}).interface).writeAll(config.version);
        std.process.exit(0);
    }

    var lua_config: Lua.Config = .{ .enabled = true, .path = null };
    if (res.args.u != null and res.args.clean == 1) {
        std.debug.panic("You cannot set both -u and --clean", .{});
    } else if (res.args.u != null) blk: {
        // this is freed in lua/lua.zig
        const path = std.fs.cwd().realpathAlloc(gpa, res.args.u.?) catch |err| switch (err) {
            error.FileNotFound => {
                std.log.err("Path {s} does not exist, and therefore won't be used for the configuration.", .{ res.args.u.? });
                break :blk;
            },
            else => return err,
        };
        lua_config.path = path;
    } else if (res.args.clean == 1) {
        lua_config.enabled = false;
    }

    wlr.log.init(.err, null);
    std.log.info("Starting mezzaluna", .{});

    server.init();
    defer server.deinit();
    try lua.init(lua_config);

    var buf: [11]u8 = undefined;
    const socket = try server.wl_server.addSocketAuto(&buf);

    env_map = try std.process.getEnvMap(gpa);
    defer env_map.deinit();
    env_map.remove("DISPLAY"); // prevent x11 clients from trying to spawn outside of mez
    try env_map.put("WAYLAND_DISPLAY", socket);

    // tell the kernel to reap the children
    var act = std.posix.Sigaction{
        .handler = .{ .handler = std.posix.SIG.IGN },
        .mask = std.posix.sigemptyset(),
        .flags = std.posix.SA.NOCLDWAIT,
    };
    std.posix.sigaction(std.posix.SIG.CHLD, &act, null);

    if (res.args.c) |cmd| {
        var child = std.process.Child.init(&[_][]const u8{ cmd }, gpa);
        child.env_map = &env_map;
        try child.spawn();
    }

    std.log.info("Starting backend", .{});
    server.backend.start() catch |err| {
        std.debug.panic("Failed to start backend: {}", .{err});
    };

    std.log.info("Starting server", .{});
    server.run();
}
