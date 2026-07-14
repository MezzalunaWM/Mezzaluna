const RemoteLuaManager = @This();

const std = @import("std");
const wayland = @import("wayland");
const Utils = @import("Utils.zig");
const RemoteLua = @import("RemoteLua.zig");
const wl = wayland.server.wl;
const mez = wayland.server.zmez;

const gpa = &@import("main.zig").gpa;
const server = &@import("main.zig").server;

global: *wl.Global,

pub fn init() !?*RemoteLuaManager {
    const self = try gpa.create(RemoteLuaManager);

    self.global = try wl.Global.create(server.wl_server, mez.RemoteLuaManagerV1, 1, ?*anyopaque, null, bind);

    return self;
}

fn bind(client: *wl.Client, _: ?*anyopaque, version: u32, id: u32) void {
    const remote_lua_manager_v1 = mez.RemoteLuaManagerV1.create(client, version, id) catch {
        client.postNoMemory();
        Utils.oomPanic();
    };
    remote_lua_manager_v1.setHandler(?*anyopaque, handleRequest, null, null);
}

fn handleRequest(
    remote_lua_manager_v1: *mez.RemoteLuaManagerV1,
    request: mez.RemoteLuaManagerV1.Request,
    _: ?*anyopaque,
) void {
    switch (request) {
        .destroy => remote_lua_manager_v1.destroy(),
        .get_remote => |req| {
            RemoteLua.create(
                remote_lua_manager_v1.getClient(),
                remote_lua_manager_v1.getVersion(),
                req.id,
            ) catch {
                remote_lua_manager_v1.getClient().postNoMemory();
                Utils.oomPanic();
            };
        },
    }
}
