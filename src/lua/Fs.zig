//! mez.fs
const Fs = @This();

const std = @import("std");
const zlua = @import("zlua");

const Lua = @import("Lua.zig");
const Utils = @import("../Utils.zig");

const gpa = std.heap.c_allocator;

/// ---Join any number of paths into one path
/// ---@param ... string Paths to join
/// ---@return string
pub fn joinpath(L: *zlua.Lua) i32 {
    const nargs: i32 = L.getTop();
    if (nargs < 2) {
        L.raiseErrorStr("Expected at least two paths to join", .{});
    }

    var paths = std.ArrayList([:0]const u8).initCapacity(gpa, @intCast(nargs)) catch Utils.oomPanic();
    defer paths.deinit(gpa);

    var i: u8 = 1;
    while (i <= nargs) : (i += 1) {
        if (!L.isString(i)) {
            L.raiseErrorStr("Expected string at argument %d", .{i});
        }

        const partial_path = L.toString(i) catch unreachable;
        paths.append(gpa, partial_path) catch Utils.oomPanic();
    }

    const final_path: []const u8 = std.fs.path.join(gpa, paths.items) catch Utils.oomPanic();
    defer gpa.free(final_path);

    _ = L.pushString(final_path);
    return 1;
}

/// ---open a directory and return its iterator
/// ---The iterator returns a `file_name` and `kind`
/// ---The kind may be any one of the following:
/// --- block_device,
/// --- character_device,
/// --- directory,
/// --- named_pipe,
/// --- sym_link,
/// --- file,
/// --- unix_domain_socket,
/// --- whiteout,
/// --- door,
/// --- event_port,
/// --- unknown,
/// ---
/// ---@param path string
/// ---@return function iterator
pub fn open_directory(L: *zlua.Lua) i32 {
    const path = L.checkString(1);

    const iterator = L.newUserdata(std.fs.Dir.Iterator);
    { // create a metatable for the userdata and add set the __gc function
        L.newTable();
        defer L.setMetatable(-2);
        L.pushFunction(zlua.wrap(directory__gc));
        L.setField(-2, "__gc");
    }

    const dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |err| {
        L.raiseErrorStr("Failed to open directory `{s}`: `{s}`", .{ path.ptr, @errorName(err).ptr });
    };
    iterator.* = dir.iterate();

    // the 1 upvalue is the userdata we just created
    L.pushClosure(zlua.wrap(directory_iterator), 1);
    return 1;
}

fn directory_iterator(L: *zlua.Lua) i32 {
    var iterator = L.toUserdata(std.fs.Dir.Iterator, zlua.Lua.upvalueIndex(1)) catch |err| {
        L.raiseErrorStr("Invalid user data: {}", .{ @errorName(err).ptr });
    };

    const entry = iterator.next() catch return 0; // the iterator shouldn't error
    if (entry) |e| {
        _ = L.pushString(e.name);
        L.pushAny(e.kind) catch Utils.oomPanic();
        return 2;
    }

    // no more values to return
    return 0;
}

fn directory__gc(L: *zlua.Lua) i32 {
    const iterator = L.toUserdata(std.fs.Dir.Iterator, 1) catch return 0;
    iterator.dir.close();
    return 0;
}
