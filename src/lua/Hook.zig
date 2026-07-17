//! mez.hook
const Hook = @This();

const std = @import("std");
const zlua = @import("zlua");
const config = @import("config");

const Utils = @import("../Utils.zig");
const LuaUtils = @import("LuaUtils.zig");
const RemoteLua = @import("../RemoteLua.zig");

const server = &@import("../main.zig").server;
const gpa = &@import("../main.zig").gpa;
const Lua = &@import("../main.zig").lua;
const log = std.log.scoped(.Hook);

pub const Events = struct {
    const Node = struct {
        hook: *const HookData,
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

    pub fn put(self: *Events, key: []const u8, hook: *const HookData) !void {
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

    pub fn del(self: *Events, key: []const u8, hook: *const HookData) void {
        if (self.events.get(key)) |e| {
            var node = e.first;
            while (node) |n| : (node = n.next) {
                const data: *Node = @fieldParentPtr("node", n);
                if (data.hook.options.lua_cb_ref_idx == hook.options.lua_cb_ref_idx) e.remove(n);
            }
        }
    }

    pub fn exec(self: *Events, comptime event: []const u8, args: anytype, comptime desc: []const u8) void {
        const ArgsType = @TypeOf(args);
        const args_type_info = @typeInfo(ArgsType);
        if (args_type_info != .@"struct") {
            @compileError("expected tuple or struct argument, found " ++ @typeName(ArgsType));
        }

        comptime if (config.event_gen) {
            // combine all the name and types of passed in args
            var fields: []const u8 = &[_]u8{};
            const args_fields = args_type_info.@"struct".fields;
            if (args_fields.len > 0) fields = std.fmt.comptimePrint("| args:", .{});
            for (args_fields) |field| {
                fields = std.fmt.comptimePrint("{s} {s}:{s}", .{
                    fields,
                    field.name,
                    @typeName(field.type),
                });
            }
            if (args_fields.len > 0) fields = fields ++ " ";

            // print out the event information in luadoc @alias format
            @compileLog(std.fmt.comptimePrint("---| '{s}' [# {s} {s}]", .{
                event,
                desc,
                fields,
            }));
        };

        if (self.events.get(event)) |e| {
            var node = e.first;
            while (node) |n| : (node = n.next) {
                const data: *Node = @fieldParentPtr("node", n);
                data.hook.callback(args);
            }
        }
    }
};

pub const HookData = struct {
    events: [][]const u8, // a list of events
    options: struct {
        // group: []const u8, // TODO: do we need groups?
        once: bool,
        /// This is the location of the callback lua function in the lua registry
        lua_cb_ref_idx: i32,
    },

    pub fn init() *HookData {
        const self = gpa.create(HookData) catch Utils.oomPanic();
        return self;
    }

    pub fn deinit(self: *HookData) void {
        for (self.events) |value| {
            server.events.del(value, self);
        }
        _ = server.hooks.remove(self.options.lua_cb_ref_idx);
        gpa.destroy(self);
    }

    pub fn callback(self: *const HookData, args: anytype) void {
        const t = Lua.state.getIndexRaw(zlua.registry_index, self.options.lua_cb_ref_idx);
        if (t != zlua.LuaType.function) {
            RemoteLua.sendNewLogEntry("Failed to call hook, it doesn't have a callback.");
            Lua.state.pop(1);
            return;
        }

        // allow passing any arguments to the lua hook
        var i: u8 = 0;
        inline for (args, 1..) |field, k| {
            Lua.state.pushAny(field) catch {
                std.log.err("Unabled to push field to callback", .{});
                Lua.state.pushNil();
            };
            i = k;
        }

        Lua.state.protectedCall(.{ .args = i }) catch LuaUtils.handleError(Lua.state);
        Lua.state.pop(-1);

        if (self.options.once) @constCast(self).deinit();
    }
};

/// ---Create a new hook on an event
/// ---@param events (string | string[])
/// ---@param options { callback: fun(...), once: boolean? }
/// ---@return number hook id
pub fn add(L: *zlua.Lua) i32 {
    L.checkType(2, .table);

    var hook: *HookData = .init();
    errdefer hook.deinit();

    // We support both a string and a table of strings as the first value of
    // add. Regardless of which type is passed in we create an arraylist of
    // []const u8's
    if (L.isTable(1)) {
        hook.events = gpa.alloc(comptime []const u8, L.lenRaw(1)) catch Utils.oomPanic();
        var i: u32 = 0;
        L.pushNil();
        while (L.next(1)) {
            if (L.isString(-1)) {
                const s = L.checkString(-1);
                hook.events[i] = gpa.dupe(u8, s) catch Utils.oomPanic();
                i += 1;
            }
            L.pop(1);
        }
    } else if (L.isString(1)) {
        hook.events = gpa.alloc(comptime []const u8, 1) catch Utils.oomPanic();
        const s = L.checkString(1);
        hook.events[0] = gpa.dupe(u8, s) catch Utils.oomPanic();
    }

    _ = L.getField(2, "callback");
    if (L.isFunction(-1)) {
        hook.options.lua_cb_ref_idx = L.ref(zlua.registry_index);
    }

    _ = L.getField(2, "once");
    hook.options.once = if(L.isBoolean(-1)) L.toBoolean(-1) else false;

    // TEST: this should be safe as the lua_cb_ref_idx's should never be the same
    // but that all really depends on the implementation of the hashmap
    server.hooks.put(hook.options.lua_cb_ref_idx, hook) catch Utils.oomPanic();

    for (hook.events) |value| {
        server.events.put(value, hook) catch Utils.oomPanic();
    }

    L.pushInteger(hook.options.lua_cb_ref_idx);
    return 1;
}

/// ---Remove an existing hook
/// ---@param id number
/// ---@return boolean has it been deleted
pub fn del(L: *zlua.Lua) i32 {
    const hook_id = LuaUtils.coerceInteger(i32, L.checkInteger(1)) catch L.raiseErrorStr("hook id must be a valid number", .{});
    const hook = server.hooks.get(hook_id);
    if (hook == null) L.raiseErrorStr("hook {} does not exist", .{hook_id});

    hook.?.deinit();
    return 0;
}
