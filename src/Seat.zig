const Seat = @This();

const std = @import("std");
const wlr = @import("wlroots");
const wl = @import("wayland").server.wl;
const xkb = @import("xkbcommon");

const KeyboardGroup = @import("KeyboardGroup.zig");
const Utils = @import("Utils.zig");
const Popup = @import("Popup.zig");
const View = @import("View.zig");
const LayerSurface = @import("LayerSurface.zig");
const Output = @import("Output.zig");
const SceneNodeData = @import("SceneNodeData.zig").SceneNodeData;

const server = &@import("main.zig").server;

pub const FocusData = union(enum) {
    view: *View,
    layer_surface: *LayerSurface,

    pub fn getSurface(self: FocusData) *wlr.Surface {
        return switch (self) {
            .view => |*v| v.*.xdg_toplevel.base.surface,
            .layer_surface => |*ls| ls.*.wlr_layer_surface.surface,
        };
    }
};

wlr_seat: *wlr.Seat,

focused_surface: ?FocusData,
focused_output: ?*Output,

keyboard_group: *KeyboardGroup,
keymap: *xkb.Keymap,

request_set_cursor: wl.Listener(*wlr.Seat.event.RequestSetCursor) = .init(handleRequestSetCursor),
request_set_selection: wl.Listener(*wlr.Seat.event.RequestSetSelection) = .init(handleRequestSetSelection),
request_set_primary_selection: wl.Listener(*wlr.Seat.event.RequestSetPrimarySelection) = .init(handleRequestSetPrimarySelection),
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
        .keyboard_group = .init(),
        .keymap = keymap.ref(),
    };
    errdefer {
        self.keyboard_group.deinit();
        self.wlr_seat.destroy();
    }

    _ = self.keyboard_group.wlr_group.keyboard.setKeymap(self.keymap);
    self.wlr_seat.setKeyboard(&self.keyboard_group.wlr_group.keyboard);

    self.wlr_seat.events.request_set_cursor.add(&self.request_set_cursor);
    self.wlr_seat.events.request_set_selection.add(&self.request_set_selection);
    self.wlr_seat.events.request_set_primary_selection.add(&self.request_set_primary_selection);
}

pub fn deinit(self: *Seat) void {
    self.request_set_cursor.link.remove();
    self.request_set_selection.link.remove();
    self.request_set_primary_selection.link.remove();

    self.keyboard_group.deinit();
    self.wlr_seat.destroy();
}

pub fn focusSurface(self: *Seat, to_focus: ?FocusData) void {
    const surface: ?*wlr.Surface = blk: {
        if (to_focus != null) {
            break :blk to_focus.?.getSurface();
        } else {
            break :blk null;
        }
    };

    // Remove focus from the current surface unless:
    //  - current and to focus are the same surface
    //  - current layer has exclusive keyboard interactivity
    //  - current is fullscreen and to focus is content
    //  - current is fullscreen and layer is bottom or background
    if (self.focused_surface) |current_focus| {
        const current_surface = current_focus.getSurface();
        if (current_surface == surface) return; // Same surface

        if (to_focus != null) {
            switch (current_focus) {
                .layer_surface => |*current_layer_surface| {
                    if (current_layer_surface.*.wlr_layer_surface.current.keyboard_interactive == .exclusive) return;
                },
                .view => |*current_view| {
                    if (current_view.*.fullscreen) {
                        switch (to_focus.?) {
                            .layer_surface => |*layer_surface| {
                                const layer = layer_surface.*.wlr_layer_surface.current.layer;
                                if (layer == .background or layer == .bottom) return;
                            },
                            .view => |*view| {
                                if (!view.*.fullscreen) return;
                            },
                        }
                    }
                },
            }
        } else if (current_focus == .view and current_focus.view.fullscreen) {
            return;
        }

        // Clear the focus if applicable
        switch (current_focus) {
            .layer_surface => {}, // IDK if we actually have to clear any focus here
            .view => {
                if (wlr.XdgSurface.tryFromWlrSurface(current_surface)) |xdg_surface| {
                    const view_id: ?u64 = blk: {
                        const scene_node_data: *SceneNodeData = @ptrCast(@alignCast(xdg_surface.data.?));
                        if(scene_node_data.* == .view) {
                            break :blk scene_node_data.view.id;
                        } else {
                            break :blk null;
                        }
                    };

                    if(view_id) |v| {
                        // ViewRemoveFocusPre is fired before a view's focus is removed
                        // ---@param view_id number
                        server.events.exec("ViewRemoveFocusPre", .{v});
                    }

                    _ = xdg_surface.role_data.toplevel.?.setActivated(false);

                    if(view_id) |v| {
                        // ViewRemoveFocusPost is fired after a view's focus is removed
                        // ---@param view_id number
                        server.events.exec("ViewRemoveFocusPost", .{v});
                    }
                }
            }
        }
    }

    if (to_focus != null) {
        server.seat.wlr_seat.keyboardNotifyEnter(surface.?, &server.seat.keyboard_group.wlr_group.keyboard.keycodes, &server.seat.keyboard_group.wlr_group.keyboard.modifiers);
        if (to_focus.? != .layer_surface) {
            if (to_focus.? == .view) to_focus.?.view.focused = true;
            if (wlr.XdgSurface.tryFromWlrSurface(surface.?)) |xdg_surface| {
                    const view_id: ?u64 = blk: {
                        const scene_node_data: *SceneNodeData = @ptrCast(@alignCast(xdg_surface.data.?));
                        if(scene_node_data.* == .view) {
                            break :blk scene_node_data.view.id;
                        } else {
                            break :blk null;
                        }
                    };

                    if(view_id) |v| {
                        // ViewSetFocusPre is fired before a view is focused
                        // ---@param view_id number
                        server.events.exec("ViewSetFocusPre", .{v});
                    }

                    _ = xdg_surface.role_data.toplevel.?.setActivated(true);

                    if(view_id) |v| {
                        // ViewSetFocusPost is fired after a view is focused
                        // ---@param view_id number
                        server.events.exec("ViewSetFocusPost", .{v});
                    }
            }
        }
    }
    self.focused_surface = to_focus;
}

pub fn focusOutput(self: *Seat, output: *Output) void {
    if (server.seat.focused_output) |prev_output| {
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

fn handleRequestSetSelection(
    _: *wl.Listener(*wlr.Seat.event.RequestSetSelection),
    event: *wlr.Seat.event.RequestSetSelection,
) void {
    server.seat.wlr_seat.setSelection(event.source, event.serial);
}

fn handleRequestSetPrimarySelection(
    _: *wl.Listener(*wlr.Seat.event.RequestSetPrimarySelection),
    event: *wlr.Seat.event.RequestSetPrimarySelection,
) void {
    server.seat.wlr_seat.setPrimarySelection(event.source, event.serial);
}
