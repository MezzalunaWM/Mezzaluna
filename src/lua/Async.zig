/// mez.async allows for the creation and manipulation of anychronous logic

const std = @import("std");
const zlua = @import("zlua");
const xev = @import("xev");
const utils = @import("../utils.zig");

const LuaUtils = @import("LuaUtils.zig");
const RemoteLua = @import("../RemoteLua.zig");

const gpa = &@import("../main.zig").gpa;
const server = &@import("../main.zig").server;
const Lua = &@import("../main.zig").lua;
const log = std.log.scoped(.@"Lua.Async");

pub const AsyncData = struct {
    lua_cb_ref_idx: i32,
    timeout: u32,
    once: bool,

    cancel_completion: xev.Completion,
    completion: xev.Completion,
    timer: xev.Timer,

    pub fn init() *AsyncData {
        const async = gpa.create(AsyncData) catch utils.oomPanic();
        async.* = .{
            .once = true,
            .timeout = 0,
            .lua_cb_ref_idx = undefined,

            .completion = undefined,
            .cancel_completion = undefined,
            .timer = xev.Timer.init() catch Lua.raiseErrorStr("failed to create timer for event loop", .{}),
        };

        return async;
    }

    pub fn deinit(self: *AsyncData) void {
        // welcome to callback hell
        self.timer.cancel(&server.xev_event_loop, &self.completion, &self.cancel_completion, AsyncData, self, &struct {
            fn callback(
                userdata: ?*AsyncData,
                _: *xev.Loop,
                _: *xev.Completion,
                _: xev.Timer.CancelError!void,
            ) xev.CallbackAction {
                // do the rest of the takedown after the timer has been canceled
                const s: *AsyncData = userdata.?;
                _ = server.async_callbacks.remove(@intFromPtr(s));
                s.timer.deinit();
                gpa.destroy(s);
                return .disarm;
            }
        }.callback);
    }
};

fn asyncCallback(
    userdata: ?*AsyncData,
    loop: *xev.Loop,
    c: *xev.Completion,
    v: xev.Timer.RunError!void,
) xev.CallbackAction {
    // don't continue if there's an error
    v catch |err| switch (err) {
        else => return .disarm,
    };
    const self: *AsyncData = userdata.?;

    const t = Lua.state.getIndexRaw(zlua.registry_index, self.lua_cb_ref_idx);
    if (t != zlua.LuaType.function) {
        RemoteLua.sendNewLogEntry("Failed to call hook, it doesn't have a callback.");
        Lua.state.pop(1);
        return .disarm;
    }

    Lua.state.protectedCall(.{ .args = 0 }) catch {
        LuaUtils.handleError(Lua.state);
        self.deinit();
        return .disarm;
    };

    // we need to call the wayland event loop to draw anything that might've
    // been updated by the lua code
    server.dispatchEvents(loop);

    // we reset the timer to be run again in the future
    if (!self.once) {
        var c_cancel: xev.Completion = undefined;
        self.timer.reset(loop, c, &c_cancel, self.timeout, AsyncData, userdata, &asyncCallback);
    } else self.deinit();

    return .disarm;
}

/// ---@class async_options
/// ---@field timeout number milliseconds
/// ---@field once boolean

/// ---run some lua code later
/// ---@param callback function
/// ---@param options (number|async_options)? if a number this must be the
/// --- timeout in milliseconds if nil defaults to 0 milliseconds aka run as
/// --- soon as possible. This always runs once unless specified otherwise.
/// ---@return id used for canceling the async function
pub fn run(L: *zlua.Lua) i32 {
    const async: *AsyncData = .init();

    if (L.isFunction(1)) {
        L.pushValue(1); // move the function to to top of the stack
        async.lua_cb_ref_idx = L.ref(zlua.registry_index);
    } else L.raiseErrorStr("argument 1 must be a function", .{});

    switch (L.typeOf(2)) {
        .table => {
            _ = L.getField(2, "timeout");
            if (L.isNumber(-1)) {
                async.timeout = LuaUtils.coerceInteger(
                    u32,
                    L.checkInteger(-1),
                ) catch L.raiseErrorStr("The x must be > -inf and < inf", .{});
            }

            _ = L.getField(2, "once");
            if (L.isBoolean(-1)) async.once = L.toBoolean(-1);
        },
        .number => async.timeout = LuaUtils.coerceInteger(
            u32,
            L.checkInteger(2),
        ) catch L.raiseErrorStr("The x must be > -inf and < inf", .{}),
        else => async.timeout = 0,
    }

    async.timer.run(&server.xev_event_loop, &async.completion, async.timeout, AsyncData, async, asyncCallback);

    const id = @intFromPtr(async);
    server.async_callbacks.put(id, async) catch utils.oomPanic();
    L.pushInteger(@intCast(id));
    return 1;
}

/// ---cancel an upcoming timer
/// ---@param id number
pub fn cancel(L: *zlua.Lua) i32 {
    const id = LuaUtils.coerceInteger(usize, L.checkInteger(1)) catch L.raiseErrorStr("The x must be > -inf and < inf", .{});
    const self = server.async_callbacks.get(id) orelse return 0;
    self.deinit();

    return 0;
}
