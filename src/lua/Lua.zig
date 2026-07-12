const Lua = @This();

const std = @import("std");
const config = @import("config");
const zlua = @import("zlua");

const Utils = @import("../Utils.zig");
const LuaUtils = @import("LuaUtils.zig");
const Bridge = @import("Bridge.zig");
const Options = @import("Options.zig");

const gpa = std.heap.c_allocator;
pub const log = std.log.scoped(.lua);

state: *zlua.Lua,

pub const Config = struct {
    path: ?[]const u8,
    enabled: bool,
};

pub fn init(self: *Lua, cfg: Config) !void {
    self.state = try zlua.Lua.init(gpa);
    errdefer self.state.deinit();
    self.state.openLibs();

    openMezLibs(self.state);

    if (cfg.path) |path| {
        defer gpa.free(path);
        try setConfig(self.state, path);
    }

    // load lua files
    loadRuntimeDir(self.state) catch |err| switch (err) {
        error.OutOfMemory => Utils.oomPanic(),
        else => log.err("{}", .{ err })
    };

    if (cfg.enabled) loadConfigDir(self.state);
    loadBaseConfig(self.state);

    log.debug("Loaded lua", .{});
}

pub fn deinit(self: *Lua) void {
    self.state.deinit();
}

pub fn loadRuntimeDir(self: *zlua.Lua) !void {
    const path_dir = try std.fs.path.joinZ(gpa, &[_][]const u8{
        config.runtime_path_prefix,
        "mez",
        "runtime",
    });
    std.debug.print("path_dir: {s}\n", .{path_dir});
    defer gpa.free(path_dir);

    {
        _ = try self.getGlobal("mez");
        defer self.pop(1);
        _ = self.getField(-1, "path");
        defer self.pop(1);
        _ = self.pushString(path_dir);
        self.setField(-2, "runtime");
    }

    const path_full = try std.fs.path.joinZ(gpa, &[_][]const u8{
        path_dir,
        "init.lua",
    });
    defer gpa.free(path_full);

    self.doFile(path_full) catch LuaUtils.handleError(self);
}

pub fn setConfig(self: *zlua.Lua, path: []const u8) !void {
    _ = try self.getGlobal("mez");
    defer self.pop(1);
    _ = self.getField(-1, "path");
    defer self.pop(1);
    _ = self.pushString(path);
    self.setField(-2, "config");
}


fn loadBaseConfig(self: *zlua.Lua) void {
    const lua_path = "mez.path.base_config";
    if (!Bridge.getNestedField(self, @constCast(lua_path[0..]))) {
        log.err("Base config path not found. Is your runtime dir setup?", .{});
        return;
    }
    const path = self.toString(-1) catch |err| {
        log.err("Failed to pop the base config path from the lua stack. {}", .{err});
        return;
    };
    self.pop(-1);
    self.doFile(path) catch LuaUtils.handleError(self);
}

fn loadConfigDir(self: *zlua.Lua) void {
    const lua_path = "mez.path.config";
    if (!Bridge.getNestedField(self, @constCast(lua_path[0..]))) {
        log.err("Config path not found. Is your runtime dir setup?", .{});
        return;
    }

    const path = self.toString(-1) catch |err| {
        log.err("Failed to pop the config path from the lua stack. {}", .{err});
        return;
    };

    self.pop(-1);
    self.doFile(path) catch LuaUtils.handleError(self);
}

pub fn openMezLibs(self: *zlua.Lua) void {
  // This is the start of ziglua docgen. My idea of how this will work right now
  // is that we're going to create a lua stack at comptime and then follow
  // (when told) the stack till it's done being created at which point we will
  // take all the functions (and variables) that we found and create a lua file
  // with a '---@meta' heading.
  //
  // Now this has two big parts:
  //  1. the comptime lua stack
  //  2. function signatures, this will require either:
  //    a) the user to provide a luadoc comment above their function (this would
  //       require us to create a luadoc compiler as we need to generate a function
  //       "declaration")
  //    b) full comptime parsing of the code to see what values are pulled off of
  //       and put back onto the lua stack, I think this will be much harder, but
  //       would also make the users job much easier
    self.newTable();
    defer _ = self.setGlobal("mez");

    self.newTable();
    _ = self.setField(-2, "path");

    Options.getDefaultOptions(self);
    _ = self.setField(-2, "opt");

    inline for (.{
        .{ "api", @import("Api.zig") },
        .{ "async", @import("Async.zig") },
        .{ "device", @import("Device.zig") },
        .{ "fs", @import("Fs.zig") },
        .{ "hook", @import("Hook.zig") },
        .{ "input", @import("Input.zig") },
        .{ "output", @import("Output.zig") },
        .{ "remote", @import("Remote.zig") },
        .{ "seat", @import("Seat.zig") },
        .{ "view", @import("View.zig") },
    }) |file| {
        const funcs = zlua.fnRegsFromType(file[1]);
        LuaUtils.newLib(self, funcs);
        self.setField(-2, file[0]);
    }
}
