const std = @import("std");

const EventGen = @import("EventGen.zig");

pub fn main(init: std.process.Init) !void {
    // TODO: switch to juicy main allocator when we switch to 0.16.0
    var arena: std.heap.ArenaAllocator = .init(init.gpa);
    const gpa = arena.allocator();
    defer arena.deinit();

    var evgen = try EventGen.init(gpa);
    defer evgen.deinit(gpa);
    try evgen.generate(init.io, gpa);

    var stdout_buf: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buf);
    const stdout: *std.Io.Writer = &stdout_writer.interface;
    try evgen.write(stdout);
    try stdout.flush();
}
