const LuaUtils = @This();

const std = @import("std");
const zlua = @import("zlua");

const View = @import("../View.zig");
const Seat = @import("../Seat.zig");
const Utils = @import("../Utils.zig");
const Bridge = @import("Bridge.zig");
const Remote = @import("Remote.zig");
const Lua = @import("Lua.zig");
const RemoteLua = @import("../RemoteLua.zig");

const server = &@import("../main.zig").server;
const gpa = std.heap.c_allocator;

pub fn coerceNumber(comptime x: type, number: zlua.Number) error{InvalidNumber}!x {
    const size = switch (@typeInfo(x)) {
        .int => .{ std.math.minInt(x), std.math.maxInt(x) },
        .float => .{ std.math.floatMin(x), std.math.floatMax(x) },
        else => unreachable,
    };
    if (number < size.@"0" or number > size.@"1" or std.math.isNan(number)) {
        return error.InvalidNumber;
    }
    switch (@typeInfo(x)) {
        .int => return @as(x, @intFromFloat(number)),
        .float => return @floatCast(number),
        else => @compileError("unsupported type"),
    }
}

pub fn coerceInteger(comptime x: type, number: zlua.Integer) error{InvalidInteger}!x {
    if (number < std.math.minInt(x) or number > std.math.maxInt(x) or std.math.isNan(number)) {
        return error.InvalidInteger;
    }
    switch (@typeInfo(x)) {
        .int => return @intCast(number),
        .float => return @as(x, @floatFromInt(number)),
        else => @compileError("unsupported type"),
    }
}

pub fn newLib(L: *zlua.Lua, f: []const zlua.FnReg) void {
    L.newLibTable(f); // documented as being unavailable, but it is.
    for (f) |value| {
        if (value.func == null) continue;
        L.pushClosure(value.func.?, 0);
        L.setField(-2, value.name);
    }
}

/// makes a best effort to convert the value at the top of the stack to a string
/// if we're unable to do so return "nil"
pub fn toStringEx(L: *zlua.Lua) [:0]const u8 {
    const errstr = "nil";
    _ = L.getGlobal("tostring") catch return errstr;
    L.insert(1);
    L.protectedCall(.{ .args = 1, .results = 1 }) catch return errstr;
    return L.toString(-1) catch errstr;
}

pub fn viewById(view_id: u64) ?*View {
    if (view_id == 0) {
        if (server.getDefaultSeat().focused_surface) |fs| {
            if (fs == .view) return fs.view;
        }
    } else {
        std.log.debug("looking for view_id {d}", .{view_id});
        return server.root.viewById(view_id);
    }
    return null;
}

pub fn seatFromId(id: u32) ?*Seat {
    var iter = server.seats.iterator(.forward);
    var j: u32 = 0;
    return while (iter.next()) |s| : (j += 1) {
        if (id == j) break s;
    } else null;
}

pub fn handleError(L: *zlua.Lua) void {
    if (Bridge.getNestedField(L, "debug.traceback")) {
        L.pushValue(1); // error message
        L.pushInteger(0); // level
        L.call(.{ .args = 2, .results = 1 });
        const error_traceback = L.toString(-1) catch unreachable;
        Lua.log.err("{s}", .{ error_traceback });
        RemoteLua.sendNewLogEntry(error_traceback);
    }
}
