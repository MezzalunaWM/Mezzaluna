const View = @This();

const std = @import("std");
const wlr = @import("wlroots");
const wl = @import("wayland").server.wl;
const utils = @import("utils.zig");

const Popup = @import("Popup.zig");
const Output = @import("Output.zig");
const SceneNode = @import("SceneNode.zig");
const Options = @import("lua/Options.zig");
const Debug = @import("Debug.zig");

const server = &@import("main.zig").server;
const gpa = &@import("main.zig").gpa;
const log = std.log.scoped(.View);

const State = struct {
    // The total geometry including borders
    parent: *wlr.SceneTree,

    geometry: wlr.Box,
    fullscreen: bool,

    activated: bool,
    enabled: bool,
    resizing: bool,

    decoration_mode: wlr.XdgToplevelDecorationV1.Mode,
    tiled_edges: wlr.Edges,
    closing: bool,
};

id: u64,
focus_count: u32,

output: ?*Output,

xdg_toplevel: *wlr.XdgToplevel,
xdg_toplevel_decoration: ?*wlr.XdgToplevelDecorationV1,

scene_tree: *wlr.SceneTree,
surface_tree: *wlr.SceneTree,
saved_surface_tree: *wlr.SceneTree,

scene_tree_snd: SceneNode.Data,
surface_tree_snd: SceneNode.Data,
saved_tree_snd: SceneNode.Data,
xdg_surface_snd: SceneNode.Data,
surface_snd: SceneNode.Data,

previous_geometry: wlr.Box,
border_width: i32,
border_color: [4]f32,
borders: [4]*wlr.SceneRect,

borders_snd: SceneNode.Data,

// These three states are what (hopefully) make perfect frames possible
// The *pending* state is state that has been queued and is waiting to be applied
// The *sending* state is state that has been sent to clients, and is waiting for acks
// The *current* state is state currently visible to the user
pending: ?State,
sending: ?State,
current: State,

awaiting_buffer: bool,
configure_serial: u32,
configure_acked: bool,
view_timer: *wl.EventSource,

// Surface Listeners
map: wl.Listener(void) = .init(handleMap),
unmap: wl.Listener(void) = .init(handleUnmap),
commit: wl.Listener(*wlr.Surface) = .init(handleCommit),
new_popup: wl.Listener(*wlr.XdgPopup) = .init(handleNewPopup),

ack_configure: wl.Listener(*wlr.XdgSurface.Configure) = .init(handleAckConfigure),

// XdgTopLevel Listeners
destroy: wl.Listener(void) = .init(handleDestroy),

request_resize: wl.Listener(*wlr.XdgToplevel.event.Resize) = .init(handleRequestResize),
request_move: wl.Listener(*wlr.XdgToplevel.event.Move) = .init(handleRequestMove),
request_fullscreen: wl.Listener(void) = .init(handleRequestFullscreen),

set_app_id: wl.Listener(void) = .init(handleSetAppId),
set_title: wl.Listener(void) = .init(handleSetTitle),

