//! mez.output
const std = @import("std");
const zlua = @import("zlua");

const Output = @import("../Output.zig");
const LuaUtils = @import("LuaUtils.zig");
const Utils = @import("../Utils.zig");
const Seat = @import("Seat.zig");
const SceneNodeData = @import("../SceneNodeData.zig").SceneNodeData;

const server = &@import("../main.zig").server;
const wlr = @import("wlroots");
const wl = @import("wayland").server.wl;
const posix = std.posix;
const gpa = std.heap.c_allocator;

const Mode = struct {
    width: i32,
    height: i32,
    refresh: i32,
    preferred: bool,
};

fn output_id_err(L: *zlua.Lua) noreturn {
    L.raiseErrorStr("The output id must be >= 0 and < inf", .{});
}

/// ---Get the ids for all available outputs
/// ---@return integer[]
pub fn get_all_ids(L: *zlua.Lua) i32 {
    var it = server.root.scene.outputs.iterator(.forward);
    var index: usize = 1;

    L.newTable();

    while (it.next()) |scene_output| : (index += 1) {
        if (scene_output.output.data == null) continue;

        const output = @as(*Output, @ptrCast(@alignCast(scene_output.output.data.?)));

        L.pushInteger(@intCast(index));
        L.pushInteger(@intCast(output.id));
        L.setTable(-3);
    }

    return 1;
}

/// ---Get the id for the focused output
/// ---@param integer? seat seat id, nil for the default seat
/// ---@return integer? result nil if the seat provided doesn't exist
pub fn get_focused_id(L: *zlua.Lua) i32 {
    const seat = if (!L.isNil(1)) blk: {
        const seat_id = LuaUtils.coerceInteger(u32, L.checkInteger(1)) catch Seat.seat_id_err(L);
        break :blk LuaUtils.seatFromId(seat_id) orelse {
            L.pushNil();
            return 1;
        };
    } else server.getDefaultSeat();

    if (seat.focused_output) |output| {
        L.pushInteger(@intCast(output.id));
        return 1;
    }

    L.pushNil();
    return 1;
}

/// Returns all the ids of views within an output
/// ---@param output_id integer 0 maps to focused output
/// ---@return integer[]?
pub fn get_views(L: *zlua.Lua) i32 {
    const output_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch output_id_err(L);

    const output: ?*Output = if (output_id == 0) server.getDefaultSeat().focused_output else server.root.outputById(output_id);
    if (output == null) {
        L.raiseErrorStr("Output with id %d not found\n", .{output_id});
    }

    var index: i32 = 1;
    L.newTable();

    const content = output.?.layers.content;
    if (@intFromPtr(content) == 0) unreachable;
    if (content.children.length() == 0) return 1; // No children

    var view_it = content.children.iterator(.forward);
    while (view_it.next()) |v| {
        if (v.data == null) unreachable;

        const scene_node_data: *SceneNodeData = @ptrCast(@alignCast(v.data.?));

        if (scene_node_data.* == .view) {
            L.pushInteger(@intCast(index));
            L.pushInteger(@intCast(scene_node_data.view.id));
            L.setTable(-3);

            index += 1;
        }
    }

    return 1;
}

const get_output_state = struct {
    rate: i32,
    scale: f32,
    resolution: wlr.Box,
    available_area: wlr.Box,
    transform: [:0]const u8,
    make: [:0]const u8,
    serial: [:0]const u8,
    model: [:0]const u8,
    description: [:0]const u8,
    name: [:0]const u8,
    modes: []Mode,
};

/// ---Get the state of an output
/// ---@param output_id integer 0 maps to focused output
/// ---@return get_output_state?
pub fn get_state(L: *zlua.Lua) i32 {
    const output_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch output_id_err(L);

    const output: ?*Output = if (output_id == 0) server.getDefaultSeat().focused_output else server.root.outputById(output_id);
    if (output) |o| {
        const output_layout = server.root.output_layout.get(o.wlr_output) orelse {
            L.pushNil();
            return 1;
        };

        const modes: []Mode = gpa.alloc(Mode, o.wlr_output.modes.length()) catch Utils.oomPanic();
        defer gpa.free(modes);
        var iter = o.wlr_output.modes.iterator(.forward);

        L.pushAny(get_output_state {
            .scale = o.wlr_output.scale,
            .resolution = .{
                .width = o.wlr_output.width,
                .height = o.wlr_output.height,
                .x = output_layout.x,
                .y = output_layout.y,
            },
            .rate = o.wlr_output.refresh,
            .available_area = o.non_exclusive_area,
            .transform = @tagName(o.wlr_output.transform),
            .make = std.mem.span(o.wlr_output.make orelse "(null)"),
            .serial = std.mem.span(o.wlr_output.serial orelse "(null)"),
            .model = std.mem.span(o.wlr_output.model orelse "(null)"),
            .description = std.mem.span(o.wlr_output.description orelse "(null)"),
            .name = std.mem.span(o.wlr_output.name),
            .modes = blk: {
                var i: u32 = 0; // I wonder how many modes a display can have
                while (iter.next()) |mode| : (i += 1) {
                    modes[i] = Mode{
                        .width = mode.width,
                        .height = mode.height,
                        .refresh = mode.refresh,
                        .preferred = mode.preferred,
                    };
                }
                break: blk modes;
            },
        }) catch unreachable;
        return 1;
    }

    L.pushNil();
    return 1;
}

/// all setter data is optional
const set_output_state = struct {
    position: ?wlr.Box, // TODO(squibid): impl
    scale: ?f32,
    transform: ?wl.Output.Transform,
    mode: ?Mode,
};

pub fn set_state(L: *zlua.Lua) i32 {
    const output_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch output_id_err(L);

    const output: ?*Output = if (output_id == 0) server.getDefaultSeat().focused_output else server.root.outputById(output_id);
    if (output) |o| {
        const lua_state = L.toAny(set_output_state, 2) catch unreachable;

        var new_state: wlr.Output.State = .init();
        defer new_state.finish();

        if (lua_state.scale) |v| new_state.setScale(if (v <= 0) o.wlr_output.scale else v);
        if (lua_state.transform) |v| new_state.setTransform(v);
        if (lua_state.mode) |v| new_state.setCustomMode(v.width, v.height, v.refresh);

        if (!o.wlr_output.testState(&new_state)) {
            L.raiseErrorStr("Output state is not usable! `{any}`", .{ new_state });
        }

        _ = o.wlr_output.commitState(&new_state);

        o.arrangeLayers();
        return 0;
    }

    L.pushNil();
    return 1;
}

/// ---Get the id of the output's fullscreened view if it exists
/// ---@param output_id integer 0 maps to focused output
/// ---@return integer?
pub fn get_fullscreen_view(L: *zlua.Lua) i32 {
    const output_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch output_id_err(L);

    const output: ?*Output = if (output_id == 0) server.getDefaultSeat().focused_output else server.root.outputById(output_id);
    if (output == null) return 0;

    const view = output.?.getEnabledFullscreen();
    if (view == null) return 0;

    L.pushInteger(@intCast(view.?.id));
    return 1;
}
