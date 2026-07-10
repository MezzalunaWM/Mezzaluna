const std = @import("std");
const wlr = @import("wlroots");
const wl = @import("wayland").server.wl;

const Popup = @import("Popup.zig");
const View = @import("View.zig");
const LayerSurface = @import("LayerSurface.zig");
const Output = @import("Output.zig");
const Root = @import("Root.zig");

pub const Data = union(enum) { 
    view: *View,
    view_surface_tree: *View,
    view_saved_tree: *View,
    view_border: *View,
    view_surface: *View,
    view_xdg_surface: *View,

    popup_surface: *Popup,

    hidden_tree: *wlr.SceneTree,

    output: *Output,
    output_layer: *wlr.SceneTree,

    layer_surface: *LayerSurface,

    root: *Root,

    pub fn fromSceneNode(node: *const wlr.SceneNode) *Data {
        std.debug.assert(node.data != null);
        return @ptrCast(@alignCast(node.data.?));
    }

    pub fn fromSurface(surface: *wlr.Surface) *Data {
        std.debug.assert(surface.data != null);
        return @ptrCast(@alignCast(surface.data.?));
    }

    pub fn getTypeName(self: *const Data) []const u8 {
        return switch (self.*) {
            .view => "view",
            .view_surface_tree => "view_surface_tree",
            .view_saved_tree => "view_saved_tree",
            .view_border => "view_border",
            .view_surface => "view_surface",
            .view_xdg_surface => "view_xdg_surface",

            .popup_surface => "popup_surface",

            .hidden_tree => "hidden_tree",

            .output => "output",
            .output_layer => "output_layer",

            .layer_surface => "layer_surface",

            .root => "root"
        };
    }
};

const IteratorConfig = struct { 
    direction: wl.list.Direction = .forward,
    safe: bool = false
};

pub fn Iterator(comptime config: IteratorConfig) type {
    const IteratorImpl = union(enum) {
        iterator: wl.list.Head(wlr.SceneNode, .link).Iterator(config.direction),
        safe_iterator: wl.list.Head(wlr.SceneNode, .link).SafeIterator(config.direction)
    };

    return struct {
        node_iter: ?IteratorImpl,
        trees: []*wlr.SceneTree = undefined,
        tree_idx: usize = 0,

        pub fn fromSceneTree(tree: *wlr.SceneTree) @This() {
            return .{
                .node_iter = if (config.safe) .{ .safe_iterator = tree.children.safeIterator(config.direction) } 
                    else .{ .iterator = tree.children.iterator(config.direction), }
            };
        }

        pub fn fromSceneTrees(trees: []*wlr.SceneTree) @This() {
            return .{
                .node_iter = null,
                .tree_idx = 0,
                .trees = trees
            };
        }
        
        pub fn next(self: *@This()) ?*Data {
            if (self.node_iter) |*it_impl| {
                const node: ?*wlr.SceneNode = if (config.safe) 
                    it_impl.safe_iterator.next() 
                else 
                    it_impl.iterator.next();
                return if (node) |n| Data.fromSceneNode(n) else null;
           }

            if (self.tree_idx < self.trees.len) {
                if (self.node_iter != null)  {
                    self.tree_idx += 1;
                }

                self.node_iter = if (config.safe)
                    .{ .safe_iterator = self.trees[self.tree_idx].children.iterator(config.direction) }
                else
                    .{ .iterator = self.trees[self.tree_idx].children.safeIterator(config.direction) };
            }

            return null;
        }
    };
}
