//! Maintains state related to cursor position, rendering, and
//! events such as button presses and dragging

pub const Cursor = @This();

const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const xkb = @import("xkbcommon");

const View = @import("View.zig");
const Seat = @import("Seat.zig");
const Utils = @import("Utils.zig");
const Mousemap = @import("lua/Input.zig").MousemapData;
const c = @import("C.zig").c;

const server = &@import("main.zig").server;

wlr_cursor: *wlr.Cursor,
x_cursor_manager: *wlr.XcursorManager,
cursor_shape_manager: *wlr.CursorShapeManagerV1,
seat: *Seat,

motion: wl.Listener(*wlr.Pointer.event.Motion) = .init(handleMotion),
motion_absolute: wl.Listener(*wlr.Pointer.event.MotionAbsolute) = .init(handleMotionAbsolute),
button: wl.Listener(*wlr.Pointer.event.Button) = .init(handleButton),
axis: wl.Listener(*wlr.Pointer.event.Axis) = .init(handleAxis),
frame: wl.Listener(*wlr.Cursor) = .init(handleFrame),
hold_begin: wl.Listener(*wlr.Pointer.event.HoldBegin) = .init(handleHoldBegin),
hold_end: wl.Listener(*wlr.Pointer.event.HoldEnd) = .init(handleHoldEnd),

request_set_cursor_shape: wl.Listener(*wlr.CursorShapeManagerV1.event.RequestSetShape) = .init(handleCursorShape),

mode: enum { normal, drag } = .normal,

// Drag information
drag: ?struct {
    event_code: u32,
    start: struct { x: c_int, y: c_int },
    view: ?struct {
        view: *View,
        dims: struct { width: c_int, height: c_int },
        offset: struct { x: c_int, y: c_int },
    },
},

pub fn init(self: *Cursor, seat: *Seat) void {
    errdefer Utils.oomPanic();

    self.* = .{
        .wlr_cursor = try wlr.Cursor.create(),
        .x_cursor_manager = try wlr.XcursorManager.create(null, 24),
        .cursor_shape_manager = try wlr.CursorShapeManagerV1.create(server.wl_server, 1),
        .drag = null,
        .seat = seat,
    };

    try self.x_cursor_manager.load(1);

    self.wlr_cursor.attachOutputLayout(server.root.output_layout);

    self.wlr_cursor.events.motion.add(&self.motion);
    self.wlr_cursor.events.motion_absolute.add(&self.motion_absolute);
    self.wlr_cursor.events.button.add(&self.button);
    self.wlr_cursor.events.axis.add(&self.axis);
    self.wlr_cursor.events.frame.add(&self.frame);
    self.wlr_cursor.events.hold_begin.add(&self.hold_begin);
    self.wlr_cursor.events.hold_end.add(&self.hold_end);

    self.cursor_shape_manager.events.request_set_shape.add(&self.request_set_cursor_shape);
}

pub fn deinit(self: *Cursor) void {
    self.motion.link.remove();
    self.motion_absolute.link.remove();
    self.button.link.remove();
    self.axis.link.remove();
    self.frame.link.remove();
    self.hold_begin.link.remove();
    self.hold_end.link.remove();

    self.wlr_cursor.destroy();
    self.x_cursor_manager.destroy();
}

