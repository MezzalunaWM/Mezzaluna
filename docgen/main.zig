const std = @import("std");

const EventGen = @import("EventGen.zig");

pub fn main() !void {
    var evgen = try EventGen.init(std.heap.page_allocator);
    defer evgen.deinit();
    try evgen.generate();

    var stdout_buf: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout: *std.Io.Writer = &stdout_writer.interface;
    try evgen.write(stdout);
    try stdout.flush();
}
