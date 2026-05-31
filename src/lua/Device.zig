//! mez.device
const std = @import("std");
const zlua = @import("zlua");
const wlr = @import("wlroots");

const Utils = @import("../Utils.zig");
const input_device = @import("../input_device.zig");
const LuaUtils = @import("LuaUtils.zig");

const gpa = std.heap.c_allocator;

const server = &@import("../main.zig").server;
const Lua = &@import("../main.zig").lua;

fn device_error(L: *zlua.Lua) noreturn {
    L.raiseErrorStr("Unable to get device.", .{});
}

pub fn get_type(L: *zlua.Lua) i32 {
    const device = L.toUserdata(wlr.InputDevice, 1) catch device_error(L);
    _ = L.pushString(std.mem.span(@tagName(device.type).ptr));
    return 1;
}

pub fn get_name(L: *zlua.Lua) i32 {
    const device = L.toUserdata(wlr.InputDevice, 1) catch device_error(L);
    _ = if (device.name) |n| L.pushString(std.mem.span(n)) else L.pushNil();
    return 1;
}
