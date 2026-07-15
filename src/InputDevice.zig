const std = @import("std");
const wlr = @import("wlroots");

const Keyboard = @import("Keyboard.zig");

const log = std.log.scoped(.InputDevice);

pub const InputDevice = union(wlr.InputDevice.Type) {
    keyboard: *Keyboard,
    pointer: *wlr.Pointer,
    touch: void,
    tablet: void,
    tablet_pad: void,
    @"switch": void,
    
    pub fn init(self: *wlr.InputDevice) void {
        switch (self.type) {
            .keyboard => {
                const keyboard = Keyboard.init(self);
                self.data = keyboard;
            },
            .pointer => {
                // the data attached here is used to figure out which seat owns
                // the pointer
                self.data = null;
            },
            else => |t| log.err("unsupported input method: {}", .{ t }),
        }
    }

    pub fn remove(self: *wlr.InputDevice) void {
        switch (self.type) {
            .keyboard => {
                const keyboard = (get(self) orelse return).keyboard;
                std.debug.assert(keyboard.group == null);
                keyboard.deinit();
            },
            .pointer => {
                std.debug.assert(self.data == null);
            },
            else => |t| log.err("unsupported input method: {}", .{ t }),
        }
    }

    pub fn get(self: *wlr.InputDevice) ?InputDevice {
        return switch (self.type) {
            .keyboard => .{ .keyboard = @alignCast(@ptrCast(self.data)) },
            .pointer => .{ .pointer = self.toPointer(), },
            else => |t| blk: {
                log.err("unsupported input method: {}", .{ t });
                break :blk null;
            },
        };
    }
};
