const std = @import("std");
const wlr = @import("wlroots");
const wl = @import("wayland").server.wl;

const View = @import("View.zig");
const LayerSurface = @import("LayerSurface.zig");
const Output = @import("Output.zig");
const Root = @import("Root.zig");

pub const Data = union(enum) {
    view: *View,
    layer_surface: *LayerSurface,
    output: *Output,
    output_layer: *wlr.SceneTree,
    root: *Root
};

pub fn Iterator(comptime direction: wl.list.Direction) type {
    return struct {
        trees: []*wlr.SceneTree,
        node_iter: wl.list.Head(wlr.SceneNode, .link).Iterator(direction),
        i: u32,
        pub fn next(self: *@This()) ?*Data {
            if (self.i >= self.trees.len) return null;
            self.node_iter = self.trees[self.i].children.iterator(direction);
            if (self.trees[self.i].children.length() == 0) {
                self.i += 1;
                return self.next();
            }

            while (self.node_iter.next()) |node| {
                if (node.data == null) continue;
                return @ptrCast(@alignCast(node.data.?));
            }

            self.i += 1;
            return self.next();
        }
    };
}

pub fn iterator(
    trees: []*wlr.SceneTree,
    comptime direction: wl.list.Direction,
) Iterator(direction) {
    return .{
        .i = 0,
        .trees = trees,
        .node_iter = trees[0].children.iterator(direction),
    };
}
