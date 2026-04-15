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

id: u64,

output: ?*Output,

xdg_toplevel: *wlr.XdgToplevel,
xdg_toplevel_decoration: ?*wlr.XdgToplevelDecorationV1,

scene_tree: *wlr.SceneTree,
surface_tree: *wlr.SceneTree,
scene_node_data: SceneNodeData,

borders: [4]*wlr.SceneRect,
border_width: i32,
geometry: wlr.Box, // The total geometry including borders

previous_geometry: wlr.Box,

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

// Do we need to add these
// request_show_window_menu: wl.Listener(comptime T: type) = .init(handleRequestShowWindowMenu),
// request_minimize: wl.Listener(comptime T: type) = .init(handleRequestMinimize),
// request_maximize: wl.Listener(comptime T: type) = .init(handleRequestMaximize),

set_app_id: wl.Listener(void) = .init(handleSetAppId),
set_title: wl.Listener(void) = .init(handleSetTitle),

// Do we need to add this
// set_parent: wl.Listener(void) = .init(handleSetParent),

pub fn init(xdg_toplevel: *wlr.XdgToplevel) *View {
    errdefer Utils.oomPanic();

    const self = try gpa.create(View);
    errdefer gpa.destroy(self);

    self.* = .{
        .id = @intFromPtr(xdg_toplevel),
        .output = null,
        .geometry = .{ .width = 0, .height = 0, .x = 0, .y = 0 },
        .previous_geometry = .{ .width = 0, .height = 0, .x = 0, .y = 0 },
        .xdg_toplevel = xdg_toplevel,
        .scene_tree = undefined,
        .surface_tree = undefined,
        .xdg_toplevel_decoration = null,
        .borders = undefined,
        .border_width = 0,
        .scene_node_data = .{ .view = self },
    };

    // Add new Toplevel to root of the tree
    if (server.getDefaultSeat().focused_output) |output| {
        self.scene_tree = try output.layers.content.createSceneTree();
        self.surface_tree = try self.scene_tree.createSceneXdgSurface(xdg_toplevel.base);
        self.output = output;
    }

    self.scene_tree.node.data = &self.scene_node_data;
    self.xdg_toplevel.base.data = &self.scene_node_data;

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

    for (self.borders, 0..) |_, i| {
        const color: [4]f32 = .{ 0, 0, 0, 1 };
        self.borders[i] = try wlr.SceneTree.createSceneRect(self.scene_tree, 0, 0, &color);
        self.borders[i].node.data = self;
    }

    return self;
}

// Tell the client to close
// It better behave!
pub fn close(self: *View) void {
    if(self.isFullscreen()) {
        self.toggleFullscreen();
    }

    self.xdg_toplevel.sendClose();
}

pub fn setBorderColor(self: *View, color: *const [4]f32) void {
    for (self.borders) |border| border.setColor(color);
}

pub fn isFullscreen(self: *View) bool {
    if(self.output == null) {
        std.log.debug("View does not have an assigned output", .{});
        unreachable;
    }

    for(self.output.?.fullscreens.items) |view| {
        if(view == self) return true;
    }

    return false;
}

pub fn toggleFullscreen(self: *View) void {
    if(self.output == null) {
        std.log.debug("View {d} has no output to fullscreen on", .{self.id});
        return;
    }

    const fullscreens = &self.output.?.fullscreens;
    if(self.output.?.getEnabledFullscreen() == self) {
        // ViewSetFullscreenPre
        // Before making a view fullscreen within it's output
        // passed view_id and true `true` if being fullscreened `false` otherwise
        server.events.exec("ViewSetFullscreenPre", .{self.id, false});

        self.scene_tree.node.reparent(self.output.?.layers.content);

        // ViewSetFullscreenPost
        // After making a view fullscreen within it's output
        // passed view_id and true `true` if being fullscreened `false` otherwise
        server.events.exec("ViewSetFullscreenPost", .{self.id, false});

        if (std.mem.indexOfScalar(*View, fullscreens.items, self)) |i| {
            _ = self.output.?.fullscreens.swapRemove(i);
        }
        _ = self.xdg_toplevel.setFullscreen(false);
        return;
    }

    // Check to see if another enabled fullscreen view exists, if so replace it
    if (self.output.?.getEnabledFullscreen()) |v| {
        _ = v.toggleFullscreen();
    }

    server.events.exec("ViewSetFullscreenPre", .{self.id, true});
    self.scene_tree.node.reparent(self.output.?.layers.top);

    self.setGeometry(0, 0, self.output.?.wlr_output.width, self.output.?.wlr_output.height);

    fullscreens.append(gpa, self) catch Utils.oomPanic();
    _ = self.xdg_toplevel.setFullscreen(true);
    server.events.exec("ViewSetFullscreenPost", .{self.id, true});
}

