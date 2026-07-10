---@class Master
local M = {}

local utils = {}

---Find view ID within all tags
---@param view_id integer
---@return "master" | "floating" | "stacking" | nil view_type
---@return number | nil tag_index
---@return number | nil view_index
utils.find_view = function(view_id)
  if view_id == 0 then view_id = mez.seat.get_focused_view(0) end

  for i, curr_tag in ipairs(M.state.tags) do
    local t = M.state.tags[i]

    if view_id == curr_tag.master then
      return "master", i, nil
    end

    for j, curr_view in ipairs(t.floating) do
      if curr_view == view_id then
        return "floating", i, j
      end
    end

    for j, curr_view in ipairs(t.stack) do
      if curr_view == view_id then
        return "stacking", i, j
      end
    end
  end

  return nil, nil, nil
end

---Merge two tables
---@param t1 table
---@param t2 table
---@return table
utils.table_merge = function(t1, t2)
  for k, v in pairs(t2) do
    if type(v) == "table" then
      if type(t1[k]) == "table" then
        t1[k] = utils.table_merge(t1[k], v)
      else
        t1[k] = utils.table_merge({}, v)
      end
    else
      if t1[k] == nil then
        t1[k] = v
      end
    end
  end
  return t1
end

---@class MasterConfig
---@field mod_key string
---@field master_ratio number
---@field tag_count number
---@field focus_on_spawn boolean
---@field refocus_on_kill boolean
---@field screen_gap number
---@field tile_gap number

---@type MasterConfig
local default_config = {
  mod_key = "alt",
  master_ratio = 0.5,
  tag_count = 5,
  focus_on_spawn = true,
  refocus_on_kill = true,
  screen_gap = 12,
  tile_gap = 7
}

---@class MasterTag
---@field master number | nil
---@field stack number[]
---@field floating number[]
---@field last_focused number | nil

---@class MasterState
---@field tag_id number
---@field tags MasterTag[]
---@field master_ratio number

