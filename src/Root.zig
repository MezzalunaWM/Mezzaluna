/// The root of Mezzaluna is, you guessed it, the root of many of the systems mez needs:
const Root = @This();

const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const server = &@import("main.zig").server;
const gpa = std.heap.c_allocator;

const Output = @import("Output.zig");
const View = @import("View.zig");
const LayerSurface = @import("LayerSurface.zig");
const SceneNodeData = @import("SceneNodeData.zig").SceneNodeData;

const Utils = @import("Utils.zig");

scene: *wlr.Scene,
scene_node_data: SceneNodeData,

scene_output_layout: *wlr.SceneOutputLayout,

output_layout: *wlr.OutputLayout,

pub fn init(self: *Root) void {
    std.log.info("Creating root of mezzaluna\n", .{});

    errdefer Utils.oomPanic();

    const output_layout = try wlr.OutputLayout.create(server.wl_server);
    errdefer output_layout.destroy();

    const scene = try wlr.Scene.create();
    errdefer scene.tree.node.destroy();

    self.* = .{
        .scene = scene,
        .scene_node_data = .{ .root = self },
        .output_layout = output_layout,
        .scene_output_layout = try scene.attachOutputLayout(output_layout),
    };

    self.scene.tree.node.data = &self.scene_node_data;
}

pub fn deinit(self: *Root) void {
    var it = self.scene.tree.children.iterator(.forward);

    while (it.next()) |node| {
        if (node.data == null) continue;

        const scene_node_data: *SceneNodeData = @ptrCast(@alignCast(node.data.?));
        switch (scene_node_data.*) {
            .output => {
                scene_node_data.output.deinit();
            },
            else => {
                std.log.debug("The root has a child that is not an output", .{});
                unreachable;
            },
        }
    }

    self.output_layout.destroy();
    self.scene.tree.node.destroy();
}

// Search output_layout's ouputs, and each outputs views
pub fn viewById(self: *Root, id: u64) ?*View {
    var output_it = self.output_layout.outputs.iterator(.forward);

    while (output_it.next()) |o| {
        if (o.output.data == null) {
            std.log.err("Wlr_output arbitrary data not assigned", .{});
            unreachable;
        }

        const output: *Output = @ptrCast(@alignCast(o.output.data.?));
        var node_it = output.layers.content.children.iterator(.forward);

        while (node_it.next()) |node| {
            if (node.data == null) continue;

            const view_snd: *SceneNodeData = @ptrCast(@alignCast(node.data.?));

            // TODO: Should we assert that we want only views to be here
            //    -- Basically should we use switch statements for snd interactions
            //    -- Or if statements, for simplicity
            if (view_snd.* == .view and view_snd.view.id == id) {
                return view_snd.view;
            }
        }

        if (output.fullscreen) |fullscreen| {
            if (fullscreen.id == id) return fullscreen;
        }
    }

    return null;
}

pub fn outputById(self: *Root, id: u64) ?*Output {
    var it = self.scene.outputs.iterator(.forward);

    while (it.next()) |scene_output| {
        if (scene_output.output.data == null) continue;

        const output: *Output = @as(*Output, @ptrCast(@alignCast(scene_output.output.data.?)));
        if (output.id == id) return output;
    }

    return null;
}
