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
            .enabled = false,

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
scene_node_data: SceneNodeData,

// These three states are what (hopefully) make perfect frames possible
// The *pending* state is state that has been queued and is waiting to be applied
// The *sending* state is state that has been sent to clients, and is waiting for acks
// The *current* state is state currently visible to the user
pending: ?State,
sending: ?State,
current: State,

previous_geometry: wlr.Box,
border_width: i32,
border_color: [4]f32,
borders: [4]*wlr.SceneRect,

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
        .scene_node_data = .{ .view = self },

        .border_width = 0,
        .border_color = .{ 0, 0, 0, 1 },
        .borders = undefined,

        .pending = State.init(),
        .sending = null,
        .current = .{},
    };

    self.scene_tree.node.setEnabled(false);
    self.surface_tree.node.setEnabled(false);
    self.saved_surface_tree.node.setEnabled(false);

    // Add new Toplevel to root of the tree
    if (server.seat.focused_output) |output| {
        self.output = output;
        self.scene_tree.node.reparent(output.layers.content);
    }

    // Create border scene_rects
    for (self.borders, 0..) |_, i| {
        self.borders[i] = try wlr.SceneTree.createSceneRect(self.scene_tree, 0, 0, &self.border_color);
        self.borders[i].node.data = self;
    }

    // Set a bunch of scene node data to point here
    self.scene_tree.node.data = &self.scene_node_data;
    self.surface_tree.node.data = &self.scene_node_data;
    self.saved_surface_tree.node.data = &self.scene_node_data;
    self.xdg_toplevel.base.data = &self.scene_node_data;

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
    if (self.output == null or !self.xdg_toplevel.base.surface.mapped) return;

    if (self.isFullscreen()) return;

    if (self.pending == null) self.pending = self.current;

    self.pending.?.geometry = .{ .x = x orelse self.current.geometry.x, .y = y orelse self.current.geometry.y, .width = @max(1 + 2 * self.border_width, width orelse self.current.geometry.width), .height = @max(1 + 2 * self.border_width, height orelse self.current.geometry.height) };

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

pub fn applyPending(self: *View, configures: *std.ArrayList(u32)) void {
    std.log.debug("\tApply pending {d}", .{self.id});

    if (self.pending == null) return;
    const pending = &self.pending.?;
    const current = &self.current;

    const is_initial_map = current.geometry.width == 0 and current.geometry.height == 0;

    if (!is_initial_map and !self.saved_surface_tree.children.empty()) {
        std.log.debug("saved surface should be empty but has {d} children", .{self.saved_surface_tree.children.length()});
        return;
    }

    if (!is_initial_map) {
        self.surface_tree.node.forEachBuffer(*wlr.SceneTree, saveSurfaceTreeIter, self.saved_surface_tree);
        self.saved_surface_tree.node.setEnabled(true);
        self.surface_tree.node.setEnabled(false);
    }

    var serial: ?u32 = null;

    // Geometry
    if (!wlr.Box.equal(&pending.geometry, &current.geometry)) {
        self.scene_tree.node.setPosition(pending.geometry.x, pending.geometry.y);
        serial = self.xdg_toplevel.setSize(
            pending.geometry.width - 2 * self.border_width,
            pending.geometry.height - 2 * self.border_width,
        );
        std.log.debug("\t\tGeometry configure {d}", .{self.id});
    }

    // Decoration mode
    if (pending.decoration_mode != current.decoration_mode and self.xdg_toplevel_decoration != null) {
        serial = self.xdg_toplevel_decoration.?.setMode(pending.decoration_mode);
        std.log.debug("\t\tDecoration configure {d}", .{self.id});
    }

    // WM Capabilities
    if (pending.wm_capabilities != current.wm_capabilities) {
        serial = self.xdg_toplevel.setWmCapabilities(pending.wm_capabilities);
        std.log.debug("\t\tCapabilities configure {d}", .{self.id});
    }

    // Activated
    if (pending.activated != current.activated) {
        serial = self.xdg_toplevel.setActivated(pending.activated);

        std.log.debug("\t\tActivated configure {d}", .{self.id});

        // After a view's focus is set
        server.events.exec("ViewSetFocusPost", .{ self.id, pending.activated });
    }

    // Tiling
    if (pending.tiled_edges != current.tiled_edges) {
        serial = self.xdg_toplevel.setTiled(pending.tiled_edges);

        std.log.debug("\t\tTiling configure {d}", .{self.id});
    }

    // self.xdg_toplevel.co
    if (serial) |s| {
        configures.append(gpa, s) catch Utils.oomPanic();
    }

    self.sending = self.pending;
    self.pending = null;
}

fn saveSurfaceTreeIter(buffer: *wlr.SceneBuffer, sx: c_int, sy: c_int, saved_surface_tree: *wlr.SceneTree) void {
    // Create new saved surface tree
    const saved = saved_surface_tree.createSceneBuffer(buffer.buffer) catch Utils.oomPanic();

    // Copy all properties
    saved.node.setPosition(sx, sy);
    saved.setDestSize(buffer.dst_width, buffer.dst_height);
    saved.setSourceBox(&buffer.src_box);
    saved.setTransform(buffer.transform);
}

fn dropSavedSurfaceTree(self: *View) void {
    var buffer_it = self.saved_surface_tree.children.safeIterator(.forward);

    while (buffer_it.next()) |buffer| {
        buffer.destroy();
    }
}

pub fn applySending(self: *View) void {
    std.log.debug("\tApplying sending {d}", .{self.id});

    if (self.sending != null) {
        self.current = self.sending.?;
    }
    self.sending = null;

    self.scene_tree.node.setEnabled(self.current.enabled);

    self.saved_surface_tree.node.setEnabled(false);
    self.surface_tree.node.setEnabled(true);

    self.dropSavedSurfaceTree();

    self.resizeBorders();
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

    if (server.seat.focused_surface) |fs| {
        if (fs == .view and fs.view == view) {
            server.seat.focusSurface(null);
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
        std.log.debug("\t\tInitial commit", .{});

        // Don't call applyPending here - Lua's ViewMapPost will call apply()
        // which will position the view correctly. Calling applyPending() now
        // would position the scene_tree at (0, 0) before Lua can set geometry.
        return;
    }

    // resize on every commit
    view.resizeBorders();
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
    if (std.mem.indexOfScalar(u32, server.root.configures.items, event.serial)) |i| {
        _ = server.root.configures.swapRemove(i);
    }

    std.log.debug("\t\tHandling configure {d} | {d} left", .{ event.serial, server.root.configures.items.len });

    if (server.root.configures.items.len == 0) {
        server.root.applySending();
    }
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
