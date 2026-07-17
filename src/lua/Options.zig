const std = @import("std");
const zlua = @import("zlua");

const server = &@import("../main.zig").server;
pub const log = std.log.scoped(.Options);

const DEFAULT_OPTIONS = .{
    .{ .name = "new_view_output", .default = 0 },
    .{ .name = "new_view_hidden", .default = false }
};

const default_options = struct {
    new_view_output: c_int = 0,
    new_view_hidden: bool = false
};

pub fn getDefaultOptions(L: *zlua.Lua) void {
    L.newTable();

    inline for(@typeInfo(default_options).@"struct".fields) |op| {
        L.pushAny(op.defaultValue().?) catch {
            log.err("Improper default value provided for option {s}", .{op.name});
            continue;
        };

        L.setField(-2, op.name);
    }
}

pub fn getOption(comptime T: zlua.LuaType, option_name: [:0]const u8) ?ReturnTypeFromLuaType(T) {
    const L = &@import("../main.zig").lua.state.*;

    if(L.getGlobal("mez") == .nil) unreachable;
    defer L.pop(1);

    _ = L.pushString("opt");
    if(L.getTable(-2) != .table) {
        unreachable;
    }
    defer L.pop(1);

    _ = L.getField(-1, option_name);

    const result: ?ReturnTypeFromLuaType(T) = switch (T) {
        .boolean => L.toBoolean(-1),
        .number => L.toNumber(-1) catch {
            log.err("Failed to convert option '{s}' to number", .{option_name});
            return null;
        },
        .string => blk: {
            const c_str = L.toString(-1) catch {
                log.err("Failed to convert option '{s}' to string", .{option_name});
                break :blk null;
            };
            break :blk std.mem.span(c_str);
        },
        else => {
            log.err("Unsupported option type for '{s}'", .{option_name});
            return null;
        },
    };
    
    L.pop(1);
    return result;
}

fn ReturnTypeFromLuaType(comptime T: zlua.LuaType) type {
    return switch (T) {
        .boolean => bool,
        .number => zlua.Number,
        .string => []const u8,
        else => @compileError("Unsupported LuaType for options"),
    };
}
