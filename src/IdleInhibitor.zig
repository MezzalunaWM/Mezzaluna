const IdleInhibitor = @This();

const std = @import("std");
const wlr = @import("wlroots");
const wl = @import("wayland").server.wl;

const utils = @import("utils.zig");

const gpa = &@import("main.zig").gpa;
const server = &@import("main.zig").server;
const log = std.log.scoped(.IdleInhibitor);

inhibitor: *wlr.IdleInhibitorV1,

destroy: wl.Listener(*wlr.Surface) = .init(handleDestroy),

pub fn init(inhibitor: *wlr.IdleInhibitorV1) *IdleInhibitor {
    const self = gpa.create(IdleInhibitor) catch utils.oomPanic();

    self.* = .{ .inhibitor = inhibitor };
    self.inhibitor.events.destroy.add(&self.destroy);
    server.idle_notifier.setInhibited(true);

    return self;
}

fn handleDestroy(
    listener: *wl.Listener(*wlr.Surface),
    _: *wlr.Surface,
) void {
    const self: *IdleInhibitor = @fieldParentPtr("destroy", listener);
    listener.link.remove();
    gpa.destroy(self);
    server.idle_notifier.setInhibited(false);
}
