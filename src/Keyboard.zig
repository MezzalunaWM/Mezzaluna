//! Maintains state related to keyboard input devices,
//! events such as button presses and dragging

const std = @import("std");
const wlr = @import("wlroots");
const wl = @import("wayland").server.wl;

const Keymap = @import("lua/Input.zig").KeymapData;
const Utils = @import("Utils.zig");
const KeyboardGroup = @import("KeyboardGroup.zig");
const Seat = @import("Seat.zig");

const xkb = @import("xkbcommon");

const gpa = &@import("main.zig").gpa;
const server = &@import("main.zig").server;
const c = @import("C.zig").c;

const Keyboard = @This();

wlr_keyboard: *wlr.Keyboard,
context: *xkb.Context,
// there's wlr.KeyboardGroup.fromKeyboard, but it doesn't seem to work
group: ?*KeyboardGroup,

// Keyboard listeners
key: wl.Listener(*wlr.Keyboard.event.Key) = .init(handleKey),
key_map: wl.Listener(*wlr.Keyboard) = .init(handleKeyMap),
modifiers: wl.Listener(*wlr.Keyboard) = .init(handleModifiers),

// Device listeners
destroy: wl.Listener(*wlr.InputDevice) = .init(handleDestroy),

pub fn init(device: *wlr.InputDevice) *Keyboard {
    const self = gpa.create(Keyboard) catch Utils.oomPanic();

    // TODO: there is no world where pluggin in a keyboard should crash the
    // compositor >:(
    errdefer {
        std.log.err("Unable to initialize new keyboard, exiting", .{});
        std.process.exit(6);
    }

    self.* = .{
        .context = xkb.Context.new(.no_flags) orelse return error.ContextFailed,
        .wlr_keyboard = device.toKeyboard(),
        .group = null,
    };

    self.wlr_keyboard.setRepeatInfo(25, 600);

    self.wlr_keyboard.events.modifiers.add(&self.modifiers);
    self.wlr_keyboard.events.key.add(&self.key);
    self.wlr_keyboard.events.keymap.add(&self.key_map);

    device.events.destroy.add(&self.destroy);

    self.wlr_keyboard.data = self;

    return self;
}

pub fn deinit(self: *Keyboard) void {
    self.key.link.remove();
    self.key_map.link.remove();
    self.modifiers.link.remove();
}

fn handleModifiers(listener: *wl.Listener(*wlr.Keyboard), wlr_keyboard: *wlr.Keyboard) void {
    const self: *Keyboard = @fieldParentPtr("modifiers", listener);
    const seat = self.group.?.seat;
    seat.wlr_seat.setKeyboard(wlr_keyboard);
    seat.wlr_seat.keyboardNotifyModifiers(&wlr_keyboard.modifiers);
}

fn handleKey(listener: *wl.Listener(*wlr.Keyboard.event.Key), event: *wlr.Keyboard.event.Key) void {
    const self: *Keyboard = @fieldParentPtr("key", listener);
    const seat = if (self.group) |group| group.seat else {
        std.log.warn(
            "dropping keyboard event: `{}` no keyboard group available",
            .{event}
        );
        return;
    };

    // Translate libinput keycode -> xkbcommon
    const keycode = event.keycode + 8;

    var handled: bool = false;
    const modifiers = self.group.?.wlr_group.keyboard.getModifiers();
    // TODO: We should check against other layers besides 0, hyprland does this according to jippity
    const level_keysyms = seat.xkb_keymap.keyGetSymsByLevel(keycode, 0, 0);
    const state_keysyms = blk: {
        if(self.wlr_keyboard.xkb_state) |xkb_state| {
            break :blk xkb_state.keyGetSyms(keycode);
        }
        break :blk null;
    };

    var syms: []const xkb.Keysym = undefined;
    for (level_keysyms) |sym| {
        handled = keypress(self.group.?.seat, modifiers, sym, event.state);
        if(handled) {
            syms = level_keysyms;
            break;
        }
    }

    if(!handled and state_keysyms != null) {
        for (state_keysyms.?) |sym| {
            handled = keypress(self.group.?.seat, modifiers, sym, event.state);
            if(handled) {
                syms = state_keysyms.?;
                break;
            }
        }
    }

    // give the keyboard group information about what to repeat and update it
    if (handled and self.wlr_keyboard.repeat_info.delay > 0) {
        self.group.?.modifiers = modifiers;
        self.group.?.keysyms = syms;
        self.group.?.repeat_source.?.timerUpdate(
            self.wlr_keyboard.repeat_info.delay,
        ) catch {
            std.log.warn("failed to update keyboard repeat timer", .{});
        };
    } else {
        self.group.?.modifiers = null;
        self.group.?.keysyms = null;
    }

    if (!handled) {
        seat.wlr_seat.setKeyboard(&self.group.?.wlr_group.keyboard);
        seat.wlr_seat.keyboardNotifyKey(event.time_msec, event.keycode, event.state);
    }

    // tell the idle notifier that we've recieved activity now that it's been
    // fully processed
    server.idle_notifier.notifyActivity(seat.wlr_seat);
}

pub fn keypress(
    seat: *Seat,
    modifiers: wlr.Keyboard.ModifierMask,
    sym: xkb.Keysym,
    state: wl.Keyboard.KeyState,
) bool {
    if (seat.keymaps.get(Keymap.hash(modifiers, sym))) |map| {
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

    std.log.debug("removing keyboard: {s}", .{keyboard.wlr_keyboard.base.name orelse "(null)"});

    keyboard.modifiers.link.remove();
    keyboard.key.link.remove();
    keyboard.key_map.link.remove();
    keyboard.destroy.link.remove();

    gpa.destroy(keyboard);
}
