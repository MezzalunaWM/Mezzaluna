---@module 'master'

---@class Master
---@field default_config MasterConfig
---@field config MasterConfig
---@field state MasterState
local M = {}

local utils = {}

---Find view ID within all tags
---@param view_id number
---@return "master" | "floating" | "stacking" | nil view_type
---@return number | nil tag_index
---@return number | nil view_index
utils.find_view = function(view_id)
	if view_id == 0 then view_id = mez.view.get_focused_id() end

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

---@class MasterConfig
---@field master_ratio number
---@field tag_count number
---@field focus_on_spawn boolean
---@field refocus_on_kill boolean
---@field screen_gap number
---@field tile_gap number
local default_config = {
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

	local res = mez.output.get_resolution(0)

	if tag.master == nil then return end

	if #tag.stack == 0 then
		mez.view.set_position(tag.master, M.config.screen_gap, M.config.screen_gap)
		mez.view.set_size(
			tag.master,
			res.width - M.config.screen_gap * 2,
			res.height - M.config.screen_gap * 2
		)
	else
		mez.view.set_position(tag.master, M.config.screen_gap, M.config.screen_gap)
		mez.view.set_size(
			tag.master,
			res.width * M.state.master_ratio - M.config.screen_gap - M.config.tile_gap,
			res.height - M.config.screen_gap * 2
		)

		local stack_x = (res.width * M.state.master_ratio)
		local stack_width = res.width * (1 - M.state.master_ratio) - M.config.tile_gap - M.config.screen_gap
		local stack_height = (res.height - (M.config.screen_gap * 2) - ((#tag.stack - 1) * M.config.tile_gap)) / #tag.stack

		for i, view_id in ipairs(tag.stack) do
			mez.view.set_position(view_id,
			stack_x,
			(stack_height + M.config.tile_gap) * (i - 1) + M.config.screen_gap)

			mez.view.set_size(view_id, stack_width, stack_height)
		end
	end
end

---Add the id of a new view
---@param view_id number
M.add_view = function(view_id)
	local tag = M.state.tags[M.state.tag_id]

	if tag.master == nil then
		tag.master = view_id
	else
		table.insert(tag.stack, #tag.stack + 1, view_id)
	end

	if M.config.focus_on_spawn then mez.view.set_focused(view_id) end

	M.tile_tag(M.state.tag_id)
end

---Move the focus in a tag to the next view
---Order is master -> stack -> floating -> master
M.focus_next = function()
	local view_id = mez.view.get_focused_id()
	local type, tag_idx, view_idx = utils.find_view(view_id)
	local tag = M.state.tags[tag_idx]

	if type == "floating" then
		if view_idx == #tag.floating then
			if tag.master ~= nil then
				mez.view.set_focused(tag.master)
			else
				mez.view.set_focused(tag.floating[1])
			end
		else
			mez.view.set_focused(tag.floating[view_idx + 1])
		end
	elseif type == "master" then
		if #tag.stack ~= 0 then
			mez.view.set_focused(tag.stack[1])
		elseif #tag.floating ~= 0 then
			mez.view.set_focused(tag.floating[1])
		else
			mez.view.set_focused(tag.master)
		end
	elseif type == "stacking" then
		if view_idx == #tag.stack then
			if #tag.floating ~= 0 then
				mez.view.set_focused(tag.floating[1])
			else
				mez.view.set_focused(tag.master)
			end
		else
			mez.view.set_focused(tag.stack[view_idx + 1])
		end
	end
end

---Move the focus in a tag to the previous view
---Order is master -> floating -> stack -> master
M.focus_prev = function()
	local view_id = mez.view.get_focused_id()
	local type, tag_idx, view_idx = utils.find_view(view_id)
	local tag = M.state.tags[tag_idx]

	if type == "floating" then
		if view_idx == 1 then
			if #tag.stack ~= 0 then
				mez.view.set_focused(tag.stack[#tag.stack])
			elseif tag.master ~= nil then
				mez.view.set_focused(tag.master)
			else
				mez.view.set_focused(tag.floating[#tag.floating])
			end
		else
			mez.view.set_focused(tag.floating[view_idx - 1])
		end
	elseif type == "master" then
		if #tag.floating ~= 0 then
			mez.view.set_focused(tag.floating[#tag.floating])
		elseif #tag.stack ~= 0 then
			mez.view.set_focused(tag.stack[#tag.stack])
		else
			mez.view.set_focused(tag.master)
		end
	elseif type == "stacking" then
		if view_idx == 1 then
			mez.view.set_focused(tag.master)
		else
			mez.view.set_focused(tag.stack[view_idx - 1])
		end
	end
end

---Remove a view_id from the layout
---@param view_id number
M.remove_view = function(view_id)
  if view_id == 0 then view_id = mez.view.get_focused_id() end

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
				mez.view.set_focused(tag.master)
			else
				mez.view.set_focused(tag.stack[is_last and view_idx - 1 or view_idx])
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
            mez.view.set_focused(tag.master)
          elseif #tag.floating ~= 0 then
            mez.view.set_focused(tag.floating[1])
          end
        else
          mez.view.set_focused(tag.last_focused)
        end
      else
        if tag.master then
          mez.view.set_focused(tag.master)
        elseif #tag.floating ~= 0 then
          mez.view.set_focused(tag.floating[1])
        end
      end
		else
			tag.last_focused = mez.view.get_focused_id()
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

	M.state.tag_id = tag_idx
end

---Move a stack window to the master, and vice versa
---@param view_id number
M.zoom = function (view_id)
	if view_id == 0 then view_id = mez.view.get_focused_id() end
	local type, tag_idx, view_idx = utils.find_view(view_id)

	if type == "floating" or type == "master" or M.state.tag_id ~= tag_idx then return end

	local tag = M.state.tags[M.state.tag_id]

	local m = tag.master
	tag.master = table.remove(tag.stack, view_idx)
	table.insert(tag.stack, 1, m)

	M.tile_tag(tag_idx)
end

---Modify the master stack ratio
---@param delta number The amount of change the master/stack ratio by
M.change_ratio = function (delta)
	M.state.master_ratio = M.state.master_ratio + delta
	M.state.master_ratio = M.state.master_ratio < 0.1 and 0.1 or M.state.master_ratio
	M.state.master_ratio = M.state.master_ratio > 0.9 and 0.9 or M.state.master_ratio

	M.tile_tag(M.state.tag_id)
end

---Move a view from tiling to floating
---@param view_id number
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

	mez.view.set_focused(tag.floating[#tag.floating])
	mez.view.raise_to_top(tag.floating[#tag.floating])
	M.tile_tag(tag_idx)
end

---Move a view from floating to tiling
---@param view_id number
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
end

M.set_fullscreen = function (view_id)
	local _, tag_idx, _ = utils.find_view(view_id)

	if not mez.view.toggle_fullscreen(view_id) then
		M.tile_tag(tag_idx)
	end
end

---@param view_id number
---@param tag_id number
M.send_view = function (view_id, tag_id)
  if view_id == 0 then view_id = mez.view.get_focused_id() end
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
      table.insert(tag.stack, #tag.stack, view_id)
    end
  end

  mez.view.set_enabled(view_id, false)
  M.tile_tag(M.state.tag_id)
  M.tile_tag(tag_id)
end

M.setup = function()
  --- Take a user config
	M.config = default_config

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

	mez.hook.add("ViewMapPre", { callback = function(view_id) M.add_view(view_id) end })
	mez.hook.add("ViewUnmapPost", { callback = function(view_id) M.remove_view(view_id) end })

	mez.input.add_keymap("alt", "j", { press = function () M.focus_next() end })
	mez.input.add_keymap("alt", "k", { press = function () M.focus_prev() end })
	mez.input.add_keymap("alt", "Return", { press = function () M.zoom(0) end })
	mez.input.add_keymap("alt", "h", { press = function () M.change_ratio(-0.05) end })
	mez.input.add_keymap("alt", "l", { press = function () M.change_ratio(0.05) end })
	mez.input.add_keymap("alt|shift", "F", { press = function () M.set_fullscreen(0) end })

	for i = 1, M.config.tag_count do
		mez.input.add_keymap("alt", i, { press = function () M.tag_enable(i) end })
	end

  -- Wow this is ass
	--  for i, k in ipairs({"exclam", "at", "numbersign", "dollar", "percent"}) do
	-- 	mez.input.add_keymap("alt|shift", k, { press = function () M.send_view(0, i) end })
	-- end

	mez.input.add_mousemap("alt", "BTN_LEFT", {
		press = function(view_id) M.make_float(view_id) end,
		drag = function(_, pos, drag)
			if drag.view ~= nil then
				mez.view.set_position(drag.view.id, pos.x - drag.view.offset.x, pos.y - drag.view.offset.y)
			end
		end
	})

	mez.input.add_mousemap("alt", "BTN_MIDDLE", { press = function(view_id) M.make_tile(view_id) end })

	mez.input.add_mousemap("alt", "BTN_RIGHT", {
		drag = function(_, pos, drag)
			if drag.view ~= nil then
				local width = (pos.x - drag.start.x) + drag.view.offset.x + (drag.view.dims.width - drag.view.offset.x)
				local height = (pos.y - drag.start.y) + drag.view.offset.y + (drag.view.dims.height - drag.view.offset.y)

				if width <= 10 then width = 10 end
				if height <= 10 then height = 10 end
				mez.view.set_size(drag.view.id, width, height)
			end
		end
	})

	mez.hook.add("OutputStateChange", { callback = function ()
		for i = 1, M.config.tag_count do
			M.tile_tag(i)
		end
	end})

	mez.hook.add("ViewRequestFullscreen", { callback = function () M.set_fullscreen(0) end })
end

return M
