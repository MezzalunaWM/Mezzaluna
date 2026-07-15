const std = @import("std");
const wlr = @import("wlroots");
const wl = @import("wayland").server.wl;

const Popup = @import("Popup.zig");
const View = @import("View.zig");
const LayerSurface = @import("LayerSurface.zig");
const Output = @import("Output.zig");
const Root = @import("Root.zig");

const log = std.log.scoped(.SceneNode);

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
        return @tagName(self.*);
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

        pub fn fromSceneTree(tree: *wlr.SceneTree) @This() {
            return .{
                .node_iter = switch (config.safe) {
                    true => .{ .safe_iterator = tree.children.safeIterator(config.direction) },
                    false => .{ .iterator = tree.children.iterator(config.direction) }
                }
            };
        }
        
        pub fn next(self: *@This()) ?*Data {
            if (self.node_iter) |*it_impl| {
                const node: ?*wlr.SceneNode = switch (config.safe) {
                    true => it_impl.safe_iterator.next(),
                    false => it_impl.iterator.next()
                };

                return if (node) |n| Data.fromSceneNode(n) else null;
            }

            return null;
        }
    };
}
