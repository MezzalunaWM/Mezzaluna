/// Maintains state related to keyboard input devices,
/// events such as button presses and dragging

const Keyboard = @This();

const std = @import("std");
const wlr = @import("wlroots");
const wl = @import("wayland").server.wl;

const Keymap = @import("lua/Input.zig").KeymapData;
const utils = @import("utils.zig");
const KeyboardGroup = @import("KeyboardGroup.zig");
const Seat = @import("Seat.zig");

const xkb = @import("xkbcommon");

const gpa = &@import("main.zig").gpa;
const server = &@import("main.zig").server;
const c = @import("c");
const log = std.log.scoped(.Keyboard);

wlr_keyboard: *wlr.Keyboard,
// there's wlr.KeyboardGroup.fromKeyboard, but it doesn't seem to work
group: ?*KeyboardGroup,

// Keyboard listeners
key: wl.Listener(*wlr.Keyboard.event.Key) = .init(handleKey),
key_map: wl.Listener(*wlr.Keyboard) = .init(handleKeyMap),
modifiers: wl.Listener(*wlr.Keyboard) = .init(handleModifiers),

// Device listeners
destroy: wl.Listener(*wlr.InputDevice) = .init(handleDestroy),

pub fn init(device: *wlr.InputDevice) *Keyboard {
    const self = gpa.create(Keyboard) catch utils.oomPanic();

    self.* = .{
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
    const group = if (self.group) |group| group else {
        log.warn(
            "dropping keyboard event: `{}` no keyboard group available",
            .{event}
        );
        return;
    };

    // tell the idle notifier that we've received activity
    server.idle_notifier.notifyActivity(group.seat.wlr_seat);

    const keycode = event.keycode + 8; // Translate libinput keycode -> xkbcommon
    const modifiers = group.wlr_group.keyboard.getModifiers();

    if (self.wlr_keyboard.xkb_state) |xkb_state| not_handled: {
        const state_keysyms = xkb_state.keyGetSyms(keycode);
        for (state_keysyms) |sym| {
            if (keypress(group.seat, modifiers, sym, event.state)) break;
        } else break :not_handled;

        // give the keyboard group information about what to repeat and update it
        if (self.wlr_keyboard.repeat_info.delay > 0) {
            group.modifiers = modifiers;
            group.keysyms = state_keysyms;
            group.repeat_source.?.timerUpdate(
                self.wlr_keyboard.repeat_info.delay,
            ) catch log.warn("failed to update keyboard repeat timer", .{});
        }

        return; // there's nothing else that should be done atp
    }

    // clear the repeat info
    group.modifiers = null;
    group.keysyms = null;

    // pass keyboard event to the focused client
    group.seat.wlr_seat.keyboardNotifyKey(event.time_msec, event.keycode, event.state);
    group.seat.wlr_seat.setKeyboard(&group.wlr_group.keyboard);
}

pub fn keypress(
    seat: *Seat,
    modifiers: wlr.Keyboard.ModifierMask,
    sym: xkb.Keysym,
    state: wl.Keyboard.KeyState,
) bool {
    if (seat.keymaps.get(Keymap.hash(modifiers, sym))) |map| {
        return map.callback(state == .released);
    }
    return false;
}

fn handleKeyMap(_: *wl.Listener(*wlr.Keyboard), _: *wlr.Keyboard) void {
    log.err("Unimplemented handle keyboard keymap", .{});
}

pub fn handleDestroy(listener: *wl.Listener(*wlr.InputDevice), _: *wlr.InputDevice) void {
    const keyboard: *Keyboard = @fieldParentPtr("destroy", listener);

    log.debug("removing keyboard: {s}", .{keyboard.wlr_keyboard.base.name orelse "(null)"});

    keyboard.modifiers.link.remove();
    keyboard.key.link.remove();
    keyboard.key_map.link.remove();
    keyboard.destroy.link.remove();

    gpa.destroy(keyboard);
}
