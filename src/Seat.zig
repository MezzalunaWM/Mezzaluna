const Seat = @This();

const std = @import("std");
const wlr = @import("wlroots");
const wayland = @import("wayland");
const wl = wayland.server.wl;
const zwlr = wayland.server.zwlr;
const xkb = @import("xkbcommon");

const KeyboardGroup = @import("KeyboardGroup.zig");
const Keyboard = @import("Keyboard.zig");
const Cursor = @import("Cursor.zig");
const Utils = @import("Utils.zig");
const input_device = @import("input_device.zig");
const Popup = @import("Popup.zig");
const View = @import("View.zig");
const LayerSurface = @import("LayerSurface.zig");
const Output = @import("Output.zig");
const SceneNodeData = @import("SceneNode.zig").Data;
const Input = @import("lua/Input.zig");
const PointerConstraint = @import("PointerConstraint.zig");

const server = &@import("main.zig").server;
const gpa = std.heap.c_allocator;

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
link: wl.list.Link,

focused_surface: ?FocusData,
focused_output: ?*Output,

keyboard_group: *KeyboardGroup,
cursor: Cursor, // all mice in a seat share one cursor
xkb_keymap: *xkb.Keymap, // TODO: configure this via lua later
active_constraint: ?*PointerConstraint = null,
constraints: wl.list.Head(PointerConstraint, .link),

// per seat lua data
keymaps: std.AutoHashMap(u64, Input.KeymapData),
mousemaps: std.AutoHashMap(u64, Input.MousemapData),

request_set_cursor: wl.Listener(*wlr.Seat.event.RequestSetCursor) = .init(handleRequestSetCursor),
request_set_selection: wl.Listener(*wlr.Seat.event.RequestSetSelection) = .init(handleRequestSetSelection),
request_set_primary_selection: wl.Listener(*wlr.Seat.event.RequestSetPrimarySelection) = .init(handleRequestSetPrimarySelection),
// request_start_drage

pub fn init(name: [*:0]const u8) !*Seat {
    const self = try gpa.create(Seat);
    errdefer gpa.destroy(self);

    const xkb_context = xkb.Context.new(.no_flags) orelse {
        std.log.err("Unable to create a xkb context, exiting", .{});
        return error.xkbContext;
    };
    defer xkb_context.unref();

    const xkb_keymap = xkb.Keymap.newFromNames(xkb_context, null, .no_flags) orelse {
        std.log.err("Unable to create a xkb keymap, exiting", .{});
        return error.xkbKeymap;
    };
    defer xkb_keymap.unref();

    self.* = .{
        .wlr_seat = try wlr.Seat.create(server.wl_server, name),
        .focused_surface = null,
        .focused_output = null,
        .keyboard_group = .init(self),
        .xkb_keymap = xkb_keymap.ref(),
        .cursor = undefined,
        .link = undefined,
        .constraints = undefined,

        .keymaps = undefined,
        .mousemaps = undefined,
    };
    errdefer {
        self.keyboard_group.deinit();
        self.wlr_seat.destroy();
    }

    _ = self.keyboard_group.wlr_group.keyboard.setKeymap(self.xkb_keymap);
    self.wlr_seat.setKeyboard(&self.keyboard_group.wlr_group.keyboard);
    self.cursor.init(self);

    self.keymaps = .init(gpa);
    self.mousemaps = .init(gpa);
    self.constraints.init();

    self.wlr_seat.events.request_set_cursor.add(&self.request_set_cursor);
    self.wlr_seat.events.request_set_selection.add(&self.request_set_selection);
    self.wlr_seat.events.request_set_primary_selection.add(&self.request_set_primary_selection);

    return self;
}

pub fn deinit(self: *Seat) void {
    // remove the seat from the list
    self.link.remove();

    self.request_set_cursor.link.remove();
    self.request_set_selection.link.remove();
    self.request_set_primary_selection.link.remove();

    self.keymaps.deinit();
    self.mousemaps.deinit();

    self.keyboard_group.deinit();
    self.wlr_seat.destroy();
}

