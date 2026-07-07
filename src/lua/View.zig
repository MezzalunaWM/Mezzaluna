//! mez.view
const std = @import("std");
const zlua = @import("zlua");
const wlr = @import("wlroots");
const wl = @import("wayland").server.wl;

const Output = @import("../Output.zig");
const Lua = @import("Lua.zig");
const View = @import("../View.zig");
const SceneNodeData = @import("../SceneNodeData.zig").SceneNodeData;
const LuaUtils = @import("LuaUtils.zig");
const Seat = @import("Seat.zig");

const server = &@import("../main.zig").server;

fn view_id_err(L: *zlua.Lua) noreturn {
    L.raiseErrorStr("The view id must be >= 0 and < inf", .{});
}

// ---Get the ids for all available views
// ---@return integer[]?
pub fn get_all_ids(L: *zlua.Lua) i32 {
    var output_it = server.root.output_layout.outputs.iterator(.forward);

    var index: i32 = 1;
    L.newTable();

    while (output_it.next()) |o| {
        std.debug.assert(o.output.data != null);
        const output: *Output = @ptrCast(@alignCast(o.output.data.?));
        if (!output.state.enabled) continue;

        // Only search the content and fullscreen layers for views
        const layers = [_]*wlr.SceneTree{
            output.layers.content,
            output.layers.top,
        };

        for (layers) |layer| {
            if (layer.children.length() == 0) continue; // No children

            var view_it = layer.children.iterator(.forward);
            while (view_it.next()) |v| {
                std.debug.assert(v.data != null);
                const snd: *SceneNodeData = @ptrCast(@alignCast(v.data.?));

                if (snd.* == .view) {
                    L.pushInteger(@intCast(index));
                    L.pushInteger(@intCast(snd.view.id));
                    L.setTable(-3);

                    index += 1;
                }
            }
        }
    }

    return 1;
}

/// ---Get the id for the focused view
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

    if (seat.focused_surface) |fs| {
        if (fs == .view) {
            L.pushInteger(@intCast(fs.view.id));
            return 1;
        }
    }

    L.pushNil();
    return 1;
}

/// ---@class Box
/// ---@field x number?
/// ---@field y number?
/// ---@field width number?
/// ---@field height number?

/// ---Position and size the view. Size includes borders and position is from top left.
/// ---@param view_id integer 0 maps to focused view
/// ---@param geometry Box Missing dimensions map to current dimensions
pub fn set_geometry(L: *zlua.Lua) i32 {
    const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);
    if (!L.isTable(2)) return 0;

    const view = LuaUtils.viewById(view_id);
    if (view == null) return 0;

    errdefer L.raiseErrorStr("Expected numbers for all fields of geometry", .{});

    _ = L.getField(2, "x");
    const x: i32 = if (L.isNil(-1))
        view.?.current.geometry.x
    else
        try LuaUtils.coerceInteger(i32, L.checkInteger(-1));
    L.pop(1);

    _ = L.getField(2, "y");
    const y: i32 = if (L.isNil(-1))
        view.?.current.geometry.y
    else
        try LuaUtils.coerceInteger(i32, L.checkInteger(-1));
    L.pop(1);

    _ = L.getField(2, "width");
    const width: i32 = if (L.isNil(-1))
        view.?.current.geometry.width
    else
        try LuaUtils.coerceInteger(i32, L.checkInteger(-1));
    L.pop(1);

    _ = L.getField(2, "height");
    const height: i32 = if (L.isNil(-1))
        view.?.current.geometry.height
    else
        try LuaUtils.coerceInteger(i32, L.checkInteger(-1));
    L.pop(1);

    view.?.setGeometry(x, y, width, height);
    view.?.setEnabled(true);

    return 0;
}

/// ---Get the geometry of the view
/// ---@param view_id integer 0 maps to focused view
/// ---@return Box?
pub fn get_geometry(L: *zlua.Lua) i32 {
    const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);

    if (LuaUtils.viewById(view_id)) |v| {
        L.newTable();

        L.pushInteger(@intCast(v.current.geometry.x));
        L.setField(-2, "x");

        L.pushInteger(@intCast(v.current.geometry.y));
        L.setField(-2, "y");

        L.pushInteger(@intCast(v.current.geometry.width));
        L.setField(-2, "width");

        L.pushInteger(@intCast(v.current.geometry.height));
        L.setField(-2, "height");

        return 1;
    }

    L.pushNil();
    return 1;
}

