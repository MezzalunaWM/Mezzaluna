/// mez.remote grants interface with remote lua clients. See https://github.com/MezzalunaWM/Whetstone for more information

const Remote = @This();

const std = @import("std");
const zlua = @import("zlua");

const LuaUtils = @import("LuaUtils.zig");
const RemoteLua = @import("../RemoteLua.zig");
pub const log = std.log.scoped(.@"Lua.Remote");

/// ---Print a string to whetstone
/// ---@param string string String to print
pub fn print(L: *zlua.Lua) i32 {
    RemoteLua.sendNewLogEntry(L.checkString(1));
    return 0;
}
