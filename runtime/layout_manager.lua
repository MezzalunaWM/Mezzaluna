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
      tile = function (view_ids, output_id, context, gap)

      end,
      default_context = {
        master_ratio = 0.5
      }
    }
  }
}

---@class (exact) LM_Layout
---@field name string
---@field tile fun(view_ids: integer[], output_id: integer, context: table, gap: { screen: integer, tile: integer })
---@field default_context table

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
