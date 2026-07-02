const wlr = @import("wlroots");

const View = @import("View.zig");
const LayerSurface = @import("LayerSurface.zig");
const Output = @import("Output.zig");
const Root = @import("Root.zig");

const SceneNodeDataType = enum {
    view,
    view_surface_tree,
    view_saved_tree,
    view_border,
    view_surface,
    view_xdg_surface,
    hidden_tree,
    output,
    output_layer,
    layer_surface,
    root
};

pub const SceneNodeData = union(SceneNodeDataType) { 
    view: *View,
    view_surface_tree: *View,
    view_saved_tree: *View,
    view_border: *View,
    view_surface: *View,
    view_xdg_surface: *View,

    hidden_tree: *wlr.SceneTree,

    output: *Output,
    output_layer: *wlr.SceneTree,

    layer_surface: *LayerSurface,

    root: *Root,
};
