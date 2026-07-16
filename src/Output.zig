const wl = @import("wayland").server.wl;
const zwlr = @import("wayland").server.zwlr;
const wlr = @import("wlroots");
const std = @import("std");

const Utils = @import("Utils.zig");

const Server = @import("Server.zig");
const Root = @import("Root.zig");
const View = @import("View.zig");
const LayerSurface = @import("LayerSurface.zig");

const SceneNode = @import("SceneNode.zig");

const gpa = &@import("main.zig").gpa;
const server = &@import("main.zig").server;
const log = std.log.scoped(.Output);

const Output = @This();

id: u64,
fullscreens: std.ArrayList(*View),

wlr_output: *wlr.Output,
scene_output: *wlr.SceneOutput,
output_snd: SceneNode.Data,
non_exclusive_area: wlr.Box,

layers: struct {
    background: *wlr.SceneTree,
    bottom: *wlr.SceneTree,
    content: *wlr.SceneTree,
    top: *wlr.SceneTree,
    overlay: *wlr.SceneTree,
},

layers_snd: struct {
    background: SceneNode.Data,
    bottom: SceneNode.Data,
    content: SceneNode.Data,
    top: SceneNode.Data,
    overlay: SceneNode.Data,
},

frame: wl.Listener(*wlr.Output) = .init(handleFrame),
request_state: wl.Listener(*wlr.Output.event.RequestState) = .init(handleRequestState),
destroy: wl.Listener(*wlr.Output) = .init(handleDestroy),

// The wlr.Output should be destroyed by the caller on failure to trigger cleanup.
pub fn init(wlr_output: *wlr.Output) ?*Output {
    errdefer Utils.oomPanic();

    if (!wlr_output.initRender(server.allocator, server.renderer)) {
        log.err("Unable to start output {s}", .{wlr_output.name});
        return null;
    }

    const self = try gpa.create(Output);
    errdefer self.deinit();

    self.* = .{
        .id = @intFromPtr(wlr_output),
        .wlr_output = wlr_output,
        .fullscreens = std.ArrayList(*View).initCapacity(gpa.*, 8) catch Utils.oomPanic(),
        .non_exclusive_area = .{ .x = 0, .y = 0, .width = 0, .height = 0 },

        .scene_output = try server.root.scene.createSceneOutput(wlr_output),
        .output_snd = .{ .output = self },

        .layers = .{
            .background = try self.scene_output.scene.tree.createSceneTree(),
            .bottom = try self.scene_output.scene.tree.createSceneTree(),
            .content = try self.scene_output.scene.tree.createSceneTree(),
            .top = try self.scene_output.scene.tree.createSceneTree(),
            .overlay = try self.scene_output.scene.tree.createSceneTree(),
        },

        .layers_snd = .{
            .background = .{ .output_layer = self.layers.background },
            .bottom = .{ .output_layer = self.layers.bottom },
            .content = .{ .output_layer = self.layers.content },
            .top = .{ .output_layer = self.layers.top },
            .overlay = .{ .output_layer = self.layers.overlay },
        },
    };

    self.wlr_output.data = self;
    self.scene_output.scene.tree.node.data = &self.output_snd;

    wlr_output.events.frame.add(&self.frame);
    wlr_output.events.destroy.add(&self.destroy);
    wlr_output.events.request_state.add(&self.request_state);

    self.layers.background.node.data = &self.layers_snd.background;
    self.layers.bottom.node.data = &self.layers_snd.bottom;
    self.layers.content.node.data = &self.layers_snd.content;
    self.layers.top.node.data = &self.layers_snd.top;
    self.layers.overlay.node.data = &self.layers_snd.overlay;

    var state = wlr.Output.State.init();
    defer state.finish();

    if (wlr_output.preferredMode()) |mode| 
        state.setMode(mode);

    state.setEnabled(true);

    if (!wlr_output.commitState(&state)) {
        log.err("Unable to commit state to output {s}", .{ wlr_output.name });
    }

    server.events.exec("OutputInitPost", .{self.id}, "After a new output is initialized. You're probably looking for OutputStateChange.");

    return self;
}

pub fn deinit(self: *Output) void {
    server.events.exec("OutputDeinitPre", .{ self.id }, "Before an output is de-initialized.");

    self.frame.link.remove();
    self.request_state.link.remove();
    self.destroy.link.remove();
    self.wlr_output.destroy();

    gpa.destroy(self);

    server.events.exec("OutputDeinitPost", .{}, "After an output is de-initialized.");
}

pub fn setFocused(self: *Output) void {
    server.getDefaultSeat().focused_output = self;
}

const SurfaceAtResult = struct {
    surface_snd: *SceneNode.Data,
    surface: *wlr.Surface,
    sx: f64,
    sy: f64,
};

