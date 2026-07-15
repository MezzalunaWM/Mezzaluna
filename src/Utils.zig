const std = @import("std");

const log = std.log.scoped(.Utils);

const Utils = @This();

pub fn oomPanic() noreturn {
    log.err("Out of memory error, exiting with 1", .{});
    std.process.exit(1);
}