pub fn init(xdg_toplevel: *wlr.XdgToplevel) *View {
    errdefer utils.oomPanic();

    const self = try gpa.create(View);
    errdefer gpa.destroy(self);

    self.* = .{
        .id = @intFromPtr(xdg_toplevel),
        .focus_count = 0,
        .output = null,

        .previous_geometry = .{ .width = 0, .height = 0, .x = 0, .y = 0 },

        .xdg_toplevel = xdg_toplevel,
        .xdg_toplevel_decoration = null,

        .scene_tree_snd = .{ .view = self },
        .surface_tree_snd = .{ .view_surface_tree = self },
        .saved_tree_snd = .{ .view_saved_tree = self },
        .surface_snd = .{ .view_surface = self },
        .xdg_surface_snd = .{ .view_xdg_surface = self },
        .borders_snd = .{ .view_border = self },

        .scene_tree = try server.root.hidden_tree.createSceneTree(),
        .surface_tree = try self.scene_tree.createSceneXdgSurface(xdg_toplevel.base),
        .saved_surface_tree = try self.scene_tree.createSceneTree(),

        .border_width = 0,
        .border_color = .{ 0, 0, 0, 1 },
        .borders = undefined,

        // State the view SHOULD start with
        .pending = .{
            .parent = server.root.hidden_tree,

            .geometry = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
            .fullscreen = false,

            .activated = false,
            .enabled = true,
            .resizing = false,
            .closing = false,

            .decoration_mode = .server_side,
            .tiled_edges = .{
                .top = true,
                .right = true,
                .left = true,
                .bottom = true
            },
        },
        .sending = null,
        // State the view DOES start with
        .current = .{
            .parent = server.root.hidden_tree,

            .geometry = .{
                .x = self.scene_tree.node.x,
                .y = self.scene_tree.node.y,
                .width = self.xdg_toplevel.current.width,
                .height = self.xdg_toplevel.current.height
            },
            .fullscreen = self.xdg_toplevel.current.fullscreen,

            .activated = self.xdg_toplevel.current.activated,
            .enabled = self.scene_tree.node.enabled,
            .resizing = self.xdg_toplevel.current.resizing,

            .decoration_mode = .server_side,
            .tiled_edges = self.xdg_toplevel.current.tiled,
            .closing = false,
        },

        .awaiting_buffer = false,
        .configure_serial = 0,
        .configure_acked = false,
        .view_timer = server.event_loop.addTimer(*View, handleViewTimer, self) catch utils.oomPanic()
    };

    self.saved_surface_tree.node.setEnabled(false);

    // Create border scene_rects
    for (self.borders, 0..) |_, i| {
        self.borders[i] = try self.scene_tree.createSceneRect(0, 0, &self.border_color);
        self.borders[i].node.data = &self.borders_snd;
    }

    // Set a bunch of scene node data to point here
    self.scene_tree.node.data = &self.scene_tree_snd;
    self.surface_tree.node.data = &self.surface_tree_snd;
    self.saved_surface_tree.node.data = &self.saved_tree_snd;

    self.xdg_toplevel.base.data = &self.xdg_surface_snd;
    self.xdg_toplevel.base.surface.data = &self.surface_snd;

    // Add events too xdg_toplevel
    self.xdg_toplevel.events.destroy.add(&self.destroy);
    self.xdg_toplevel.base.surface.events.map.add(&self.map);
    self.xdg_toplevel.base.surface.events.unmap.add(&self.unmap);
    self.xdg_toplevel.base.surface.events.commit.add(&self.commit);
    self.xdg_toplevel.base.events.new_popup.add(&self.new_popup);

    return self;
}

pub fn setParent(self: *View, parent: *wlr.SceneTree) void {
    if (self.pending == null) self.pending = self.sending orelse self.current;
    self.pending.?.parent = parent;
}

// Null values are set to their corresponding current geometry values
pub fn setGeometry(self: *View, x: ?i32, y: ?i32, width: ?i32, height: ?i32) void {
    // You shouldn't be able to resize fullscreen views
    if(self.current.fullscreen) return;

    if (self.pending == null) self.pending = self.sending orelse self.current;

    server.events.exec("ViewSetGeometryPre", .{ self.id, self.pending.?.geometry }, "A view has had it's pending geometry status set.");

    self.previous_geometry = self.current.geometry;
    const geo_base = self.sending orelse self.current; // use in-flight geometry as default for nil fields
    self.pending.?.geometry = .{
        .x = x orelse geo_base.geometry.x,
        .y = y orelse geo_base.geometry.y,
        .width = @max(1 + 2 * self.border_width, width orelse geo_base.geometry.width),
        .height = @max(1 + 2 * self.border_width, height orelse geo_base.geometry.height),
    };

    self.resizeBorders();
}