---Tile all of the master and stack windows for a tag
---@param tag_id number
M.tile_tag = function(tag_id)
  local tag = M.state.tags[tag_id]

  local area = mez.output.get_state(0).available_area

  if tag.master == nil then return end

  if #tag.stack == 0 then
    mez.view.set_geometry(tag.master, {
      x = M.config.screen_gap + area.x,
      y = M.config.screen_gap + area.y,
      width = area.width - M.config.screen_gap * 2,
      height = area.height - M.config.screen_gap * 2
    })
  else
    mez.view.set_geometry(tag.master, {
      x = M.config.screen_gap + area.x,
      y = M.config.screen_gap + area.y,
      width = area.width * M.state.master_ratio - M.config.screen_gap - M.config.tile_gap,
      height = area.height - M.config.screen_gap * 2
    })

    local stack_x = (area.width * M.state.master_ratio) + area.x
    local stack_width = area.width * (1 - M.state.master_ratio) - M.config.tile_gap - M.config.screen_gap
    local stack_height = (area.height - (M.config.screen_gap * 2) - ((#tag.stack - 1) * M.config.tile_gap)) / #tag.stack

    for i, view_id in ipairs(tag.stack) do
      mez.view.set_geometry(view_id, {
        x = stack_x,
        y = (stack_height + M.config.tile_gap) * (i - 1) + M.config.screen_gap + area.y,
        width = stack_width,
        height = stack_height
      })
    end
  end
end

---Add the id of a new view
---@param view_id integer
M.add_view = function(view_id)
  local tag = M.state.tags[M.state.tag_id]

  if tag.master == nil then
    tag.master = view_id
  else
    table.insert(tag.stack, #tag.stack + 1, view_id)
  end

  if M.config.focus_on_spawn then mez.seat.set_focused_view(0, view_id) end

  M.tile_tag(M.state.tag_id)
  mez.view.apply()
end

---Move the focus in a tag to the next view
---Order is master -> stack -> floating -> master
M.focus_next = function()
  local view_id = mez.seat.get_focused_view(0)
  local type, tag_idx, view_idx = utils.find_view(view_id)
  local tag = M.state.tags[tag_idx]

  if type == "floating" then
    if view_idx == #tag.floating then
      if tag.master ~= nil then
        mez.seat.set_focused_view(0, tag.master)
      else
        mez.seat.set_focused_view(0, tag.floating[1])
      end
    else
      mez.seat.set_focused_view(0, tag.floating[view_idx + 1])
    end
  elseif type == "master" then
    if #tag.stack ~= 0 then
      mez.seat.set_focused_view(0, tag.stack[1])
    elseif #tag.floating ~= 0 then
      mez.seat.set_focused_view(0, tag.floating[1])
    else
      mez.seat.set_focused_view(0, tag.master)
    end
  elseif type == "stacking" then
    if view_idx == #tag.stack then
      if #tag.floating ~= 0 then
        mez.seat.set_focused_view(0, tag.floating[1])
      else
        mez.seat.set_focused_view(0, tag.master)
      end
    else
      mez.seat.set_focused_view(0, tag.stack[view_idx + 1])
    end
  end

  mez.view.apply()
end

---Move the focus in a tag to the previous view
---Order is master -> floating -> stack -> master
M.focus_prev = function()
  local view_id = mez.seat.get_focused_view(0)
  local type, tag_idx, view_idx = utils.find_view(view_id)
  local tag = M.state.tags[tag_idx]

  if type == "floating" then
    if view_idx == 1 then
      if #tag.stack ~= 0 then
        mez.seat.set_focused_view(0, tag.stack[#tag.stack])
      elseif tag.master ~= nil then
        mez.seat.set_focused_view(0, tag.master)
      else
        mez.seat.set_focused_view(0, tag.floating[#tag.floating])
      end
    else
      mez.seat.set_focused_view(0, tag.floating[view_idx - 1])
    end
  elseif type == "master" then
    if #tag.floating ~= 0 then
      mez.seat.set_focused_view(0, tag.floating[#tag.floating])
    elseif #tag.stack ~= 0 then
      mez.seat.set_focused_view(0, tag.stack[#tag.stack])
    else
      mez.seat.set_focused_view(0, tag.master)
    end
  elseif type == "stacking" then
    if view_idx == 1 then
      mez.seat.set_focused_view(0, tag.master)
    else
      mez.seat.set_focused_view(0, tag.stack[view_idx - 1])
    end
  end

  mez.view.apply()
end

---Remove a view_id from the layout
---@param view_id integer
M.remove_view = function(view_id)
  if view_id == 0 then view_id = mez.seat.get_focused_view(0) end

  local type, tag_idx, view_idx = utils.find_view(view_id)

  local tag = M.state.tags[tag_idx]

  --- Now remove the view and re-tile if needed
  if type == "floating" then
    table.remove(tag.floating, view_idx)
  elseif type == "master" then
    tag.master = table.remove(tag.stack, 1)

    if M.config.refocus_on_kill then
      mez.view.set_focused(tag.master)
    end
  elseif type == "stacking" then
    local is_last = #tag.stack == view_idx

    table.remove(tag.stack, view_idx)

    if M.config.refocus_on_kill then
      if #tag.stack == 0 then
        mez.seat.set_focused_view(0, tag.master)
      else
        mez.seat.set_focused_view(0, tag.stack[is_last and view_idx - 1 or view_idx])
      end
    end
  end

  M.tile_tag(tag_idx)
end

---Switch to a tag by enabling all views for 1 tag,
---and disabling all the views for the old tag
---@param tag_idx number
M.tag_enable = function (tag_idx)
  ---@param t number
  ---@param enabled boolean
  local set_tag_enable = function (t, enabled)
    local tag = M.state.tags[t]

    if enabled then
      if tag.last_focused ~= nil then

        if utils.find_view(tag.last_focused) == nil then
          if tag.master then
            mez.seat.set_focused_view(0, tag.master)
          elseif #tag.floating ~= 0 then
            mez.seat.set_focused_view(0, tag.floating[1])
          end
        else
          mez.seat.set_focused_view(0, tag.last_focused)
        end
      else
        if tag.master then
          mez.seat.set_focused_view(0, tag.master)
        elseif #tag.floating ~= 0 then
          mez.seat.set_focused_view(0, tag.floating[1])
        end
      end
    else
      tag.last_focused = mez.seat.get_focused_view(0)
    end

    for _, v in ipairs(tag.floating) do
      mez.view.set_enabled(v, enabled)
    end

    if tag.master ~= nil then
      mez.view.set_enabled(tag.master, enabled)

      for _, v in ipairs(tag.stack) do
        mez.view.set_enabled(v, enabled)
      end
    end
  end

  set_tag_enable(M.state.tag_id, false)
  set_tag_enable(tag_idx, true)
  mez.view.apply()

  M.state.tag_id = tag_idx
end

---Move a stack window to the master, and vice versa
---@param view_id integer
M.zoom = function (view_id)
  if view_id == 0 then view_id = mez.seat.get_focused_view(0) end
  local type, tag_idx, view_idx = utils.find_view(view_id)

  if type == "floating" or type == "master" or M.state.tag_id ~= tag_idx then return end

  local tag = M.state.tags[M.state.tag_id]

  local m = tag.master
  tag.master = table.remove(tag.stack, view_idx)
  table.insert(tag.stack, 1, m)

  M.tile_tag(tag_idx)
  mez.view.apply()
end

---Modify the master stack ratio
---@param delta number The amount of change the master/stack ratio by
M.change_ratio = function (delta)
  M.state.master_ratio = M.state.master_ratio + delta
  M.state.master_ratio = M.state.master_ratio < 0.1 and 0.1 or M.state.master_ratio
  M.state.master_ratio = M.state.master_ratio > 0.9 and 0.9 or M.state.master_ratio

  M.tile_tag(M.state.tag_id)
  mez.view.apply()
end

---Move a view from tiling to floating
---@param view_id integer
M.make_float = function (view_id)
  local type, tag_idx, view_idx = utils.find_view(view_id)

  local tag = M.state.tags[tag_idx]

  if type == "floating" then return end

  if type == "master" then
    table.insert(tag.floating, #tag.floating + 1, tag.master)
    tag.master = nil
    if #tag.stack ~= 0 then
      tag.master = table.remove(tag.stack, 1)
    end
  elseif type == "stacking" then
    table.insert(
      tag.floating,
      #tag.floating + 1,
      table.remove(tag.stack, view_idx)
    )
  end

  mez.view.raise_to_top(tag.floating[#tag.floating])
  mez.seat.set_focused_view(0, tag.floating[#tag.floating])
  M.tile_tag(tag_idx)
  mez.view.apply()
end

---Move a view from floating to tiling
---@param view_id integer
M.make_tile = function (view_id)
  local type, tag_idx, view_idx = utils.find_view(view_id)

  local tag = M.state.tags[tag_idx]

  if type ~= "floating" then return end

  if tag.master == nil then
    tag.master = table.remove(tag.floating, view_idx)
  else
    table.insert(tag.stack, #tag.stack + 1, table.remove(tag.floating, view_idx))
  end

  M.tile_tag(tag_idx)
  mez.view.apply()
end

M.toggle_fullscreen = function (view_id)
  local _, tag_idx, _ = utils.find_view(view_id)

  local fullscreen = mez.view.get_fullscreen(view_id)
  mez.view.set_fullscreen(view_id, not fullscreen)

  if fullscreen then
    mez.view.set_geometry(view_id, mez.view.get_previous_geometry(view_id))
  end

  mez.view.apply()
end

---@param view_id integer
---@param tag_id number
M.send_view = function (view_id, tag_id)
  if view_id == 0 then view_id = mez.seat.get_focused_view(0) end
  if tag_id == M.state.tag_id then return end

  local type, _, _ = utils.find_view(view_id)

  local tag = M.state.tags[tag_id]

  M.remove_view(view_id)

  if type == "floating" then
    table.insert(tag.floating, #tag.floating, view_id)
  else
    if tag.master == nil then
      tag.master = view_id
    else
      tag.stack[#tag.stack + 1] = view_id
    end
  end

  mez.view.set_enabled(view_id, false)
  M.tile_tag(M.state.tag_id)
  M.tile_tag(tag_id)
  mez.view.apply()
end

---@param config MasterConfig
M.setup = function(config)
  --- Take a user config
  M.config = utils.table_merge(config or {}, default_config)

  M.state = {
    tag_id = 1,
    tags = {},
    master_ratio = M.config.master_ratio
  }

  -- Create all tags for the state
  for i = 1, M.config.tag_count do
    M.state.tags[i] = {
      master = nil,
      floating = {},
      stack = {},
      last_focused = nil
    }
  end

  mez.hook.add("ViewCommitPost", { callback = function(view_id, initial) if initial then M.add_view(view_id) end end })
  mez.hook.add("ViewSetClosePre", { callback = function(view_id, close) if close then M.remove_view(view_id) end end })

  mez.input.add_keymap(M.config.mod_key, "j", { press = function () M.focus_next() end })
  mez.input.add_keymap(M.config.mod_key, "k", { press = function () M.focus_prev() end })
  mez.input.add_keymap(M.config.mod_key, "Return", { press = function () M.zoom(0) end })
  mez.input.add_keymap(M.config.mod_key, "h", { press = function () M.change_ratio(-0.03) end })
  mez.input.add_keymap(M.config.mod_key, "l", { press = function () M.change_ratio(0.03) end })
  mez.input.add_keymap(M.config.mod_key.."|shift", "F", { press = function () M.toggle_fullscreen(0) end })

  for i = 1, M.config.tag_count do
    mez.input.add_keymap(M.config.mod_key, tostring(i), {
      press = function ()
        M.tag_enable(i)
      end
    })

    mez.input.add_keymap(M.config.mod_key.."|shift", tostring(i), {
      press = function ()
        M.send_view(0, i)
      end
    })
  end

  mez.input.add_mousemap(M.config.mod_key, "BTN_LEFT", {
    press = function(view_id) M.make_float(view_id) end,
    drag = function(view_id, pos, _, offset)
      if view_id ~= nil then
        mez.view.set_geometry(view_id, {
          x = pos.x - offset.x,
          y = pos.y - offset.y
        })
        mez.view.apply();
      end
    end
  })

  mez.input.add_mousemap(M.config.mod_key, "BTN_MIDDLE", {
    press = function(view_id)
      M.make_tile(view_id)
    end
  })

  mez.input.add_mousemap(M.config.mod_key, "BTN_RIGHT", {
    press = function(view_id)
      M.make_float(view_id)
      mez.view.set_resizing(view_id, true)
      mez.view.apply()
    end,
    drag = function(view_id, pos, drag_start, offset)
      if view_id ~= nil then
        local width = (pos.x - drag_start.x) + offset.x
        local height = (pos.y - drag_start.y) + offset.y

        if width <= 10 then width = 10 end
        if height <= 10 then height = 10 end
        mez.view.set_geometry(view_id, {
          width = width,
          height = height
        })
        mez.view.apply()
      end
    end,
    release = function (view_id)
      mez.view.set_resizing(view_id, false)
      mez.view.apply()
    end
  })

  mez.hook.add("OutputStateChange", { callback = function ()
    for i = 1, M.config.tag_count do
      M.tile_tag(i)
      mez.view.apply()
    end
  end})

  mez.hook.add("ViewRequestFullscreen", {
    callback = function (view_id)
      M.toggle_fullscreen(view_id)
    end
  })
end

return M
