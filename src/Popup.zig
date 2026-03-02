const Popup = @This();

const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const Utils = @import("Utils.zig");
const Output = @import("Output.zig");
const SceneNodeData = @import("SceneNodeData.zig");

const gpa = std.heap.c_allocator;
const server = &@import("main.zig").server;

id: u64,

xdg_popup: *wlr.XdgPopup,
tree: *wlr.SceneTree,

// Surface Listeners
destroy: wl.Listener(void) = wl.Listener(void).init(handleDestroy),
commit: wl.Listener(*wlr.Surface) = wl.Listener(*wlr.Surface).init(handleCommit),
new_popup: wl.Listener(*wlr.XdgPopup) = wl.Listener(*wlr.XdgPopup).init(handleNewPopup),
reposition: wl.Listener(void) = wl.Listener(void).init(handleReposition),

pub fn init(
    xdg_popup: *wlr.XdgPopup,
    parent: *wlr.SceneTree,
) *Popup {
    errdefer Utils.oomPanic();

    const self = try gpa.create(Popup);
    errdefer gpa.destroy(self);

    self.* = .{
        .id = @intFromPtr(xdg_popup),
        .xdg_popup = xdg_popup,
        .tree = try parent.createSceneXdgSurface(xdg_popup.base),
    };

    xdg_popup.events.destroy.add(&self.destroy);
    xdg_popup.base.surface.events.commit.add(&self.commit);
    xdg_popup.base.events.new_popup.add(&self.new_popup);
    xdg_popup.events.reposition.add(&self.reposition);

    return self;
}

fn handleDestroy(listener: *wl.Listener(void)) void {
    const popup: *Popup = @fieldParentPtr("destroy", listener);

    popup.destroy.link.remove();
    popup.commit.link.remove();
    popup.new_popup.link.remove();
    popup.reposition.link.remove();

    gpa.destroy(popup);
}

fn handleCommit(listener: *wl.Listener(*wlr.Surface), _: *wlr.Surface) void {
    const popup: *Popup = @fieldParentPtr("commit", listener);
    if (popup.xdg_popup.base.initial_commit) {
        handleReposition(&popup.reposition);
    }
}

fn handleNewPopup(listener: *wl.Listener(*wlr.XdgPopup), xdg_popup: *wlr.XdgPopup) void {
    const popup: *Popup = @fieldParentPtr("new_popup", listener);

    _ = Popup.init(xdg_popup, popup.tree);
}

fn handleReposition(listener: *wl.Listener(void)) void {
    const popup: *Popup = @fieldParentPtr("reposition", listener);

    var box: wlr.Box = undefined;

    // TODO: figure this out to prevent popups from rendering outside of the
    // current monitor
    //
    // if (SceneNodeData.getFromNode(&popup.tree.node)) |node| {
    //   const output = switch (node.data) {
    //     .view => |view| view.output orelse return,
    //     .layer_surface => |layer_surface| layer_surface.output,
    //   };
    //
    //   server.root.output_layout.getBox(output.wlr_output, &box);
    // }

    var root_lx: c_int = undefined;
    var root_ly: c_int = undefined;
    _ = popup.tree.node.coords(&root_lx, &root_ly);

    box.x -= root_lx;
    box.y -= root_ly;

    popup.xdg_popup.unconstrainFromBox(&box);
}
