//! mez.input
const Input = @This();

const std = @import("std");
const zlua = @import("zlua");
const xkb = @import("xkbcommon");
const wlr = @import("wlroots");

const Utils = @import("../Utils.zig");
const LuaUtils = @import("LuaUtils.zig");
const RemoteLua = @import("../RemoteLua.zig");

const c = @import("../C.zig").c;
const server = &@import("../main.zig").server;
const Lua = &@import("../main.zig").lua;

fn parse_modkeys(modStr: []const u8) wlr.Keyboard.ModifierMask {
    var it = std.mem.splitScalar(u8, modStr, '|');
    var modifiers = wlr.Keyboard.ModifierMask{};
    while (it.next()) |m| {
        inline for (std.meta.fields(@TypeOf(modifiers))) |f| {
            if (f.type == bool and std.ascii.eqlIgnoreCase(m, f.name)) {
                @field(modifiers, f.name) = true;
            }
        }
    }

    return modifiers;
}

pub const KeymapData = struct {
    modifier: wlr.Keyboard.ModifierMask,
    keysym: xkb.Keysym,
    options: struct {
        repeat: bool,
        /// This is the location of the on press lua function in the lua registry
        lua_press_ref_idx: i32,
        /// This is the location of the on release lua function in the lua registry
        lua_release_ref_idx: i32,
    },

    pub fn callback(self: *const KeymapData, release: bool) void {
        const lua_ref_idx = if (release) self.options.lua_release_ref_idx else self.options.lua_press_ref_idx;

        const t = Lua.state.rawGetIndex(zlua.registry_index, lua_ref_idx);
        if (t != zlua.LuaType.function) {
            RemoteLua.sendNewLogEntry("Failed to call keybind, it doesn't have a callback.");
            Lua.state.pop(1);
            return;
        }

        Lua.state.protectedCall(.{ .args = 0, .results = 0 }) catch LuaUtils.handleError(Lua.state);
        Lua.state.pop(-1);
    }

    pub fn hash(modifier: wlr.Keyboard.ModifierMask, keycode: xkb.Keysym) u64 {
        const mod_val: u32 = @bitCast(modifier);
        const key_val: u32 = @intFromEnum(keycode);
        return (@as(u64, mod_val) << 32) | @as(u64, key_val);
    }
};

