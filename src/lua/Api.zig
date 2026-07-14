//! mez.api
const std = @import("std");
const zlua = @import("zlua");
const wlr = @import("wlroots");

const Utils = @import("../Utils.zig");
const LuaUtils = @import("LuaUtils.zig");

const gpa = &@import("../main.zig").gpa;
const io = &@import("../main.zig").io;
const environ_map = &@import("../main.zig").environ_map;
const server = &@import("../main.zig").server;

/// ---Spawn new application via the shell command. If you wish to pass in args
/// ---to your command then you must use a table of strings.
/// ---@param cmd []string|string Command to be run by a shell
pub fn spawn(L: *zlua.Lua) i32 {
    const t = L.typeOf(1);
    const command = switch (t) {
        .string => &[_][]const u8{ L.checkString(1) },
        .table => blk: {
            const list = gpa.alloc([]const u8, L.lenRaw(1)) catch Utils.oomPanic();

            var i: u32 = 0;
            L.pushNil();
            while (L.next(1)) : (i += 1) {
                const s = L.toString(-1) catch L.raiseErrorStr("Unable to spawn process child process", .{});
                list[i] = gpa.dupe(u8, s) catch Utils.oomPanic();
                L.pop(1);  // remove value, keep key for next iteration
            }

            break :blk list;
        },
        else => L.raiseErrorStr("Must pass a string or table", .{}),
    };
    defer if (t == .table) {
        for (command) |v| gpa.free(v);
        gpa.free(command);
    };

    _ = std.process.spawn(io.*, .{ 
        .argv = command,
        .environ_map = environ_map.*
    }) catch |err| switch (err) {
        error.OutOfMemory => Utils.oomPanic(),
        else => L.raiseErrorStr("Unable to spawn process child process", .{}),
    };

    return 0;
}

/// ---Exit mezzaluna
pub fn exit(L: *zlua.Lua) i32 {
    server.terminate();

    L.pushNil();
    return 1;
}

/// ---Change to a different virtual terminal
/// ---@param vt_num integer virtual terminal number to switch to
pub fn change_vt(L: *zlua.Lua) i32 {
    const vt_num = LuaUtils.coerceInteger(c_uint, L.checkInteger(1)) catch L.raiseErrorStr("The vt number must be >= 1 and < inf", .{});

    if (server.session) |session| {
        session.changeVt(vt_num) catch {
            L.raiseErrorStr("Failed to switch vt", .{});
        };
    } else L.raiseErrorStr("Mez has not been initialized yet", .{});

    L.pushNil();
    return 1;
}
