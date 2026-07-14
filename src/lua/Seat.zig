//! mez.seat
const Seat = @This();

const std = @import("std");
const zlua = @import("zlua");
const wlr = @import("wlroots");
const wl = @import("wayland").server.wl;

const LuaUtils = @import("LuaUtils.zig");
const Utils = @import("../Utils.zig");
const ServerSeat = @import("../Seat.zig");

const server = &@import("../main.zig").server;
const gpa = std.heap.c_allocator;

pub fn seat_id_err(L: *zlua.Lua) noreturn {
    L.raiseErrorStr("The seat id must be >= 0 and < inf", .{});
}

pub const options = struct {
    inherit: ?bool,
};

/// ---Create a new seat
/// ---@param name string the seat name
/// ---@param options options seat options
/// ---@return integer seat seat id
pub fn create(L: *zlua.Lua) i32 {
    const name = L.toString(1) catch {
        L.raiseErrorStr("The seat name must be a valid string", .{});
    };

    const seat = ServerSeat.init(name.ptr) catch {
        L.raiseErrorStr("Failed to create the new seat", .{});
    };

    const opts = L.toAny(options, 2) catch unreachable;
    if (opts.inherit != null and opts.inherit.?) {
        const repeat_info = server.getDefaultSeat().keyboard_group.wlr_group.keyboard.repeat_info;
        seat.keyboard_group.wlr_group.keyboard.setRepeatInfo(
            repeat_info.rate,
            repeat_info.delay,
        );
    }

    // the new seat starts on the same output as the default seat
    seat.focused_output = server.getDefaultSeat().focused_output;

    server.seats.append(seat);

    L.pushInteger(@intCast(server.seats.length() - 1));
    return 1;
}

/// ---Remove an existing seat
/// ---@param id integer
/// ---@return boolean has it been deleted
pub fn remove(L: *zlua.Lua) i32 {
    const seat_id = LuaUtils.coerceInteger(u32, L.checkInteger(1)) catch seat_id_err(L);
    const seat = LuaUtils.seatFromId(seat_id) orelse {
        L.pushBoolean(false);
        return 1;
    };
    if (seat == server.getDefaultSeat()) {
        L.pushBoolean(false);
        return 1;
    }

    seat.deinit();
    L.pushBoolean(true);
    return 1;
}

/// ---Get a seats name
/// ---@param seat_id integer
/// ---@return string? seat name
pub fn get_name(L: *zlua.Lua) i32 {
    const seat_id = LuaUtils.coerceInteger(u32, L.checkInteger(1)) catch seat_id_err(L);
    const seat = LuaUtils.seatFromId(seat_id);

    if (seat) |s| {
        _ = L.pushString(std.mem.span(s.wlr_seat.name));
    } else L.pushNil();

    return 1;
}

/// ---Set a seats name. Returns nil if no seat was found.
/// ---@param seat_id integer
/// ---@param name string
pub fn set_name(L: *zlua.Lua) i32 {
    const seat_id = LuaUtils.coerceInteger(u32, L.checkInteger(1)) catch seat_id_err(L);
    const seat = LuaUtils.seatFromId(seat_id);
    const name = L.toString(2) catch L.raiseErrorStr("Invalid seat name", .{});

    if (seat) |s| {
        s.wlr_seat.setName(name);
        return 0;
    }

    L.pushNil();
    return 1;
}

/// ---add an input device to a seat. Returns nil if no seat was found.
/// ---@param seat integer seat id
/// ---@param device userdata device
pub fn add_device(L: *zlua.Lua) i32 {
    const seat_id = LuaUtils.coerceInteger(u32, L.checkInteger(1)) catch seat_id_err(L);
    const seat = LuaUtils.seatFromId(seat_id);

    const device = L.toUserdata(wlr.InputDevice, 2) catch L.raiseErrorStr("Unable to get device.", .{});

    if (seat) |s| {
        s.addInputDevice(device);
        return 0;
    }

    L.pushNil();
    return 1;
}

/// ---remove an input device to a seat. Returns nil if no seat was found.
/// ---@param seat integer seat id
/// ---@param device userdata device
pub fn remove_device(L: *zlua.Lua) i32 {
    const seat_id = LuaUtils.coerceInteger(u32, L.checkInteger(1)) catch seat_id_err(L);
    const seat = LuaUtils.seatFromId(seat_id);

    const device = L.toUserdata(wlr.InputDevice, 2) catch L.raiseErrorStr("Unable to get device.", .{});

    if (seat) |s| {
        s.removeInputDevice(device);
        return 0;
    }

    L.pushNil();
    return 1;
}

