const options = @This();

const std = @import("std");
const zlua = @import("zlua");

const server = &@import("../main.zig").server;
pub const log = std.log.scoped(.@"Lua.Options");

pub const Default = struct {
    new_view_output: c_int = 0,
    new_view_hidden: bool = false,

    pub fn pushTable(L: *zlua.Lua) void {
        L.newTable();

        inline for (std.meta.fields(@This())) |field| {
            L.pushAny(field.defaultValue().?) catch {
                log.err("Improper default value provided for option {s}", .{field.name});
                continue;
            };

            L.setField(-2, field.name);
        }
    }
};

pub fn get(
    comptime option: std.meta.FieldEnum(Default),
) !@FieldType(Default, @tagName(option)) {
    const L = &@import("../main.zig").lua.state.*;
    const option_name = @tagName(option);
    const FieldType = @FieldType(Default, option_name);

    std.debug.assert(L.getGlobal("mez") != .nil);
    defer L.pop(1);

    _ = L.pushString("opt");
    std.debug.assert(L.getTable(-2) == .table);
    defer L.pop(1);

    _ = L.getField(-1, option_name);
    defer L.pop(1);

    return L.toAny(FieldType, -1);
}