pub fn surfaceAt(self: *Output, lx: f64, ly: f64) ?SurfaceAtResult {
    var sx: f64 = undefined;
    var sy: f64 = undefined;

    const layers = [_]*wlr.SceneTree{ self.layers.overlay, self.layers.top, self.layers.content, self.layers.bottom, self.layers.background };

    for (layers) |layer| {
        const node = layer.node.at(lx, ly, &sx, &sy);
        if (node == null) continue;

        const surface: *wlr.Surface = blk: {
            if (node.?.type == .buffer) {
                const scene_buffer = wlr.SceneBuffer.fromNode(node.?);
                if (wlr.SceneSurface.tryFromBuffer(scene_buffer)) |scene_surface| {
                    break :blk scene_surface.surface;
                }
            }
            continue;
        };

        const snd: *SceneNode.Data = .fromSurface(surface);
        return SurfaceAtResult{
            .surface = surface,
            .surface_snd = snd,
            .sx = sx,
            .sy = sy
        };

        // NOTE: I dont think we need to crawl up, but leaving this here just in case
        // while(node.? != &self.scene_output.scene.tree) {
        //     node = if (node.?.parent) |p| &p.node else continue;
        //
        //     const snd: *SceneNode.Data = .fromSceneNode(node);
        //     switch (snd.*) {
        //         .layer_surface, .view => {
        //             return .{
        //                 .scene_node_data = snd,
        //                 .surface = surface,
        //                 .sx = sx,
        //                 .sy = sy,
        //             };
        //         },
        //         else => continue
        //     }
        // }
    }

    return null;
}

// Get the first enabled fullscreened view
pub fn getEnabledFullscreen(self: *Output) ?*View {
    for(self.fullscreens.items) |view| {
        if(view.scene_tree.node.enabled)
            return view;
    }

    return null;
}


// --------- WlrOutput Event Handlers ---------
fn handleRequestState(
    listener: *wl.Listener(*wlr.Output.event.RequestState),
    event: *wlr.Output.event.RequestState,
) void {
    const self: *Output = @fieldParentPtr("request_state", listener);

    if (!self.wlr_output.commitState(event.state)) {
        log.warn("failed to set output state {}", .{event.state});
        // nothing should've changed, so we don't do anything
        return;
    }

    Root.configureOutputs(&server.root);
    self.arrangeLayers();

    server.events.exec("OutputStateChange", .{self.id}, "After an outputs state has been changed.");
}

fn handleFrame(listener: *wl.Listener(*wlr.Output), _: *wlr.Output) void {
    const self: *Output = @fieldParentPtr("frame", listener);

    if (!self.scene_output.commit(null)) {
        log.warn("setting output state failed for output: {}", .{ self.id });
    }

    var now: std.posix.timespec = undefined;
    _ = std.posix.system.clock_gettime(.MONOTONIC, &now);
    self.scene_output.sendFrameDone(&now);
}

fn handleDestroy(listener: *wl.Listener(*wlr.Output), _: *wlr.Output) void {
    const output: *Output = @fieldParentPtr("destroy", listener);

    output.frame.link.remove();
    output.request_state.link.remove();
    output.destroy.link.remove();

    server.root.output_layout.remove(output.wlr_output);

    gpa.destroy(output);
}

pub fn arrangeLayers(self: *Output) void {
    var full_box: wlr.Box = .{
        .x = 0,
        .y = 0,
        .width = undefined,
        .height = undefined,
    };
    self.wlr_output.effectiveResolution(&full_box.width, &full_box.height);
    self.non_exclusive_area = full_box;

    inline for (@typeInfo(zwlr.LayerShellV1.Layer).@"enum".fields) |comptime_layer| {
        const layer: *wlr.SceneTree = @field(self.layers, comptime_layer.name);
        var it: SceneNode.Iterator(.{ .safe = true }) = .fromSceneTree(layer);

        while (it.next()) |data| {
            if(data.* != .layer_surface) continue;

            const layer_surface: *LayerSurface = data.layer_surface;

            // TEST: should we set the layersurface to the correct output?
            if (layer_surface.getOutput().wlr_output != self.wlr_output) continue;

            if (!layer_surface.wlr_layer_surface.initialized) continue;

            // TEST: river seems to try and prevent clients from taking an
            // exclusive size greater than half the screen by killing them. Do we
            // need to? Clients can do quite a bit of nasty stuff and taking
            // exclusive focus isn't even that bad.

            layer_surface.scene_layer_surface.configure(
                &full_box,
                &self.non_exclusive_area
            );

            // set the position of the new layersurface relative to the output
            // it belongs to
            const x = layer_surface.getOutput().scene_output.x;
            const y = layer_surface.getOutput().scene_output.y;
            layer_surface.scene_layer_surface.tree.node.setPosition(x, y);
            layer_surface.scene_layer_surface.tree.node.subsurfaceTreeSetClip(&.{
                .x = 0,
                .y = 0,
                .width = layer_surface.getOutput().wlr_output.width,
                .height = layer_surface.getOutput().wlr_output.height,
            });
        }
    }
}