/// ---Remove focus from current view, and set to given id. Returns nil if no seat was found.
/// ---@param seat_id integer Id of the seat to be focused, 0 for default seat
/// ---@param view_id integer? Id of the view to be focused, or nil to remove focus
pub fn set_focused_view(L: *zlua.Lua) i32 {
    const seat_id = LuaUtils.coerceInteger(u32, L.checkInteger(1)) catch seat_id_err(L);
    const seat = LuaUtils.seatFromId(seat_id) orelse seat_id_err(L);
    const view_id: ?c_longlong = L.optInteger(2);

    if (view_id == null) {
        seat.focusSurface(null);
    } else if (server.root.viewById(@intCast(view_id.?))) |view| {
        seat.focusSurface(.{ .view = view });
    }

    return 0;
}

/// ---Get the focused view of a seat. Returns nil if no seat was found.
/// ---@param seat_id seat seat id
/// ---@return view_id? result nil if the seat provided doesn't exist or nothing is focused
pub fn get_focused_view(L: *zlua.Lua) i32 {
    const seat_id = LuaUtils.coerceInteger(u32, L.checkInteger(1)) catch seat_id_err(L);
    const seat = LuaUtils.seatFromId(seat_id);

    if (seat) |s| if (s.focused_surface) |surface| switch (surface) {
        .view => |v| {
            L.pushInteger(@intCast(v.id));
            return 1;
        },
        .layer_surface => {},
    };

    L.pushNil();
    return 1;
}

/// ---Remove focus from current output, and set to given id. Returns nil if no seat was found.
/// ---@param seat_id integer Id of the seat to be focused
/// ---@param output_id integer? Id of the output to be focused
pub fn set_focused_output(L: *zlua.Lua) i32 {
    const seat_id = LuaUtils.coerceInteger(u32, L.checkInteger(1)) catch seat_id_err(L);
    const seat = LuaUtils.seatFromId(seat_id) orelse seat_id_err(L);

    const output_id = LuaUtils.coerceInteger(u64, L.checkInteger(2)) catch L.raiseErrorStr("Invalid output id", .{});
    if (server.root.outputById(output_id)) |output| {
        seat.focusOutput(output);
    }

    L.pushNil();
    return 1;
}

/// ---Get the focused output of a seat
/// ---@param seat_id seat seat id
/// ---@return output_id? result nil if the seat provided doesn't exist or nothing is focused
pub fn get_focused_output(L: *zlua.Lua) i32 {
    const seat_id = LuaUtils.coerceInteger(u32, L.checkInteger(1)) catch seat_id_err(L);
    const seat = LuaUtils.seatFromId(seat_id);

    if (seat) |s| if (s.focused_output) |output| {
        L.pushInteger(@intCast(output.id));
    } else L.pushNil();

    return 1;
}

/// ---Set the repeat information for a seat. Returns nil if no seat was found.
/// ---@param seat integer seat id
/// ---@param rate integer
/// ---@param delay integer
pub fn set_repeat_info(L: *zlua.Lua) i32 {
    const seat_id = LuaUtils.coerceInteger(u32, L.checkInteger(1)) catch seat_id_err(L);
    const seat = LuaUtils.seatFromId(seat_id);

    const rate = LuaUtils.coerceInteger(i32, L.checkInteger(2)) catch {
        L.raiseErrorStr("The rate must be a valid number", .{});
    };
    const delay = LuaUtils.coerceInteger(i32, L.checkInteger(3)) catch {
        L.raiseErrorStr("The delay must be a valid number", .{});
    };

    if (seat) |s| {
        s.keyboard_group.wlr_group.keyboard.setRepeatInfo(rate, delay);
        return 0;
    }

    L.pushNil();
    return 1;
}

/// ---Get the repeat information of a seat
/// ---@param seat integer seat id
/// ---@return { rate: integer, delay: integer }?
pub fn get_repeat_info(L: *zlua.Lua) i32 {
    const seat_id = LuaUtils.coerceInteger(u32, L.checkInteger(1)) catch seat_id_err(L);
    const seat = LuaUtils.seatFromId(seat_id);

    if (seat) |s| {
        const repeat_info = s.keyboard_group.wlr_group.keyboard.repeat_info;
        L.pushAny(.{
            .rate = repeat_info.rate,
            .delay = repeat_info.delay,
        }) catch Utils.oomPanic();
    } else {
        // if the seat isn't found then return nil
        L.pushNil();
    }

    return 1;
}
