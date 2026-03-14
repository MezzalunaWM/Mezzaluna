---@module "mez_types"

local mod = "logo"
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
		mez.view.close(0)
	end
})

mez.input.add_keymap(mod .. "|shift", "Q", {
	press = function ()
		mez.api.exit();
	end
})

mez.hook.add("ViewSetFocusPost", {
	callback = function (view_id, focus)
    if focus then
      mez.view.set_border(view_id, { color = "#FFDD33", width = border_width })
    else
      mez.view.set_border(view_id, { color = "#52493E", width = border_width })
    end
	end
})

mez.hook.add("ViewMapPre", {
  callback = function(view_id)
    mez.view.set_border(view_id, { color = "#52493E", width = border_width })
  end
})

mez.hook.add("ViewPointerMotion", {
	callback = function (view_id, _, _)
		mez.view.set_focused(view_id)
	end
})

for i = 1, 12 do
	mez.input.add_keymap("ctrl|alt", "XF86Switch_VT_"..i, {
		press = function() mez.api.change_vt(i) end
	})
end