pub fn setFullscreen(self: *View, fullscreen: bool) void {
    if (self.pending == null) self.pending = self.sending orelse self.current;

    if (self.output == null) {
        log.debug("View {d} has no output to fullscreen on", .{self.id});
        return;
    }

    // ViewSetFullscreenPre
    // Before making a view fullscreen within it's output
    // passed view_id and true `true` if being fullscreened `false` otherwise
    server.events.exec("ViewSetFullscreenPre", .{ self.id, fullscreen }, "A view has had it's pending fullscreen status set.");

    // log.debug("Setting fullscreen to {}", .{fullscreen});

    const fullscreens = &self.output.?.fullscreens;
    if(fullscreen and !self.current.fullscreen) {
        if(self.output.?.getEnabledFullscreen()) |ef| {
            ef.setFullscreen(false);
        }

        self.previous_geometry = (self.sending orelse self.current).geometry;

        self.setParent(self.output.?.layers.top);
        self.setGeometry(0, 0, self.output.?.wlr_output.width, self.output.?.wlr_output.height);
        self.pending.?.fullscreen = true;

        fullscreens.append(gpa.*, self) catch utils.oomPanic();
    } else if (!fullscreen and self.current.fullscreen) {
        self.setParent(self.output.?.layers.content);
        self.pending.?.fullscreen = false;

        // self.setGeometry(
        //     self.previous_geometry.x,
        //     self.previous_geometry.y,
        //     self.previous_geometry.width,
        //     self.previous_geometry.height,
        // );

        if (std.mem.indexOfScalar(*View, fullscreens.items, self)) |i| {
            _ = self.output.?.fullscreens.swapRemove(i);
        }
    }
}

pub fn setActivated(self: *View, activated: bool) void {
    if (self.pending == null) self.pending = self.sending orelse self.current;

    // Before a view's focus is set
    server.events.exec("ViewSetFocusPre", .{ self.id, activated }, "A view has had it's pending focus status set.");

    self.pending.?.activated = activated;
}

pub fn setEnabled(self: *View, enabled: bool) void {
    if (self.pending == null) self.pending = self.sending orelse self.current;

    server.events.exec("ViewSetEnabledPre", .{ self.id, enabled }, "A view has had it's pending enabled status set.");

    self.pending.?.enabled = enabled;
}

pub fn setResizing(self: *View, resizing: bool) void {
    if (self.pending == null) self.pending = self.sending orelse self.current;
    self.pending.?.resizing = resizing;
}

pub fn setClosing(self: *View, closing: bool) void {
    if (self.pending == null) self.pending = self.sending orelse self.current;

    if (closing and self.current.fullscreen) {
        self.setFullscreen(false);
    }

    server.events.exec("ViewSetClosingPre", .{ self.id, closing }, "A view has had it's pending closing status set.");

    self.pending.?.closing = closing;
}

pub fn setDecorationMode(self: *View, mode: wlr.XdgToplevelDecorationV1.Mode) void {
    if (self.pending == null) self.pending = self.sending orelse self.current;
    self.pending.?.decoration_mode = mode;
}

pub fn setTiledEdges(self: *View, edges: wlr.Edges) void {
    if (self.pending == null) self.pending = self.sending orelse self.current;
    self.pending.?.tiled_edges = edges;
}

pub fn setBorderColor(self: *View, color: *const [4]f32) void {
    for (self.borders) |border| border.setColor(color);
}

/// this function handles all things related to sizing and positioning and
/// should be called after something in the size or position is changed
pub fn resizeBorders(self: *View) void {
    // set the position of the surface to not clip with the borders
    self.surface_tree.node.setPosition(self.border_width, self.border_width);

    // clip the surface tree to the size of the view
    self.surface_tree.node.subsurfaceTreeSetClip(&wlr.Box{
        // use the offset relative to the surface geometry, not the output geometry
        .x = self.xdg_toplevel.base.geometry.x,
        .y = self.xdg_toplevel.base.geometry.y,
        .width = self.current.geometry.width - 2 * self.border_width,
        .height = self.current.geometry.height - 2 * self.border_width,
    });

    self.borders[0].setSize(self.current.geometry.width, self.border_width);
    self.borders[1].setSize(self.current.geometry.width, self.border_width);
    self.borders[2].setSize(self.border_width, self.current.geometry.height);
    self.borders[3].setSize(self.border_width, self.current.geometry.height);
    self.borders[1].node.setPosition(0, self.current.geometry.height - self.border_width);
    self.borders[2].node.setPosition(self.current.geometry.width - self.border_width, 0);
}

