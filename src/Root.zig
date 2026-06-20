/// The root of Mezzaluna is, you guessed it, the root of many of the systems mez needs:
const Root = @This();

const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const server = &@import("main.zig").server;

const Output = @import("Output.zig");
const View = @import("View.zig");
const LayerSurface = @import("LayerSurface.zig");
const SceneNodeData = @import("SceneNodeData.zig").SceneNodeData;

const Utils = @import("Utils.zig");

scene_node_data: SceneNodeData,

pending_views: u32,
pending_state_dirty: bool,

scene: *wlr.Scene,
scene_output_layout: *wlr.SceneOutputLayout,

hidden_tree: *wlr.SceneTree,

// All visible views should be accessed through these
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
        .scene_output_layout = try scene.attachOutputLayout(output_layout),

        .hidden_tree = try scene.tree.createSceneTree(),

        .output_manager = try wlr.OutputManagerV1.create(server.wl_server),
        .output_power_manager = try wlr.OutputPowerManagerV1.create(server.wl_server),
        .output_layout = output_layout,

        .pending_views = 0,
        .pending_state_dirty = false,
    };

    // This hidden tree is, you guessed it, hidden
    self.hidden_tree.node.setEnabled(false);

    self.hidden_tree.node.data = &self.scene_node_data;

    if (server.linux_dmabuf) |dmabuf| self.scene.setLinuxDmabufV1(dmabuf);

    self.scene.tree.node.data = &self.scene_node_data;

    self.output_manager.events.apply.add(&self.output_manager_apply);
    self.output_manager.events.@"test".add(&self.output_manager_test);
    self.output_power_manager.events.set_mode.add(&self.output_power_manager_set);
}

pub fn deinit(self: *Root) void {
    var output_it = self.output_layout.outputs.iterator(.forward);

    while(output_it.next()) |o| {
        if(o.output.data == null) continue;

        const output: *Output = @ptrCast(@alignCast(o.output.data));
        output.deinit();
    }

    self.output_layout.destroy();
    self.hidden_tree.node.destroy();
    self.scene.tree.node.destroy();
}

// This function is ugly as hell because I am stobbournly
// trying to avoid data duplication. Therefore we need to
// search everywhere there can be a view.
pub fn viewById(self: *Root, id: u64) ?*View {
    // Check all hidden children
    var hidden_view_it = self.hidden_tree.children.iterator(.forward);
    while(hidden_view_it.next()) |scene_node| {
        if(scene_node.data == null) continue;
        const scene_node_data: *SceneNodeData = @ptrCast(@alignCast(scene_node.data.?));

        if(scene_node_data.* == .view and scene_node_data.view.id == id) {
            return scene_node_data.view;
        }
    }

    var output_it = self.output_layout.outputs.iterator(.forward);
    while(output_it.next()) |o| {
        if (o.output.data == null) continue;
        const output: *Output = @ptrCast(@alignCast(o.output.data));

        var view_it = output.layers.content.children.iterator(.forward);
        while(view_it.next()) |scene_node| {
            if(scene_node.data == null) continue;

            const scene_node_data: *SceneNodeData = @ptrCast(@alignCast(scene_node.data.?));

            if(scene_node_data.* == .view and scene_node_data.view.id == id) {
                return scene_node_data.view;
            }
        }

        for(output.fullscreens.items) |view| {
            if(view.id == id) return view;
        }
    }

    return null;
}

pub fn outputById(self: *Root, id: u64) ?*Output {
    var output_it = self.output_layout.outputs.iterator(.forward);
    while(output_it.next()) |o| {
        if (o.output.data == null) continue;
        const output: *Output = @ptrCast(@alignCast(o.output.data));

        if(output.id == id) {
            return output;
        }
    }

    return null;
}

pub fn applyPending(self: *Root) void {
    // Check if state is already sending and come back to new pending later
    if (self.pending_views > 0) {
        self.pending_state_dirty = true;
        return;
    }

    self.pending_views = 0;

    var output_it = self.output_layout.outputs.iterator(.forward);

    while(output_it.next()) |o| {
        if (o.output.data == null) continue;

        const output: *Output = @ptrCast(@alignCast(o.output.data.?));

        var view_it = output.layers.content.children.iterator(.forward);

        while(view_it.next()) |scene_node| {
            if(scene_node.data == null) continue;

            const view_snd: *SceneNodeData = @ptrCast(@alignCast(scene_node.data.?));
            if(view_snd.* != .view) continue;

            view_snd.view.applyPending();
        }
    }

    // Apply sending if no configures were sent
    if (self.pending_views == 0) {
        self.applySending();
    }
}

pub fn applySending(self: *Root) void {

    std.log.debug("Going through hidden tree", .{});
    // std.log.debug("The hidden tree has {d}")

    var hidden_view_it = self.hidden_tree.children.safeIterator(.forward);
    while(hidden_view_it.next()) |scene_node| {
        std.log.debug("Getting the scene node data", .{});

        if(scene_node.data == null) continue;
        const view_snd: *SceneNodeData = @ptrCast(@alignCast(scene_node.data.?));

        std.log.debug("Finished alignment, starting to reparent", .{});

        if(view_snd.view.output orelse server.getDefaultSeat().focused_output) |o| {
            view_snd.view.scene_tree.node.reparent(o.layers.content);
        }

        std.log.debug("Finished reparenting", .{});
    }
    std.log.debug("Finished", .{});

    var output_it = self.output_layout.outputs.iterator(.forward);

    while(output_it.next()) |o| {
        if (o.output.data == null) continue;

        const output: *Output = @ptrCast(@alignCast(o.output.data.?));

        var view_it = output.layers.content.children.iterator(.forward);

        while(view_it.next()) |scene_node| {
            if(scene_node.data == null) continue;

            const view_snd: *SceneNodeData = @ptrCast(@alignCast(scene_node.data.?));
            if(view_snd.* != .view) continue;

            view_snd.view.applySending();
        }
    }

    // Take care of state that was made pending while handling other sending state
    if (self.pending_state_dirty) {
        self.pending_state_dirty = false;
        self.applyPending();
    }
}

// --------- OutputManagerV1 event handlers ---------
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
