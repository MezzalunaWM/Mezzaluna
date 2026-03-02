//! This is a simple way to define a mousemap. To keep hashing consistent the
//! hash is generated here.
const Mousemap = @This();

const std = @import("std");

const xkb = @import("xkbcommon");
const wlr = @import("wlroots");
const zlua = @import("zlua");

const RemoteLua = @import("../RemoteLua.zig");
const Lua = &@import("../main.zig").lua;

modifier: wlr.Keyboard.ModifierMask,
event_code: i32,
options: struct {
    /// This is the location of the on press lua function in the lua registry
    lua_press_ref_idx: i32,
    /// This is the location of the on release lua function in the lua registry
    lua_release_ref_idx: i32,
    /// This is the location of the on drag lua function in the lua registry
    lua_drag_ref_idx: i32,
},

pub const MousemapState = enum { press, drag, release };

// Returns true if mouse input should be passed through
pub fn callback(self: *const Mousemap, state: MousemapState, args: anytype) bool {
    const ArgsType = @TypeOf(args);
    const args_type_info = @typeInfo(ArgsType);
    if (args_type_info != .@"struct") {
        @compileError("expected tuple or struct argument, found " ++ @typeName(ArgsType));
    }

    const lua_ref_idx = switch (state) {
        .press => self.options.lua_press_ref_idx,
        .release => self.options.lua_release_ref_idx,
        .drag => self.options.lua_drag_ref_idx,
    };

    const t = Lua.state.rawGetIndex(zlua.registry_index, lua_ref_idx);
    if (t != zlua.LuaType.function) {
        RemoteLua.sendNewLogEntry("Failed to call mousemap, it doesn't have a callback.");
        Lua.state.pop(1);
        return false;
    }

    // allow passing any arguments to the lua hook
    var i: u8 = 0;
    inline for (args, 1..) |field, k| {
        try Lua.state.pushAny(field);
        i = k;
    }

    Lua.state.protectedCall(.{ .args = i, .results = 1 }) catch {
        RemoteLua.sendNewLogEntry(Lua.state.toString(-1) catch unreachable);
    };

    const ret = if (Lua.state.isBoolean(-1)) Lua.state.toBoolean(-1) else false;
    Lua.state.pop(-1);
    return ret;
}

pub fn hash(modifier: wlr.Keyboard.ModifierMask, event_code: i32) u64 {
    const mod_val: u32 = @bitCast(modifier);
    const button_val: u32 = @bitCast(event_code);
    return (@as(u64, mod_val) << 32) | @as(u64, button_val);
}