pub fn processCursorMotion(
    self: *Cursor,
    time_msec: u32,
    device: *wlr.InputDevice,
    delta_x: f64,
    delta_y: f64,
    unaccel_dx: f64,
    unaccel_dy: f64,
) void {
    var dx = delta_x;
    var dy = delta_y;

    // tell the idle notifier that we've recieved activity now that it's been
    // fully processed
    server.idle_notifier.notifyActivity(self.seat.wlr_seat);

    // try and activate a cursor constraint
    var iter = self.seat.constraints.iterator(.forward);
    while (iter.next()) |constraint| constraint.activate();

    if (self.seat.active_constraint) |active_constraint| {
        // get the view from the constrained surface
        const view = View.fromSurface(active_constraint.constraint.surface);
        if (view) |v| if (self.seat.focused_surface) |fs| if (fs == .view and v == fs.view) {
            const sx = self.wlr_cursor.x - @as(f64, @floatFromInt(v.geometry.x)) - @as(f64, @floatFromInt(v.border_width));
            const sy = self.wlr_cursor.y - @as(f64, @floatFromInt(v.geometry.y)) - @as(f64, @floatFromInt(v.border_width));
            var x_out: f64 = 0;
            var y_out: f64 = 0;

            if (wlr.region.confine(
                &active_constraint.constraint.region,
                sx,
                sy,
                sx + delta_x,
                sy + delta_y,
                &x_out,
                &y_out
            )) {
                dx = x_out - sx;
                dy = y_out - sy;
            }
        };
    }


    // send relative motion
    server.relative_pointer_manager.sendRelativeMotion(
        self.seat.wlr_seat,
        @as(u64, time_msec) * std.time.us_per_ms,
        dx,
        dy,
        unaccel_dx,
        unaccel_dy
    );

    if (self.seat.active_constraint != null) return;

    // process the cursor motion
    self.wlr_cursor.move(device, dx, dy);

    const view: ?*View = blk: {
        if (self.seat.focused_surface) |fs| {
            if (fs == .view) {
                break :blk fs.view;
            }
        }
        break :blk null;
    };

    var passthrough = true;
    if (self.mode == .drag) {
        const modifiers = self.seat.keyboard_group.wlr_group.keyboard.getModifiers();

        // Proceed if mousemap for current mouse and modifier state's exist
        if (self.seat.mousemaps.get(Mousemap.hash(modifiers, @bitCast(self.drag.?.event_code)))) |map| {
            if (map.options.lua_drag_ref_idx > 0) {
                passthrough = map.callback(.drag, .{
                    if (view != null) view.?.id else null, // view_id
                    .{ // pos
                        .x = @as(c_int, @intFromFloat(self.wlr_cursor.x)),
                        .y = @as(c_int, @intFromFloat(self.wlr_cursor.y)),
                    },
                    self.drag.?.start, // start
                    // TODO: Do we really need an offset , is it necessary
                    if (self.drag.?.view != null) self.drag.?.view.?.offset else null, // offset
                });
                if (!passthrough) return;
            }
        }
    }

    if(!passthrough) return;

    const output = self.seat.focused_output;
    // Exit the switch if no focused output exists
    std.debug.assert(output != null);

    const surfaceAtResult = output.?.surfaceAt(self.wlr_cursor.x, self.wlr_cursor.y);
    if (surfaceAtResult) |surface| {
        if (surface.scene_node_data.* == .view) {
            server.events.exec("ViewPointerMotion", .{
                surface.scene_node_data.view.id,
                @as(c_int, @intFromFloat(self.wlr_cursor.x)),
                @as(c_int, @intFromFloat(self.wlr_cursor.y)),
            });
        }

        self.seat.wlr_seat.pointerNotifyEnter(surface.surface, surface.sx, surface.sy);
        self.seat.wlr_seat.pointerNotifyMotion(time_msec, surface.sx, surface.sy);
    } else {
        self.seat.wlr_seat.pointerClearFocus();
        self.wlr_cursor.setXcursor(self.x_cursor_manager, "default");
    }
}

// --------- WLR Cursor event handlers ---------
fn handleMotion(
    listener: *wl.Listener(*wlr.Pointer.event.Motion),
    event: *wlr.Pointer.event.Motion,
) void {
    const self: *Cursor = @fieldParentPtr("motion", listener);
    self.processCursorMotion(
        event.time_msec,
        event.device,
        event.delta_x,
        event.delta_y,
        event.unaccel_dx,
        event.unaccel_dy,
    );
}

fn handleMotionAbsolute(
    listener: *wl.Listener(*wlr.Pointer.event.MotionAbsolute),
    event: *wlr.Pointer.event.MotionAbsolute,
) void {
    const self: *Cursor = @fieldParentPtr("motion_absolute", listener);
    // comment from dwl:
    // This event is forwarded by the cursor when a pointer emits an _absolute_
    // motion event, from 0..1 on each axis. This happens, for example, when
    // wlroots is running under a Wayland window rather than KMS+DRM, and you
    // move the mouse over the window. You could enter the window from any edge,
    // so we have to warp the mouse there. Also, some hardware emits these events.

    // move the cursor when it doesn't order its events
    if (event.time_msec == 0) {
        self.wlr_cursor.warpAbsolute(event.device, event.x, event.y);
    }

    var layout_x: f64 = 0;
    var layout_y: f64 = 0;
    self.wlr_cursor.absoluteToLayoutCoords(event.device, event.x, event.y, &layout_x, &layout_y);

    const delta_x = layout_x - self.wlr_cursor.x;
    const delta_y = layout_y - self.wlr_cursor.y;
    self.processCursorMotion(
        event.time_msec,
        event.device,
        delta_x,
        delta_y,
        delta_x, // absolute motions decelerate immediately
        delta_y,
    );
}

