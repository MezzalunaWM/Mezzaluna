//! mez.fs
const Fs = @This();

const std = @import("std");
const zlua = @import("zlua");

const Lua = @import("Lua.zig");
const Utils = @import("../Utils.zig");

const gpa = std.heap.c_allocator;

/// ---Join any number of paths into one path
/// ---@param ... string Paths to join
/// ---@return string?
pub fn joinpath(L: *zlua.Lua) i32 {
    const nargs: i32 = L.getTop();
    if (nargs < 2) {
        L.raiseErrorStr("Expected at least two paths to join", .{});
        return 0;
    }

    var paths = std.ArrayList([:0]const u8).initCapacity(gpa, @intCast(nargs)) catch Utils.oomPanic();
    defer paths.deinit(gpa);

    var i: u8 = 1;
    while (i <= nargs) : (i += 1) {
        if (!L.isString(i)) {
            L.raiseErrorStr("Expected string at argument %d", .{i});
            return 0;
        }

        const partial_path = L.toString(i) catch unreachable;
        paths.append(gpa, partial_path) catch Utils.oomPanic();
    }

    const final_path: []const u8 = std.fs.path.join(gpa, paths.items) catch Utils.oomPanic();
    defer gpa.free(final_path);

    _ = L.pushString(final_path);
    return 1;
}

/// ---List sub-directories given an abosolute parent path
/// ---@param path string 
/// ---@return string[] list of sub directories
pub fn subdirs(L: *zlua.Lua) i32 {
    const nargs: i32 = L.getTop();
    if (nargs != 1) {
        L.raiseErrorStr("Expected exactly one path", .{});
        return 0;
    }

    const path = L.checkString(1);

    var dir = std.fs.openDirAbsoluteZ(path, .{ .iterate = true }) catch {
        L.raiseErrorStr("Directory does not exist", .{});
    };
    defer dir.close();
    var dir_it = dir.iterate();

    L.newTable();

    var i: i32 = 1;
    while(dir_it.next() catch {
        L.raiseErrorStr("An error has occured while getting subdirectories", .{});
    }) |entry| : (i += 1) {
        if (entry.kind != .directory and entry.kind != .sym_link ) continue;

        L.pushInteger(i);
        _ = L.pushString(entry.name);
        L.setTable(-3);
    }

    return 1;
}
