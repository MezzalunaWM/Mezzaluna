const Bridge = @This();

const std = @import("std");
const zlua = @import("zlua");

const gpa = std.heap.c_allocator;

pub fn getNestedField(L: *zlua.Lua, path: []const u8) bool {
    var tokens = std.mem.tokenizeScalar(u8, path, '.');
    var first = true;

    while (tokens.next()) |token| {
        const tok = gpa.dupeZ(u8, token) catch return false;
        if (first) {
            if(L.getGlobal(tok) == .nil) return false;
            first = false;
        } else {
            _ = L.getField(-1, tok);
            L.remove(-2);
        }

        if (L.isNil(-1)) {
            return false;
        }
    }

    return true;
}
