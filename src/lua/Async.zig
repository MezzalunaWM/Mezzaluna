/// mez.async allows for the creation and manipulation of anychronous logic

const std = @import("std");
const zlua = @import("zlua");
const xev = @import("xev");
const wl = @import("wayland").server.wl;
const utils = @import("../utils.zig");

const LuaUtils = @import("LuaUtils.zig");
const RemoteLua = @import("../RemoteLua.zig");

const gpa = &@import("../main.zig").gpa;
const server = &@import("../main.zig").server;
const Lua = &@import("../main.zig").lua;
const log = std.log.scoped(.@"Lua.Async");

pub const AsyncData = struct {
    lua_cb_ref_idx: i32,
    timeout: c_int, // in ms
    once: bool,
    timer: ?*wl.EventSource,

    pub fn init() !*AsyncData {
        const self = gpa.create(AsyncData) catch utils.oomPanic();
        self.* = .{
            .once = true,
            .timeout = 0,
            .lua_cb_ref_idx = undefined,

            .timer = undefined,
        };

        self.timer = try server.event_loop.addTimer(?*AsyncData, asyncCallback, self);

        return self;
    }

    pub fn deinit(self: *AsyncData) void {
        _ = server.async_callbacks.remove(@intFromPtr(self));
        self.timer.?.timerUpdate(0) catch {}; // disarm
        self.timer.?.remove();
        gpa.destroy(self);
    }
};

fn asyncCallback(data: ?*AsyncData) c_int {
    const self = data orelse return 0;

    const t = Lua.state.getIndexRaw(zlua.registry_index, self.lua_cb_ref_idx);
    if (t != zlua.LuaType.function) {
        RemoteLua.sendNewLogEntry("Failed to call hook, it doesn't have a callback.");
        Lua.state.pop(1);
        self.deinit();
        return 0;
    }

    Lua.state.protectedCall(.{ .args = 0 }) catch {
        LuaUtils.handleError(Lua.state);
        self.deinit();
        return 0;
    };

    // we reset the timer to be run again in the future
    if (!self.once) b: {
        self.timer.?.timerUpdate(self.timeout) catch break :b;
        return 0;
    }

    self.deinit();
    return 0;
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
    const self = AsyncData.init() catch |err| {
        L.raiseErrorStr("Failed to create async timer: {s}", .{ @errorName(err).ptr });
    };

    if (L.isFunction(1)) {
        L.pushValue(1); // move the function to to top of the stack
        self.lua_cb_ref_idx = L.ref(zlua.registry_index);
    } else L.raiseErrorStr("argument 1 must be a function", .{});

    switch (L.typeOf(2)) {
        .table => {
            _ = L.getField(2, "timeout");
            if (L.isNumber(-1)) {
                self.timeout = LuaUtils.coerceInteger(
                    c_int,
                    L.checkInteger(-1),
                ) catch L.raiseErrorStr("The x must be > -inf and < inf", .{});
            }

            _ = L.getField(2, "once");
            if (L.isBoolean(-1)) self.once = L.toBoolean(-1);
        },
        .number => self.timeout = LuaUtils.coerceInteger(
            c_int,
            L.checkInteger(2),
        ) catch L.raiseErrorStr("The x must be > -inf and < inf", .{}),
        else => self.timeout = 0,
    }

    self.timer.?.timerUpdate(self.timeout) catch {
        self.deinit();
        @panic("posix unexpected error");
    };

    const id = @intFromPtr(self);
    server.async_callbacks.put(id, self) catch utils.oomPanic();
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
