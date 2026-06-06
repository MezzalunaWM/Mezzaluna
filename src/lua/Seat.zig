//! mez.seat
const Seat = @This();

const std = @import("std");
const zlua = @import("zlua");

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

// TODO: finish this
pub fn add_intput_device(L: *zlua.Lua) i32 {
    _ = L;
    return 0;
}

/// ---Get the focused view of a seat
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

/// ---Get the focused output of a seat
/// ---@param seat_id seat seat id
/// ---@return output_id? result nil if the seat provided doesn't exist or nothing is focused
pub fn get_focused_output(L: *zlua.Lua) i32 {
    const seat_id = LuaUtils.coerceInteger(u32, L.checkInteger(1)) catch seat_id_err(L);
    const seat = LuaUtils.seatFromId(seat_id);

    if (seat) |s| if (s.focused_output) |output| {
        L.pushInteger(@intCast(output.id));
        return 1;
    };

    L.pushNil();
    return 1;
}

/// ---Set the repeat information for a seat
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
    }

    return 0;
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