// Null values are set to their corresponding current geometry values
pub fn setGeometry(self: *View, x: ?i32, y: ?i32, width: ?i32, height: ?i32) void {
    if (self.output == null or !self.xdg_toplevel.base.surface.mapped) return;

    if(self.isFullscreen()) return;

    self.previous_geometry = self.geometry;

    self.geometry = .{
        .x = x orelse self.geometry.x,
        .y = y orelse self.geometry.y,
        .width = @max(1 + 2 * self.border_width, width orelse self.geometry.width),
        .height = @max(1 + 2 * self.border_width, height orelse self.geometry.height)
    };

    self.scene_tree.node.setPosition(self.geometry.x, self.geometry.y);
    _ = self.xdg_toplevel.setSize(
        self.geometry.width - 2 * self.border_width,
        self.geometry.height - 2 * self.border_width,
    );

    self.resizeBorders();
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
        .width = self.geometry.width - 2 * self.border_width,
        .height = self.geometry.height - 2 * self.border_width,
    });

    self.borders[0].setSize(self.geometry.width, self.border_width);
    self.borders[1].setSize(self.geometry.width, self.border_width);
    self.borders[2].setSize(self.border_width, self.geometry.height);
    self.borders[3].setSize(self.border_width, self.geometry.height);
    self.borders[1].node.setPosition(0, self.geometry.height - self.border_width);
    self.borders[2].node.setPosition(self.geometry.width - self.border_width, 0);
}

pub fn setActivated(self: *View, activated: bool) void {
    // Before a view's focus is set
    server.events.exec("ViewSetFocusPre", .{ self.id, activated });
    _ = self.xdg_toplevel.setActivated(activated);
    // After a view's focus is set
    server.events.exec("ViewSetFocusPost", .{ self.id, activated });
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

    server.events.exec("ViewMapPre", .{view.id});

    // we're gonna tell the client that it's tiled so it doesn't try anything
    // stupid
    _ = view.xdg_toplevel.setTiled(.{
        .top = true,
        .bottom = true,
        .left = true,
        .right = true,
    });

    server.events.exec("ViewMapPost", .{view.id});
}

fn handleUnmap(listener: *wl.Listener(void)) void {
    const view: *View = @fieldParentPtr("unmap", listener);
    std.log.debug("Unmapping view '{s}'", .{view.xdg_toplevel.title orelse "(unnamed)"});

    server.events.exec("ViewUnmapPre", .{view.id});

    var iter = server.seats.iterator(.forward);
    while (iter.next()) |seat| {
        if (seat.focused_surface) |fs| {
            if (fs == .view and fs.view == view) seat.focusSurface(null);
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

    // On the first commit, send a configure to tell the client it can proceed
    if (view.xdg_toplevel.base.initial_commit) {

        // 5 is the XDG_TOPLEVEL_WM_CAPABILITIES_SINCE_VERSION, I'm just not sure where it is in the bindings
        if (view.xdg_toplevel.base.client.shell.version >= 5) {
            // the client should know that it can only fullscreen, nothing else
            _ = view.xdg_toplevel.setWmCapabilities(.{
                .fullscreen = true,
            });
        }

        // before committing we tell the client that we'll handle the decorations
        if (view.xdg_toplevel_decoration) |deco| _ = deco.setMode(.server_side);

        // this tells the client that it can start doing things we don't use our
        // wrapper here cause we don't want to enforce any of our rules
        _ = view.xdg_toplevel.setSize(0, 0);
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
    listener: *wl.Listener(*wlr.XdgSurface.Configure),
    _: *wlr.XdgSurface.Configure,
) void {
    const view: *View = @fieldParentPtr("ack_configure", listener);
    _ = view;
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
    std.log.debug("request_set_app_id unimplemented", .{});
}

fn handleSetTitle(listener: *wl.Listener(void)) void {
    const view: *View = @fieldParentPtr("set_title", listener);
    server.events.exec("ViewTitleUpdate", .{view.id});
    std.log.debug("request_set_title unimplemented", .{});
}