pub fn applyPending(self: *View) void {
    if (self.pending == null) return;
    const pending = &self.pending.?;
    const current = &self.current;

    var serial: u32 = 0;

    // Resizing
    if (pending.geometry.height != current.geometry.height or pending.geometry.width != current.geometry.width) {
        if(!current.resizing) {
            self.surface_tree.node.forEachBuffer(*wlr.SceneTree, saveSurfaceTreeIter, self.saved_surface_tree);

            // Hiding
            self.surface_tree.node.setEnabled(false);
            self.saved_surface_tree.node.setEnabled(true);

            self.awaiting_buffer = true;
            server.root.pending_views += 1;
        }

        // Position is not something the client needs to consider so it happens instantly
        // We wait till the client commits its new buffer to position
        serial = self.xdg_toplevel.setSize(
            pending.geometry.width - 2 * self.border_width,
            pending.geometry.height - 2 * self.border_width,
        );
    }

    // Fullscreen
    if(pending.fullscreen != current.fullscreen) {
        serial = @max(serial, self.xdg_toplevel.setFullscreen(pending.fullscreen));
    }

    // Activated
    if (pending.activated != current.activated) {
        serial = @max(serial, self.xdg_toplevel.setActivated(pending.activated));
    }

    // Decoration mode
    if (pending.decoration_mode != current.decoration_mode and self.xdg_toplevel_decoration != null) {
        serial = @max(serial, self.xdg_toplevel_decoration.?.setMode(pending.decoration_mode));
    }

    // Resizing
    if(pending.resizing != current.resizing) {
        serial = @max(serial, self.xdg_toplevel.setResizing(pending.resizing));
    }

    // Tiled edges
    if(pending.tiled_edges != current.tiled_edges) {
        serial = @max(serial, self.xdg_toplevel.setTiled(pending.tiled_edges));
    }

    self.configure_serial = serial;
    self.configure_acked = false;
    if (self.awaiting_buffer) {
        self.view_timer.timerUpdate(140) catch {};
    }

    self.sending = self.pending;
    self.pending = null;
}

fn saveSurfaceTreeIter(scene_buffer: *wlr.SceneBuffer, sx: c_int, sy: c_int, saved_surface_tree: *wlr.SceneTree) void {
    const buffer = scene_buffer.buffer orelse return;

    // Create saved scene buffer
    const saved = saved_surface_tree.createSceneBuffer(buffer) catch utils.oomPanic();

    // Copy all properties
    saved.node.setPosition(sx, sy);
    saved.setDestSize(scene_buffer.dst_width, scene_buffer.dst_height);
    saved.setSourceBox(&scene_buffer.src_box);
    saved.setTransform(scene_buffer.transform);
}

fn dropSavedSurfaceTree(self: *View) void {
    var buffer_it = self.saved_surface_tree.children.safeIterator(.forward);

    while (buffer_it.next()) |buffer| {
        buffer.destroy();
    }
}

pub fn applySending(self: *View) void {
    if(self.sending == null) return;

    if (self.sending.?.closing) {
        self.scene_tree.node.setEnabled(false);

        server.events.exec("ViewSetClosingPost", .{ self.id }, "A view is being closed.");
        
        self.xdg_toplevel.sendClose();

        self.current = self.sending.?;
        self.sending = null;
        return;
    }

    if (self.sending.?.geometry.x != self.current.geometry.x or
        self.sending.?.geometry.y != self.current.geometry.y or
        self.sending.?.geometry.width != self.current.geometry.width or
        self.sending.?.geometry.height != self.current.geometry.height) 
        server.events.exec("ViewSetGeometryPost", .{ self.id }, "A view has had it's pending geometry applied.");

    if (self.sending.?.fullscreen != self.current.fullscreen)
        server.events.exec("ViewSetFullscreenPost", .{ self.id, self.sending.?.fullscreen }, "A view has had it's pending fullscreen status applied.");

    if (self.sending.?.activated != self.current.activated) {
        server.events.exec("ViewSetFocusPost", .{ self.id, self.sending.?.activated, self.focus_count }, "A view has had it's pending focus status applied.");
    }

    if (self.sending.?.enabled != self.current.enabled) {
        self.scene_tree.node.setEnabled(self.sending.?.enabled);

        server.events.exec("ViewSetEnabledPost", .{ self.id, self.sending.?.enabled }, "A view has had it's pending enabled status applied.");
    }

    if(self.sending.?.parent != self.current.parent) {
        self.scene_tree.node.reparent(self.sending.?.parent);

        var scene_node = &self.scene_tree.node;
        self.output = while (true) {
            const parent_scene_node = if (scene_node.parent) |p| &p.node else break null;
            const parent_snd: *SceneNode.Data = .fromSceneNode(parent_scene_node);

            switch (parent_snd.*) {
                .hidden_tree, .root => break null,
                .output => |*output| break output.*,
                else => { scene_node = parent_scene_node; }
            }
        };
    }


    self.current = self.sending.?;
    self.sending = null;

    self.scene_tree.node.setPosition(self.current.geometry.x, self.current.geometry.y);
    self.resizeBorders();

    // Revealing
    self.surface_tree.node.setEnabled(true);
    self.saved_surface_tree.node.setEnabled(false);

    self.dropSavedSurfaceTree();
}

