const PointerConstraint = @This();

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const std = @import("std");

const Seat = @import("Seat.zig");
const Utils = @import("Utils.zig");

const gpa = &@import("main.zig").gpa;
const server = &@import("main.zig").server;

constraint: *wlr.PointerConstraintV1,
seat: *Seat,
link: wl.list.Link,

destroy: wl.Listener(*wlr.PointerConstraintV1) = .init(handleDestroy),

pub fn init(constraint: *wlr.PointerConstraintV1) *PointerConstraint {
    const self = gpa.create(PointerConstraint) catch Utils.oomPanic();

    self.* = .{
        .constraint = constraint,
        .seat = blk: {
            var iter = server.seats.iterator(.forward);
            while (iter.next()) |seat| {
                if (seat.wlr_seat == constraint.seat) break :blk seat;
            }
            @panic("Invalid seat provided to cursor constraint.");
        },
        .link = undefined,
    };

    constraint.events.destroy.add(&self.destroy);

    self.seat.constraints.append(self);
    return self;
}

pub fn deinit(self: *PointerConstraint) void {
    self.destroy.link.remove();
    self.link.remove();
    gpa.destroy(self);
}

pub fn warpToHint(self: *PointerConstraint) void {
    const sx = self.constraint.current.cursor_hint.x;
    const sy = self.constraint.current.cursor_hint.y;

    if (self.constraint.current.cursor_hint.enabled) {
        _ = self.seat.cursor.wlr_cursor.warp(null, sx, sy);
        self.seat.wlr_seat.pointerWarp(sx, sy);
    }
}

pub fn activate(self: *PointerConstraint) void {
    if (self.seat.active_constraint == self) return;
    if (self.seat.active_constraint) |constraint| {
        constraint.constraint.sendDeactivated();
    }

    self.seat.active_constraint = self;
    self.constraint.sendActivated();
}

fn handleDestroy(
    listener: *wl.Listener(*wlr.PointerConstraintV1),
    _: *wlr.PointerConstraintV1,
) void {
    const self: *PointerConstraint = @fieldParentPtr("destroy", listener);

    if (self.seat.active_constraint != null and self.seat.active_constraint.? == self) {
        self.warpToHint();
        self.seat.active_constraint = null;
    }
    self.constraint.sendDeactivated();
    self.deinit();
}
