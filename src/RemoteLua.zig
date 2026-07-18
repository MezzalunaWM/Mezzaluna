const RemoteLua = @This();

const std = @import("std");
const wl = wayland.server.wl;
const zlua = @import("zlua");
const utils = @import("utils.zig");

const wayland = @import("wayland");
const LuaUtils = @import("lua/LuaUtils.zig");
const Lua = @import("lua/Lua.zig");
const mez = wayland.server.zmez;

const server = &@import("main.zig").server;
const gpa = &@import("main.zig").gpa;
const io = &@import("main.zig").io;
const lua = &@import("main.zig").lua;
const log = std.log.scoped(.RemoteLua);

node: std.DoublyLinkedList.Node,
remote_lua_v1: *mez.RemoteLuaV1,
L: *zlua.Lua,

pub fn sendNewLogEntry(str: [*:0]const u8) void {
    var node = server.remote_lua_clients.first;
    while (node) |n| {
        const data: ?*RemoteLua = @fieldParentPtr("node", n);
        if (data) |d| d.remote_lua_v1.sendNewLogEntry(str);
        node = n.next;
    }
}

pub fn create(client: *wl.Client, version: u32, id: u32) !void {
    const remote_lua_v1 = try mez.RemoteLuaV1.create(client, version, id);

    const node = try gpa.create(RemoteLua);
    errdefer gpa.destroy(node);
    node.* = .{
        .remote_lua_v1 = remote_lua_v1,
        .node = .{},
        .L = lua.state,
    };
    // TODO: replace stdout and stderr with buffers we can send to the clients

    server.remote_lua_clients.prepend(&node.node);

    remote_lua_v1.setHandler(*RemoteLua, handleRequest, handleDestroy, node);
}

fn handleRequest(
    remote_lua_v1: *mez.RemoteLuaV1,
    request: mez.RemoteLuaV1.Request,
    remote: *RemoteLua,
) void {
    const L = remote.L;
    switch (request) {
        .destroy => remote_lua_v1.destroy(),
        .push_lua => |req| {
            const chunk: [:0]const u8 = std.mem.sliceTo(req.lua_chunk, 0);

            const str = std.mem.concatWithSentinel(gpa.*, u8, &[_][]const u8{
                "return ",
                chunk,
                ";",
            }, 0) catch return catchLuaFail(remote);
            defer gpa.free(str);

            L.loadBuffer(str, "=repl") catch {
                L.pop(L.getTop());
                L.loadString(chunk) catch {
                    catchLuaFail(remote);
                    L.pop(-1);
                };
                return;
            };

            L.protectedCall(.{
                .results = zlua.mult_return,
            }) catch {
                catchLuaFail(remote);
                L.pop(1);
            };

            var i: i32 = 1;
            const nresults = L.getTop();
            while (i <= nresults) : (i += 1) {
                sendNewLogEntry(LuaUtils.toStringEx(L));
                L.pop(-1);
            }
        },
    }
}

fn handleDestroy(_: *mez.RemoteLuaV1, remote_lua: *RemoteLua) void {
    if (remote_lua.node.prev) |p| {
        if (remote_lua.node.next) |n| n.prev.? = p;
        p.next = remote_lua.node.next;
    } else server.remote_lua_clients.first = remote_lua.node.next;
    gpa.destroy(remote_lua);
}

fn catchLuaFail(remote: *RemoteLua) void {
    const err: [:0]const u8 = LuaUtils.toStringEx(remote.L);
    sendNewLogEntry(std.mem.sliceTo(err, 0));
}
