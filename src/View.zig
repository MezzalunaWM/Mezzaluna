const View = @This();

const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const Popup = @import("Popup.zig");
const Output = @import("Output.zig");
const SceneNodeData = @import("SceneNodeData.zig").SceneNodeData;

const Utils = @import("Utils.zig");

const gpa = std.heap.c_allocator;
const server = &@import("main.zig").server;

const State = struct {
    // The total geometry including borders
    geometry: wlr.Box = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    activated: bool = false,
    enabled: bool = false,

    decoration_mode: wlr.XdgToplevelDecorationV1.Mode = .none,
    wm_capabilities: wlr.XdgToplevel.WmCapabilities = .{},

    tiled_edges: wlr.Edges = .{},

    // Give the default state we want views to start with
    pub fn init() State {
        return .{
            .geometry = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
            .activated = false,
            .enabled = true,

            .decoration_mode = .server_side,
            .wm_capabilities = .{ .fullscreen = true },

            .tiled_edges = .{
                .top = true,
                .bottom = true,
                .left = true,
                .right = true,
            }
        };
    }
};

id: u64,

output: ?*Output,

xdg_toplevel: *wlr.XdgToplevel,
xdg_toplevel_decoration: ?*wlr.XdgToplevelDecorationV1,

scene_tree: *wlr.SceneTree,
surface_tree: *wlr.SceneTree,
saved_surface_tree: *wlr.SceneTree,

scene_tree_snd: SceneNodeData,
surface_tree_snd: SceneNodeData,
saved_tree_snd: SceneNodeData,
surface_snd: SceneNodeData,

previous_geometry: wlr.Box,
border_width: i32,
border_color: [4]f32,
borders: [4]*wlr.SceneRect,

borders_snd: SceneNodeData,

// These three states are what (hopefully) make perfect frames possible
// The *pending* state is state that has been queued and is waiting to be applied
// The *sending* state is state that has been sent to clients, and is waiting for acks
// The *current* state is state currently visible to the user
pending: ?State,
sending: ?State,
current: State,

// After view configure, and waiting for new buffer commitment
awaiting_buffer: bool,

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
    errdefer Utils.oomPanic();

    const self = try gpa.create(View);
    errdefer gpa.destroy(self);

    self.* = .{
        .id = @intFromPtr(xdg_toplevel),
        .output = null,

        .previous_geometry = .{ .width = 0, .height = 0, .x = 0, .y = 0 },

        .xdg_toplevel = xdg_toplevel,
        .xdg_toplevel_decoration = null,

        .scene_tree = try server.root.hidden_tree.createSceneTree(),
        .surface_tree = try self.scene_tree.createSceneXdgSurface(xdg_toplevel.base),
        .saved_surface_tree = try self.scene_tree.createSceneTree(),

        .scene_tree_snd = .{ .view = self },
        .surface_tree_snd = .{ .view_surface_tree = self },
        .saved_tree_snd = .{ .view_saved_tree = self },
        .surface_snd = .{ .view_surface = self },
        .borders_snd = .{ .view_border = self },

        .border_width = 0,
        .border_color = .{ 0, 0, 0, 1 },
        .borders = undefined,

        .pending = State.init(),
        .sending = null,
        .current = .{},

        .awaiting_buffer = false,
    };

    self.scene_tree.node.setEnabled(true);
    self.surface_tree.node.setEnabled(true);
    self.saved_surface_tree.node.setEnabled(false);

    // Add new Toplevel to root of the tree
    if (server.getDefaultSeat().focused_output) |output| {
        self.scene_tree.node.reparent(output.layers.content);
        self.output = output;
    }

    // Create border scene_rects
    for (self.borders, 0..) |_, i| {
        self.borders[i] = try wlr.SceneTree.createSceneRect(self.scene_tree, 0, 0, &self.border_color);
        self.borders[i].node.data = self;
    }

    // Set a bunch of scene node data to point here
    self.scene_tree.node.data = &self.scene_tree_snd;
    self.surface_tree.node.data = &self.surface_tree_snd;
    self.saved_surface_tree.node.data = &self.saved_tree_snd;

    self.xdg_toplevel.base.data = &self.scene_tree_snd;
    self.xdg_toplevel.base.surface.data = &self.surface_snd;

    // Add events too xdg_toplevel
    self.xdg_toplevel.events.destroy.add(&self.destroy);
    self.xdg_toplevel.base.surface.events.map.add(&self.map);
    self.xdg_toplevel.base.surface.events.unmap.add(&self.unmap);
    self.xdg_toplevel.base.surface.events.commit.add(&self.commit);
    self.xdg_toplevel.base.events.new_popup.add(&self.new_popup);
    self.xdg_toplevel.base.events.ack_configure.add(&self.ack_configure);

    self.xdg_toplevel.events.request_fullscreen.add(&self.request_fullscreen);
    self.xdg_toplevel.events.request_move.add(&self.request_move);
    self.xdg_toplevel.events.request_resize.add(&self.request_resize);
    self.xdg_toplevel.events.set_app_id.add(&self.set_app_id);
    self.xdg_toplevel.events.set_title.add(&self.set_title);
    // self.xdg_toplevel.events.set_parent.add(&self.set_parent);

    return self;
}

