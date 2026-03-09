const Input = @This();

const std = @import("std");
const zlua = @import("zlua");
const xkb = @import("xkbcommon");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const Keymap = @import("../types/Keymap.zig");
const Utils = @import("../Utils.zig");
const LuaUtils = @import("LuaUtils.zig");
const c = @import("../C.zig").c;

const server = &@import("../main.zig").server;

fn parse_modkeys(modStr: []const u8) wlr.Keyboard.ModifierMask {
  var it = std.mem.splitScalar(u8, modStr, '|');
  var modifiers = wlr.Keyboard.ModifierMask{};
  while (it.next()) |m| {
    inline for (std.meta.fields(@TypeOf(modifiers))) |f| {
      if (f.type == bool and std.mem.eql(u8, m, f.name)) {
        @field(modifiers, f.name) = true;
      }
    }
  }

  return modifiers;
}

/// ---Create a new keymap
/// ---@param string modifiers
/// ---@param string keys
/// ---@param table options
pub fn add_keymap(L: *zlua.Lua) i32 {
  var keymap: Keymap = undefined;
  keymap.options.repeat = true;

  const mod = L.checkString(1);
  keymap.modifier = parse_modkeys(mod);

  const key = L.checkString(2);
  keymap.keycode = xkb.Keysym.fromName(key, .no_flags);

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

  const hash = Keymap.hash(keymap.modifier, keymap.keycode);
  server.keymaps.put(hash, keymap) catch Utils.oomPanic();

  L.pushNil();
  return 1;
}

/// ---Remove an existing keymap
/// ---@param string modifiers
/// ---@param string keys
pub fn del_keymap(L: *zlua.Lua) i32 {
  L.checkType(1, .string);
  L.checkType(2, .string);

  var keymap: Keymap = undefined;
  const mod = L.checkString(1);

  keymap.modifier = parse_modkeys(mod);

  const key = L.checkString(2);

  keymap.keycode = xkb.Keysym.fromName(key, .no_flags);
  _ = server.keymaps.remove(Keymap.hash(keymap.modifier, keymap.keycode));

  L.pushNil();
  return 1;
}

/// ---Get the repeat information
/// ---@return integer[2]
pub fn get_repeat_info(L: *zlua.Lua) i32 {
  L.newTable();

  L.pushInteger(server.seat.keyboard_group.keyboard.repeat_info.rate);
  L.setField(-2, "rate");
  L.pushInteger(server.seat.keyboard_group.keyboard.repeat_info.delay);
  L.setField(-2, "delay");

  return 1;
}

/// ---Set the repeat information
/// ---@param integer rate
/// ---@param integer delay
pub fn set_repeat_info(L: *zlua.Lua) i32 {
  const rate = LuaUtils.coerceInteger(i32, L.checkInteger(1)) catch {
    L.raiseErrorStr("The rate must be a valid number", .{});
  };
  const delay = LuaUtils.coerceInteger(i32, L.checkInteger(2)) catch {
    L.raiseErrorStr("The delay must be a valid number", .{});
  };

  server.seat.keyboard_group.keyboard.setRepeatInfo(rate, delay);
  return 0;
}

/// FIXME: this doesn't work just yet, and I'm not sure how we can get the
/// correct time.
fn getTimeMs() u32 {
  const now = std.posix.clock_gettime(.MONOTONIC) catch unreachable;
  return @intCast(now.sec * 1000 + @divTrunc(now.nsec, 1000000));
}

pub fn send_key(L: *zlua.Lua) i32 {
  const key = L.checkString(1);
  const state = L.checkString(2);

  var pressed: u32 = 1;
  if (std.mem.eql(u8, state, "press")) {
    pressed = 1;
  } if (std.mem.eql(u8, state, "release")) {
    pressed = 0;
  }

  const keysym = xkb.Keysym.fromName(key, .no_flags);

  server.seat.wlr_seat.keyboardNotifyKey(
    getTimeMs(),
    keysym.toUTF32(),
    .pressed,
  );

  return 0;
}

pub fn send_pointer_motion(L: *zlua.Lua) i32 {
  const sx = L.checkNumber(1);
  const sy = L.checkNumber(2);

  server.seat.wlr_seat.pointerNotifyMotion(getTimeMs(), sx, sy);
  server.seat.wlr_seat.pointerNotifyFrame();

  return 0;
}

pub fn send_pointer_button(L: *zlua.Lua) i32 {
  const button = L.checkString(1);
  const state = L.checkString(2);

  var pressed: wl.Pointer.ButtonState = .pressed;
  if (std.mem.eql(u8, state, "press")) {
    pressed = .pressed;
  } if (std.mem.eql(u8, state, "release")) {
    pressed = .released;
  } else {
    return 0;
  }

  const mousesym = c.libevdev_event_code_from_name(c.EV_KEY, button);
  _ = server.seat.wlr_seat.pointerNotifyButton(getTimeMs(), @intCast(mousesym), pressed);

  return 0;
}

// ---@param x number x position of cursor
// ---@param y number y position of cursor
pub fn warp_pointer(L: *zlua.Lua) i32 {
  const x = L.checkNumber(1);
  const y = L.checkNumber(2);

  server.seat.wlr_seat.pointerWarp(x, y);
  server.seat.wlr_seat.pointerNotifyFrame();
  return 0;
}
