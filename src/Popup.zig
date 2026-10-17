const Popup = @This();

const std = @import("std");
const wlr = @import("wlroots");
const wl = @import("wayland").server.wl;

const utils = @import("utils.zig");
const Output = @import("Output.zig");

const gpa = &@import("main.zig").gpa;
const server = &@import("main.zig").server;
const log = std.log.scoped(.Popup);

id: u64,

xdg_popup: *wlr.XdgPopup,
tree: *wlr.SceneTree,

// Surface Listeners
destroy: wl.Listener(void) = .init(handleDestroy),
commit: wl.Listener(*wlr.Surface) = .init(handleCommit),
new_popup: wl.Listener(*wlr.XdgPopup) = .init(handleNewPopup),
reposition: wl.Listener(void) = .init(handleReposition),

pub fn init(
    xdg_popup: *wlr.XdgPopup,
    parent: *wlr.SceneTree,
) *Popup {
    errdefer utils.oomPanic();

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

fn handleReposition(_: *wl.Listener(void)) void {
    log.debug("Unimplemented Popup.handleReposition", .{});
}
