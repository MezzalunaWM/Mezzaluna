const LayerSurface = @This();

const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const Utils = @import("Utils.zig");
const Output = @import("Output.zig");
const SceneNode = @import("SceneNode.zig");

const gpa = &@import("main.zig").gpa;
const server = &@import("main.zig").server;

layer_surface_snd: SceneNode.Data,
wlr_layer_surface: *wlr.LayerSurfaceV1,
scene_layer_surface: *wlr.SceneLayerSurfaceV1,

destroy: wl.Listener(*wlr.LayerSurfaceV1) = .init(handleDestroy),
map: wl.Listener(void) = .init(handleMap),
unmap: wl.Listener(void) = .init(handleUnmap),
commit: wl.Listener(*wlr.Surface) = .init(handleCommit),
// new_popup: wl.Listener(*wlr.XdgPopup) = wl.Listener(*wlr.XdgPopup).init(handleNewPopup),

pub fn init(wlr_layer_surface: *wlr.LayerSurfaceV1) *LayerSurface {
    errdefer wlr_layer_surface.destroy();
    errdefer Utils.oomPanic();

    const self = try gpa.create(LayerSurface);

    self.* = .{
        .wlr_layer_surface = wlr_layer_surface,
        .scene_layer_surface = undefined,
        .layer_surface_snd = .{ .layer_surface = self },
    };

    self.scene_layer_surface = blk: {
        inline for (std.meta.fields(@TypeOf(wlr_layer_surface.current.layer))) |field| {
            if (std.mem.eql(u8, @tagName(wlr_layer_surface.current.layer), field.name)) {
                const layer = @field(self.getOutput().layers, field.name);
                break :blk try layer.createSceneLayerSurfaceV1(wlr_layer_surface);
            }
        }
        std.debug.panic("New layer surface which we do not support: `{s}`", .{
            @tagName(wlr_layer_surface.current.layer),
        });
    };

    self.wlr_layer_surface.surface.data = &self.layer_surface_snd;
    self.scene_layer_surface.tree.node.data = &self.layer_surface_snd;

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

pub fn getOutput(self: *LayerSurface) *Output {
    return @alignCast(@ptrCast(self.wlr_layer_surface.output.?.data));
}

// --------- LayerSurface event handlers ---------
fn handleDestroy(listener: *wl.Listener(*wlr.LayerSurfaceV1), _: *wlr.LayerSurfaceV1) void {
    const layer: *LayerSurface = @fieldParentPtr("destroy", listener);
    layer.deinit();
}

fn handleMap(listener: *wl.Listener(void)) void {
    const layer_suraface: *LayerSurface = @fieldParentPtr("map", listener);
    layer_suraface.getOutput().arrangeLayers();
    if (layer_suraface.wlr_layer_surface.current.keyboard_interactive != .none) {
        server.getDefaultSeat().focusSurface(.{ .layer_surface = layer_suraface });
    }
}

fn handleUnmap(listener: *wl.Listener(void)) void {
    const layer_surface: *LayerSurface = @fieldParentPtr("unmap", listener);

    if (server.getDefaultSeat().focused_surface) |fs| {
        if (fs == .layer_surface and fs.layer_surface == layer_surface) {
            server.getDefaultSeat().focusSurface(null);
        }
    }

    // FIXME: this crashes mez when killing mez
    layer_surface.getOutput().arrangeLayers();

    // TODO: Idk if this should be deiniting the layer surface entirely
    layer_surface.deinit();
}

fn handleCommit(listener: *wl.Listener(*wlr.Surface), _: *wlr.Surface) void {
    const layer_surface: *LayerSurface = @fieldParentPtr("commit", listener);

    if (!layer_surface.wlr_layer_surface.initial_commit) return;
    layer_surface.getOutput().arrangeLayers();
}
