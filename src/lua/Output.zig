const std = @import("std");
const zlua = @import("zlua");
const wlr = @import("wlroots");

const Output = @import("../Output.zig");
const LuaUtils = @import("LuaUtils.zig");
const SceneNodeData = @import("../SceneNodeData.zig").SceneNodeData;

const server = &@import("../main.zig").server;

fn output_id_err(L: *zlua.Lua) noreturn {
  L.raiseErrorStr("The output id must be >= 0 and < inf", .{});
}

/// ---@alias output_id integer

/// ---Get the ids for all available outputs
/// ---@return output_id[]?
pub fn get_all_ids(L: *zlua.Lua) i32 {
  var it = server.root.scene.outputs.iterator(.forward);
  var index: usize = 1;

  L.newTable();

  while(it.next()) |scene_output| : (index += 1) {
    if(scene_output.output.data == null) continue;

    const output = @as(*Output, @ptrCast(@alignCast(scene_output.output.data.?)));

    L.pushInteger(@intCast(index));
    L.pushInteger(@intCast(output.id));
    L.setTable(-3);
  }

  return 1;
}

/// ---Get the view ids for all views on an output
/// ---@param output_id output_id
/// ---@return view_id[]?
pub fn get_all_views(L: *zlua.Lua) i32 {
  const output_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch output_id_err(L);
  var index: i32 = 1;

  L.newTable();

  if(LuaUtils.outputById(output_id)) |o| {
    if(o.wlr_output.data == null) {
      L.pushNil();
      return 1;
    }
    const output: *Output = @ptrCast(@alignCast(o.wlr_output.data.?));
    if (!output.state.enabled) {
      std.log.debug("ts not enabled", .{});
      L.pushNil();
      return 1;
    }

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

/// ---Get the id for the focused output
/// ---@return output_id?
pub fn get_focused_id(L: *zlua.Lua) i32 {
  if(server.seat.focused_output) |output| {
    L.pushInteger(@intCast(output.id));
    return 1;
  }

  L.pushNil();
  return 1;
}

/// ---Get refresh rate for the output
/// ---@param output_id output_id 0 maps to focused output
/// ---@return integer?
pub fn get_rate(L: *zlua.Lua) i32 {
  const output_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch output_id_err(L);

  const output: ?*Output = if (output_id == 0) server.seat.focused_output else server.root.outputById(output_id);
  if(output) |o| {
    L.pushInteger(@intCast(o.wlr_output.refresh));
    return 1;
  }

  L.pushNil();
  return 1;
}

/// ---Get resolution in pixels of the output
/// ---@param output_id output_id 0 maps to focused output
/// ---@return { width: integer, height: integer }?
pub fn get_resolution(L: *zlua.Lua) i32 {
  const output_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch output_id_err(L);

  const output: ?*Output = if (output_id == 0) server.seat.focused_output else server.root.outputById(output_id);
  if(output) |o| {
    L.newTable();

    _ = L.pushString("width");
    L.pushInteger(@intCast(o.wlr_output.width));
    L.setTable(-3);

    _ = L.pushString("height");
    L.pushInteger(@intCast(o.wlr_output.height));
    L.setTable(-3);

    return 1;
  }

  L.pushNil();
  return 1;
}

/// ---Get the serial for the output
/// ---@param output_id output_id 0 maps to focused output
/// ---@return string?
pub fn get_serial(L: *zlua.Lua) i32 {
  const output_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch output_id_err(L);

  const output: ?*Output = if (output_id == 0) server.seat.focused_output else server.root.outputById(output_id);
  if(output) |o| {
    if(o.wlr_output.serial == null) {
      L.pushNil();
      return 1;
    }

    _ = L.pushString(std.mem.span(o.wlr_output.serial.?));
    return 1;
  }

  L.pushNil();
  return 1;
}

/// ---Get the make for the output
/// ---@param output_id output_id 0 maps to focused output
/// ---@return string?
pub fn get_make(L: *zlua.Lua) i32 {
  const output_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch output_id_err(L);

  const output: ?*Output = if (output_id == 0) server.seat.focused_output else server.root.outputById(output_id);
  if(output) |o| {
    if(o.wlr_output.make == null) {
      L.pushNil();
      return 1;
    }

    _ = L.pushString(std.mem.span(o.wlr_output.make.?));
    return 1;
  }

  L.pushNil();
  return 1;
}

/// ---Get the model for the output
/// ---@param output_id output_id 0 maps to focused output
/// ---@return stirng?
pub fn get_model(L: *zlua.Lua) i32 {
  const output_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch output_id_err(L);

  const output: ?*Output = if (output_id == 0) server.seat.focused_output else server.root.outputById(output_id);
  if(output) |o| {
    if(o.wlr_output.model == null) {
      L.pushNil();
      return 1;
    }

    _ = L.pushString(std.mem.span(o.wlr_output.model.?));
    return 1;
  }

  L.pushNil();
  return 1;
}

/// ---Get the description for the output
/// ---@param output_id output_id 0 maps to focused output
/// ---@return stirng?
pub fn get_description(L: *zlua.Lua) i32 {
  const output_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch output_id_err(L);

  const output: ?*Output = if (output_id == 0) server.seat.focused_output else server.root.outputById(output_id);
  if(output) |o| {
    if(o.wlr_output.description == null) {
      L.pushNil();
      return 1;
    }

    _ = L.pushString(std.mem.span(o.wlr_output.description.?));
    return 1;
  }

  L.pushNil();
  return 1;
}

/// ---Get the name of the output
/// ---@param output_id output_id 0 maps to focused output
/// ---@return stirng
pub fn get_name(L: *zlua.Lua) i32 {
  const output_id = LuaUtils.coerceInteger(u64, L.checkInteger(1)) catch output_id_err(L);

  const output: ?*Output = if (output_id == 0) server.seat.focused_output else server.root.outputById(output_id);
  if(output) |o| {
    _ = L.pushString(std.mem.span(o.wlr_output.name));
    return 1;
  }

  L.pushNil();
  return 1;
}
