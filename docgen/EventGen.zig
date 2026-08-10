const EventGen = @This();

const std = @import("std");

/// key is the event documentation val is the number of references
events: std.StringHashMap(u8),

pub fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!*EventGen {
    const self = try allocator.create(EventGen);

    self.* = .{
        .events = .init(allocator),
    };

    return self;
}

pub fn deinit(self: *EventGen, allocator: std.mem.Allocator) void {
    // collect all the key pointers for freeing
    const key_ptrs = allocator.alloc([]const u8, self.events.count()) catch |err| {
        std.debug.panic("Can't free event key memory: {any}", .{ err });
    };
    var iter = self.events.keyIterator();
    var i: u16 = 0;
    while (iter.next()) |key| : (i += 1) key_ptrs[i] = key.*;

    self.events.clearAndFree();
    for (key_ptrs) |v| allocator.free(v);

    allocator.destroy(self);
}

pub fn generate(self: *EventGen, io: std.Io, allocator: std.mem.Allocator) !void {
    const proc = try std.process.spawn(io, .{
        .argv = &[_][]const u8{
            "zig",
            "build",
            "-Devent_gen=true",
        },
        .stdout = .ignore,
        .stderr = .pipe,
        .stdin = .ignore,
    });

    var reader_buf: [1024]u8 = undefined;
    var f_reader = proc.stderr.?.reader(io, &reader_buf);
    var reader = &f_reader.interface;
    while (true) {
        const chunk = reader.takeDelimiter('\n') catch |err| switch (err) {
            error.StreamTooLong => break,
            else => return err,
        } orelse break;

        if (std.mem.containsAtLeast(u8, chunk, 1, "@as")) {
            const start = std.mem.indexOf(u8, chunk, "\"") orelse continue;
            const end = std.mem.lastIndexOf(u8, chunk, "\"") orelse continue;

            const event = chunk[start + 1..end];
            if (self.events.get(event)) |ev| {
                _ = try self.events.getOrPutValue(event, ev + 1);
            } else {
                try self.events.put(try allocator.dupe(u8, event), 1);
            }
        }
    }
}

pub fn write(self: *EventGen, writer: *std.Io.Writer) !void {
    var iter = self.events.iterator();
    try writer.writeAll("---@alias mez.hook.Events\n");
    while (iter.next()) |v| try writer.print("{s}\n", .{ v.key_ptr.* });
}
