const std = @import("std");
const zlua = @import("zlua");
const xev = @import("xev");

const Utils = @import("../Utils.zig");
const LuaUtils = @import("LuaUtils.zig");
const RemoteLua = @import("../RemoteLua.zig");

const gpa = std.heap.c_allocator;

const server = &@import("../main.zig").server;
const Lua = &@import("../main.zig").lua;

const AsyncData = struct {
    lua_cb_ref_idx: i32,
    timeout: u32,
    once: bool,

    completion: xev.Completion,
    timer: xev.Timer,

    pub fn init() *AsyncData {
        const async = gpa.create(AsyncData) catch Utils.oomPanic();
        async.* = .{
            .once = true,
            .timeout = 0,
            .lua_cb_ref_idx = undefined,

            .completion = undefined,
            .timer = xev.Timer.init() catch Lua.raiseErrorStr("failed to create timer for event loop", .{}),
        };

        return async;
    }

    pub fn deinit(self: *AsyncData) void {
        self.timer.deinit(server.xev_event_loop);
        gpa.destroy(self);
    }
};

fn asyncCallback(
    userdata: ?*AsyncData,
    loop: *xev.Loop,
    c: *xev.Completion,
    _: xev.Timer.RunError!void,
) xev.CallbackAction {
    const self: *AsyncData = userdata.?;

    const t = Lua.state.rawGetIndex(zlua.registry_index, self.lua_cb_ref_idx);
    if (t != zlua.LuaType.function) {
        RemoteLua.sendNewLogEntry("Failed to call hook, it doesn't have a callback.");
        Lua.state.pop(1);
        return .disarm;
    }

    Lua.state.protectedCall(.{ .args = 0 }) catch {
        RemoteLua.sendNewLogEntry(Lua.state.toString(-1) catch unreachable);
    };

    // we reset the timer to be run again in the future
    if (!self.once) {
        var c_cancel: xev.Completion = .{};
        self.timer.reset(loop, c, &c_cancel, self.timeout, AsyncData, userdata, &asyncCallback);
    }

    return .disarm;
}

/// ---@class async_options
/// ---@field number timeout milliseconds
/// ---@field boolean once

/// ---run some lua code later
/// ---@param function callback
/// ---@param (number|async_options)? options if a number this must be the
/// --- timeout in milliseconds if nil defaults to 0 milliseconds aka run as
/// --- soon as possible. This always runs once unless specified otherwise.
pub fn run(L: *zlua.Lua) i32 {
    const async: *AsyncData = .init();

    if (L.isFunction(1)) {
        L.pushValue(1); // move the function to to top of the stack
        async.lua_cb_ref_idx = L.ref(zlua.registry_index) catch Utils.oomPanic();
    } else L.raiseErrorStr("argument 1 must be a function", .{});

    switch (L.typeOf(2)) {
        .table => {
            _ = L.pushString("timeout");
            _ = L.getTable(2);
            if (L.isNumber(-1)) {
                async.timeout = LuaUtils.coerceInteger(
                    u32,
                    L.checkInteger(-1),
                ) catch L.raiseErrorStr("The x must be > -inf and < inf", .{});
            }

            _ = L.pushString("once");
            _ = L.getTable(2);
            if (L.isBoolean(-1)) async.once = L.toBoolean(-1);
        },
        .number => async.timeout = LuaUtils.coerceInteger(
            u32,
            L.checkInteger(2),
        ) catch L.raiseErrorStr("The x must be > -inf and < inf", .{}),
        else => async.timeout = 0,
    }

    async.timer.run(&server.xev_event_loop, &async.completion, async.timeout, AsyncData, async, asyncCallback);
    return 0;
}
