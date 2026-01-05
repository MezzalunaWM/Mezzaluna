//! Maintains state related to cursor position, rendering, and
//! events such as button presses and dragging

pub const Cursor = @This();

const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const xkb = @import("xkbcommon");

const View = @import("View.zig");
const Utils = @import("Utils.zig");
const c = @import("C.zig").c;

const server = &@import("main.zig").server;

wlr_cursor: *wlr.Cursor,
x_cursor_manager: *wlr.XcursorManager,

motion: wl.Listener(*wlr.Pointer.event.Motion) = .init(handleMotion),
motion_absolute: wl.Listener(*wlr.Pointer.event.MotionAbsolute) = .init(handleMotionAbsolute),
button: wl.Listener(*wlr.Pointer.event.Button) = .init(handleButton),
axis: wl.Listener(*wlr.Pointer.event.Axis) = .init(handleAxis),
frame: wl.Listener(*wlr.Cursor) = .init(handleFrame),
hold_begin: wl.Listener(*wlr.Pointer.event.HoldBegin) = .init(handleHoldBegin),
hold_end: wl.Listener(*wlr.Pointer.event.HoldEnd) = .init(handleHoldEnd),

mode: enum { normal, drag } = .normal,

// Drag information
drag: struct {
  start_x:       c_int,
  start_y:       c_int,
  view:          ?*View,
  view_offset_x: ?c_int,
  view_offset_y: ?c_int,
},

