const std = @import("std");

const Utils = @This();

pub fn oomPanic() noreturn {
    std.log.err("Out of memory error, exiting with 1", .{});
    std.process.exit(1);
}
