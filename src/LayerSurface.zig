const LayerSurface = @This();

const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const Utils = @import("Utils.zig");
const Output = @import("Output.zig");
const SceneNodeData = @import("SceneNodeData.zig").SceneNodeData;

const gpa = std.heap.c_allocator;
const server = &@import("main.zig").server;

output: *Output,
scene_node_data: SceneNodeData,
wlr_layer_surface: *wlr.LayerSurfaceV1,
scene_layer_surface: *wlr.SceneLayerSurfaceV1,

destroy: wl.Listener(*wlr.LayerSurfaceV1) = .init(handleDestroy),
map: wl.Listener(void) = .init(handleMap),
unmap: wl.Listener(void) = .init(handleUnmap),
commit: wl.Listener(*wlr.Surface) = .init(handleCommit),
// new_popup: wl.Listener(*wlr.XdgPopup) = wl.Listener(*wlr.XdgPopup).init(handleNewPopup),

pub fn init(wlr_layer_surface: *wlr.LayerSurfaceV1) *LayerSurface {
  errdefer Utils.oomPanic();

  const self = try gpa.create(LayerSurface);

  self.* = .{
    .output = undefined,
    .wlr_layer_surface = wlr_layer_surface,
    .scene_layer_surface = undefined,
    .scene_node_data = .{ .layer_surface = self }
  };

  if(wlr_layer_surface.output.?.data == null) {
    std.log.err("Wlr_output arbitrary data not assigned", .{});
    unreachable;
  }
  self.output = @ptrCast(@alignCast(wlr_layer_surface.output.?.data));

  if(server.seat.focused_output) |output| {
    self.scene_layer_surface = switch (wlr_layer_surface.current.layer) {
      .background => try output.layers.background.createSceneLayerSurfaceV1(wlr_layer_surface),
      .bottom => try output.layers.bottom.createSceneLayerSurfaceV1(wlr_layer_surface),
      .top => try output.layers.top.createSceneLayerSurfaceV1(wlr_layer_surface),
      .overlay => try output.layers.overlay.createSceneLayerSurfaceV1(wlr_layer_surface),
      else => {
        std.log.err("New layer surface of unidentified type", .{});
        unreachable;
      }
    };
  }

  self.wlr_layer_surface.surface.data = &self.scene_node_data;
  self.scene_layer_surface.tree.node.data = &self.scene_node_data;

  self.wlr_layer_surface.events.destroy.add(&self.destroy);
  self.wlr_layer_surface.surface.events.map.add(&self.map);
  self.wlr_layer_surface.surface.events.unmap.add(&self.unmap);
  self.wlr_layer_surface.surface.events.commit.add(&self.commit);

  return self;
}

pub fn deinit(self: *LayerSurface) void {
  self.destroy.link.remove();
  self.map.link.remove();
  self.unmap.link.remove();
  self.commit.link.remove();

  self.wlr_layer_surface.surface.data = null;

  gpa.destroy(self);
}

pub fn allowKeyboard(self: *LayerSurface) void {
  const keyboard_interactive = self.wlr_layer_surface.current.keyboard_interactive;
  if(keyboard_interactive == .exclusive or keyboard_interactive == .on_demand) {
    server.seat.wlr_seat.keyboardNotifyEnter(
      self.wlr_layer_surface.surface,
      &server.seat.wlr_seat.keyboard_state.keyboard.?.keycodes,
      null
    );
  }
}

// --------- LayerSurface event handlers ---------
fn handleDestroy(
  listener: *wl.Listener(*wlr.LayerSurfaceV1),
  _: *wlr.LayerSurfaceV1
) void {
  const layer: *LayerSurface = @fieldParentPtr("destroy", listener);
  layer.deinit();
}

fn handleMap(
  listener: *wl.Listener(void)
) void {
  const layer_suraface: *LayerSurface = @fieldParentPtr("map", listener);
  std.log.debug("layer surface mapped", .{});
  layer_suraface.output.arrangeLayers();
  layer_suraface.allowKeyboard();
}

fn handleUnmap(listener: *wl.Listener(void)) void {
  const layer_surface: *LayerSurface = @fieldParentPtr("unmap", listener);

  if (server.seat.focused_surface) |fs| {
    if (fs == .layer_surface and fs.layer_surface == layer_surface) {
      server.seat.focusSurface(null);
    }
  }

  // FIXME: this crashes mez when killing mez
  layer_surface.output.arrangeLayers();

  // TODO: Idk if this should be deiniting the layer surface entirely
  layer_surface.deinit();
}

fn handleCommit(
  listener: *wl.Listener(*wlr.Surface),
  _: *wlr.Surface
) void {
  const layer_surface: *LayerSurface = @fieldParentPtr("commit", listener);

  if (!layer_surface.wlr_layer_surface.initial_commit) return;
  layer_surface.output.arrangeLayers();
}
