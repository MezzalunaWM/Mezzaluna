const wlr = @import("wlroots");

const View = @import("View.zig");
const LayerSurface = @import("LayerSurface.zig");
const Output = @import("Output.zig");
const Root = @import("Root.zig");

const SceneNodeType = enum {
  view,
  layer_surface,
  output,
  output_layer,
  root
};

pub const SceneNodeData = union(SceneNodeType) {
  view: *View,
  layer_surface: *LayerSurface,
  output: *Output,
  output_layer: *wlr.SceneTree,
  root: *Root
};
