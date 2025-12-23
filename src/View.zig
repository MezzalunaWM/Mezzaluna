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

mapped: bool,
focused: bool,
fullscreen: bool,
id: u64,

// workspace: Workspace,
output: ?*Output,
xdg_toplevel: *wlr.XdgToplevel,
xdg_toplevel_decoration: ?*wlr.XdgToplevelDecorationV1,
scene_tree: *wlr.SceneTree,
scene_node_data: SceneNodeData,

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
    .focused = false,
    .mapped = false,
    .fullscreen = false,
    .id = @intFromPtr(xdg_toplevel),
    .output = null,

    .xdg_toplevel = xdg_toplevel,
    .scene_tree = undefined,
    .xdg_toplevel_decoration = null,

    .scene_node_data = .{ .view = self }
  };

  // Add new Toplevel to root of the tree
  if(server.seat.focused_output) |output| {
    self.scene_tree = try output.layers.content.createSceneXdgSurface(xdg_toplevel.base);
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

  return self;
}

/// tell the client that we're removing it
pub fn close(self: *View) void {
  self.xdg_toplevel.sendClose();
}

pub fn toggleFullscreen(self: *View) void {
  self.fullscreen = !self.fullscreen;
  if(self.output) |output| {
    if(self.fullscreen and output.fullscreen != self) {
      // Check to see if another fullscreened view exists, if so replace it
      if(output.getFullscreenedView()) |view| {
        view.toggleFullscreen();
      }

      self.scene_tree.node.reparent(output.layers.fullscreen);
      self.setPosition(0, 0);
      self.setSize(output.wlr_output.width, output.wlr_output.height);
      output.fullscreen = self;
    } else {
      self.scene_tree.node.reparent(output.layers.content);
      output.fullscreen = null;
    }
  }
  _ = self.xdg_toplevel.setFullscreen(self.fullscreen);
}

pub fn setPosition(self: *View, x: i32, y: i32) void {
  self.scene_tree.node.setPosition(x, y);
}

pub fn setSize(self: *View, width: i32, height: i32) void {
  // This returns a configure serial for verifying the configure
  _ = self.xdg_toplevel.setSize(width, height);
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

  view.xdg_toplevel.events.request_fullscreen.add(&view.request_fullscreen);
  view.xdg_toplevel.events.request_move.add(&view.request_move);
  view.xdg_toplevel.events.request_resize.add(&view.request_resize);
  view.xdg_toplevel.events.set_app_id.add(&view.set_app_id);
  view.xdg_toplevel.events.set_title.add(&view.set_title);
  // view.xdg_toplevel.events.set_parent.add(&view.set_parent);

  const xdg_surface = view.xdg_toplevel.base;
  server.seat.wlr_seat.keyboardNotifyEnter(
    xdg_surface.surface,
    &server.seat.keyboard_group.keyboard.keycodes,
    &server.seat.keyboard_group.keyboard.modifiers
  );

  view.mapped = true;
  server.events.exec("ViewMapPost", .{view.id});
}

fn handleUnmap(listener: *wl.Listener(void)) void {
  const view: *View = @fieldParentPtr("unmap", listener);
  std.log.debug("Unmapping view '{s}'", .{view.xdg_toplevel.title orelse "(unnamed)"});

  server.events.exec("ViewUnmapPre", .{view.id});
  view.mapped = false; // we do this before any work is done so that nobody tries
                       // any funny business

  view.request_fullscreen.link.remove();
  view.request_move.link.remove();
  view.request_resize.link.remove();
  view.set_title.link.remove();
  view.set_app_id.link.remove();
  view.ack_configure.link.remove();

  server.events.exec("ViewUnmapPost", .{view.id});
}

fn handleDestroy(listener: *wl.Listener(void)) void {
  const view: *View = @fieldParentPtr("destroy", listener);

  // Remove decorations

  view.map.link.remove();
  view.unmap.link.remove();
  view.commit.link.remove();
  view.destroy.link.remove();
  view.new_popup.link.remove();

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
      _ = view.xdg_toplevel.setWmCapabilities(.{ .fullscreen = true, });
    }

    // before committing we tell the client that we'll handle the decorations
    if (view.xdg_toplevel_decoration) |deco| _ = deco.setMode(.server_side);

    // this tells the client that it can start doing things
    view.setSize(0, 0);
  }
}

// --------- XdgToplevel Event Handlers ---------
fn handleNewPopup(listener: *wl.Listener(*wlr.XdgPopup), xdg_popup: *wlr.XdgPopup) void {
  const view: *View = @fieldParentPtr("new_popup", listener);
  _ = Popup.init(xdg_popup, view.scene_tree);
}

fn handleRequestMove(
  listener: *wl.Listener(*wlr.XdgToplevel.event.Move),
  _: *wlr.XdgToplevel.event.Move
) void {
  const view: *View = @fieldParentPtr("request_move", listener);
  server.events.exec("ViewRequestMove", .{view.id});
}

fn handleRequestResize(
  listener: *wl.Listener(*wlr.XdgToplevel.event.Resize),
  _: *wlr.XdgToplevel.event.Resize
) void {
  const view: *View = @fieldParentPtr("request_resize", listener);
  server.events.exec("ViewRequestResize", .{view.id});
}

fn handleAckConfigure(
  listener: *wl.Listener(*wlr.XdgSurface.Configure),
  _: *wlr.XdgSurface.Configure,
) void {
  const view: *View = @fieldParentPtr("ack_configure", listener);
  _ = view;
  std.log.err("Unimplemented ack configure", .{});
}

fn handleRequestFullscreen(
  listener: *wl.Listener(void)
) void {
  const view: *View = @fieldParentPtr("request_fullscreen", listener);
  server.events.exec("ViewRequestFullscreen", .{view.id});
}

fn handleRequestMinimize(
  listener: *wl.Listener(void)
) void {
  const view: *View = @fieldParentPtr("request_minimize", listener);
  server.events.exec("ViewRequestMinimize", .{view.id});
  std.log.debug("request_minimize unimplemented", .{});
}

fn handleSetAppId(
  listener: *wl.Listener(void)
) void {
  const view: *View = @fieldParentPtr("set_app_id", listener);
  server.events.exec("ViewAppIdUpdate", .{view.id});
  std.log.debug("request_set_app_id unimplemented", .{});
}

fn handleSetTitle(
  listener: *wl.Listener(void)
) void {
  const view: *View = @fieldParentPtr("set_title", listener);
  server.events.exec("ViewTitleUpdate", .{view.id});
  std.log.debug("request_set_title unimplemented", .{});
}
