const input_device = @This();

const std = @import("std");
const wlr = @import("wlroots");

const Keyboard = @import("Keyboard.zig");

pub const InputDevice = union(wlr.InputDevice.Type) {
    keyboard: *Keyboard,
    pointer: *wlr.Pointer,
    touch: void,
    tablet: void,
    tablet_pad: void,
    @"switch": void,
};

pub fn init(device: *wlr.InputDevice) void {
    switch (device.type) {
        .keyboard => {
            const keyboard = Keyboard.init(device);
            device.data = keyboard;
        },
        .pointer => {
            // the data attached here is used to figure out which seat owns
            // the pointer
            device.data = null;
        },
        else => |t| std.log.err("unsupported input method: {}", .{ t }),
    }
}

pub fn remove(device: *wlr.InputDevice) void {
    switch (device.type) {
        .keyboard => {
            const keyboard = (get(device) orelse return).keyboard;
            std.debug.assert(keyboard.group == null);
            keyboard.deinit();
        },
        .pointer => {
            std.debug.assert(device.data == null);
        },
        else => |t| std.log.err("unsupported input method: {}", .{ t }),
    }
}

pub fn get(device: *wlr.InputDevice) ?InputDevice {
    return switch (device.type) {
        .keyboard => .{ .keyboard = @alignCast(@ptrCast(device.data)) },
        .pointer => .{ .pointer = device.toPointer(), },
        else => |t| blk: {
            std.log.err("unsupported input method: {}", .{ t });
            break :blk null;
        },
    };
}
