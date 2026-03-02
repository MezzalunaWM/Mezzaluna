const wlr = @import("wlroots");

const View = @import("View.zig");
const LayerSurface = @import("LayerSurface.zig");
const Output = @import("Output.zig");
const Root = @import("Root.zig");

pub const SceneNodeData = union(enum) { view: *View, layer_surface: *LayerSurface, output: *Output, output_layer: *wlr.SceneTree, root: *Root };