fn handleButton(listener: *wl.Listener(*wlr.Pointer.event.Button), event: *wlr.Pointer.event.Button) void {
    const self: *Cursor = @fieldParentPtr("button", listener);

    const view: ?*View = blk: {
        if (self.seat.focused_surface) |fs| {
            if (fs == .view) {
                break :blk fs.view;
            }
        }
        break :blk null;
    };

    // Set drag information based on button type
    switch (event.state) {
        .pressed => {
            self.mode = .drag;

            self.drag = .{
                .event_code = event.button,
                .start = .{
                    .x = @as(c_int, @intFromFloat(self.wlr_cursor.x)),
                    .y = @as(c_int, @intFromFloat(self.wlr_cursor.y))
                },
                .view = null
            };

            // Keep track of where the drag started
            if(view) |v| {
                self.drag.?.view = .{
                    .view = v,
                    .dims = .{ .width = v.xdg_toplevel.base.geometry.width, .height = v.xdg_toplevel.base.geometry.height },
                    .offset = .{ .x = self.drag.?.start.x - v.scene_tree.node.x, .y = self.drag.?.start.y - v.scene_tree.node.y },
                };
            }
        },
        .released => {
            self.mode = .normal;

            self.drag.?.view = null;
        },
        else => {
            std.log.err("Invalid/Unimplemented pointer button event type", .{});
        },
    }

    // run this as late as possible that way we can use the current drag info
    // in the release callback
    defer if (event.state == .released) {
        self.mode = .normal;
        self.drag.?.view = null; // the drag is over, don't keep any information
    };

    // by default we pass the mouse clicks through to the client
    var passthrough = true;

    // Proceed if mousemap for current mouse and modifier state's exist
    const modifiers = self.seat.keyboard_group.wlr_group.keyboard.getModifiers();
    if (self.seat.mousemaps.get(Mousemap.hash(modifiers, @bitCast(event.button)))) |map| {
        const args = .{
            if (view != null) view.?.id else null, // view_id
            .{ // pos
                .x = @as(c_int, @intFromFloat(self.wlr_cursor.x)),
                .y = @as(c_int, @intFromFloat(self.wlr_cursor.y)),
            },
            self.drag.?.start, // start
            if (self.drag.?.view != null) self.drag.?.view.?.offset else null
        };

        switch (event.state) {
            .pressed => {
                // Only call callback if a callback function exists
                if (map.options.lua_press_ref_idx > 0) {
                    passthrough = map.callback(.press, args);
                }
            },
            .released => {
                // Only call callback if a callback function exists
                if (map.options.lua_release_ref_idx > 0) {
                    passthrough = map.callback(.release, args);
                }
            },
            else => undefined
        }
    }

    // If no keymap exists for button event, forward it to a surface
    if (passthrough) {
        _ = self.seat.wlr_seat.pointerNotifyButton(event.time_msec, event.button, event.state);
    }

    // tell the idle notifier that we've recieved activity now that it's been
    // fully processed
    server.idle_notifier.notifyActivity(self.seat.wlr_seat);
}

fn handleHoldBegin(listener: *wl.Listener(*wlr.Pointer.event.HoldBegin), event: *wlr.Pointer.event.HoldBegin) void {
    _ = listener;
    _ = event;
}

fn handleHoldEnd(listener: *wl.Listener(*wlr.Pointer.event.HoldEnd), event: *wlr.Pointer.event.HoldEnd) void {
    _ = listener;
    _ = event;
}

fn handleAxis(
    listener: *wl.Listener(*wlr.Pointer.event.Axis),
    event: *wlr.Pointer.event.Axis,
) void {
    const self: *Cursor = @fieldParentPtr("axis", listener);

    const event_name = if(event.orientation == .vertical_scroll) "REL_WHEEL" else "REL_HWHEEL";
    const event_code = c.libevdev_event_code_from_name(c.EV_REL, event_name);

    var passthrough = true;

    const modifiers = self.seat.keyboard_group.wlr_group.keyboard.getModifiers();
    if (self.seat.mousemaps.get(Mousemap.hash(modifiers, event_code))) |map| {
        const view: ?*View = blk: {
            if (self.seat.focused_surface) |fs| {
                if (fs == .view) {
                    break :blk fs.view;
                }
            }
            break :blk null;
        };

        const args = .{
            if (view != null) view.?.id else null, // view_id
            .{ // pos
                .x = @as(c_int, @intFromFloat(self.wlr_cursor.x)),
                .y = @as(c_int, @intFromFloat(self.wlr_cursor.y)),
            },
            event.delta,
            event.delta_discrete
        };

        if(map.options.lua_scroll_ref_idx > 0) {
            passthrough = map.callback(.scroll, args);
        }
    }

    // tell the idle notifier that we've recieved activity now that it's been
    // fully processed
    server.idle_notifier.notifyActivity(self.seat.wlr_seat);

    if(!passthrough) return;

    self.seat.wlr_seat.pointerNotifyAxis(
        event.time_msec,
        event.orientation,
        event.delta,
        event.delta_discrete,
        event.source,
        event.relative_direction,
    );
}

fn handleFrame(listener: *wl.Listener(*wlr.Cursor), _: *wlr.Cursor) void {
    const self: *Cursor = @fieldParentPtr("frame", listener);
    self.seat.wlr_seat.pointerNotifyFrame();
}

fn handleCursorShape(
    listener: *wl.Listener(*wlr.CursorShapeManagerV1.event.RequestSetShape),
    event: *wlr.CursorShapeManagerV1.event.RequestSetShape,
) void {
    const self: *Cursor = @fieldParentPtr("request_set_cursor_shape", listener);
    if (event.seat_client == self.seat.wlr_seat.pointer_state.focused_client) {
        self.wlr_cursor.setXcursor(self.x_cursor_manager, wlr.CursorShapeManagerV1.shapeName(event.shape));
    }
}
