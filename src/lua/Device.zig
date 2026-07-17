//! mez.device
const std = @import("std");
const zlua = @import("zlua");
const wlr = @import("wlroots");
const log = std.log.scoped(.Device);

fn device_error(L: *zlua.Lua) noreturn {
    L.raiseErrorStr("Unable to get device.", .{});
}

/// ---Get the type of a device
/// ---@param device userdata
/// ---@return string type
pub fn get_type(L: *zlua.Lua) i32 {
    const device = L.toUserdata(wlr.InputDevice, 1) catch device_error(L);
    _ = L.pushString(std.mem.span(@tagName(device.type).ptr));
    return 1;
}

/// ---Get the name of a device
/// ---@param device userdata
/// ---@return string name
pub fn get_name(L: *zlua.Lua) i32 {
    const device = L.toUserdata(wlr.InputDevice, 1) catch device_error(L);
    _ = if (device.name) |n| L.pushString(std.mem.span(n)) else L.pushNil();
    return 1;
}
