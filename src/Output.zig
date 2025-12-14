const Output = @This();

const wl = @import("wayland").server.wl;
const zwlr = @import("wayland").server.zwlr;
const wlr = @import("wlroots");
const std = @import("std");

const Utils =  @import("Utils.zig");

const Server = @import("Server.zig");
const View =   @import("View.zig");
const LayerSurface = @import("LayerSurface.zig");

const SceneNodeData = @import("SceneNodeData.zig").SceneNodeData;

const posix = std.posix;
const gpa = std.heap.c_allocator;
const server = &@import("main.zig").server;

focused: bool,
id: u64,

wlr_output: *wlr.Output,
state: wlr.Output.State,
tree: *wlr.SceneTree,
scene_node_data: SceneNodeData,
scene_output: *wlr.SceneOutput,

layers: struct {
  background: *wlr.SceneTree,
  bottom: *wlr.SceneTree,
  content: *wlr.SceneTree,
  top: *wlr.SceneTree,
  fullscreen: *wlr.SceneTree,
  overlay: *wlr.SceneTree
},

layer_scene_node_data: struct {
  background: SceneNodeData,
  bottom: SceneNodeData,
  content: SceneNodeData,
  top: SceneNodeData,
  fullscreen: SceneNodeData,
  overlay: SceneNodeData
},

frame: wl.Listener(*wlr.Output) = .init(handleFrame),
request_state: wl.Listener(*wlr.Output.event.RequestState) = .init(handleRequestState),
destroy: wl.Listener(*wlr.Output) = .init(handleDestroy),


// The wlr.Output should be destroyed by the caller on failure to trigger cleanup.
pub fn init(wlr_output: *wlr.Output) ?*Output {
  errdefer Utils.oomPanic();

  server.events.exec("OutputInitPre", .{});

  const self = try gpa.create(Output);

  self.* = .{
    .focused = false,
    .id = @intFromPtr(wlr_output),
    .wlr_output = wlr_output,
    .tree = try server.root.scene.tree.createSceneTree(),
    .layers = .{
      .background = try self.tree.createSceneTree(),
      .bottom = try self.tree.createSceneTree(),
      .content = try self.tree.createSceneTree(),
      .top = try self.tree.createSceneTree(),
      .fullscreen = try self.tree.createSceneTree(),
      .overlay = try self.tree.createSceneTree(),
    },
    .layer_scene_node_data = .{
      .background = .{ .output_layer = self.layers.background },
      .bottom = .{ .output_layer = self.layers.bottom },
      .content = .{ .output_layer = self.layers.content },
      .top = .{ .output_layer = self.layers.top },
      .fullscreen = .{ .output_layer = self.layers.fullscreen },
      .overlay = .{ .output_layer = self.layers.overlay }
    },
    .scene_output = try server.root.scene.createSceneOutput(wlr_output),
    .scene_node_data = SceneNodeData{ .output = self },
    .state = wlr.Output.State.init()
  };

  wlr_output.events.frame.add(&self.frame);
  wlr_output.events.request_state.add(&self.request_state);
  wlr_output.events.destroy.add(&self.destroy);

  errdefer deinit(self);

  if(!wlr_output.initRender(server.allocator, server.renderer)) {
    std.log.err("Unable to start output {s}", .{wlr_output.name});
    return null;
  }

  self.state.setEnabled(true);

  if (wlr_output.preferredMode()) |mode| {
    self.state.setMode(mode);
  }

  if(!wlr_output.commitState(&self.state)) {
    std.log.err("Unable to commit state to output {s}", .{wlr_output.name});
    return null;
  }

  const layout_output = try server.root.output_layout.addAuto(self.wlr_output);
  server.root.scene_output_layout.addOutput(layout_output, self.scene_output);
  self.setFocused();

  self.wlr_output.data = &self.scene_node_data;
  self.tree.node.data = &self.scene_node_data;

  self.layers.background.node.data = &self.layer_scene_node_data.background;
  self.layers.bottom.node.data = &self.layer_scene_node_data.bottom;
  self.layers.content.node.data = &self.layer_scene_node_data.content;
  self.layers.top.node.data = &self.layer_scene_node_data.top;
  self.layers.fullscreen.node.data = &self.layer_scene_node_data.fullscreen;
  self.layers.overlay.node.data = &self.layer_scene_node_data.overlay;

  server.events.exec("OutputInitPost", .{self.id});

  return self;
}

pub fn deinit(self: *Output) void {
  server.events.exec("OutputDeinitPre", .{self.id});

  self.frame.link.remove();
  self.request_state.link.remove();
  self.destroy.link.remove();

  self.state.finish();

  self.wlr_output.destroy();

  server.events.exec("OutputDeinitPost", .{});

  gpa.destroy(self);
}

pub fn setFocused(self: *Output) void {
  if(server.seat.focused_output) |prev_output| {
    prev_output.focused = false;
  }

  server.seat.focused_output = self;
  self.focused = true;
}

