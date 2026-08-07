---@class Layout_Manager
local M = {}

local table_deep_copy
---@generic T
---@param t T
---@return T
table_deep_copy = function (t)
  local out = {}
  for k, v in pairs(t) do
    if type(v) == "table" then
      v = table_deep_copy(v)
    end
    out[k] = v
  end
  return out
end

local table_deep_merge
---@generic T
---@param novel T
---@param default T
---@return T
table_deep_merge = function (novel, default)
  local out = {}
  for k, v in pairs(default) do
    if novel[k] ~= nil and type(v) == "table" then
      v = table_deep_merge(novel[k], default[k])
    end
    out[k] = novel[k] or default[k]
  end
  return out
end

---@param t number
---@param low number
---@param high number
---@return number
local clamp = function (t, low, high)
  if t < low then
    return low
  elseif t > high then
    return high
  end

  return t
end

---Use a tag's current layout to tile its views
---@param tag_idx integer 0 maps to focused tag
M.tile_tag = function (tag_idx)
  if tag_idx == 0 then tag_idx = M.state.tag_idx end
  local tag = M.state.tags[tag_idx]

  -- Check tag exists and has a layout
  if not tag then return end
  if not tag.layout then return end

  M.state.layouts[tag.layout --[[@as string]]].tile(
    tag.tiling,
    mez.seat.get_focused_output(0),
    tag.contexts[tag.layout],
    M.state.gap
  )
end

---@param search_view_id view_id
---@return { floating: boolean, tag_idx: integer, view_idx: integer }?
M.find_view = function (search_view_id)
  for tag_idx, tag in ipairs(M.state.tags) do
    for view_idx, view_id in ipairs(tag.floating) do
      if view_id == search_view_id then
        return { floating = true, tag_idx = tag_idx, view_idx = view_idx }
      end
    end

    for view_idx, view_id in ipairs(tag.tiling) do
      if view_id == search_view_id then
        return { floating = false, tag_idx = tag_idx, view_idx = view_idx }
      end
    end
  end
end

---@class (exact) LM_Tag
---@field tiling view_id[]
---@field floating view_id[]
---@field last_focused integer?
---@field layout string?
---@field contexts { [string]: table }

---@param tag_idx integer 0 maps to focused tag
---@return LM_Tag tag
M.get_tag = function (tag_idx)
  if tag_idx == 0 then tag_idx = M.state.tag_idx end
  return M.state.tags[tag_idx]
end

---Get the current layout context for a tag
---@param tag_idx integer 0 maps to focused tag
---@param layout string? nil maps to focused tag layout
---@return table? context
M.get_tag_context = function (tag_idx, layout)
  local tag = M.get_tag(tag_idx)
  if tag == nil then return nil end

  layout = layout or tag.layout
  return tag.contexts[tag.layout]
end

--- Focus the next view in the tag. Cycles the tiling list,
--- then the floating list, wrapping back around.
M.focus_next = function ()
  local tag = M.get_tag(0)
  local view_addr = M.find_view(mez.seat.get_focused_view(0))

  if not view_addr then
    mez.seat.set_focused_view(0, tag.tiling[1] or tag.floating[1])
    return
  end

  local list = view_addr.floating and tag.floating or tag.tiling
  local other = view_addr.floating and tag.tiling or tag.floating

  local next_view = list[view_addr.view_idx + 1]
      or other[1]
      or list[1]

  mez.seat.set_focused_view(0, next_view)
end

