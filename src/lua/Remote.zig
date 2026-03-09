//! mez.remote
const Remote = @This();

const std = @import("std");
const zlua = @import("zlua");

const LuaUtils = @import("LuaUtils.zig");
const RemoteLua = @import("../RemoteLua.zig");

pub fn print(L: *zlua.Lua) i32 {
  RemoteLua.sendNewLogEntry(L.checkString(1));
  return 0;
}