/// ---Get the geometry of the view before its last `set_geometry` or fullscreen
/// ---@param view_id integer 0 maps to the focused view
/// ---@return Box?
pub fn get_previous_geometry(L: *zlua.Lua) i32 {
    const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);

    if (LuaUtils.viewById(view_id)) |v| {
        L.newTable();

        L.pushInteger(@intCast(v.previous_geometry.x));
        L.setField(-2, "x");

        L.pushInteger(@intCast(v.previous_geometry.y));
        L.setField(-2, "y");

        L.pushInteger(@intCast(v.previous_geometry.width));
        L.setField(-2, "width");

        L.pushInteger(@intCast(v.previous_geometry.height));
        L.setField(-2, "height");

        return 1;
    }

    L.pushNil();
    return 1;
}

/// ---Set the view's fullscreen status. Will enter the fullscreen layer
/// ---if true and will enter content layer if false.
/// ---and remove any preexisting fullscreened view for it's output.
/// ---@param view_id integer 0 maps to focused view
/// ---@param fullscreen bool status of fullscreen
pub fn set_fullscreen(L: *zlua.Lua) i32 {
    const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);
    const fullscreen = L.toBoolean(2);

    if (LuaUtils.viewById(view_id)) |v| {
        v.setFullscreen(fullscreen);
    }

    return 0;
}

/// ---True if view is fullscreened, false otherwise
/// ---@param view_id integer 0 maps to focused view
/// ---@return bool?
pub fn get_fullscreen(L: *zlua.Lua) i32 {
    const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);

    if (LuaUtils.viewById(view_id)) |v| {
        _ = L.pushBoolean(v.current.fullscreen);
        return 1;
    }

    L.pushNil();
    return 1;
}


/// ---Remove focus from current view, and set to given id
/// ---@param view_id integer? Id of the view to be focused, or nil to remove focus
pub fn set_focused(L: *zlua.Lua) i32 {
    const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);

    if(LuaUtils.viewById(view_id)) |v| {
        server.getDefaultSeat().focusSurface(.{ .view = v });
    } else {
        server.getDefaultSeat().focusSurface(null);
    }

    return 0;
}

/// ---Enable or disable a view
/// ---@param view_id integer 0 maps to focused view
/// ---@param enabled boolean
pub fn set_enabled(L: *zlua.Lua) i32 {
    const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);
    const enabled = L.toBoolean(2);

    if (LuaUtils.viewById(view_id)) |v| {
        v.setEnabled(enabled);
    }

    return 0;
}

/// ---Check if a view is enabled
/// ---@param view_id integer 0 maps to focused view
/// ---@return boolean?
pub fn get_enabled(L: *zlua.Lua) i32 {
    const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);

    if (LuaUtils.viewById(view_id)) |v| {
        _ = L.pushBoolean(v.current.enabled);
        return 1;
    }

    L.pushNil();
    return 1;
}

/// ---Set the view's resizing status.
/// ---@param view_id integer 0 maps to focused view
/// ---@param resizing bool status of resizing
pub fn set_resizing(L: *zlua.Lua) i32 {
    const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);
    const resizing = L.toBoolean(2);

    if (LuaUtils.viewById(view_id)) |v| {
        v.setResizing(resizing);
    }

    return 0;
}

/// ---True if view is resizing, false otherwise
/// ---@param view_id integer 0 maps to focused view
/// ---@return bool
pub fn get_resizing(L: *zlua.Lua) i32 {
    const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);

    if (LuaUtils.viewById(view_id)) |v| {
        _ = L.pushBoolean(v.current.resizing);
        return 1;
    }

    L.pushNil();
    return 1;
}

