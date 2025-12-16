const Seat = @This();

const std = @import("std");
const wlr = @import("wlroots");
const wl = @import("wayland").server.wl;
const xkb = @import("xkbcommon");

const Utils =  @import("Utils.zig");
const Popup = @import("Popup.zig");
const View =   @import("View.zig");
const LayerSurface = @import("LayerSurface.zig");
const Output = @import("Output.zig");

const server = &@import("main.zig").server;

const FocusDataType = enum { view, popup, layer_surface };
pub const FocusData = union(FocusDataType) {
  view: *View,
  popup: *Popup,
  layer_surface: *LayerSurface
};

wlr_seat: *wlr.Seat,

focused_surface: ?FocusData,
focused_output: ?*Output,

keyboard_group: *wlr.KeyboardGroup,
keymap: *xkb.Keymap,

request_set_cursor: wl.Listener(*wlr.Seat.event.RequestSetCursor) = .init(handleRequestSetCursor),
request_set_selection: wl.Listener(*wlr.Seat.event.RequestSetSelection) = .init(handleRequestSetSelection),
// request_set_primary_selection
// request_start_drage

pub fn init(self: *Seat) void {
  errdefer Utils.oomPanic();

  const xkb_context = xkb.Context.new(.no_flags) orelse {
    std.log.err("Unable to create a xkb context, exiting", .{});
    std.process.exit(7);
  };
  defer xkb_context.unref();

  const keymap = xkb.Keymap.newFromNames(xkb_context, null, .no_flags) orelse {
    std.log.err("Unable to create a xkb keymap, exiting", .{});
    std.process.exit(8);
  };
  defer keymap.unref();

  self.* = .{
    .wlr_seat = try wlr.Seat.create(server.wl_server, "default"),
    .focused_surface = null,
    .focused_output = null,
    .keyboard_group = try wlr.KeyboardGroup.create(),
    .keymap = keymap.ref(),
  };
  errdefer {
    self.keyboard_group.destroy();
    self.wlr_seat.destroy();
  }

  _ = self.keyboard_group.keyboard.setKeymap(self.keymap);
  self.wlr_seat.setKeyboard(&self.keyboard_group.keyboard);

  self.wlr_seat.events.request_set_cursor.add(&self.request_set_cursor);
  self.wlr_seat.events.request_set_selection.add(&self.request_set_selection);
}

pub fn deinit(self: *Seat) void {
  self.request_set_cursor.link.remove();
  self.request_set_selection.link.remove();

  self.keyboard_group.destroy();
  self.wlr_seat.destroy();
}

pub fn focusSurface(self: *Seat, to_focus: ?FocusData) void {
  const surface: ?*wlr.Surface = blk: {
    if (to_focus != null) {
      break :blk switch (to_focus.?) {
        .view => to_focus.?.view.xdg_toplevel.base.surface,
        .layer_surface => to_focus.?.layer_surface.wlr_layer_surface.surface,
        .popup => to_focus.?.popup.xdg_popup.base.surface
      };
    } else {
      break :blk null;
    }
  };

  // Remove focus from the current surface unless
  //  - current has exclusive keyboard interactivity
  //  - the current view is fullscreen and
  //      - to focus is a content level view
  //      - to focus is a bottom or background level layer
  if (self.focused_surface) |current_focus| {
    const current_surface = switch(current_focus) {
      .view => current_focus.view.xdg_toplevel.base.surface,
      .layer_surface => current_focus.layer_surface.wlr_layer_surface.surface,
      .popup => current_focus.popup.xdg_popup.base.surface
    };
    if (current_surface == surface) return; // Same surface

    // Don't change focus under these circumstances
    if(current_focus == .layer_surface) {
      if(current_focus.layer_surface.wlr_layer_surface.current.keyboard_interactive == .exclusive) return;
    } else if(current_focus == .view and current_focus.view.fullscreen) { // Current focus is a fullscreened view
      switch (to_focus.?) {
        .layer_surface => |*layer_surface| {
          const layer = layer_surface.*.wlr_layer_surface.current.layer;
          if(layer == .background or layer == .bottom) return;
        },
        .view => |*view| {
          if(!view.*.fullscreen) return; // TODO: Is this the correct conditional
        },
        else => {}
      }
    }

    // Clear the focus if applicable
    switch (current_focus) {
      .layer_surface => {}, // IDK if we actually have to clear any focus here
      else => {
        if(wlr.XdgSurface.tryFromWlrSurface(current_surface)) |xdg_surface| {
          _ = xdg_surface.role_data.toplevel.?.setActivated(false);
        }
      }
    }
  }

  if(to_focus != null) {
    server.seat.wlr_seat.keyboardNotifyEnter(
      surface.?,
      &server.seat.wlr_seat.keyboard_state.keyboard.?.keycodes,
      null
    );
    if(to_focus.? != .layer_surface) {
      if(wlr.XdgSurface.tryFromWlrSurface(surface.?)) |xdg_surface| {
        _ = xdg_surface.role_data.toplevel.?.setActivated(true);
      }
    }
    self.focused_surface = to_focus;
  }
}

pub fn focusOutput(self: *Seat, output: *Output) void {
  if(server.seat.focused_output) |prev_output| {
    prev_output.focused = false;
  }

  self.focused_output = output;
}

fn handleRequestSetCursor(
  _: *wl.Listener(*wlr.Seat.event.RequestSetCursor),
  event: *wlr.Seat.event.RequestSetCursor,
) void {
  if (event.seat_client == server.seat.wlr_seat.pointer_state.focused_client)
  server.cursor.wlr_cursor.setSurface(event.surface, event.hotspot_x, event.hotspot_y);
}

fn handleRequestSetSelection (
  _: *wl.Listener(*wlr.Seat.event.RequestSetSelection),
  event: *wlr.Seat.event.RequestSetSelection,
) void {
  server.seat.wlr_seat.setSelection(event.source, event.serial);
}
