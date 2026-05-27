const wlr = @import("wlroots");

const View = @import("View.zig");
const LayerSurface = @import("LayerSurface.zig");
const Output = @import("Output.zig");
const Root = @import("Root.zig");

pub const SceneNodeData = union(enum) { 
    view: *View,
    view_surface_tree: *View,
    view_saved_tree: *View,
    view_border: *View,
    view_surface: *View,

    output: *Output,
    output_layer: *wlr.SceneTree,

    layer_surface: *LayerSurface,

    root: *Root
};
