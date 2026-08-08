---@module "mez_types"

local mod = "alt"
local terminal_emulator = "foot"
local run_launcher = "wmenu-run"

do
  local layout_manager = require("layout_manager")
  layout_manager.setup({ mod_key = mod })

  local master_layout = layout_manager.get_layout("master")
  mez.input.add_keymap(mod, "h", {
    press = function ()
      master_layout.builtins.dec_master_ratio(0.05)
      mez.view.apply()
    end
  })

  mez.input.add_keymap(mod, "l", {
    press = function ()
      master_layout.builtins.inc_master_ratio(0.05)
      mez.view.apply()
    end
  })

  mez.input.add_keymap(mod, "Return", {
    press = function ()
      master_layout.builtins.zoom(0)
      mez.view.apply()
    end
  })
end

-- local master = require("master")
-- master.setup({ mod_key = mod })

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
		local view_id = mez.seat.get_focused_view(0)
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