pub const MousemapData = struct {
    modifier: wlr.Keyboard.ModifierMask,
    event_code: i32,
    options: struct {
        /// This is the location of the on press lua function in the lua registry
        lua_press_ref_idx: i32,
        /// This is the location of the on release lua function in the lua registry
        lua_release_ref_idx: i32,
        /// This is the location of the on drag lua function in the lua registry
        lua_drag_ref_idx: i32,
        /// This is the location of the on drag lua function in the lua registry
        lua_scroll_ref_idx: i32,
    },

    pub const MousemapState = enum { press, drag, release, scroll };

    // Returns true if mouse input should be passed through
    pub fn callback(self: *const MousemapData, state: MousemapState, args: anytype) bool {
        const ArgsType = @TypeOf(args);
        const args_type_info = @typeInfo(ArgsType);
        if (args_type_info != .@"struct") {
            @compileError("expected tuple or struct argument, found " ++ @typeName(ArgsType));
        }

        const lua_ref_idx = switch (state) {
            .press => self.options.lua_press_ref_idx,
            .release => self.options.lua_release_ref_idx,
            .drag => self.options.lua_drag_ref_idx,
            .scroll => self.options.lua_scroll_ref_idx
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

        Lua.state.protectedCall(.{ .args = i, .results = 1 }) catch LuaUtils.handleError(Lua.state);
        const ret = Lua.state.toBoolean(-1);
        Lua.state.pop(1);

        return ret;
    }

    pub fn hash(modifier: wlr.Keyboard.ModifierMask, event_code: i32) u64 {
        const mod_val: u32 = @bitCast(modifier);
        const button_val: u32 = @bitCast(event_code);
        return (@as(u64, mod_val) << 32) | @as(u64, button_val);
    }
};

/// ---Create a new keymap
/// ---@param modifiers string
/// ---@param keys string
/// ---@param options table { press: fun(), repeat: fun(), release: fun() }
pub fn add_keymap(L: *zlua.Lua) i32 {
    var keymap: KeymapData = undefined;
    keymap.options.repeat = true;

    const mod = L.checkString(1);
    keymap.modifier = parse_modkeys(mod);

    const key = L.checkString(2);
    keymap.keysym = xkb.Keysym.fromName(key, .no_flags);

    _ = L.pushString("press");
    _ = L.getTable(3);
    if (L.isFunction(-1)) {
        keymap.options.lua_press_ref_idx = L.ref(zlua.registry_index) catch Utils.oomPanic();
    }

    _ = L.pushString("release");
    _ = L.getTable(3);
    if (L.isFunction(-1)) {
        keymap.options.lua_release_ref_idx = L.ref(zlua.registry_index) catch Utils.oomPanic();
    }

    _ = L.pushString("repeat");
    _ = L.getTable(3);
    keymap.options.repeat = L.isNil(-1) or L.toBoolean(-1);

    const hash = KeymapData.hash(keymap.modifier, keymap.keysym);
    server.keymaps.put(hash, keymap) catch Utils.oomPanic();

    L.pushNil();
    return 1;
}

/// ---Remove an existing keymap
/// ---@param modifiers string
/// ---@param keys string
pub fn del_keymap(L: *zlua.Lua) i32 {
    L.checkType(1, .string);
    L.checkType(2, .string);

    var keymap: KeymapData = undefined;
    const mod = L.checkString(1);

    keymap.modifier = parse_modkeys(mod);

    const key = L.checkString(2);

    keymap.keysym = xkb.Keysym.fromName(key, .no_flags);
    _ = server.keymaps.remove(KeymapData.hash(keymap.modifier, keymap.keysym));

    L.pushNil();
    return 1;
}


/// ---@class Position
/// ---@field x number
/// ---@field y number

/// ---@alias MousemapButtonFunc fun(
/// ---     view_id: integer,
/// ---     pos: Position,
/// ---     start: Position,
/// ---     offset: Position): boolean?

/// ---@alias MousemapScrollFunc fun(
/// ---     view_id: integer,
/// ---     pos: Position,
/// ---     delta: integer,
/// ---     discrete_delta: number) :boolean?

/// ---Create a new mousemap
/// ---@param modifiers string
/// ---@param btn_name string button name (ex. "BTN_LEFT", "BTN_RIGHT")
/// ---@param options {
/// ---     press: MousemapButtonFunc?,
/// ---     drag: MousemapButtonFunc?,
/// ---     release: MousemapButtonFunc?,
/// ---     scroll: MousemapScrollFunc? }
pub fn add_mousemap(L: *zlua.Lua) i32 {
    var mousemap: MousemapData = undefined;

    const mod = L.checkString(1);
    mousemap.modifier = parse_modkeys(mod);

    const button = L.checkString(2);
    mousemap.event_code = -1;
    const key_event_code = c.libevdev_event_code_from_name(c.EV_KEY, button);
    const rel_event_code = c.libevdev_event_code_from_name(c.EV_REL, button);

    if(key_event_code != -1) {
        mousemap.event_code = key_event_code;

        _ = L.pushString("press");
        _ = L.getTable(3);
        if (L.isFunction(-1)) {
            mousemap.options.lua_press_ref_idx = L.ref(zlua.registry_index) catch Utils.oomPanic();
        }

        _ = L.pushString("release");
        _ = L.getTable(3);
        if (L.isFunction(-1)) {
            mousemap.options.lua_release_ref_idx = L.ref(zlua.registry_index) catch Utils.oomPanic();
        }

        _ = L.pushString("drag");
        _ = L.getTable(3);
        if (L.isFunction(-1)) {
            mousemap.options.lua_drag_ref_idx = L.ref(zlua.registry_index) catch Utils.oomPanic();
        }
    } else if(rel_event_code != 1){
        mousemap.event_code = rel_event_code;

        _ = L.pushString("scroll");
        _ = L.getTable(3);
        if (L.isFunction(-1)) {
            mousemap.options.lua_scroll_ref_idx = L.ref(zlua.registry_index) catch Utils.oomPanic();
        }
    }

    if(mousemap.event_code != -1) {
        const hash = MousemapData.hash(mousemap.modifier, mousemap.event_code);
        server.mousemaps.put(hash, mousemap) catch Utils.oomPanic();
    }

    L.pushNil();
    return 1;
}

/// ---Remove an existing mousemap
/// ---@param modifiers string
/// ---@param button string
pub fn del_mousemap(L: *zlua.Lua) i32 {
    L.checkType(1, .string);
    L.checkType(2, .string);

    var mousemap: MousemapData = undefined;
    const mod = L.checkString(1);
    mousemap.modifier = parse_modkeys(mod);

    const button = L.checkString(2);
    mousemap.event_code = blk: {
        const key_event_code = c.libevdev_event_code_from_name(c.EV_KEY, button);
        const rel_event_code = c.libevdev_event_code_from_name(c.EV_REL, button);

        if(key_event_code != -1) break :blk key_event_code;
        if(rel_event_code != -1) break :blk rel_event_code;
        break :blk -1;
    };

    if(mousemap.event_code != -1) {
        _ = server.mousemaps.remove(MousemapData.hash(mousemap.modifier, mousemap.event_code));
    }

    return 0;
}

/// ---Get the repeat information
/// ---@return { rate: integer, delay: integer }
pub fn get_repeat_info(L: *zlua.Lua) i32 {
    L.newTable();

    L.pushInteger(server.seat.keyboard_group.wlr_group.keyboard.repeat_info.rate);
    L.setField(-2, "rate");
    L.pushInteger(server.seat.keyboard_group.wlr_group.keyboard.repeat_info.delay);
    L.setField(-2, "delay");

    return 1;
}

/// ---Set the repeat information
/// ---@param rate integer
/// ---@param delay integer
pub fn set_repeat_info(L: *zlua.Lua) i32 {
    const rate = LuaUtils.coerceInteger(i32, L.checkInteger(1)) catch {
        L.raiseErrorStr("The rate must be a valid number", .{});
    };
    const delay = LuaUtils.coerceInteger(i32, L.checkInteger(2)) catch {
        L.raiseErrorStr("The delay must be a valid number", .{});
    };

    server.seat.keyboard_group.wlr_group.keyboard.setRepeatInfo(rate, delay);
    return 0;
}

/// ---Set the cursor type
/// ---@param cursor string name
pub fn set_cursor_type(L: *zlua.Lua) i32 {
    const name = L.checkString(1);
    server.cursor.wlr_cursor.setXcursor(server.cursor.x_cursor_manager, name);

    return 0;
}