// Tell the client to close
// It better behave!
pub fn close(self: *View) void {
    if (self.isFullscreen()) {
        self.toggleFullscreen();
    }

    self.xdg_toplevel.sendClose();
}

pub fn setBorderColor(self: *View, color: *const [4]f32) void {
    for (self.borders) |border| border.setColor(color);
}

pub fn isFullscreen(self: *View) bool {
    if (self.output == null) {
        std.log.debug("View does not have an assigned output", .{});
        unreachable;
    }

    for (self.output.?.fullscreens.items) |view| {
        if (view == self) return true;
    }

    return false;
}

pub fn toggleFullscreen(self: *View) void {
    if (self.output == null) {
        std.log.debug("View {d} has no output to fullscreen on", .{self.id});
        return;
    }

    const fullscreens = &self.output.?.fullscreens;
    if (self.output.?.getEnabledFullscreen() == self) {
        // ViewSetFullscreenPre
        // Before making a view fullscreen within it's output
        // passed view_id and true `true` if being fullscreened `false` otherwise
        server.events.exec("ViewSetFullscreenPre", .{ self.id, false });

        self.scene_tree.node.reparent(self.output.?.layers.content);

        // ViewSetFullscreenPost
        // After making a view fullscreen within it's output
        // passed view_id and true `true` if being fullscreened `false` otherwise
        server.events.exec("ViewSetFullscreenPost", .{ self.id, false });

        if (std.mem.indexOfScalar(*View, fullscreens.items, self)) |i| {
            _ = self.output.?.fullscreens.swapRemove(i);
        }

        // This needs to be acknowledged with configures
        _ = self.xdg_toplevel.setFullscreen(false);
        return;
    }

    // Check to see if another enabled fullscreen view exists, if so replace it
    if (self.output.?.getEnabledFullscreen()) |v| {
        _ = v.toggleFullscreen();
    }

    server.events.exec("ViewSetFullscreenPre", .{ self.id, true });
    self.scene_tree.node.reparent(self.output.?.layers.top);

    self.setGeometry(0, 0, self.output.?.wlr_output.width, self.output.?.wlr_output.height);

    fullscreens.append(gpa, self) catch Utils.oomPanic();
    _ = self.xdg_toplevel.setFullscreen(true);
    server.events.exec("ViewSetFullscreenPost", .{ self.id, true });
}

// Null values are set to their corresponding current geometry values
pub fn setGeometry(self: *View, x: ?i32, y: ?i32, width: ?i32, height: ?i32) void {
    // if (!self.xdg_toplevel.base.surface.mapped) return;

    if (self.isFullscreen()) return;

    if (self.pending == null) self.pending = self.current;

    self.pending.?.geometry = .{ 
        .x = x orelse self.current.geometry.x, 
        .y = y orelse self.current.geometry.y, 
        .width = @max(1 + 2 * self.border_width, width orelse self.current.geometry.width), 
        .height = @max(1 + 2 * self.border_width, height orelse self.current.geometry.height) 
    };

    // self.resizeBorders();
}

pub fn setDecorationMode(self: *View, mode: wlr.XdgToplevelDecorationV1.Mode) void {
    if (self.pending == null) self.pending = self.current;
    self.pending.?.decoration_mode = mode;
}

