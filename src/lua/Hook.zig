const Hook = @This();

const std = @import("std");
const zlua = @import("zlua");

const THook = @import("../types/Hook.zig");
const Utils = @import("../Utils.zig");
const LuaUtils = @import("LuaUtils.zig");

const gpa = std.heap.c_allocator;
const server = &@import("../main.zig").server;

/// ---Create a new hook on an event
/// ---@param events string|string[]
/// ---@param options table
/// ---@return number id
pub fn add(L: *zlua.Lua) i32 {
    L.checkType(2, .table);

    var hook: *THook = gpa.create(THook) catch Utils.oomPanic();

    // We support both a string and a table of strings as the first value of
    // add. Regardless of which type is passed in we create an arraylist of
    // []const u8's
    if (L.isTable(1)) {
        hook.events = gpa.alloc(comptime []const u8, L.objectLen(1)) catch Utils.oomPanic();
        var i: u32 = 0;
        L.pushNil();
        while (L.next(1)) {
            if (L.isString(-1)) {
                const s = L.checkString(-1);
                hook.events[i] = gpa.dupe(u8, s) catch Utils.oomPanic();
                i += 1;
            }
            L.pop(1);
        }
    } else if (L.isString(1)) {
        hook.events = gpa.alloc(comptime []const u8, 1) catch Utils.oomPanic();
        const s = L.checkString(1);
        hook.events[0] = gpa.dupe(u8, s) catch Utils.oomPanic();
    }

    _ = L.pushString("callback");
    _ = L.getTable(2);
    if (L.isFunction(-1)) {
        hook.options.lua_cb_ref_idx = L.ref(zlua.registry_index) catch Utils.oomPanic();
    }

    // TEST: this should be safe as the lua_cb_ref_idx's should never be the same
    // but that all really depends on the implementation of the hashmap
    server.hooks.put(hook.options.lua_cb_ref_idx, hook) catch Utils.oomPanic();

    for (hook.events) |value| {
        server.events.put(value, hook) catch Utils.oomPanic();
    }

    L.pushInteger(hook.options.lua_cb_ref_idx);
    return 1;
}

/// ---Create an existing hook
/// ---@param id number
/// ---@return boolean has it been deleted
pub fn del(L: *zlua.Lua) i32 {
    const hook_id = LuaUtils.coerceInteger(i32, L.checkInteger(1)) catch L.raiseErrorStr("hook id must be a valid number", .{});
    const hook = server.hooks.get(hook_id);
    if (hook == null) L.raiseErrorStr("hook {} does not exist", .{hook_id});

    for (hook.?.events) |value| {
        server.events.del(value, hook.?);
    }
    L.pushBoolean(server.hooks.remove(hook_id));
    return 1;
}
