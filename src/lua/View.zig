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
        if (o.output.data == null) {
            Lua.log.err("Output arbitrary data not assigned", .{});
            unreachable;
        }

        const output: *Output = @ptrCast(@alignCast(o.output.data.?));
        if (!output.state.enabled) continue;

        // Only search the content and fullscreen layers for views
        const layers = [_]*wlr.SceneTree{
            output.layers.content,
            output.layers.top,
        };

        for (layers) |layer| {
            if (layer.children.length() == 0) continue; // No children

            if (@intFromPtr(layer) == 0) unreachable;

            var view_it = layer.children.iterator(.forward);

            while (view_it.next()) |v| {
                if (v.data == null) {
                    Lua.log.err("Unassigned arbitrary data in scene graph", .{});
                    unreachable;
                }

                const scene_node_data: *SceneNodeData = @ptrCast(@alignCast(v.data.?));

                if (scene_node_data.* == .view) {
                    L.pushInteger(@intCast(index));
                    L.pushInteger(@intCast(scene_node_data.view.id));
                    L.setTable(-3);

                    index += 1;
                }
            }
        }
    }

    return 1;
}

/// ---Get the id for the focused view
/// ---@return integer?
pub fn get_focused_id(L: *zlua.Lua) i32 {
    if (server.getDefaultSeat().focused_surface) |fs| {
        if (fs == .view) {
            L.pushInteger(@intCast(fs.view.id));
            return 1;
        }
    }

    L.pushNil();
    return 1;
}

/// ---Close the view with view_id
/// ---@param view_id integer 0 maps to focused view
pub fn close(L: *zlua.Lua) i32 {
    const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);

    if (LuaUtils.viewById(view_id)) |v| {
        v.close();
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
    if(!L.isTable(2)) return 0;

    const view = LuaUtils.viewById(view_id);
    if(view == null) return 0;

    errdefer L.raiseErrorStr("Expected numbers for all fields of geometry", .{});

    _ = L.pushString("x");
    _ = L.getTable(2);
    const x: i32 = if (L.isNil(-1))
        view.?.geometry.x
    else
        try LuaUtils.coerceInteger(i32, L.checkInteger(-1));
    L.pop(1);

    _ = L.pushString("y");
    _ = L.getTable(2);
    const y: i32 = if (L.isNil(-1))
        view.?.geometry.y
    else
        try LuaUtils.coerceInteger(i32, L.checkInteger(-1));
    L.pop(1);

    _ = L.pushString("width");
    _ = L.getTable(2);
    const width: i32 = if (L.isNil(-1))
        view.?.geometry.width
    else
        try LuaUtils.coerceInteger(i32, L.checkInteger(-1));
    L.pop(1);

    _ = L.pushString("height");
    _ = L.getTable(2);
    const height: i32 = if (L.isNil(-1))
        view.?.geometry.height
    else
        try LuaUtils.coerceInteger(i32, L.checkInteger(-1));
    L.pop(1);

    view.?.setGeometry(x, y, width, height);

    return 0;
}

/// ---Get the geometry of the view
/// ---@param view_id integer 0 maps to focused view
/// ---@return Box?
pub fn get_geometry(L: *zlua.Lua) i32 {
    const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);
    const view = LuaUtils.viewById(view_id);
    if(view == null) return 0;

    L.newTable();

    _ = L.pushString("x");
    L.pushInteger(@intCast(view.?.geometry.x));
    L.setTable(-3);

    _ = L.pushString("y");
    L.pushInteger(@intCast(view.?.geometry.y));
    L.setTable(-3);

    _ = L.pushString("width");
    L.pushInteger(@intCast(view.?.geometry.width));
    L.setTable(-3);

    _ = L.pushString("height");
    L.pushInteger(@intCast(view.?.geometry.height));
    L.setTable(-3);

    return 1;
}

/// ---Get the geometry of the view before its last `set_geometry` or fullscreen
/// ---@param view_id integer 0 maps to the focused view
/// ---@return Box?
pub fn get_previous_geometry(L: *zlua.Lua) i32 {
    const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);
    const view = LuaUtils.viewById(view_id);
    if(view == null) return 0;

    L.newTable();

    _ = L.pushString("x");
    L.pushInteger(@intCast(view.?.previous_geometry.x));
    L.setTable(-3);

    _ = L.pushString("y");
    L.pushInteger(@intCast(view.?.previous_geometry.y));
    L.setTable(-3);

    _ = L.pushString("width");
    L.pushInteger(@intCast(view.?.previous_geometry.width));
    L.setTable(-3);

    _ = L.pushString("height");
    L.pushInteger(@intCast(view.?.previous_geometry.height));
    L.setTable(-3);

    return 1;
}

