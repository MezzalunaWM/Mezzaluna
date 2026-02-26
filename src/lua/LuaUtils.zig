const LuaUtils = @This();

const std = @import("std");
const zlua = @import("zlua");

const View = @import("../View.zig");

const server = &@import("../main.zig").server;

pub fn coerceNumber(comptime x: type, number: zlua.Number) error{InvalidNumber}!x {
  if (number < std.math.minInt(x) or number > std.math.maxInt(x) or std.math.isNan(number)) {
    return error.InvalidNumber;
  }
  switch (@typeInfo(x)) {
    .int => return @as(x, @intFromFloat(number)),
    .float => return @floatCast(number),
    else => @compileError("unsupported type"),
  }
}

pub fn coerceInteger(comptime x: type, number: zlua.Integer) error{InvalidInteger}!x {
  if (number < std.math.minInt(x) or number > std.math.maxInt(x) or std.math.isNan(number)) {
    return error.InvalidInteger;
  }
  switch (@typeInfo(x)) {
    .int => return @intCast(number),
    .float => return @as(x, @floatFromInt(number)),
    else => @compileError("unsupported type"),
  }
}

pub fn newLib(L: *zlua.Lua, f: []const zlua.FnReg) void {
  L.newLibTable(f); // documented as being unavailable, but it is.
  for (f) |value| {
    if (value.func == null) continue;
    L.pushClosure(value.func.?, 0);
    L.setField(-2, value.name);
  }
}

/// makes a best effort to convert the value at the top of the stack to a string
/// if we're unable to do so return "nil"
pub fn toStringEx(L: *zlua.Lua) [:0]const u8 {
  const errstr = "nil";
  _ = L.getGlobal("tostring") catch return errstr;
  L.insert(1);
  L.protectedCall(.{ .args = 1, .results = 1 }) catch return errstr;
  return L.toString(-1) catch errstr;
}

pub fn viewById(view_id: u64) ?*View {
  if (view_id == 0) {
    if(server.seat.focused_surface) |fs| {
      if(fs == .view) return fs.view;
    }
  } else {
    return server.root.viewById(view_id);
  }
  return null;
}
