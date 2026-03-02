//! This is a simple way to define a hook.
const Hook = @This();

const std = @import("std");

const xkb = @import("xkbcommon");
const wlr = @import("wlroots");
const zlua = @import("zlua");

const Event = @import("Events.zig");
const RemoteLua = @import("../RemoteLua.zig");
const Lua = &@import("../main.zig").lua;

events: [][]const u8, // a list of events
options: struct {
    // group: []const u8, // TODO: do we need groups?
    /// This is the location of the callback lua function in the lua registry
    lua_cb_ref_idx: i32,
},

pub fn callback(self: *const Hook, args: anytype) void {
    const ArgsType = @TypeOf(args);
    const args_type_info = @typeInfo(ArgsType);
    if (args_type_info != .@"struct") {
        @compileError("expected tuple or struct argument, found " ++ @typeName(ArgsType));
    }

    const t = Lua.state.rawGetIndex(zlua.registry_index, self.options.lua_cb_ref_idx);
    if (t != zlua.LuaType.function) {
        RemoteLua.sendNewLogEntry("Failed to call hook, it doesn't have a callback.");
        Lua.state.pop(1);
        return;
    }

    // allow passing any arguments to the lua hook
    var i: u8 = 0;
    inline for (args, 1..) |field, k| {
        try Lua.state.pushAny(field);
        i = k;
    }

    Lua.state.protectedCall(.{ .args = i }) catch {
        RemoteLua.sendNewLogEntry(Lua.state.toString(-1) catch unreachable);
    };
    Lua.state.pop(-1);
}
