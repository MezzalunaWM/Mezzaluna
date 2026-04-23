const ViewNew = @This();

const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const Output = @import("Output.zig");
const Popup = @import("Popup.zig");
const Utils = @import("Utils.zig");

const XdgToplevel = @import("XdgToplevel.zig");
const LayerSurface = @import("LayerSurface.zig");
const XwaylandSurface = @import("XwaylandSurface.zig");

const gpa = std.heap.c_allocator;
const server = &@import("main.zig").server;

pub const Surface = union(enum) {
    xdg: *wlr.Surface,
    x11: *wlr.XwaylandSurface,
};

id: u64,
output: ?*Output,

scene_tree: *wlr.SceneTree,
surface_tree: *wlr.SceneTree,
surface: Surface,

borders: [4]*wlr.SceneRect,
border_width: i32,

geometry: wlr.Box, // The total geometry including borders
previous_geometry: wlr.Box, // the last applied geometry

// impl agnostic listeners
map: wl.Listener(void) = .init(handleMap),
unmap: wl.Listener(void) = .init(handleUnmap),
commit: wl.Listener(*wlr.Surface) = .init(handleCommit),
destroy: wl.Listener(void) = .init(handleDestroy),

pub fn init(surface: Surface) *ViewNew {
    const self = gpa.create(ViewNew) catch Utils.oomPanic();
    errdefer gpa.destroy(self);

    self.* = .{
        .id = @intFromPtr(self),
        .surface = surface,
        .output = null,
        .geometry = .{ .width = 0, .height = 0, .x = 0, .y = 0 },
        .previous_geometry = self.geometry,
        .scene_tree = undefined,
        .surface_tree = undefined,
    };

    if (server.getDefaultSeat().focused_output) |output| {
        self.output = output;
        self.scene_tree = try output.layers.content.createSceneTree();
        self.surface_tree = switch (self.surface) {
            .xdg => |xdg| try self.scene_tree.createSceneXdgSurface(xdg),
            .x11 => |x11| try self.scene_tree.createSceneSubsurfaceTree(x11),
        };
    }
}

fn handleMap(listener: *wl.Listener(void)) void {
    const self: ViewNew = @fieldParentPtr("map", listener);
    _ = self;
}

fn handleUnmap(listener: *wl.Listener(void)) void {
    const self: ViewNew = @fieldParentPtr("unmap", listener);
    _ = self;
}

fn handleCommit(listener: *wl.Listener(*wlr.Surface), _: *wlr.Surface) void {
    const self: ViewNew = @fieldParentPtr("commit", listener);
    _ = self;
}

fn handleDestroy(listener: *wl.Listener(void)) void {
    const self: ViewNew = @fieldParentPtr("destroy", listener);
    _ = self;
}
