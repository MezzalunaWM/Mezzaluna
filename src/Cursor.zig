//! Maintains state related to cursor position, rendering, and
//! events such as button presses and dragging

pub const Cursor = @This();

const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const xkb = @import("xkbcommon");

const View = @import("View.zig");
const Utils = @import("Utils.zig");
const Mousemap = @import("types/Mousemap.zig");
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
drag: ?struct {
  event_code: u32,
  start: struct {
    x: c_int,
    y: c_int
  },
  view: ?struct {
    view: *View,
    dims: struct { width: c_int, height: c_int },
    offset: struct { x: c_int, y: c_int, }
  },
},

pub fn init(self: *Cursor) void {
  errdefer Utils.oomPanic();

  self.* = .{
    .wlr_cursor = try wlr.Cursor.create(),
    .x_cursor_manager = try wlr.XcursorManager.create(null, 24),
    .drag = null
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
  // TODO: allow acces via lua

  var handled = false;

  if (self.mode == .drag) {
    const modifiers = server.seat.keyboard_group.keyboard.getModifiers();

    std.debug.assert(self.drag != null);

    // Proceed if mousemap for current mouse and modifier state's exist
    if (server.mousemaps.get(Mousemap.hash(modifiers, @bitCast(self.drag.?.event_code)))) |map| {
      if(map.options.lua_drag_ref_idx > 0) {
        handled = map.callback(.drag, .{
          .{
            .x = @as(c_int, @intFromFloat(self.wlr_cursor.x)),
            .y = @as(c_int, @intFromFloat(self.wlr_cursor.y))
          },
          .{
            .start = self.drag.?.start,
            .view = if (self.drag.?.view != null) .{
              .id = self.drag.?.view.?.view.id,
              .dims = self.drag.?.view.?.dims,
              .offset = self.drag.?.view.?.offset
            } else null
          }
        });
      }
    }
  }

  if(!handled) {
    const output = server.seat.focused_output;
    // Exit the switch if no focused output exists
    std.debug.assert(output != null);

    const surfaceAtResult = output.?.surfaceAt(self.wlr_cursor.x, self.wlr_cursor.y);
    if (surfaceAtResult) |surface| {
      if(surface.scene_node_data.* == .view) {
        server.events.exec("ViewPointerMotion", .{
          surface.scene_node_data.view.id,
          @as(c_int, @intFromFloat(self.wlr_cursor.x)),
          @as(c_int, @intFromFloat(self.wlr_cursor.y))
        });
      }

      server.seat.wlr_seat.pointerNotifyEnter(surfaceAtResult.?.surface, surfaceAtResult.?.sx, surfaceAtResult.?.sy);
      server.seat.wlr_seat.pointerNotifyMotion(time_msec, surfaceAtResult.?.sx, surfaceAtResult.?.sy);
    } else {
      // This may not be necessary, remove if no bugs
      server.seat.wlr_seat.pointerClearFocus();
      self.wlr_cursor.setXcursor(self.x_cursor_manager, "default");
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

  switch (event.state) {
    .pressed => {
      cursor.mode = .drag;

      cursor.drag = .{
        .event_code = event.button,
        .start = .{
          .x = @as(c_int, @intFromFloat(cursor.wlr_cursor.x)),
          .y = @as(c_int, @intFromFloat(cursor.wlr_cursor.y))
        },
        .view = null
      };

      // Keep track of where the drag started
      if(server.seat.focused_surface) |fs| {
        if(fs == .view) {
          cursor.drag.?.view = .{
            .view = fs.view,
            .dims = .{
              .width = fs.view.xdg_toplevel.base.geometry.width,
              .height = fs.view.xdg_toplevel.base.geometry.height
            },
            .offset = .{
              .x = cursor.drag.?.start.x - fs.view.scene_tree.node.x,
              .y = cursor.drag.?.start.y - fs.view.scene_tree.node.y
            },
          };
        }
      }
    },
    .released => {
      cursor.mode = .normal;

      // How do we do this on the lua side
      // if(cursor.drag.view) |view| {
      //   _ = view.xdg_toplevel.setResizing(false);
      // }

      cursor.drag.?.view = null;
    },
    else => {
      std.log.err("Invalid/Unimplemented pointer button event type", .{});
    }
  }

  var handled = false;
  const modifiers = server.seat.keyboard_group.keyboard.getModifiers();

  // Proceed if mousemap for current mouse and modifier state's exist
  if (server.mousemaps.get(Mousemap.hash(modifiers, @bitCast(event.button)))) |map| {
    switch (event.state) {
      .pressed => {
        // Only make callback if a callback function exists
        if(map.options.lua_press_ref_idx > 0) {
          handled = map.callback(.press, .{
            .{
              .x = @as(c_int, @intFromFloat(cursor.wlr_cursor.x)),
              .y = @as(c_int, @intFromFloat(cursor.wlr_cursor.y))
            },
          });
        }
      },
      .released => {
        if(map.options.lua_press_ref_idx > 0) {
          handled = map.callback(.release, .{
            .{
              .x = @as(c_int, @intFromFloat(cursor.wlr_cursor.x)),
              .y = @as(c_int, @intFromFloat(cursor.wlr_cursor.y))
            },
          });
        }
      },
      else => { unreachable; }
    }
  }

  // If no keymap exists for button event, forward it to a surface
  // TODO: Allow for transparent mousemaps that pass mouse button events anyways
  if(!handled) {
    _ = server.seat.wlr_seat.pointerNotifyButton(event.time_msec, event.button, event.state);
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
