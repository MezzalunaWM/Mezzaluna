const Lua = @This();

const std = @import("std");
const config = @import("config");
const zlua = @import("zlua");

const LuaUtils = @import("LuaUtils.zig");
const Bridge = @import("Bridge.zig");
const Fs =     @import("Fs.zig");
const Input =  @import("Input.zig");
const Api =    @import("Api.zig");
const Hook =   @import("Hook.zig");
const View =   @import("View.zig");
const Output = @import("Output.zig");
const Remote = @import("Remote.zig");

const gpa = std.heap.c_allocator;

state: *zlua.Lua,

pub fn loadRuntimeDir(self: *zlua.Lua) !void {
  const path_dir = try std.fs.path.joinZ(gpa, &[_][]const u8{
    config.runtime_path_prefix,
    "share",
    "mezzaluna",
  });
  defer gpa.free(path_dir);

  {
    _ = try self.getGlobal("mez");
    _ = self.getField(-1, "path");
    defer self.pop(2);
    _ = self.pushString(path_dir);
    self.setField(-2, "runtime");
  }

  const path_full = try std.fs.path.joinZ(gpa, &[_][]const u8{
    path_dir,
    "init.lua",
  });
  defer gpa.free(path_full);

  self.doFile(path_full) catch {
    const err = try self.toString(-1);
    std.log.debug("Failed to run lua file: {s}", .{err});
  };
}

pub fn setBaseConfig(self: *zlua.Lua, path: []const u8) !void {
  {
    _ = try self.getGlobal("mez");
    _ = self.getField(-1, "path");
    defer self.pop(2);
    const new_path = try std.fs.path.join(gpa, &[_][]const u8{path, "init.lua"});
    defer gpa.free(new_path);
    _ = self.pushString(new_path);
    self.setField(-2, "config");
  }
  {
    _ = try self.getGlobal("mez");
    _ = self.getField(-1, "path");
    defer self.pop(2);
    const cur_path = self.toString(-1) catch "";

    const unsentinel: []const u8 = std.mem.span(cur_path.ptr);
    const new_path = try std.mem.concat(gpa, u8, &[_][]const u8{
      unsentinel,
      ";",
      path,
    });
    defer gpa.free(new_path);
    _ = self.pushString(new_path);
    _ = self.setField(-2, "path");
  }
}

fn loadBaseConfig(self: *zlua.Lua) !void {
  const lua_path = "mez.path.base_config";
  if (!Bridge.getNestedField(self, @constCast(lua_path[0..]))) {
    std.log.err("Base config path not found. is your runtime dir setup?", .{});
    return;
  }
  const path = self.toString(-1) catch |err| {
    std.log.err("Failed to pop the base config path from the lua stack. {}", .{err});
    return;
  };
  self.pop(-1);
  try self.doFile(path);
}

fn loadConfigDir(self: *zlua.Lua) !void {
  const lua_path = "mez.path.config";
  if (!Bridge.getNestedField(self, @constCast(lua_path[0..]))) {
    std.log.err("Config path not found. is your runtime dir setup?", .{});
    return;
  }
  const path = self.toString(-1) catch |err| {
    std.log.err("Failed to pop the config path from the lua stack. {}", .{err});
    return;
  };
  self.pop(-1);
  try self.doFile(path);
}

pub fn openLibs(self: *zlua.Lua) void {
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
  {
    self.newTable();
    defer _ = self.setGlobal("mez");
    {
      self.newTable();
      defer _ = self.setField(-2, "path");
    }
    {
      const fs_funcs = zlua.fnRegsFromType(Fs);
      LuaUtils.newLib(self, fs_funcs);
      self.setField(-2, "fs");
    }
    {
      const input_funcs = zlua.fnRegsFromType(Input);
      LuaUtils.newLib(self, input_funcs);
      self.setField(-2, "input");
    }
    {
      const hook_funcs = zlua.fnRegsFromType(Hook);
      LuaUtils.newLib(self, hook_funcs);
      self.setField(-2, "hook");
    }
    {
      const api_funcs = zlua.fnRegsFromType(Api);
      LuaUtils.newLib(self, api_funcs);
      self.setField(-2, "api");
    }
    {
      const view_funcs = zlua.fnRegsFromType(View);
      LuaUtils.newLib(self, view_funcs);
      self.setField(-2, "view");
    }
    {
      const output_funcs = zlua.fnRegsFromType(Output);
      LuaUtils.newLib(self, output_funcs);
      self.setField(-2, "output");
    }
    {
      const remote_funcs = zlua.fnRegsFromType(Remote);
      LuaUtils.newLib(self, remote_funcs);
      self.setField(-2, "remote");
    }
  }
}

pub const Config = struct { str: ?[]const u8, enabled: bool, };
pub fn init(self: *Lua, cfg: Config) !void {
  self.state = try zlua.Lua.init(gpa);
  errdefer self.state.deinit();
  self.state.openLibs();

  openLibs(self.state);

  if (!cfg.enabled) try setBaseConfig(self.state, "");
  loadRuntimeDir(self.state) catch |err| if (err == error.LuaRuntime) {
    std.log.warn("{s}", .{try self.state.toString(-1)});
  };

  loadBaseConfig(self.state) catch |err| if (err == error.LuaRuntime) {
    std.log.warn("{s}", .{try self.state.toString(-1)});
  };

  if (cfg.str) |path| {
    defer gpa.free(path);
    try setBaseConfig(self.state, path);
  }
  if (cfg.enabled) {
    loadConfigDir(self.state) catch |err| if (err == error.LuaRuntime) {
      std.log.warn("{s}", .{try self.state.toString(-1)});
    };
  }

  std.log.debug("Loaded lua", .{});
}

pub fn deinit(self: *Lua) void {
  self.state.deinit();
}
