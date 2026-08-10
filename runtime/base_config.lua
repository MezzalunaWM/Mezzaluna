---@module "mez_types"

local mod = "alt"
local terminal_emulator = "foot"
local run_launcher = "wmenu-run"

do
  local layout_manager = require("layout_manager")
  layout_manager.setup({})
  local master_layout = layout_manager.get_layout("master")

  -- Keybinds and mouse maps for layout manager
  mez.input.add_keymap(mod, "j", {
    press = function ()
      layout_manager.focus_next()
      mez.view.apply()
    end
  })

  mez.input.add_keymap(mod, "k", {
    press = function ()
      layout_manager.focus_previous()
      mez.view.apply()
    end
  })

  mez.input.add_keymap(mod .. "|shift", "F", {
    press = function ()
      layout_manager.toggle_fullscreen(0)
      mez.view.apply()
    end
  })

  for i = 1, config.tag_count do
    mez.input.add_keymap(mod, tostring(i), {
      press = function ()
        layout_manager.switch_to_tag(i)
        mez.view.apply()
      end
    })

    mez.input.add_keymap(mod .. "|shift", tostring(i), {
      press = function ()
        layout_manager.send_to_tag(0, i)
        mez.view.apply()
      end
    })
  end

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

  mez.input.add_keymap(mod, "t", {
    press = function ()
      layout_manager.get_tag(0).layout = "master"
      layout_manager.tile_tag(0)
      mez.view.apply()
    end
  })

  mez.input.add_mousemap(mod, "BTN_LEFT", {
    press = function(view_id)
      layout_manager.make_floating(view_id)
      layout_manager.tile_tag(0)
      mez.view.raise_to_top(view_id)
      mez.view.apply()
    end,
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

  mez.input.add_mousemap(mod, "BTN_MIDDLE", {
    press = function(view_id)
      layout_manager.make_tiling(view_id)
      layout_manager.tile_tag(0)
      mez.view.apply()
    end
  })

  mez.input.add_mousemap(mod, "BTN_RIGHT", {
    press = function(view_id)
      layout_manager.make_floating(view_id)
      layout_manager.tile_tag(0)
      mez.view.raise_to_top(view_id)
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
end

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
    mez.view.apply()
	end
})

for i = 1, 12 do
	mez.input.add_keymap("ctrl|alt", "XF86Switch_VT_"..i, {
		press = function() mez.api.change_vt(i) end
	})
end