pub fn setActivated(self: *View, activated: bool) void {
    if (self.pending == null) self.pending = self.current;

    // Before a view's focus is set
    server.events.exec("ViewSetFocusPre", .{ self.id, activated });

    self.pending.?.activated = activated;
}

pub fn setEnabled(self: *View, enabled: bool) void {
    if (self.pending == null) self.pending = self.current;
    self.pending.?.enabled = enabled;
}

fn setWmCapabilities(self: *View, wm_capabilities: wlr.XdgToplevel.WmCapabilities) void {
    if (self.pending == null) self.pending = self.current;
    self.pending.?.wm_capabilities = wm_capabilities;
}

fn setTiledEdges(self: *View, tiled_edges: wlr.Edges) void {
    if (self.pending == null) self.pending = self.current;
    self.pending.?.tiled_edges = tiled_edges;
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

    // Check if geometry has changed
    if (!wlr.Box.equal(&pending.geometry, &current.geometry)) {
        self.dropSavedSurfaceTree();

        self.surface_tree.node.forEachBuffer(*wlr.SceneTree, saveSurfaceTreeIter, self.saved_surface_tree);

        self.surface_tree.node.setEnabled(false);
        self.saved_surface_tree.node.setEnabled(true);

        // Position is not something the client needs to consider so it happens instantly
        // We wait till the client commits its new buffer to position

        _ = self.xdg_toplevel.setSize(
            pending.geometry.width - 2 * self.border_width,
            pending.geometry.height - 2 * self.border_width,
        );
        std.log.debug("\t\t\tGeometry configure {d}", .{self.id});

        self.awaiting_buffer = true;
        server.root.pending_views += 1;
    }

    // Decoration mode
    if (pending.decoration_mode != current.decoration_mode and self.xdg_toplevel_decoration != null) {
        _ = self.xdg_toplevel_decoration.?.setMode(pending.decoration_mode);
    }

    // WM Capabilities
    if (pending.wm_capabilities != current.wm_capabilities) {
        _ = self.xdg_toplevel.setWmCapabilities(pending.wm_capabilities);
    }

    // Activated
    if (pending.activated != current.activated) {
        _ = self.xdg_toplevel.setActivated(pending.activated);

        // After a view's focus is set
        server.events.exec("ViewSetFocusPost", .{ self.id, pending.activated });
    }

    // Tiling
    if (pending.tiled_edges != current.tiled_edges) {
        _ = self.xdg_toplevel.setTiled(pending.tiled_edges);
    }

    self.sending = self.pending;
    self.pending = null;
}

fn saveSurfaceTreeIter(scene_buffer: *wlr.SceneBuffer, sx: c_int, sy: c_int, saved_surface_tree: *wlr.SceneTree) void {
    const buffer = scene_buffer.buffer orelse return;

    // Create saved scene buffer
    const saved = saved_surface_tree.createSceneBuffer(buffer) catch Utils.oomPanic();

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
    if (self.sending != null) self.current = self.sending.?;
    self.sending = null;

    self.scene_tree.node.setPosition(self.current.geometry.x, self.current.geometry.y);
    self.resizeBorders();

    self.surface_tree.node.setEnabled(true);
    self.saved_surface_tree.node.setEnabled(false);

    self.dropSavedSurfaceTree();
}

