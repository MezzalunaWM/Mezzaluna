const IdleNotifer = @This();

const std = @import("std");
const wlr = @import("wlroots");

const Utils = @import("Utils.zig");

const gpa = std.heap.c_allocator;
const server = &@import("main.zig").server;

idle_notifier: *wlr.IdleNotifierV1,

pub fn init() *IdleNotifer {
    const self = gpa.create(IdleNotifer) catch Utils.oomPanic();

    self.* = .{
        .idle_notifier = wlr.IdleNotifierV1.create(server.wl_server) catch Utils.oomPanic(),
    };

    return self;
}

pub fn deinit(self: *IdleNotifer) void {
    self.idle_notifier.global.remove();
    gpa.destroy(self);
}

pub fn notifyActivity(self: *IdleNotifer, seat: *wlr.Seat) void {
    self.idle_notifier.notifyActivity(seat);
    server.events.exec("NotifyActivity", .{}, "After the server is notified of activity on a seat.");
}

pub fn setInhibited(self: *IdleNotifer, inhibited: bool) void {
    self.idle_notifier.setInhibited(inhibited);
    server.events.exec("SetIdleInhibit", .{ inhibited }, "After the server has been asked to change idle inhibiting from a client.");
}