pub fn configureLayers(self: *Output) void {
  var output_box: wlr.Box = .{
    .x = 0,
    .y = 0,
    .width = undefined,
    .height = undefined,
  };
  self.wlr_output.effectiveResolution(&output_box.width, &output_box.height);

  // Should calculate usable area here for LUA view positioning
  for ([_]zwlr.LayerShellV1.Layer{ .background, .bottom, .top, .overlay }) |layer| {
    const tree = blk: {
      const trees = [_]*wlr.SceneTree{
          self.layers.background,
          self.layers.bottom,
          self.layers.top,
          self.layers.overlay,
      };
      break :blk trees[@intCast(@intFromEnum(layer))];
    };

    var it = tree.children.iterator(.forward);
    while(it.next()) |node| {
      if(node.data == null) continue;

      const scene_node_data: *SceneNodeData = @ptrCast(@alignCast(node.data.?));
      switch (scene_node_data.*) {
        .layer_surface => {
          _ = scene_node_data.layer_surface.wlr_layer_surface.configured(
            @intCast(output_box.width),
            @intCast(output_box.height)
          );
        },
        else => {
          std.log.err("Something other than a layer surface found in layer surface scene trees", .{});
          unreachable;
        }
      }
    }
  }
}

const SurfaceAtResult = struct {
    scene_node_data: *SceneNodeData,
    surface: *wlr.Surface,
    sx: f64,
    sy: f64,
};

pub fn surfaceAt(self: *Output, lx: f64, ly: f64) ?SurfaceAtResult {
  var sx: f64 = undefined;
  var sy: f64 = undefined;

  const layers = [_]*wlr.SceneTree{
    self.layers.top,
    self.layers.overlay,
    self.layers.fullscreen,
    self.layers.content,
    self.layers.bottom,
    self.layers.background
  };

  for(layers) |layer| {
    const node = layer.node.at(lx, ly, &sx, &sy);
    if(node == null) continue;

    const surface: ?*wlr.Surface = blk: {
      if (node.?.type == .buffer) {
        const scene_buffer = wlr.SceneBuffer.fromNode(node.?);
        if (wlr.SceneSurface.tryFromBuffer(scene_buffer)) |scene_surface| {
          break :blk scene_surface.surface;
        }
      }
      break :blk null;
    };
    if(surface == null) continue;

    const scene_node_data: *SceneNodeData = blk: {
      var n = node.?;
      while (true) {
        if (@as(?*SceneNodeData, @ptrCast(@alignCast(n.data)))) |snd| {
          break :blk snd;
        }
        if (n.parent) |parent_tree| {
          n = &parent_tree.node;
        } else {
          continue;
        }
      }
    };

    switch (scene_node_data.*) {
      .layer_surface, .view => {
        return SurfaceAtResult{
          .scene_node_data = scene_node_data,
          .surface = surface.?,
          .sx = sx,
          .sy = sy,
        };
      },
      else => continue
    }
  }

  return null;
}

// --------- WlrOutput Event Handlers ---------
fn handleRequestState(
  listener: *wl.Listener(*wlr.Output.event.RequestState),
  event: *wlr.Output.event.RequestState,
) void {
  const output: *Output = @fieldParentPtr("request_state", listener);

  if (!output.wlr_output.commitState(event.state)) {
    std.log.warn("failed to set output state {}", .{event.state});
  }
}

fn handleFrame(
  _: *wl.Listener(*wlr.Output),
  wlr_output: *wlr.Output
) void {
  const scene_output = server.root.scene.getSceneOutput(wlr_output);

  if(scene_output == null) {
    std.log.err("Unable to get scene output to render", .{});
    return;
  }

  // std.log.info("Rendering commited scene output\n", .{});
  _ = scene_output.?.commit(null);

  var now = posix.clock_gettime(posix.CLOCK.MONOTONIC) catch @panic("CLOCK_MONOTONIC not supported");
  scene_output.?.sendFrameDone(&now);
}

fn handleDestroy(
  listener: *wl.Listener(*wlr.Output),
  _: *wlr.Output
) void {
  std.log.debug("Handling destroy", .{});
  const output: *Output = @fieldParentPtr("destroy", listener);

  std.log.debug("removing output: {s}", .{output.wlr_output.name});

  output.frame.link.remove();
  output.request_state.link.remove();
  output.destroy.link.remove();

  server.root.output_layout.remove(output.wlr_output);

  gpa.destroy(output);
}

pub fn arrangeLayers(self: *Output) void {
  const debug = @import("Debug.zig");
  debug.debugPrintSceneTree();

  var full_box: wlr.Box = .{
    .x = 0,
    .y = 0,
    .width = undefined,
    .height = undefined,
  };
  self.wlr_output.effectiveResolution(&full_box.width, &full_box.height);

  inline for (@typeInfo(zwlr.LayerShellV1.Layer).@"enum".fields) |comptime_layer| {
    const layer: *wlr.SceneTree = @field(self.layers, comptime_layer.name);
    var it = layer.children.safeIterator(.forward);

    while (it.next()) |node| {
      if (@as(?*SceneNodeData, @alignCast(@ptrCast(node.data)))) |node_data| {
        const scene_node_data: *SceneNodeData = @ptrCast(@alignCast(node.data.?));

        const layer_surface: *LayerSurface = switch(node_data.*) {
          .layer_surface => @fieldParentPtr("scene_node_data", scene_node_data),
          else => continue
        };

        if (!layer_surface.wlr_layer_surface.initialized) continue;

        // TEST: river seems to try and prevent clients from taking an
        // exclusive size greater than half the screen by killing them. Do we
        // need to? Clients can do quite a bit of nasty stuff and taking
        // exclusive focus isn't even that bad.

        layer_surface.scene_layer_surface.configure(&full_box, &full_box);

        // TEST: are these calls useless?
        // const x = layer_surface.scene_layer_surface.tree.node.x;
        // const y = layer_surface.scene_layer_surface.tree.node.y;
        // layer_surface.scene_layer_surface.tree.node.setPosition(x, y);
      }
    }
  }
}
