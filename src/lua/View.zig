const std = @import("std");
const zlua = @import("zlua");
const wlr = @import("wlroots");

const Output = @import("../Output.zig");
const View = @import("../View.zig");
const SceneNodeData = @import("../SceneNodeData.zig").SceneNodeData;
const LuaUtils = @import("LuaUtils.zig");

const server = &@import("../main.zig").server;

fn view_id_err(L: *zlua.Lua) noreturn {
  L.raiseErrorStr("The view id must be >= 0 and < inf", .{});
}

// ---@alias view_id integer

// ---Get the ids for all available views
// ---@return view_id[]?
pub fn get_all_ids(L: *zlua.Lua) i32 {
  var output_it = server.root.output_layout.outputs.iterator(.forward);
  var index: i32 = 1;

  L.newTable();

  while(output_it.next()) |o| {
    if(o.output.data == null) continue;
    const output: *Output = @ptrCast(@alignCast(o.output.data.?));

    const layers = [_]*wlr.SceneTree{
      output.layers.content,
      output.layers.fullscreen,
    };

    for(layers) |layer| {
      if(layer.children.length() == 0) continue;
      if(@intFromPtr(layer) == 0) {
        std.log.debug("ts is literally a null ptr", .{});
        continue;
      }

      var view_it = layer.children.iterator(.forward);

      while(view_it.next()) |v| {
        if(v.data == null) continue;
        const scene_node_data: *SceneNodeData = @ptrCast(@alignCast(v.data.?));

        if(scene_node_data.* == .view) {
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

// TODO: What is this?
pub fn check(L: *zlua.Lua) i32 {
  L.pushNil();
  return 1;
}

// ---Get the id for the focused view
// ---@return view_id?
pub fn get_focused_id(L: *zlua.Lua) i32 {
  if(server.seat.focused_surface) |fs| {
    if(fs == .view) {
      L.pushInteger(@intCast(fs.view.id));
      return 1;
    }
  }

  L.pushNil();
  return 1;
}

// ---Close the view with view_id
// ---@param view_id view_id 0 maps to focused view
pub fn close(L: *zlua.Lua) i32 {
  const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);

  if(LuaUtils.viewById(view_id)) |v| {
    v.close();
  }

  L.pushNil();
  return 1;
}

// ---position the view by it's top left corner
// ---@param view_id view_id 0 maps to focused view
// ---@param x number x position for view
// ---@param y number y position for view
pub fn set_position(L: *zlua.Lua) i32 {
  const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);
  const x = LuaUtils.coerceNumber(i32, L.checkNumber(2)) catch L.raiseErrorStr("The x must be > -inf and < inf", .{});
  const y = LuaUtils.coerceNumber(i32, L.checkNumber(3)) catch L.raiseErrorStr("The y must be > -inf and < inf", .{});

  if(LuaUtils.viewById(view_id)) |v| {
    v.setPosition(x, y);
  }

  L.pushNil();
  return 1;
}

// ---Get the position of the view
// ---@param view_id view_id 0 maps to focused view
// ---@return { x: integer, y: integer }? Position of the view
pub fn get_position(L: *zlua.Lua) i32 {
  const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);
  if (LuaUtils.viewById(view_id)) |v| {
    L.newTable();

    _ = L.pushString("x");
    L.pushInteger(@intCast(v.xdg_toplevel.base.geometry.x));
    L.setTable(-3);

    _ = L.pushString("y");
    L.pushInteger(@intCast(v.xdg_toplevel.base.geometry.y));
    L.setTable(-3);

    return 1;
  }

  L.pushNil();
  return 1;
}

// ---Set the size of the spesified view. Will be resized relative to
//    the view's top left corner.
// ---@param view_id view_id 0 maps to focused view
// ---@return
pub fn set_size(L: *zlua.Lua) i32 {
  const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);
  // We use u32s here to enforce a minimum size of zero. The call to resize a
  // toplevel requires a i32, which doesn't make too much sense as there's an
  // assertion in the code enforcing that both the width and height are greater
  // than or equal to zero.
  const width = LuaUtils.coerceNumber(u32, L.checkNumber(2)) catch L.raiseErrorStr("The width must be >= 0 and < inf", .{});
  const height = LuaUtils.coerceNumber(u32, L.checkNumber(3)) catch L.raiseErrorStr("The height must be >= 0 and < inf", .{});

  if(LuaUtils.viewById(view_id)) |v| {
    v.setSize(@intCast(width), @intCast(height));
  }

  L.pushNil();
  return 1;
}

// ---Get the size of the view
// ---@param view_id view_id 0 maps to focused view
// ---@return { width: integer, height: integer }? Size of the view
pub fn get_size(L: *zlua.Lua) i32 {
  const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);
  if (LuaUtils.viewById(view_id)) |v| {
    L.newTable();

    _ = L.pushString("width");
    L.pushInteger(@intCast(v.xdg_toplevel.current.width));
    L.setTable(-3);

    _ = L.pushString("height");
    L.pushInteger(@intCast(v.xdg_toplevel.current.height));
    L.setTable(-3);

    return 1;
  }

  L.pushNil();
  return 1;
}

// ---Remove focus from current view, and set to given id
// ---@param view_id view_id Id of the view to be focused, or nil to remove focus
pub fn set_focused(L: *zlua.Lua) i32 {
  const view_id: ?c_longlong = L.optInteger(1);

  if(view_id == null) {
    server.seat.focusSurface(null);
  } else if(server.root.viewById(@intCast(view_id.?))) |view| {
    server.seat.focusSurface(.{ .view = view });
  }

  L.pushNil();
  return 1;
}

// ---Resize the view by it's top left corner
// ---@param view_id view_id 0 maps to focused view
pub fn toggle_fullscreen(L: *zlua.Lua) i32 {
  const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);

  std.log.debug("fullscreen view {d}", .{view_id});
  if(LuaUtils.viewById(view_id)) |v| {
    std.log.debug("toggling fullscreen", .{});
    v.toggleFullscreen();
  }

  L.pushNil();
  return 1;
}

// ---Get the title of the view
// ---@param view_id view_id 0 maps to focused view
// ---@return string?
pub fn get_title(L: *zlua.Lua) i32 {
  const view_id: u64 = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);

  if(LuaUtils.viewById(view_id)) |v| {
    if(v.xdg_toplevel.title == null) {
      L.pushNil();
      return 1;
    }

    _ = L.pushString(std.mem.span(v.xdg_toplevel.title.?));
    return 1;
  }

  L.pushNil();
  return 1;
}

// ---Get the app_id of the view
// ---@param view_id view_id 0 maps to focused view
// ---@return string?
pub fn get_app_id(L: *zlua.Lua) i32 {
  const view_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch view_id_err(L);

  if(LuaUtils.viewById(view_id)) |v| {
    if(v.xdg_toplevel.app_id == null) {
      L.pushNil();
      return 1;
    }

    _ = L.pushString(std.mem.span(v.xdg_toplevel.app_id.?));
    return 1;
  }

  L.pushNil();
  return 1;
}
