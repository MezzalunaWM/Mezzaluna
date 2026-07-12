---@module "mez_types"

local mod = "alt"
local terminal_emulator = "foot"
local run_launcher = "wmenu-run"

local master = require("master")
master.setup({ mod_key = mod })

-- local euclid = require("euclid")
-- euclid.setup({ mod_key = mod })

local border_width = 4

mez.input.add_keymap(mod, "p", {
	press = function()
		mez.api.spawn(run_launcher)
	end,
})

mez.input.add_keymap(mod .. "|shift", "Return", {
	press = function()
		mez.api.spawn(terminal_emulator)
	end,
})

mez.input.add_keymap(mod .. "|shift", "C", {
	press = function ()
		local view_id = mez.view.get_focused_id(0)
		if view_id then
			mez.view.set_closing(view_id, true)
			mez.view.apply()
		end
	end
})

mez.input.add_keymap(mod .. "|shift", "Q", {
	press = function ()
		mez.api.exit();
	end
})

mez.hook.add("ViewSetFocusPost", {
	callback = function(view_id, _, focus_count)
    if focus_count > 0 then
      mez.view.set_border(view_id, { color = "#FFDD33", width = border_width })
    else
      mez.view.set_border(view_id, { color = "#52493E", width = border_width })
    end
	end
})

mez.hook.add("ViewCommitPost", {
  callback = function(view_id, initial)
    if initial then
      mez.view.set_border(view_id, { color = "#52493E", width = border_width })
    end
  end
})

mez.hook.add("ViewPointerMotion", {
	callback = function (view_id, _, _, seat_id)
    mez.seat.set_focused_view(seat_id, view_id)
	end
})

for i = 1, 12 do
	mez.input.add_keymap("ctrl|alt", "XF86Switch_VT_"..i, {
		press = function() mez.api.change_vt(i) end
	})
end
