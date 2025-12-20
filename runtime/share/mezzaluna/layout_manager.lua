--- This is a wrapper around mez's hooks and keybinds to allow users to create
--- layouts without multiple different layouts conflicting.
---
--- TODO: this may be overridden by the user by setting mez.layout prior to the
--- runtime loading

local mapper = require("mapper")

---@class layout.options options when creating a layout
---@field name string the name of the layout
---@field callback function this is the function which is run when changes to current state have been made
---@field events string[]? this is a list of the events that callback will be run on
---@field layout_maps mapper.map[]? a list of layout maps
---@field focus_maps mapper.map[]? a list of focus changing maps
---@field cursor_maps mapper.map[]? a list of focus changing maps

---@class layout : layout.options a singular layout
---@field callback_id number the id of the callback

---@class layout_manager manage all your layouts
---@field layouts layout[] all the layouts that are registered
---@field current_layout layout the currently active layout
local layout_manager = {
  layouts = {},
  --- the baseline events for a new layout
  events = {
    "ViewMapPre",
    "ViewUnmapPost",
    -- "ViewPointerMotion",
  }
}

--- create a new layout
---@param options layout.options
---@return layout your_layout returns your new layout
function layout_manager.new_layout(options)
  local layout = {}

  layout.name = options.name
  layout.callback = options.callback
  layout.events = layout_manager.events
  layout.layout_maps = options.layout_maps
  layout.focus_maps = options.focus_maps
  layout.cursor_maps = options.cursor_maps

  -- store the new layout in the layout list
  layout_manager.layouts[#layout_manager.layouts + 1] = layout
  return layout
end

--- set the current layout
---@param layout_name string the name of the layout already created in the layout_manager
function layout_manager.set_layout(layout_name)
  local layout = nil
  for _, l in ipairs(layout_manager.layouts) do
    if l.name == layout_name then
      layout = l
    end
  end
  assert(layout, "layout '"..layout_name.."' does not exist")

  if layout_manager.current_layout then
    local current_layout = layout_manager.current_layout
    mez.hook.del(layout_manager.current_layout.callback_id)
    for _, maps in ipairs({
      current_layout.layout_maps,
      current_layout.focus_maps,
      current_layout.cursor_maps,
    }) do
      mapper.del(maps)
    end
  end
  layout_manager.current_layout = layout
  layout.callback_id = mez.hook.add(layout.events, {
    callback = function ()
      for _, output in ipairs(mez.output.get_all_ids()) do
        layout.callback(output)
      end
    end,
  })
  for _, maps in ipairs({
    layout.layout_maps,
    layout.focus_maps,
    layout.cursor_maps,
  }) do
    mapper.add(maps)
  end
  layout.callback()
end

return layout_manager
