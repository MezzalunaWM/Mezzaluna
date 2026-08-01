const std = @import("std");
const wlr = @import("wlroots");
const config = @import("config");
const clap = @import("clap");

const Server = @import("Server.zig");
const Lua = @import("lua/Lua.zig");

pub var server: Server = undefined;
pub var gpa: std.mem.Allocator = undefined;
pub var io: std.Io = undefined;
pub var lua: Lua = undefined;
pub var environ_map: *std.process.Environ.Map = undefined;
const log = std.log.scoped(.Main);

const usage =
    \\Usage: mez [options]
    \\
    \\Options:
++ "\n" ++ args ++ "\n"
;

const args =
    \\   -u <path>            Use this config
    \\   -c <command>         Runs this command at startup
    \\   -v, --version        Print the version and exit
    \\   -h, --help           Print this help and exit
    \\
    \\   --clean              "Factory defaults" (skip user config)
;

pub fn main(init: std.process.Init) !void {
    gpa = init.gpa;
    io = init.io;

    environ_map = init.environ_map;
    defer environ_map.deinit();

    const params = comptime clap.parseParamsComptime(args);
    var diag = clap.Diagnostic{};
    const parsers = comptime .{
        .path = clap.parsers.string,
        .command = clap.parsers.string,
    };

    var res = clap.parse(clap.Help, &params, parsers, init.minimal.args, .{
        .diagnostic = &diag,
        .allocator = gpa,
    }) catch |err| {
        try diag.reportToFile(io, .stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help == 1) {
        try @constCast(&std.Io.File.stdout().writer(io, &.{}).interface).writeAll(usage);
        std.process.exit(0);
    }

    if (res.args.version == 1) {
        try @constCast(&std.Io.File.stdout().writer(io, &.{}).interface).writeAll(config.version);
        std.process.exit(0);
    }

    var lua_config: Lua.Config = .{ .enabled = true, .path = null };
    if (res.args.u != null and res.args.clean == 1) {
        std.debug.panic("You cannot set both -u and --clean", .{});
    } else if (res.args.u != null) blk: {
        // this is freed in lua/lua.zig
        const path = std.Io.Dir.cwd().realPathFileAlloc(io, res.args.u.?, gpa) catch |err| switch (err) {
            error.FileNotFound => {
                log.err("Path {s} does not exist, and therefore won't be used for the configuration.", .{ res.args.u.? });
                break :blk;
            },
            else => return err,
        };
        lua_config.path = path;
    } else if (res.args.clean == 1) {
        lua_config.enabled = false;
    }

    wlr.log.init(.err, null);
    log.info("Starting mezzaluna", .{});

    server.init();
    defer server.deinit();
    try lua.init(lua_config);

    var buf: [11]u8 = undefined;
    const socket = try server.wl_server.addSocketAuto(&buf);

    _ = environ_map.swapRemove("DISPLAY"); // prevent x11 clients from trying to spawn outside of mez
    try environ_map.put("WAYLAND_DISPLAY", socket);

    // tell the kernel to reap the children
    var act = std.posix.Sigaction {
        .handler = .{ .handler = std.posix.SIG.IGN },
        .mask = std.posix.sigemptyset(),
        .flags = std.posix.SA.NOCLDWAIT,
    };
    std.posix.sigaction(std.posix.SIG.CHLD, &act, null);

    if (res.args.c) |cmd| {
        _ = std.process.spawn(io, .{
            .argv = &.{ cmd },
            .environ_map = environ_map
        }) catch { log.err("Unable to spawn child processes from cli arguments", .{}); };
    }

    log.info("Starting backend", .{});
    server.backend.start() catch |err| {
        std.debug.panic("Failed to start backend: {}", .{ err });
    };

    log.info("Starting server", .{});
    server.run();
}