pub fn fromSurface(surface: *wlr.Surface) ?*View {
    var xdg_surface = wlr.XdgSurface.tryFromWlrSurface(surface);
    while (xdg_surface) |xs| {
        switch (xs.role) {
            .toplevel => {
                const scene_node_data: *SceneNodeData = @ptrCast(@alignCast(xs.data));
                return if (scene_node_data.* == .view) scene_node_data.view else null;
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
    std.log.debug("Mapping view '{s}'", .{view.xdg_toplevel.title orelse "(unnamed)"});

    // TODO: Do we actually need these two in the end
    server.events.exec("ViewMapPre", .{view.id});
    server.events.exec("ViewMapPost", .{view.id});
}

fn handleUnmap(listener: *wl.Listener(void)) void {
    const view: *View = @fieldParentPtr("unmap", listener);
    std.log.debug("Unmapping view '{s}'", .{view.xdg_toplevel.title orelse "(unnamed)"});

    server.events.exec("ViewUnmapPre", .{view.id});

    if (server.getDefaultSeat().focused_surface) |fs| {
        if (fs == .view and fs.view == view) {
            server.getDefaultSeat().focusSurface(null);
        }
    }

    // If this view was part of an inflight transaction, clean up so the
    // root counter doesn't get stuck and other views can be revealed.
    if (view.awaiting_buffer) {
        view.awaiting_buffer = false;
        if (server.root.pending_views > 0) {
            server.root.pending_views -= 1;
        }
        if (server.root.pending_views == 0) {
            server.root.applySending();
        }
    }

    server.events.exec("ViewUnmapPost", .{view.id});
}

fn handleDestroy(listener: *wl.Listener(void)) void {
    const view: *View = @fieldParentPtr("destroy", listener);

    // Remove decorations
    for (view.borders) |b| {
        b.node.destroy();
    }

    // remove listeners
    view.destroy.link.remove();
    view.ack_configure.link.remove();
    view.map.link.remove();
    view.unmap.link.remove();
    view.commit.link.remove();
    view.new_popup.link.remove();
    view.request_fullscreen.link.remove();
    view.request_move.link.remove();
    view.request_resize.link.remove();
    view.set_title.link.remove();
    view.set_app_id.link.remove();

    view.xdg_toplevel.base.surface.data = null;

    view.scene_tree.node.destroy();
    // Destroy popups

    gpa.destroy(view);
}

fn handleCommit(listener: *wl.Listener(*wlr.Surface), _: *wlr.Surface) void {
    const view: *View = @fieldParentPtr("commit", listener);

    if (view.xdg_toplevel.base.initial_commit) {
        server.root.applyPending();
        return;
    }

    if (view.awaiting_buffer) {
        view.awaiting_buffer = false;

        if (server.root.pending_views > 0) {
            server.root.pending_views -= 1;
        }

        // All views have gotten their commitments
        if (server.root.pending_views == 0) {
            server.root.applySending();
        }
    }
}

// --------- XdgToplevel Event Handlers ---------
fn handleNewPopup(listener: *wl.Listener(*wlr.XdgPopup), xdg_popup: *wlr.XdgPopup) void {
    const view: *View = @fieldParentPtr("new_popup", listener);
    _ = Popup.init(xdg_popup, view.scene_tree);
}

fn handleRequestMove(listener: *wl.Listener(*wlr.XdgToplevel.event.Move), _: *wlr.XdgToplevel.event.Move) void {
    const view: *View = @fieldParentPtr("request_move", listener);
    server.events.exec("ViewRequestMove", .{view.id});
}

fn handleRequestResize(listener: *wl.Listener(*wlr.XdgToplevel.event.Resize), _: *wlr.XdgToplevel.event.Resize) void {
    const view: *View = @fieldParentPtr("request_resize", listener);
    server.events.exec("ViewRequestResize", .{view.id});
}

fn handleAckConfigure(
    _: *wl.Listener(*wlr.XdgSurface.Configure),
    event: *wlr.XdgSurface.Configure,
) void {
    _ = event;
    // We no longer trigger applySending on ack. Instead we wait for the
    // client to commit the new buffer (handleCommit), which is the correct
    // point to reveal the live surface and drop the saved copy.
}

fn handleRequestFullscreen(listener: *wl.Listener(void)) void {
    const view: *View = @fieldParentPtr("request_fullscreen", listener);
    server.events.exec("ViewRequestFullscreen", .{view.id});
}

fn handleRequestMinimize(listener: *wl.Listener(void)) void {
    const view: *View = @fieldParentPtr("request_minimize", listener);
    server.events.exec("ViewRequestMinimize", .{view.id});
    std.log.debug("request_minimize unimplemented", .{});
}

fn handleSetAppId(listener: *wl.Listener(void)) void {
    const view: *View = @fieldParentPtr("set_app_id", listener);
    server.events.exec("ViewAppIdUpdate", .{view.id});
}

fn handleSetTitle(listener: *wl.Listener(void)) void {
    const view: *View = @fieldParentPtr("set_title", listener);
    server.events.exec("ViewTitleUpdate", .{view.id});
}
