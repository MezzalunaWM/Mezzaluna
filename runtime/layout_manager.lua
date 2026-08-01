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
  else if t > high then
    return high
  end

  return t
end

---@class (exact) LM_Tag
---@field tiling integer[]
---@field floating integer[]
---@field layout string?
---@field contexts table[]

---@param tag_id integer? 0 => focused tag
---@return LM_Tag tag
M.get_tag = function (tag_id)
  if tag_id == 0 then tag_id = M.state.tag_id end
  return M.state.tags[tag_id]
end

---@param tag_id integer? 0 => focused tag
---@param layout string? nil => current tag layout
---@return table? context
M.get_tag_layout_context = function (tag_id, layout)
  local tag = M.get_tag(tag_id)
  if tag == nil then return nil end

  layout = layout or tag.layout
  return tag.contexts[tag.layout]
end

local = master_tile = function (view_ids, output_id, context, gap)
  local output_state = mez.output.get_state(output_id)

  if output_state == nil or #view_idx == 0 then
    return
  end

  local view_area = {
    x = gap.screen,
    y = gap.screen,
    width = output_state.available_area.width,
    height = output_state.available_area.height
  }

  -- Set the geometry for the master view
  local mg = { x = 0, y = 0, height = view_area.height }
  if #view_ids == 1 then
    mg.width = view_area.width
  else if #view_ids > 1 then
    mg.width = view_area * context.master_ratio
  end
  mez.view.set_geometry(view_ids[1], mg)

  -- Set geometry for all stack views
  if #view_ids > 1 then
    local stack_x = (view_area.width * context.master_ratio) + view_area.x
    local stack_width = view_area.width * (1 - context.master_ratio)
    local stack_height = view_area.height / #view_ids

    for i, view_id in ipairs(view_ids) do
      mez.view.set_geometry(view_id, {
        x = stack_x,
        y = stack_height * (i - 1) + view_area.y,
        width = stack_width,
        height = stack_height
      })
    end
  end
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
    screen = 5,
    tile = 5
  },
  layouts = {
    {
      name = "master",
    default_context = {
      master_ratio = 0.5
    },
    builtins = {
      ---@param delta amount to increment mater by
      inc_master_ratio = function (delta)
        local context = M.get_tag_layout_context()
        if context == nil then return end
        context.master_ratio = clamp(context.master_ratio + 0.1, 0.1, 0.9)
      end,
      ---@param delta amount to increment mater by
      dec_master_ratio = function (delta)
        local context = M.get_tag_layout_context()
        if context == nil then return end
        context.master_ratio = clamp(context.master_ratio + 0.1, 0.1, 0.9)
      end
    }
  }
}
}

---@class (exact) LM_Layout
---@field name string
---@field tile fun(view_ids: integer[], output_id: integer, context: table, gap: { screen: integer, tile: integer })
---@field default_context table
---@field builtins functions[]

---@class (exact) LM_State
---@field tag_id integer
---@field tags LM_Tag[]
---@field layouts { [string]: LM_Layout }
---@field gap { screen: integer, tile: integer }
M.state = {}

---@param layout LM_Layout
M.add_layout = function (layout)
  if M.state.layouts[layout.name] ~= nil then
    --TODO: Maybe this should error
    print("This layout already exist")
    return
  end
  M.state.layouts[layout.name] = layout

  for _, tag in ipairs(M.state.tags) do
    tag.contexts[layout.name] = table_deep_copy(layout.default_context)
  end
end

---@param config LM_Config
M.setup = function (config)
  config = table_deep_merge(config, default_config)

  M.state = {
    tag_id = 1,
    tags = {},
    layouts = {},
    gap = config.gap
  }

  for i = 1, config.tag_count do
    local dl= nil
    if config.layouts[1] ~= nil then
      dl = config.layouts[1]
    end

    M.state.tags[i] = {
      tiling = {},
      floating = {},
      layout = dl,
      contexts = {}
    }
  end

  return M
end