// TODO: Is this necessary if only used once in Cursor.zig
pub fn fromSurface(surface: *wlr.Surface) ?*View {
    var xdg_surface = wlr.XdgSurface.tryFromWlrSurface(surface);
    if (xdg_surface) |xs| {
        switch (xs.role) {
            .toplevel => {
                const snd: *SceneNode.Data = @ptrCast(@alignCast(xs.data));
                return if (snd.* == .view) snd.view else null;
            },
            .popup => {
                if (xs.popups.first() == null or xs.popups.first().?.parent == null) {
                    return null;
                }

                const tmp_xdg_surface = wlr.XdgSurface.tryFromWlrSurface(
                    xs.popups.first().?.parent.?
                ) orelse return fromSurface(xs.popups.first().?.parent.?);

                xdg_surface = tmp_xdg_surface;
            },
            .none => return null,
        }
    }

    return null;
}

// --------- XdgTopLevel event handlers ---------
fn handleMap(listener: *wl.Listener(void)) void {
    const view: *View = @fieldParentPtr("map", listener);

    server.events.exec("ViewMapPre", .{view.id}, "Before a view is mapped to the screen. This means the view is not yet displayed to the user.");

    const new_view_hidden = Options.getOption(.boolean, "new_view_hidden");
    if(new_view_hidden != null and !new_view_hidden.?) {
        if(server.getDefaultSeat().focused_output) |output| {
            view.setParent(output.layers.content);
        }
    } else {
        view.setParent(server.root.hidden_tree);
    }


    view.xdg_toplevel.base.events.ack_configure.add(&view.ack_configure);
    view.xdg_toplevel.events.request_fullscreen.add(&view.request_fullscreen);
    view.xdg_toplevel.events.request_move.add(&view.request_move);
    view.xdg_toplevel.events.request_resize.add(&view.request_resize);
    view.xdg_toplevel.events.set_app_id.add(&view.set_app_id);
    view.xdg_toplevel.events.set_title.add(&view.set_title);

    server.root.applyPending();

    server.events.exec("ViewMapPost", .{view.id}, "After a view is mapped to the screen. This view is now being displayed to the user.");
}

fn handleUnmap(listener: *wl.Listener(void)) void {
    const view: *View = @fieldParentPtr("unmap", listener);

    server.events.exec("ViewUnmapPre", .{view.id}, "Before the view is unmapped. This view is still currently visible to the user.");

    var iter = server.seats.iterator(.forward);
    while (iter.next()) |seat| {
        if (seat.focused_surface) |fs| {
            if (fs == .view and fs.view == view) seat.focusSurface(null);
        }
    }

    // If this view was part of an sending transaction, clean up so the
    // root counter doesn't get stuck and other views can be revealed.
    if (view.awaiting_buffer) {
        view.view_timer.timerUpdate(0) catch {};
        server.root.pending_views -|= 1;
        view.awaiting_buffer = false;
        view.configure_serial = 0;
        view.configure_acked = false;
        if (server.root.pending_views == 0) {
            server.root.applySending();
        }
    }

    view.ack_configure.link.remove();
    view.request_fullscreen.link.remove();
    view.request_move.link.remove();
    view.request_resize.link.remove();
    view.set_title.link.remove();
    view.set_app_id.link.remove();


    server.events.exec("ViewUnmapPost", .{view.id}, "After the view is unmapped. This view is no longer visible to the user.");
}

