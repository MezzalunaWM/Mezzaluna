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
const SceneNode = @import("SceneNode.zig");

const Utils = @import("Utils.zig");

scene_node_data: SceneNode.Data,

scene: *wlr.Scene,
output_layout: *wlr.OutputLayout,
output_manager: *wlr.OutputManagerV1,
output_power_manager: *wlr.OutputPowerManagerV1,

// listeners
output_manager_apply: wl.Listener(*wlr.OutputConfigurationV1) = .init(handleOutputManagerApply),
output_manager_test: wl.Listener(*wlr.OutputConfigurationV1) = .init(handleOutputManagerTest),
output_power_manager_set: wl.Listener(*wlr.OutputPowerManagerV1.event.SetMode) = .init(handleOutputPowerManagerSet),

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
        .output_manager = try wlr.OutputManagerV1.create(server.wl_server),
        .output_power_manager = try wlr.OutputPowerManagerV1.create(server.wl_server),
        .output_layout = output_layout,
    };

    if (server.linux_dmabuf) |dmabuf| self.scene.setLinuxDmabufV1(dmabuf);

    self.scene.tree.node.data = &self.scene_node_data;

    self.output_manager.events.apply.add(&self.output_manager_apply);
    self.output_manager.events.@"test".add(&self.output_manager_test);
    self.output_power_manager.events.set_mode.add(&self.output_power_manager_set);
}

pub fn deinit(self: *Root) void {
    var iter = SceneNode.iterator(
        @constCast(&[_]*wlr.SceneTree{ &self.scene.tree }),
        .forward
    );
    while (iter.next()) |node_data| {
        switch (node_data.*) {
            .output => |output| output.deinit(),
            else => {
                std.debug.panic("The root has a child that is not an output", .{});
            },
        }
    }

    self.output_layout.destroy();
    self.scene.tree.node.destroy();
}

pub fn configureOutputs(self: *const Root) void {
    // update the config with all monitors and send it to the output_manager
    const config = wlr.OutputConfigurationV1.create() catch Utils.oomPanic();

    // TODO: do we ommit disabled monitors here?
    var iter = self.scene.outputs.iterator(.forward);
    while (iter.next()) |scene_output| {
        const config_head = wlr.OutputConfigurationV1.Head.create(config, scene_output.output) catch Utils.oomPanic();

        if (self.output_layout.get(scene_output.output)) |o| {
            _ = self.output_layout.add(scene_output.output, o.x, o.y) catch Utils.oomPanic();

            config_head.state.x = o.x;
            config_head.state.y = o.y;
        }
    }

    self.output_manager.setConfiguration(config);
}

// Search output_layout's outputs, and each outputs views
pub fn viewById(self: *Root, id: u64) ?*View {
    var output_it = self.output_layout.outputs.iterator(.forward);

    while (output_it.next()) |o| {
        if (o.output.data == null) {
            std.debug.panic("Wlr_output arbitrary data not assigned", .{});
        }

        const output: *Output = @ptrCast(@alignCast(o.output.data.?));
        var iter = SceneNode.iterator(@constCast(&[_]*wlr.SceneTree{
            output.layers.content,
            output.layers.top,
        }), .forward);
        while (iter.next()) |node_data| {
            if (node_data.* == .view and node_data.view.id == id) {
                return node_data.view;
            }
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

fn handleOutputManagerApply(
    _: *wl.Listener(*wlr.OutputConfigurationV1),
    config: *wlr.OutputConfigurationV1
) void {
    outputManagerConfigure(config, true);
}

fn handleOutputManagerTest(
    _: *wl.Listener(*wlr.OutputConfigurationV1),
    config: *wlr.OutputConfigurationV1
) void {
    outputManagerConfigure(config, false);
}

/// if apply is false we test the output instead
fn outputManagerConfigure(config: *wlr.OutputConfigurationV1, apply: bool) void {
    // by default we will tell the client this worked, if we encounter an error
    // we keep going, but tell the client that we did not succeed.
    var success = true;
    defer config.destroy();

    var iter = config.heads.iterator(.forward);
    while (iter.next()) |head| {
        const output: *Output = @fieldParentPtr("wlr_output", &head.state.output);
        var state: wlr.Output.State = .init();
        defer state.finish();

        state.setEnabled(head.state.enabled);

        // TEST: further configuration only happens if the output is enabled
        // if (state.enabled) {
            if (head.state.mode) |mode| {
                state.setMode(mode);
            } else {
                state.setCustomMode(
                    head.state.custom_mode.width,
                    head.state.custom_mode.height,
                    head.state.custom_mode.refresh,
                );
            }

            state.setTransform(head.state.transform);
            state.setScale(head.state.scale);
            state.setAdaptiveSyncEnabled(head.state.adaptive_sync_enabled);
        // }

        success &= if (apply) output.wlr_output.commitState(&state)
            else output.wlr_output.testState(&state);
    }

    if (success) {
        config.sendSucceeded();
    } else config.sendFailed();
}

fn handleOutputPowerManagerSet(
    _: *wl.Listener(*wlr.OutputPowerManagerV1.event.SetMode),
    event: *wlr.OutputPowerManagerV1.event.SetMode
) void {
    const output: *Output = @fieldParentPtr("wlr_output", &event.output);
    var state: wlr.Output.State = .init();
    defer state.finish();

    state.setEnabled(event.mode == .on);
    _ = output.wlr_output.commitState(&state);
}
