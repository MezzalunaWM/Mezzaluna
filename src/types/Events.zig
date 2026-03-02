pub const Events = @This();

const std = @import("std");

const Hook = @import("Hook.zig");

const server = &@import("../main.zig").server;

const Node = struct {
    hook: *const Hook,
    node: std.SinglyLinkedList.Node,
};

events: std.StringHashMap(*std.SinglyLinkedList),
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) !Events {
    return Events{
        .allocator = allocator,
        .events = .init(allocator),
    };
}

pub fn put(self: *Events, key: []const u8, hook: *const Hook) !void {
    var ll: *std.SinglyLinkedList = undefined;
    if (self.events.get(key)) |sll| {
        ll = sll;
    } else {
        ll = try self.allocator.create(std.SinglyLinkedList);
        ll.* = .{};
        try self.events.put(key, ll);
    }
    const data = try self.allocator.create(Node);
    data.* = .{
        .hook = hook,
        .node = .{},
    };
    ll.prepend(&data.node);
}

pub fn del(self: *Events, key: []const u8, hook: *const Hook) void {
    if (self.events.get(key)) |e| {
        var node = e.first;
        while (node) |n| : (node = n.next) {
            const data: *Node = @fieldParentPtr("node", n);
            if (data.hook.options.lua_cb_ref_idx == hook.options.lua_cb_ref_idx) e.remove(n);
        }
    }
}

pub fn exec(self: *Events, event: []const u8, args: anytype) void {
    if (self.events.get(event)) |e| {
        var node = e.first;
        while (node) |n| : (node = n.next) {
            const data: *Node = @fieldParentPtr("node", n);
            data.hook.callback(args);
        }
    }
}