fn handleDestroy(listener: *wl.Listener(void)) void {
    const view: *View = @fieldParentPtr("destroy", listener);

    // Remove decorations
    for (view.borders) |b| {
        b.node.destroy();
    }

    // remove listeners
    view.destroy.link.remove();
    view.map.link.remove();
    view.unmap.link.remove();
    view.commit.link.remove();
    view.new_popup.link.remove();

    view.view_timer.remove();

    view.xdg_toplevel.base.surface.data = null;

    view.scene_tree.node.destroy();
    // Destroy popups

    gpa.destroy(view);
}

fn handleCommit(listener: *wl.Listener(*wlr.Surface), _: *wlr.Surface) void {
    const view: *View = @fieldParentPtr("commit", listener);

    server.events.exec("ViewCommitPost", .{view.id, view.xdg_toplevel.base.initial_commit}, "After a view receives a commit. The commit may be the initial commit.");
    if (view.xdg_toplevel.base.initial_commit) {
        if (view.xdg_toplevel_decoration) |deco| {
            _ = deco.setMode(.server_side);
        }
        return;
    }

    if (view.awaiting_buffer and view.configure_acked) {
        view.awaiting_buffer = false;
        view.configure_serial = 0;
        view.view_timer.timerUpdate(0) catch {};
        if (server.root.pending_views > 0) server.root.pending_views -= 1;
        if (server.root.pending_views == 0) server.root.applySending();
    }
}

// --------- XdgToplevel Event Handlers ---------
fn handleAckConfigure(listener: *wl.Listener(*wlr.XdgSurface.Configure), configure: *wlr.XdgSurface.Configure) void {
    const view: *View = @fieldParentPtr("ack_configure", listener);

    if (view.configure_serial == 0 or configure.serial < view.configure_serial) return;
    view.configure_acked = true;
    view.configure_serial = 0;

    // Client has acked — wait for the actual buffer commit. Set a shorter
    // timeout so we don't block other views if the client stalls after acking.
    //  -- BigPickle with love

    if (view.awaiting_buffer) {
        view.view_timer.timerUpdate(50) catch {};
    }
}

fn handleViewTimer(data: *View) c_int {
    if (!data.awaiting_buffer) return 0;
    data.awaiting_buffer = false;
    data.configure_serial = 0;
    data.configure_acked = false;
    if (server.root.pending_views > 0) server.root.pending_views -= 1;
    if (server.root.pending_views == 0) server.root.applySending();
    return 0;
}

fn handleNewPopup(listener: *wl.Listener(*wlr.XdgPopup), xdg_popup: *wlr.XdgPopup) void {
    const view: *View = @fieldParentPtr("new_popup", listener);
    _ = Popup.init(xdg_popup, view.scene_tree);
}

fn handleRequestMove(listener: *wl.Listener(*wlr.XdgToplevel.event.Move), _: *wlr.XdgToplevel.event.Move) void {
    const view: *View = @fieldParentPtr("request_move", listener);
    server.events.exec("ViewRequestMove", .{view.id}, "Before the view requests to move.");
}

fn handleRequestResize(listener: *wl.Listener(*wlr.XdgToplevel.event.Resize), _: *wlr.XdgToplevel.event.Resize) void {
    const view: *View = @fieldParentPtr("request_resize", listener);
    server.events.exec("ViewRequestResize", .{view.id}, "Before the view requests to resize.");
}

fn handleRequestFullscreen(listener: *wl.Listener(void)) void {
    const view: *View = @fieldParentPtr("request_fullscreen", listener);
    server.events.exec("ViewRequestFullscreen", .{view.id}, "Before the view requests to be fullscreened.");
}

fn handleRequestMinimize(listener: *wl.Listener(void)) void {
    const view: *View = @fieldParentPtr("request_minimize", listener);
    server.events.exec("ViewRequestMinimize", .{view.id}, "Before the view requests to be minimized.");
    log.debug("request_minimize unimplemented", .{});
}

fn handleSetAppId(listener: *wl.Listener(void)) void {
    const view: *View = @fieldParentPtr("set_app_id", listener);
    server.events.exec("ViewAppIdUpdate", .{view.id}, "Before the view requests to update its appid.");
    log.debug("request_set_app_id unimplemented", .{});
}

fn handleSetTitle(listener: *wl.Listener(void)) void {
    const view: *View = @fieldParentPtr("set_title", listener);
    server.events.exec("ViewTitleUpdate", .{view.id}, "Before the view requests to update its title.");
    log.debug("request_set_title unimplemented", .{});
}
