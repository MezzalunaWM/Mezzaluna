/// The root of Mezzaluna is, you guessed it, the root of many of the systems mez needs

const Root = @This();

const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const utils = @import("utils.zig");

const Output = @import("Output.zig");
const View = @import("View.zig");
const LayerSurface = @import("LayerSurface.zig");
const SceneNode = @import("SceneNode.zig");

const server = &@import("main.zig").server;
const log = std.log.scoped(.Root);

scene_node_data: SceneNode.Data,

pending_views: u32,
pending_state_dirty: bool,

scene: *wlr.Scene,
scene_output_layout: *wlr.SceneOutputLayout,

hidden_tree: *wlr.SceneTree,
hidden_tree_scene_node_data: SceneNode.Data,

// All visible views should be accessed through these
output_layout: *wlr.OutputLayout,
output_manager: *wlr.OutputManagerV1,
output_power_manager: *wlr.OutputPowerManagerV1,

// listeners
output_manager_apply: wl.Listener(*wlr.OutputConfigurationV1) = .init(handleOutputManagerApply),
output_manager_test: wl.Listener(*wlr.OutputConfigurationV1) = .init(handleOutputManagerTest),
output_power_manager_set: wl.Listener(*wlr.OutputPowerManagerV1.event.SetMode) = .init(handleOutputPowerManagerSet),

pub fn init(self: *Root) void {
    log.info("Creating root of mezzaluna\n", .{});

    errdefer utils.oomPanic();

    const output_layout = try wlr.OutputLayout.create(server.wl_server);
    errdefer output_layout.destroy();

    const scene = try wlr.Scene.create();
    errdefer scene.tree.node.destroy();

    self.* = .{
        .scene = scene,
        .scene_node_data = .{ .root = self },
        .scene_output_layout = try scene.attachOutputLayout(output_layout),

        .hidden_tree = try scene.tree.createSceneTree(),
        .hidden_tree_scene_node_data = .{ .hidden_tree = self.hidden_tree },

        .output_manager = try wlr.OutputManagerV1.create(server.wl_server),
        .output_power_manager = try wlr.OutputPowerManagerV1.create(server.wl_server),
        .output_layout = output_layout,

        .pending_views = 0,
        .pending_state_dirty = false,
    };

    self.hidden_tree.node.data = &self.hidden_tree_scene_node_data;

    if (server.linux_dmabuf) |dmabuf| self.scene.setLinuxDmabufV1(dmabuf);

    self.scene.tree.node.data = &self.scene_node_data;

    self.output_manager.events.apply.add(&self.output_manager_apply);
    self.output_manager.events.@"test".add(&self.output_manager_test);
    self.output_power_manager.events.set_mode.add(&self.output_power_manager_set);
}

pub fn deinit(self: *Root) void {
    self.output_manager_apply.link.remove();
    self.output_manager_test.link.remove();
    self.output_power_manager_set.link.remove();

    var output_it = self.output_layout.outputs.safeIterator(.forward);
    while(output_it.next()) |o| {
        std.debug.assert(o.output.data != null);
        const output: *Output = @ptrCast(@alignCast(o.output.data.?));

        output.deinit();
    }

    self.output_layout.destroy();
    self.hidden_tree.node.destroy();
    self.scene.tree.node.destroy();
}

pub fn configureOutputs(self: *const Root) void {
    // update the config with all monitors and send it to the output_manager
    const config = wlr.OutputConfigurationV1.create() catch utils.oomPanic();

    // TODO: do we ommit disabled monitors here?
    var iter = self.scene.outputs.iterator(.forward);
    while (iter.next()) |scene_output| {
        const config_head = wlr.OutputConfigurationV1.Head.create(config, scene_output.output) catch utils.oomPanic();

        if (self.output_layout.get(scene_output.output)) |o| {
            _ = self.output_layout.add(scene_output.output, o.x, o.y) catch utils.oomPanic();

            config_head.state.x = o.x;
            config_head.state.y = o.y;
        }
    }

    self.output_manager.setConfiguration(config);
}

// Search output_layout's outputs, and each outputs views
pub fn viewById(self: *Root, id: u64) ?*View {
    // Check all hidden children
    var hidden_it: SceneNode.Iterator(.{}) = .fromSceneTree(self.hidden_tree);
    while(hidden_it.next()) |data| {
        std.debug.assert(data.* == .view);

        if(data.view.id == id) return data.view;
    }

    var output_it = self.output_layout.outputs.iterator(.forward);
    while(output_it.next()) |o| {
        std.debug.assert(o.output.data != null);
        const output: *Output = @ptrCast(@alignCast(o.output.data));

        const layers = [_]*wlr.SceneTree{ output.layers.content, output.layers.top };
        for(layers) |layer| {
            var view_it: SceneNode.Iterator(.{}) = .fromSceneTree(layer);

            while(view_it.next()) |data| {
                if (data.* != .view) continue;

                if(data.view.id == id) return data.view;
            }
        }
    }

    return null;
}

pub fn outputById(self: *Root, id: u64) ?*Output {
    var output_it = self.output_layout.outputs.iterator(.forward);
    while(output_it.next()) |o| {
        std.debug.assert(o.output.data != null);
        const output: *Output = @ptrCast(@alignCast(o.output.data));

        if(output.id == id) return output;
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

    var hidden_it: SceneNode.Iterator(.{}) = .fromSceneTree(self.hidden_tree);
    while(hidden_it.next()) |data| {
        std.debug.assert(data.* == .view);
        data.view.applyPending();
    }

    var output_it = self.output_layout.outputs.safeIterator(.forward);
    while(output_it.next()) |o| {
        std.debug.assert(o.output.data != null);
        const output: *Output = @ptrCast(@alignCast(o.output.data.?));

        const layers = [_]*wlr.SceneTree{ output.layers.content, output.layers.top };
        for(layers) |layer| {
            var view_it: SceneNode.Iterator(.{}) = .fromSceneTree(layer);
            while(view_it.next()) |data| {
                if (data.* != .view) continue;

                data.view.applyPending();
            }
        }
    }

    // Apply sending if no configures were sent
    if (self.pending_views == 0) {
        self.applySending();
    }
}

// If a view is moved from one scene tree to a "later" scene tree
// it will applyPending twice. The second call should do nothing
pub fn applySending(self: *Root) void {
    var hidden_it: SceneNode.Iterator(.{ .safe = true }) = .fromSceneTree(self.hidden_tree);
    while(hidden_it.next()) |data| {
        std.debug.assert(data.* == .view);
        data.view.applySending();
    }

    var output_it = self.output_layout.outputs.iterator(.forward);
    while(output_it.next()) |o| {
        std.debug.assert(o.output.data != null);
        const output: *Output = @ptrCast(@alignCast(o.output.data.?));

        const layers = [_]*wlr.SceneTree{ output.layers.content, output.layers.top };
        for(layers) |layer| {
            var view_it: SceneNode.Iterator(.{ .safe = true }) = .fromSceneTree(layer);

            while(view_it.next()) |data| {
                if (data.* != .view) continue;

                data.view.applySending();
            }
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
