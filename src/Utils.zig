const Utils = @This();

const std = @import("std");

pub fn oomPanic() noreturn {
    std.log.err("Out of memory error, exiting with 1", .{});
    std.process.exit(1);
}
