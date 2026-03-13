//! Maintains state related to keyboard input devices,
//! events such as button presses and dragging

const Keyboard = @This();

const std = @import("std");
const gpa = std.heap.c_allocator;
const server = &@import("main.zig").server;
const Keymap = @import("lua/Input.zig").KeymapData;
const Utils = @import("Utils.zig");

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const xkb = @import("xkbcommon");

const c = @import("C.zig").c;

wlr_keyboard: *wlr.Keyboard,
context: *xkb.Context,
device: *wlr.InputDevice,

// Keyboard listeners
key: wl.Listener(*wlr.Keyboard.event.Key) = .init(handleKey),
key_map: wl.Listener(*wlr.Keyboard) = .init(handleKeyMap),
modifiers: wl.Listener(*wlr.Keyboard) = .init(handleModifiers),

// Device listeners
destroy: wl.Listener(*wlr.InputDevice) = .init(handleDestroy),

pub fn init(device: *wlr.InputDevice) *Keyboard {
    const self = gpa.create(Keyboard) catch Utils.oomPanic();

    errdefer {
        std.log.err("Unable to initialize new keyboard, exiting", .{});
        std.process.exit(6);
    }

    self.* = .{
        .context = xkb.Context.new(.no_flags) orelse return error.ContextFailed,
        .wlr_keyboard = device.toKeyboard(),
        .device = device,
    };

    // TODO: configure this via lua later
    // Should handle this error here
    if (!self.wlr_keyboard.setKeymap(server.seat.xkb_keymap)) return error.SetKeymapFailed;
    self.wlr_keyboard.setRepeatInfo(25, 600);

    self.wlr_keyboard.events.modifiers.add(&self.modifiers);
    self.wlr_keyboard.events.key.add(&self.key);
    self.wlr_keyboard.events.keymap.add(&self.key_map);

    device.events.destroy.add(&self.destroy);

    self.wlr_keyboard.data = self;

    std.log.info("Adding new keyboard {s}", .{device.name orelse "(unnamed)"});
    if (!server.seat.keyboard_group.wlr_group.addKeyboard(self.wlr_keyboard)) {
        std.log.err("Adding new keyboard {s} failed", .{device.name orelse "(unnamed)"});
    }

    return self;
}

pub fn deinit(self: *Keyboard) void {
    self.key.link.remove();
    self.key_map.link.remove();
    self.modifiers.link.remove();
}

fn handleModifiers(_: *wl.Listener(*wlr.Keyboard), wlr_keyboard: *wlr.Keyboard) void {
    server.seat.wlr_seat.setKeyboard(wlr_keyboard);
    server.seat.wlr_seat.keyboardNotifyModifiers(&wlr_keyboard.modifiers);
}

fn handleKey(listener: *wl.Listener(*wlr.Keyboard.event.Key), event: *wlr.Keyboard.event.Key) void {
    const keyboard: *Keyboard = @fieldParentPtr("key", listener);
    // Translate libinput keycode -> xkbcommon
    const keycode = event.keycode + 8;

    var handled: bool = false;
    const modifiers = server.seat.keyboard_group.wlr_group.keyboard.getModifiers();
    // TODO: We should check against other layers besides 0, hyprland does this according to jippity
    const level_keysyms = server.seat.xkb_keymap.keyGetSymsByLevel(keycode, 0, 0);
    const state_keysyms = blk: {
        if(keyboard.wlr_keyboard.xkb_state) |xkb_state| {
            break :blk xkb_state.keyGetSyms(keycode);
        }
        break :blk null;
    };

    var syms: []const xkb.Keysym = undefined;
    for (level_keysyms) |sym| {
        handled = keypress(modifiers, sym, event.state);
        if(handled) {
            syms = level_keysyms;
            break;
        }
    }

    if(!handled and state_keysyms != null) {
        for (state_keysyms.?) |sym| {
            handled = keypress(modifiers, sym, event.state);
            if(handled) {
                syms = state_keysyms.?;
                break;
            }
        }
    }

    // give the keyboard group information about what to repeat and update it
    if (handled and keyboard.wlr_keyboard.repeat_info.delay > 0) {
        server.seat.keyboard_group.modifiers = modifiers;
        server.seat.keyboard_group.keysyms = syms;
        server.seat.keyboard_group.repeat_source.?.timerUpdate(
            keyboard.wlr_keyboard.repeat_info.delay,
        ) catch {
            std.log.warn("failed to update keyboard repeat timer", .{});
        };
    } else {
        server.seat.keyboard_group.modifiers = null;
        server.seat.keyboard_group.keysyms = null;
    }

    if (!handled) {
        server.seat.wlr_seat.setKeyboard(&server.seat.keyboard_group.wlr_group.keyboard);
        server.seat.wlr_seat.keyboardNotifyKey(event.time_msec, event.keycode, event.state);
    }
}

pub fn keypress(modifiers: wlr.Keyboard.ModifierMask, sym: xkb.Keysym, state: wl.Keyboard.KeyState) bool {
    if (server.keymaps.get(Keymap.hash(modifiers, sym))) |map| {
        if (state == .pressed and map.options.lua_press_ref_idx > 0) {
            map.callback(false);
            return true;
        } else if (state == .released and map.options.lua_release_ref_idx > 0) {
            map.callback(true);
            return true;
        }
    }

    return false;
}

fn handleKeyMap(_: *wl.Listener(*wlr.Keyboard), _: *wlr.Keyboard) void {
    std.log.err("Unimplemented handle keyboard keymap", .{});
}

pub fn handleDestroy(listener: *wl.Listener(*wlr.InputDevice), _: *wlr.InputDevice) void {
    const keyboard: *Keyboard = @fieldParentPtr("destroy", listener);

    std.log.debug("removing keyboard: {s}", .{keyboard.device.name orelse "(null)"});

    keyboard.modifiers.link.remove();
    keyboard.key.link.remove();
    keyboard.key_map.link.remove();
    keyboard.destroy.link.remove();

    gpa.destroy(keyboard);
}