/// ---Remove focus from current view, and set to given id
/// ---@param view_id integer? Id of the view to be focused, or nil to remove focus
pub fn set_focused(L: *zlua.Lua) i32 {
    const view_id: ?c_longlong = L.optInteger(1);

    if (view_id == null) {
        server.getDefaultSeat().focusSurface(null);
    } else if (server.root.viewById(@intCast(view_id.?))) |view| {
        server.getDefaultSeat().focusSurface(.{ .view = view });
    }

    L.pushNil();
    return 1;
}

/// ---Toggle the view to enter fullscreen. Will enter the fullscreen layer
/// ---and remove any preexisting fullscreened view for it's output.
/// ---@param view_id integer 0 maps to focused view
pub fn toggle_fullscreen(L: *zlua.Lua) i32 {
    const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);

    if (LuaUtils.viewById(view_id)) |v| {
        v.toggleFullscreen();
    }

    return 0;
}

/// ---True if view is fullscreened
/// ---@param view_id integer 0 maps to focused view
/// ---@return bool
pub fn get_fullscreen(L: *zlua.Lua) i32 {
    const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);
    const view = LuaUtils.viewById(view_id);

    L.pushBoolean(if (view == null) false else view.?.isFullscreen());
    return 1;
}

/// ---Get the title of the view
/// ---@param view_id integer 0 maps to focused view
/// ---@return string?
pub fn get_title(L: *zlua.Lua) i32 {
    const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);

    if (LuaUtils.viewById(view_id)) |v| {
        if (v.xdg_toplevel.title == null) {
            L.pushNil();
            return 1;
        }

        _ = L.pushString(std.mem.span(v.xdg_toplevel.title.?));
        return 1;
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
        if (v.xdg_toplevel.app_id == null) {
            L.pushNil();
            return 1;
        }

        _ = L.pushString(std.mem.span(v.xdg_toplevel.app_id.?));
        return 1;
    }

    L.pushNil();
    return 1;
}

/// ---Enable or disable a view
/// ---@param view_id integer 0 maps to focused view
/// ---@param enabled boolean
pub fn set_enabled(L: *zlua.Lua) i32 {
    const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);
    if (!L.isBoolean(2)) {
        L.raiseErrorStr("argument 2 must be a boolean", .{});
    }
    const activate = L.toBoolean(2);

    if (LuaUtils.viewById(view_id)) |v| {
        v.scene_tree.node.setEnabled(activate);
        return 0;
    }

    L.pushNil();
    return 1;
}

/// ---Check if a view is enabled
/// ---@param view_id integer 0 maps to focused view
/// ---@return boolean?
pub fn get_enabled(L: *zlua.Lua) i32 {
    const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);

    if (LuaUtils.viewById(view_id)) |v| {
        _ = L.pushBoolean(v.scene_tree.node.enabled);
        return 1;
    }

    L.pushNil();
    return 1;
}

/// ---Set a view you intend to resize
/// ---@param view_id integer 0 maps to focused view
/// ---@param enable boolean
pub fn set_resizing(L: *zlua.Lua) i32 {
    const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);
    if (!L.isBoolean(2)) {
        L.raiseErrorStr("argument 2 must be a boolean", .{});
    }
    const resizing = L.toBoolean(2);

    if (LuaUtils.viewById(view_id)) |v| {
        _ = v.xdg_toplevel.setResizing(resizing);
        return 0;
    }

    L.pushNil();
    return 1;
}

/// ---Check if a view is resizing
/// ---@param view_id integer 0 maps to focused view
/// ---@return boolean? nil if view cannot be found
pub fn get_resizing(L: *zlua.Lua) i32 {
    const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);

    if (LuaUtils.viewById(view_id)) |v| {
        _ = L.pushBoolean(v.xdg_toplevel.current.resizing);
        return 1;
    }

    L.pushNil();
    return 1;
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
