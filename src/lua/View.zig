const std = @import("std");
const zlua = @import("zlua");

const View = @import("../View.zig");

const server = &@import("../main.zig").server;

// ---@alias view_id integer

// ---Get the ids for all available views
// ---@return view_id[]?
pub fn get_all_ids(L: *zlua.Lua) i32 {
  var it = server.root.scene.tree.children.iterator(.forward);
  var index: usize = 1;

  L.newTable();

  while(it.next()) |node| : (index += 1) {
    if(node.data == null) continue;

    const view = @as(*View, @ptrCast(@alignCast(node.data.?)));

    L.pushInteger(@intCast(index));
    L.pushInteger(@intCast(view.id));
    L.setTable(-3);
  }

  return 1;
}

pub fn check(L: *zlua.Lua) i32 {
  L.pushNil();
  return 1;
}

// ---Get the id for the focused view
// ---@return view_id?
pub fn get_focused_id(L: *zlua.Lua) i32 {
  if(server.seat.focused_view) |view| {
    L.pushInteger(@intCast(view.id));
    return 1;
  }

  L.pushNil();
  return 1;
}

// ---Close the view with view_id
// ---@param view_id view_id 0 maps to focused view
pub fn close(L: *zlua.Lua) i32 {
  const view_id: u64 = @intCast(L.checkInteger(1));

  const view: ?*View = if (view_id == 0) server.seat.focused_view else server.root.viewById(view_id);
  if(view) |v| {
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
  const view_id: u64 = @intCast(L.checkInteger(1));
  const x: i32 = @intFromFloat(@round(L.checkNumber(2)));
  const y: i32 = @intFromFloat(@round(L.checkNumber(3)));

  const view: ?*View = if (view_id == 0) server.seat.focused_view else server.root.viewById(view_id);
  if(view) |v| {
    v.setPosition(x, y);
  }

  L.pushNil();
  return 1;
}

// ---Resize the view by it's top left corner
// ---@param view_id view_id 0 maps to focused view
// ---@param width number width for view
// ---@param height number height for view
pub fn set_size(L: *zlua.Lua) i32 {
  const view_id: u64 = @intCast(L.checkInteger(1));
  const width: i32 = @intFromFloat(@round(L.checkNumber(2)));
  const height: i32 = @intFromFloat(@round(L.checkNumber(3)));

  const view: ?*View = if (view_id == 0) server.seat.focused_view else server.root.viewById(view_id);
  if(view) |v| {
    v.setSize(width, height);
  }

  L.pushNil();
  return 1;
}

// ---Remove focus from current view, and set to given id
// ---@param view_id view_id Id of the view to be focused, or nil to remove focus
pub fn set_focused(L: *zlua.Lua) i32 {
  const view_id: ?c_longlong = L.optInteger(1);

  if(view_id == null) {
    if(server.seat.focused_view != null) {
      server.seat.focused_view.?.focused = false;
      server.seat.focused_view = null;
    }
    L.pushNil();
    return 1;
  }

  if (view_id == null) {
    L.pushNil();
    return 1;
  }

  if(server.root.viewById(@intCast(view_id.?))) |view| {
    view.setFocused();
    L.pushNil();
    return 1;
  }

  L.pushNil();
  return 1;
}

// ---Get the title of the view
// ---@param view_id view_id 0 maps to focused view
// ---@return string?
pub fn get_title(L: *zlua.Lua) i32 {
  const view_id: u64 = @intCast(L.checkInteger(1));

  const view: ?*View = if (view_id == 0) server.seat.focused_view else server.root.viewById(view_id);
  if(view) |v| {
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
  const view_id: u64 = @intCast(L.checkInteger(1));

  const view: ?*View = if (view_id == 0) server.seat.focused_view else server.root.viewById(view_id);
  if(view) |v| {
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
