const KeyboardGroup = @This();

const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const xkb = @import("xkbcommon");

const Keyboard = @import("Keyboard.zig");
const Utils = @import("Utils.zig");
const Seat = @import("Seat.zig");

const server = &@import("main.zig").server;
const gpa = std.heap.c_allocator;

wlr_group: *wlr.KeyboardGroup,
repeat_source: ?*wl.EventSource,
modifiers: ?wlr.Keyboard.ModifierMask,
keysyms: ?[]const xkb.Keysym,
seat: *Seat,

pub fn init(seat: *Seat) *KeyboardGroup {
    errdefer Utils.oomPanic();

    const self = try gpa.create(KeyboardGroup);
    self.* = .{
        .wlr_group = wlr.KeyboardGroup.create() catch Utils.oomPanic(),
        .repeat_source = blk: {
            break :blk server.event_loop.addTimer(?*KeyboardGroup, handleRepeat, self) catch {
                std.log.err("Failed to create event loop timer, keyboard repeating will not work!", .{});
                break :blk null;
            };
        },
        .modifiers = null,
        .keysyms = null,
        .seat = seat,
    };

    return self;
}

pub fn addKeyboard(self: *KeyboardGroup, keyboard: *Keyboard) void {
    if (!self.wlr_group.addKeyboard(keyboard.wlr_keyboard)) {
        std.log.err("Adding new keyboard {s} failed", .{ keyboard.device.name orelse "(unnamed)" });
    }
    keyboard.group = self;
}

pub fn deinit(self: *KeyboardGroup) void {
    self.wlr_group.destroy();
    gpa.destroy(self);
}

fn handleRepeat(data: ?*KeyboardGroup) c_int {
    // we failed to create the event loop timer, which means we can't repeat keys
    if (data.?.repeat_source == null) return 0;

    if (data == null or data.?.keysyms == null or data.?.modifiers == null or
        data.?.wlr_group.keyboard.repeat_info.rate <= 0)
    {
        return 0;
    }

    data.?.repeat_source.?.timerUpdate(
        @divTrunc(1000, data.?.wlr_group.keyboard.repeat_info.rate),
    ) catch {
        // not sure how big of a deal it is if we miss a timer update
        std.log.warn("failed to update keyboard repeat timer", .{});
    };
    for (data.?.keysyms.?) |sym| {
        _ = Keyboard.keypress(data.?.modifiers.?, sym, .pressed);
    }

    return 0;
}