pub fn id(self: *Seat) u32 {
    var iter_seat = server.seats.iterator(.forward);
    var i: u32 = 0;
    while (iter_seat.next()) |v| : (i += 1) {
        if (v == self) return i;
    }

    std.debug.panic("Trying to get id of seat not in the server's list of seats!", .{});
}

pub fn focusSurface(self: *Seat, to_focus: ?FocusData) void {
    if (to_focus == null) {
        self.focused_surface = to_focus;
        self.wlr_seat.keyboardClearFocus();
        return;
    }
    const surface = to_focus.?.getSurface();

    // Remove focus from the current surface unless...
    if (self.focused_surface) |current_focus| {
        // the current surface and the surface to focus are the same
        if (current_focus.getSurface() == surface) return;

        switch (current_focus) {
            .layer_surface => |*current_layer_surface| {
                const layer = @intFromEnum(current_layer_surface.*.wlr_layer_surface.current.layer);
                // the current surface is over on or above the top layer
                if (layer >= @intFromEnum(zwlr.LayerShellV1.Layer.top)) return;
            },
            .view => |*current_view| {
                // the current surface is fullscreen and the layer surface to
                // focus is not on or above the top layer
                if (current_view.*.isFullscreen() and current_view.*.scene_tree.node.enabled) {
                    switch (to_focus.?) {
                        .layer_surface => |*layer_surface| {
                            const layer = @intFromEnum(layer_surface.*.wlr_layer_surface.current.layer);
                            if (layer < @intFromEnum(zwlr.LayerShellV1.Layer.top)) return;
                        },
                        .view => return,
                    }
                }
            },
        }

        // deactivate the current surface
        if (current_focus == .view) current_focus.view.setActivated(false);
    }

    // focus the new surface
    self.wlr_seat.keyboardNotifyEnter(
        surface,
        &self.keyboard_group.wlr_group.keyboard.keycodes,
        &self.keyboard_group.wlr_group.keyboard.modifiers,
    );
    // activate the new surface
    if (to_focus.? == .view) to_focus.?.view.setActivated(true);
    self.focused_surface = to_focus;
}

pub fn focusOutput(self: *Seat, output: *Output) void {
    self.focused_output = output;
}

pub fn addInputDevice(self: *Seat, device: *wlr.InputDevice) void {
    switch (device.type) {
        .keyboard => {
            const keyboard = (input_device.get(device) orelse return).keyboard;
            self.keyboard_group.addKeyboard(keyboard);
        },
        .pointer => {
            self.cursor.wlr_cursor.attachInputDevice(device);
        },
        else => |t| std.log.err("unsupported input method: {}", .{ t }),
    }
}

fn handleRequestSetCursor(
    listener: *wl.Listener(*wlr.Seat.event.RequestSetCursor),
    event: *wlr.Seat.event.RequestSetCursor,
) void {
    const self: *Seat = @fieldParentPtr("request_set_cursor", listener);
    if (event.seat_client == self.wlr_seat.pointer_state.focused_client) {
        self.cursor.wlr_cursor.setSurface(event.surface, event.hotspot_x, event.hotspot_y);
    }
}

fn handleRequestSetSelection(
    listener: *wl.Listener(*wlr.Seat.event.RequestSetSelection),
    event: *wlr.Seat.event.RequestSetSelection,
) void {
    const self: *Seat = @fieldParentPtr("request_set_selection", listener);
    self.wlr_seat.setSelection(event.source, event.serial);
}

fn handleRequestSetPrimarySelection(
    listener: *wl.Listener(*wlr.Seat.event.RequestSetPrimarySelection),
    event: *wlr.Seat.event.RequestSetPrimarySelection,
) void {
    const self: *Seat = @fieldParentPtr("request_set_primary_selection", listener);
    self.wlr_seat.setPrimarySelection(event.source, event.serial);
}