/// ---Set the window decoration style for a view
/// ---@param view_id integer 0 maps to focused view
/// ---@param mode "server_side", "client_side" or "none"
pub fn set_decoration_mode(L: *zlua.Lua) i32 {
    const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);
    if(!L.isString(2)) { 
        L.raiseErrorStr("argument 2 must be a string", .{});
    }

    const mode_str = L.checkString(2);
    const mode: wlr.XdgToplevelDecorationV1.Mode = if (std.mem.eql(u8, mode_str, "server_side")) .server_side
        else if (std.mem.eql(u8, mode_str, "client_side")) .client_side
        else if (std.mem.eql(u8, mode_str, "none")) .none
        else L.raiseErrorStr("argument two must be one of { \"server_side\", \"client_side\", \"none\" }", .{});

    if(LuaUtils.viewById(view_id)) |v| {
        v.setDecorationMode(mode);
    }

    return 0;
}

/// ---Set the window decoration style for a view
/// ---@param view_id integer 0 maps to focused view
/// ---@return string? current view decoration state or nil if not found
pub fn get_decoration_mode(L: *zlua.Lua) i32 {
    const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);

    if(LuaUtils.viewById(view_id)) |v| {
        _ = L.pushString(switch(v.current.decoration_mode) {
            .client_side => "client_side",
            .server_side => "server_side",
            .none => "none"
        });
        return 1;
    }

    L.pushNil();
    return 1;
}

/// ---@class Edges
/// ---@field left boolean?
/// ---@field top boolean?
/// ---@field right boolean?
/// ---@field bottom boolean?

/// ---Set the tiling edge status of a view
/// ---@param view_id integer 0 maps to focused view
/// ---@param edges Edges tiling edges
pub fn set_tiled_edges(L: *zlua.Lua) i32 {
    const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);
    if(!L.isTable(2)) {
        L.raiseErrorStr("Expected table for argument 2, found {s}", .{L.typeName(L.typeOf(2))});
    }

    const view = LuaUtils.viewById(view_id);
    if (view == null) return 0;

    errdefer L.raiseErrorStr("Expected boolean for all fields of edges", .{});

    if (LuaUtils.viewById(view_id)) |v| {
        _ = L.getField(2, "left");
        const left: bool = if (L.isNil(-1))
            v.current.tiled_edges.left
        else
            L.toBoolean(-2);
        L.pop(1);

        _ = L.getField(2, "top");
        const top: bool = if (L.isNil(-1))
            v.current.tiled_edges.top
        else
            L.toBoolean(-2);
        L.pop(1);

        _ = L.getField(2, "right");
        const right: bool = if (L.isNil(-1))
            v.current.tiled_edges.right
        else
            L.toBoolean(-2);
        L.pop(1);

        _ = L.getField(2, "bottom");
        const bottom: bool = if (L.isNil(-1))
            v.current.tiled_edges.bottom
        else
            L.toBoolean(-2);
        L.pop(1);

        v.setTiledEdges(.{
            .left = left,
            .top = top,
            .right = right,
            .bottom = bottom
        });
    }

    return 0;
}

/// ---Set the tiling edge status of a view
/// ---@param view_id integer 0 maps to focused view
/// ---@return Edges?
pub fn get_tiled_edges(L: *zlua.Lua) i32 {
    const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);

    if (LuaUtils.viewById(view_id)) |v| {
        L.newTable();

        L.pushBoolean(v.current.tiled_edges.left);
        L.setField(-2, "left");

        L.pushBoolean(v.current.tiled_edges.top);
        L.setField(-2, "top");

        L.pushBoolean(v.current.tiled_edges.right);
        L.setField(-2, "right");

        L.pushBoolean(v.current.tiled_edges.bottom);
        L.setField(-2, "bottom");

        return 1;
    }

    L.pushNil();
    return 1;
}

/// ---Set a view as closing (part of the state cycle)
/// ---@param view_id integer 0 maps to focused view
/// ---@param closing boolean
pub fn set_close(L: *zlua.Lua) i32 {
    const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);
    const close = L.toBoolean(2);

    if (LuaUtils.viewById(view_id)) |v| {
        v.setClose(close);
    }

    return 0;
}

pub fn get_close(L: *zlua.Lua) i32 {
    const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);

    if (LuaUtils.viewById(view_id)) |v| {
        _ = L.pushBoolean(v.current.close);
        return 1;
    }

    L.pushNil();
    return 1;
}

