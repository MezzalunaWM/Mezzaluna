//! mez.fs
const Fs = @This();

const std = @import("std");
const zlua = @import("zlua");

const Lua = @import("Lua.zig");
const Utils = @import("../Utils.zig");

const gpa = &@import("../main.zig").gpa;
const io = &@import("../main.zig").io;
const log = std.log.scoped(.Device);

/// ---Join any number of paths into one path
/// ---@param ... string Paths to join
/// ---@return string
pub fn joinpath(L: *zlua.Lua) i32 {
    const nargs: i32 = L.getTop();
    if (nargs < 2) {
        L.raiseErrorStr("Expected at least two paths to join", .{});
    }

    var paths = std.ArrayList([:0]const u8).initCapacity(gpa.*, @intCast(nargs)) catch Utils.oomPanic();
    defer paths.deinit(gpa.*);

    var i: u8 = 1;
    while (i <= nargs) : (i += 1) {
        if (!L.isString(i)) {
            L.raiseErrorStr("Expected string at argument %d", .{i});
        }

        const partial_path = L.toString(i) catch unreachable;
        paths.append(gpa.*, partial_path) catch Utils.oomPanic();
    }

    const final_path: []const u8 = std.fs.path.join(gpa.*, paths.items) catch Utils.oomPanic();
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

    // create a metatable for the userdata and add set the __gc function
    L.newTable();
    L.pushFunction(zlua.wrap(directory__gc));
    L.setField(-2, "__gc");
    L.setMetatable(-2);

    // PLEASE CHECK THIS, IDK IF THIS IS CORRECT
    const iterator = L.newUserdata(std.Io.Dir.Iterator, 1);

    const dir = std.Io.Dir.cwd().openDir(io.*, path, .{ .iterate = true }) catch |err| {
        L.raiseErrorStr("Failed to open directory `{s}`: `{s}`", .{ path.ptr, @errorName(err).ptr });
    };
    iterator.* = dir.iterate();

    // the 1 upvalue is the userdata we just created
    L.pushClosure(zlua.wrap(directory_iterator), 1);
    return 1;
}

fn directory_iterator(L: *zlua.Lua) i32 {
    var iterator = L.toUserdata(std.Io.Dir.Iterator, zlua.Lua.upvalueIndex(1)) catch |err| {
        L.raiseErrorStr("Invalid user data: {}", .{ @errorName(err).ptr });
    };

    const entry = iterator.next(io.*) catch return 0; // the iterator shouldn't error
    if (entry) |e| {
        _ = L.pushString(e.name);
        L.pushAny(e.kind) catch Utils.oomPanic();
        return 2;
    }

    // no more values to return
    return 0;
}

fn directory__gc(L: *zlua.Lua) i32 {
    const iterator = L.toUserdata(std.Io.Dir.Iterator, 1) catch return 0;
    iterator.reader.dir.close(io.*);
    return 0;
}