pub fn init(self: *Cursor) void {
  errdefer Utils.oomPanic();

  self.* = .{
    .wlr_cursor = try wlr.Cursor.create(),
    .x_cursor_manager = try wlr.XcursorManager.create(null, 24),
    .drag = .{
      .start_x = 0,
      .start_y = 0,
      .view = null,
      .view_offset_x = null,
      .view_offset_y = null,
    }
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

pub fn processCursorMotion(self: *Cursor, time_msec: u32) void {
  server.events.exec("PointerMotion", .{self.wlr_cursor.x, self.wlr_cursor.y});

  switch (self.mode) {
    .normal => {
      const output = server.seat.focused_output;
      // Exit the switch if no focused output exists
      if (output == null) return;

      const surfaceAtResult = output.?.surfaceAt(self.wlr_cursor.x, self.wlr_cursor.y);
      if (surfaceAtResult == null) {
        self.wlr_cursor.setXcursor(self.x_cursor_manager, "default");
        server.seat.wlr_seat.pointerClearFocus();

        // This is gonna be fun
        // server.seat.wlr_seat.keyboardSendKey(time_msec: u32, key: u32, state: u32);
        // server.seat.wlr_seat.pointerSendMotion(time_msec: u32, sx: f64, sy: f64)
        // server.seat.wlr_seat.pointerSendButton(time_msec: u32, button: u32, state: ButtonState)
        return;
      }

      switch (surfaceAtResult.?.scene_node_data.*) {
        .view => {
          // TODO: If serious performance issues arise from this, we need to be able to disable unused hooks
          // Perhaps after the config is executed, if no callbacks are present on this hook, we disable it entirely
          server.events.exec("ViewPointerMotion", .{surfaceAtResult.?.scene_node_data.view.id, self.wlr_cursor.x, self.wlr_cursor.y});
        },
        .layer_surface => { },
        else => unreachable
      }

      server.seat.wlr_seat.pointerNotifyEnter(surfaceAtResult.?.surface, surfaceAtResult.?.sx, surfaceAtResult.?.sy);
      server.seat.wlr_seat.pointerNotifyMotion(time_msec, surfaceAtResult.?.sx, surfaceAtResult.?.sy);
    },
    .drag => {

      // @hook PointerDragMotion
      // @param button string // TODO Translate a button to a string or smth
      // @param state string - "pressed" or "released"
      // @param time_msecs number // TODO idk what the hell msecs is
      server.events.exec("PointerDragMotion", .{
        self.wlr_cursor.x,
        self.wlr_cursor.y,

        self.drag.start_x,
        self.drag.start_y,
        self.drag.view.?.id,
        self.drag.view_offset_x,
        self.drag.view_offset_y
      });
    }
  }
}

// --------- WLR Cursor event handlers ---------
fn handleMotion(
_: *wl.Listener(*wlr.Pointer.event.Motion),
event: *wlr.Pointer.event.Motion,
) void {
  server.cursor.wlr_cursor.move(event.device, event.delta_x, event.delta_y);
  server.cursor.processCursorMotion(event.time_msec);
}

fn handleMotionAbsolute(
_: *wl.Listener(*wlr.Pointer.event.MotionAbsolute),
event: *wlr.Pointer.event.MotionAbsolute,
) void {
  server.cursor.wlr_cursor.warpAbsolute(event.device, event.x, event.y);
  server.cursor.processCursorMotion(event.time_msec);
}

fn handleButton(
listener: *wl.Listener(*wlr.Pointer.event.Button),
event: *wlr.Pointer.event.Button
) void {
  const cursor: *Cursor = @fieldParentPtr("button", listener);

  _ = server.seat.wlr_seat.pointerNotifyButton(event.time_msec, event.button, event.state);

  // @hook PointerButtonPress // TODO Probably change this name
  // @param button string // TODO Translate a button to a string or smth
  // @param state string - "pressed" or "released"
  // @param time_msecs number
  const state = if (event.state == .pressed) "pressed" else "released";
  server.events.exec("PointerButtonPress", .{event.button, state, event.time_msec});

  switch (event.state) {
    .pressed => {
      if(server.seat.keyboard_group.keyboard.getModifiers().alt) {
        // Can be BTN_RIGHT, BTN_LEFT, or BTN_MIDDLE
        cursor.drag.start_x = @as(c_int, @intFromFloat(cursor.wlr_cursor.x));
        cursor.drag.start_y = @as(c_int, @intFromFloat(cursor.wlr_cursor.y));
        if(server.seat.focused_surface) |fs| {
          // Keep track of where the drag started

          if(fs == .view) {
            cursor.drag.view = fs.view;
            cursor.drag.view_offset_x = cursor.drag.start_x - fs.view.scene_tree.node.x;
            cursor.drag.view_offset_y = cursor.drag.start_y - fs.view.scene_tree.node.y;
          }

          // Maybe comptime this for later reference
          if(event.button == c.libevdev_event_code_from_name(c.EV_KEY, "BTN_LEFT")) {
            cursor.mode = .move;
          } else if(event.button == c.libevdev_event_code_from_name(c.EV_KEY, "BTN_RIGHT")) {
            if(fs == .view) {
              cursor.mode = .resize;
              _ = fs.view.xdg_toplevel.setResizing(true);
            }
          }
        }
      }
    },
    .released => {
      cursor.mode = .normal;

      if(cursor.drag.view) |view| {
        _ = view.xdg_toplevel.setResizing(false);
      }

      cursor.drag.view = null;
      cursor.drag.view_offset_x = null;
      cursor.drag.view_offset_y = null;
    },
    else => {
      std.log.err("Invalid/Unimplemented pointer button event type", .{});
    }
  }
}

fn handleHoldBegin(
listener: *wl.Listener(*wlr.Pointer.event.HoldBegin),
event: *wlr.Pointer.event.HoldBegin
) void {
  _ = listener;
  _ = event;
  std.log.err("Unimplemented cursor start hold", .{});
}

fn handleHoldEnd(
listener: *wl.Listener(*wlr.Pointer.event.HoldEnd),
event: *wlr.Pointer.event.HoldEnd
) void {
  _ = listener;
  _ = event;
  std.log.err("Unimplemented cursor end hold", .{});
}

fn handleAxis(
_: *wl.Listener(*wlr.Pointer.event.Axis),
event: *wlr.Pointer.event.Axis,
) void {
  server.seat.wlr_seat.pointerNotifyAxis(
  event.time_msec,
  event.orientation,
  event.delta,
  event.delta_discrete,
  event.source,
  event.relative_direction,
);
}

fn handleFrame(_: *wl.Listener(*wlr.Cursor), _: *wlr.Cursor) void {
  server.seat.wlr_seat.pointerNotifyFrame();
}