--- Focus the previous view in the tag. Cycles the floating list,
--- then the tiling list, wrapping back around.
M.focus_previous = function ()
  local tag = M.get_tag(0)
  local view_addr = M.find_view(mez.seat.get_focused_view(0))

  if not view_addr then
    mez.seat.set_focused_view(0, tag.tiling[#tag.tiling] or tag.floating[#tag.floating])
    return
  end

  local list = view_addr.floating and tag.floating or tag.tiling
  local other = view_addr.floating and tag.tiling or tag.floating

  local prev_view = list[view_addr.view_idx - 1]
      or other[#other]
      or list[#list]

  mez.seat.set_focused_view(0, prev_view)
end

---@class (exact) LM_Config
---@field mod_key string
---@field tag_count integer
---@field gap { screen: integer, tile: integer }
---@field layouts LM_Layout[]
local default_config = {
  mod_key = "alt",
  tag_count = 9,
  gap = {
    screen = 10,
    tile = 5
  },
  layouts = {
    {
      name = "master",
        tile = function (view_ids, output_id, context, gap)
          local output_state = mez.output.get_state(output_id)
          if output_state == nil or #view_ids == 0 then
            return
          end

          local area = output_state.available_area

          local tx = area.x + gap.screen
          local ty = area.y + gap.screen
          local tw = area.width - gap.screen * 2
          local th = area.height - gap.screen * 2

          if #view_ids == 1 then
            mez.view.set_geometry(view_ids[1], {
              x = tx, y = ty, width = tw, height = th
            })
            return
          end

          local master_width = tw * context.master_ratio - gap.tile / 2

          mez.view.set_geometry(view_ids[1], {
            x = tx, y = ty, width = master_width, height = th
          })

          -- Stack views share the remaining space, split by tile gaps
          local stack_count = #view_ids - 1
          local stack_x = tx + tw * context.master_ratio + gap.tile / 2
          local stack_width = tw * (1 - context.master_ratio) - gap.tile / 2
          local stack_height = (th - (stack_count - 1) * gap.tile) / stack_count

          for i = 1, stack_count do
            mez.view.set_geometry(view_ids[i + 1], {
              x = stack_x,
              y = ty + (stack_height + gap.tile) * (i - 1),
              width = stack_width,
              height = stack_height
            })
          end
        end,
      default_context = {
        master_ratio = 0.5
      },
      builtins = {
        ---@param delta number amount to increment the master ratio by
        inc_master_ratio = function (delta)
          local context = M.get_tag_layout_context(0)
          if context == nil then return end
          context.master_ratio = clamp(context.master_ratio + 0.1, 0.1, 0.9)
        end,

        ---@param delta number amount to decrement the master ratio by
        dec_master_ratio = function (delta)
          local context = M.get_tag_layout_context(0)
          if context == nil then return end
          context.master_ratio = clamp(context.master_ratio + 0.1, 0.1, 0.9)
        end,

        ---Swap a stack view and the master
        ---@param view_id view_id|`0` 0 maps to focused view
        zoom = function (view_id)
          if view_id == 0 then view_id = mez.seat.get_focused_view(0) end
          if not view_id then return end

          local view_addr = M.find_view(view_id --[[@as view_id]])
          if not view_addr then return end

          local tag = M.get_tag(view_addr.tag_idx)

          local from = view_addr.floating and tag.floating or tag.tiling
          table.insert(tag.tiling, 1, table.remove(from, view_addr.view_idx))
        end,

        ---Make a tiling view floating
        ---@param view_id view_id|`0` 0 maps to focused view
        make_floating = function (view_id)
          if view_id == 0 then view_id = mez.seat.get_focused_view(0) end
          if not view_id then return end

          local view_addr = M.find_view(view_id --[[@as view_id]])
          if not view_addr then return end
          if view_addr.floating then return end

          local tag = M.get_tag(view_addr.tag_idx)
          tag.floating[#tag.floating + 1] = table.remove(tag.tiling, view_addr.view_idx)
        end,

        ---Make a floating view tiling
        ---@param view_id view_id|`0` 0 maps to focused view
        make_tiling = function (view_id)
          if view_id == 0 then view_id = mez.seat.get_focused_view(0) end
          if not view_id then return end

          local view_addr = M.find_view(view_id --[[@as view_id]])
          if not view_addr then return end
          if not view_addr.floating then return end

          local tag = M.get_tag(view_addr.tag_idx)
          tag.tiling[#tag.tiling + 1] = table.remove(tag.floating, view_addr.view_idx)
        end
      }
    }
  }
}

---@class (exact) LM_Layout
---@field name string
---@field tile fun(view_ids: integer[], output_id: integer, context: table, gap: { screen: integer, tile: integer })
---@field default_context table
---@field builtins function[]

---@class (exact) LM_State
---@field tag_idx integer
---@field tags LM_Tag[]
---@field layouts { [string]: LM_Layout }
---@field gap { screen: integer, tile: integer }
M.state = {}

---@param layout LM_Layout
M.add_layout = function (layout)
  if M.state.layouts[layout.name] ~= nil then return end
  M.state.layouts[layout.name] = layout

  for _, tag in ipairs(M.state.tags) do
    tag.contexts[layout.name] = table_deep_copy(layout.default_context)
  end
end

---@param config LM_Config
M.setup = function (config)
  config = table_deep_merge(config, default_config)

  M.state = {
    tag_idx = 1,
    tags = {},
    layouts = {},
    gap = config.gap
  }

  local dl = config.layouts[1]
  for i = 1, config.tag_count do
    M.state.tags[i] = {
      tiling = {},
      floating = {},
      last_focused = nil,
      contexts = {}
    }

    if dl ~= nil then
      M.state.tags[i].layout = dl.name
    end
  end

  for _, layout in ipairs(config.layouts) do
    M.add_layout(layout)
  end

  -- Keybinds
  mez.input.add_keymap(config.mod_key, "j", {
    press = function ()
      M.focus_next()
    end
  })
  mez.input.add_keymap(config.mod_key, "k", {
    press = function ()
      M.focus_previous()
    end
  })

  -- Hooks
  mez.hook.add("ViewCommitPost", {
    callback = function(view_id, initial)
      if initial then
        local tag = M.get_tag(0)
        table.insert(tag.tiling, view_id)
        M.tile_tag(0)
        mez.view.apply()
        mez.seat.set_focused_view(0, view_id)
      end
    end
  })

  mez.hook.add("ViewSetClosingPre", {
    callback = function(view_id, closing)
      if closing then
        local view_addr = M.find_view(view_id)
        if not view_addr then return end

        local tag = M.state.tags[view_addr.tag_idx]
        local list = view_addr.floating and tag.floating or tag.tiling

        table.remove(list, view_addr.view_idx)

        M.tile_tag(view_addr.tag_idx)

        local focus_idx = view_addr.view_idx
        if view_addr.view_idx == #list + 1 then focus_idx = focus_idx - 1 end
        mez.seat.set_focused_view(0, list[focus_idx])
      end
    end
  })

  return M
end

return M