/// ---Get the title of the view
/// ---@param view_id integer 0 maps to focused view
/// ---@return string?
pub fn get_title(L: *zlua.Lua) i32 {
    const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);

    if (LuaUtils.viewById(view_id)) |v| {
        if (v.xdg_toplevel.title) |title| {
            _ = L.pushString(std.mem.span(title));
            return 1;
        }
    }

    L.pushNil();
    return 1;
}

/// ---Get the app_id of the view
/// ---@param view_id integer 0 maps to focused view
/// ---@return string?
pub fn get_app_id(L: *zlua.Lua) i32 {
    const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);

    if (LuaUtils.viewById(view_id)) |v| {
        if(v.xdg_toplevel.app_id) |app_id| {
            _ = L.pushString(std.mem.span(app_id));
            return 1;
        }
    }

    L.pushNil();
    return 1;
}


/// --- Apply all pending state changes
pub fn apply(_: *zlua.Lua) i32 {
    server.root.applyPending();

    return 0;
}

// ---Set the borders of a view
// ---@param view_id view_id 0 maps to focused view
// ---@param options table options for the view's borders
pub fn set_border(L: *zlua.Lua) i32 {
    const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);

    var border_color: ?[4]f32 = null;
    var width: ?u32 = null;

    _ = L.pushString("color");
    if (L.getTable(2) != .nil) {
        if (!L.isString(-1)) L.raiseErrorStr("The color must be a string", .{});
        const color = L.checkString(-1);
        border_color = color: {
            errdefer L.raiseErrorStr("The color must be a valid hex string", .{});

            var start_color_idx: u8 = 0;
            if (color[0] == '#') start_color_idx = 1;
            const color_fields = (color.len - start_color_idx) / 2;

            var alpha: ?f32 = null;
            if (color_fields != 4) {
                if (color_fields != 3) L.raiseErrorStr("The color must be at least 6 characters long", .{});
                alpha = 1;
            }

            const r = ((@as(f32, @floatFromInt(try std.fmt.parseInt(u8, color[start_color_idx .. start_color_idx + 2], 16))) / 255.0) * 1000.0) / 1000.0;
            const g = ((@as(f32, @floatFromInt(try std.fmt.parseInt(u8, color[start_color_idx + 2 .. start_color_idx + 4], 16))) / 255.0) * 1000.0) / 1000.0;
            const b = ((@as(f32, @floatFromInt(try std.fmt.parseInt(u8, color[start_color_idx + 4 .. start_color_idx + 6], 16))) / 255.0) * 1000.0) / 1000.0;
            const a = alpha orelse ((@as(f32, @floatFromInt(try std.fmt.parseInt(u8, color[start_color_idx + 6 .. start_color_idx + 8], 16))) / 255.0) * 1000.0) / 1000.0;

            break :color .{ r, g, b, a };
        };
    }

    _ = L.pushString("width");
    if (L.getTable(2) != .nil) {
        width = LuaUtils.coerceInteger(u32, L.checkInteger(-1)) catch {
            L.raiseErrorStr("The border width must be >= 0 and < inf", .{});
        };
    }

    if (LuaUtils.viewById(view_id)) |v| {
        if (border_color != null) v.setBorderColor(&border_color.?);

        if (width != null and width.? != v.border_width) {
            v.border_width = @intCast(width.?);
            // the size has changed which means we need to update the borders
            v.resizeBorders();
        }

        return 0;
    }

    return 0;
}

// ---Raise view to render above other views
// ---@param view_id view_id 0 maps to focused view
pub fn raise_to_top(L: *zlua.Lua) i32 {
    const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);

    if (LuaUtils.viewById(view_id)) |v| {
        v.scene_tree.node.raiseToTop();
    }

    return 0;
}

/// TODO: impl
/// Setting the wm capabilities is for telling the client what they can request.
/// This is important to letting the user define whatever type of layout they
/// wish and have it be as seamless as possbile.
///
/// NOTE(squibid): this should be handled by the layout_manager to reduce the
/// work required by the user
pub fn setWmCapabilities(L: *zlua.Lua) i32 {
    _ = L;
    return 0;
}
