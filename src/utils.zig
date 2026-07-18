const utils = @This();

const std = @import("std");

const log = std.log.scoped(.Utils);

pub fn oomPanic() noreturn {
    log.err("Out of memory error, exiting with 1", .{});
    std.process.exit(1);
}
