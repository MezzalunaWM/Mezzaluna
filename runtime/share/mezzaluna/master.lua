mez.input.add_keymap("alt", "g", {
  press = function ()
    for _, id in ipairs(mez.view.get_all_ids()) do
      print(id)
    end
  end
})

local master = function()
  local config = {
    tag_count = 5,
  }

  local ctx = {
    master_ratio = 0.5,
    tags = {},
    tag_id = 1,
  }

  local tile_onscreen = function(tag_id, res)
    if ctx.tags[tag_id].master == nil then
      return
    end

    mez.view.set_enabled(ctx.tags[tag_id].master, true)
    if #ctx.tags[tag_id].stack == 0 then
      mez.view.set_size(ctx.tags[tag_id].master, res.width, res.height)
      mez.view.set_position(ctx.tags[tag_id].master, 0, 0)
    else
      mez.view.set_size(ctx.tags[tag_id].master, res.width * ctx.master_ratio, res.height)
      mez.view.set_position(ctx.tags[tag_id].master, 0, 0)

      for i, stack_id in ipairs(ctx.tags[tag_id].stack) do
        mez.view.set_enabled(stack_id, true)
        mez.view.set_size(stack_id, res.width * (1 - ctx.master_ratio), res.height / #ctx.tags[tag_id].stack)
        mez.view.set_position(stack_id, res.width * ctx.master_ratio, (res.height / #ctx.tags[tag_id].stack * (i - 1)))
      end
    end
  end

  local tile_offscreen = function(tag_id, res)
    if ctx.tags[tag_id].master == nil then
      return
    end

    mez.view.set_enabled(ctx.tags[tag_id].master, false)
    for _, view in ipairs(ctx.tags[tag_id].stack) do
      mez.view.set_enabled(view, false)
    end
  end

  local tile_all = function ()
    local res = mez.output.get_resolution(0)

    for id = 1,config.tag_count do
      if id == ctx.tag_id then
        tile_onscreen(id, res)
      else
        tile_offscreen(id, res)
      end
    end
  end

  for i = 1,config.tag_count do
    ctx.tags[#ctx.tags + 1] = {
      stack = {},
      master = nil,
    }
    mez.input.add_keymap("alt", "" .. i, {
      press = function ()
        ctx.tag_id = i

        if ctx.tags[i].master then
          mez.view.set_focused(ctx.tags[i].master)
        else
          mez.view.set_focused(nil)
        end

        tile_all()
      end
    })
  end

  mez.hook.add("ServerStartPost", {
    callback = function()
      print("ServerStartPost")
      print("Doesn't do anything :(")
    end
  })

  mez.hook.add("ViewMapPre", {
    callback = function(v)
      if ctx.tags[ctx.tag_id].master == nil then
        ctx.tags[ctx.tag_id].master = v
      else
        table.insert(ctx.tags[ctx.tag_id].stack, #ctx.tags[ctx.tag_id].stack + 1, v)
      end

      mez.view.set_focused(v)

      tile_all()
    end
  })

  mez.hook.add("ViewUnmapPost", {
    callback = function(v)
      if v == ctx.tags[ctx.tag_id].master then
        if #ctx.tags[ctx.tag_id].stack > 0 then
          ctx.tags[ctx.tag_id].master = table.remove(ctx.tags[ctx.tag_id].stack, 1)
          mez.view.set_focused(ctx.tags[ctx.tag_id].master)
        else
          ctx.tags[ctx.tag_id].master = nil
        end
      else
        for i, id in ipairs(ctx.tags[ctx.tag_id].stack) do
          if id == v then
            if i == 1 then
              mez.view.set_focused(ctx.tags[ctx.tag_id].master)
            elseif i == #ctx.tags[ctx.tag_id].stack then
              mez.view.set_focused(ctx.tags[ctx.tag_id].stack[i - 1])
            else
              mez.view.set_focused(ctx.tags[ctx.tag_id].stack[i + 1])
            end

            table.remove(ctx.tags[ctx.tag_id].stack, i)
          end
        end
      end

      tile_all()
    end
  })

  mez.input.add_keymap("alt", "p", {
    press = function()
      mez.api.spawn("wmenu-run")
    end,
  })

  mez.input.add_keymap("alt", "b", {
    press = function()
      mez.api.spawn("swaybg -i ~/Images/wallpapers/void/gruv_void.png")
    end,
  })

  mez.input.add_keymap("alt|shift", "Return", {
    press = function()
      mez.api.spawn("alacritty")
    end,
  })

  mez.input.add_keymap("alt|shift", "C", {
    press = function ()
      mez.view.close(0)
    end
  })

  mez.input.add_keymap("alt|shift", "q", {
    press = function ()
      mez.api.exit();
    end
  })

  mez.input.add_keymap("alt", "Return", {
    press = function()
      local focused = mez.view.get_focused_id()

      if focused == ctx.tags[ctx.tag_id].master then return end

      for i, id in ipairs(ctx.tags[ctx.tag_id].stack) do
        if focused == id then
          local t = ctx.tags[ctx.tag_id].master
          ctx.tags[ctx.tag_id].master = ctx.tags[ctx.tag_id].stack[i]
          ctx.tags[ctx.tag_id].stack[i] = t
        end
      end

      tile_all()
    end,
  })

  mez.input.add_keymap("alt", "j", {
    press = function ()
      local focused = mez.view.get_focused_id()

      if focused == ctx.tags[ctx.tag_id].master then
        mez.view.set_focused(ctx.tags[ctx.tag_id].stack[1])
      elseif focused == ctx.tags[ctx.tag_id].stack[#ctx.tags[ctx.tag_id].stack] then
        mez.view.set_focused(ctx.tags[ctx.tag_id].master)
      else
        for i, id in ipairs(ctx.tags[ctx.tag_id].stack) do
          -- TODO: use table.find
          if focused == id then
            mez.view.set_focused(ctx.tags[ctx.tag_id].stack[i + 1])
          end
        end
      end
    end
  })

  mez.input.add_keymap("alt", "k", {
    press = function ()
      local focused = mez.view.get_focused_id()

      if focused == ctx.tags[ctx.tag_id].master then
        mez.view.set_focused(ctx.tags[ctx.tag_id].stack[#ctx.tags[ctx.tag_id].stack])
      elseif focused == ctx.tags[ctx.tag_id].stack[1] then
        mez.view.set_focused(ctx.tags[ctx.tag_id].master)
      else
        for i, id in ipairs(ctx.tags[ctx.tag_id].stack) do
          -- TODO: use table.find
          if focused == id then
            mez.view.set_focused(ctx.tags[ctx.tag_id].stack[i - 1])
          end
        end
      end
    end
  })

  mez.input.add_keymap("alt", "h", {
    press = function()
      if ctx.master_ratio > 0.15 then
        ctx.master_ratio = ctx.master_ratio - 0.05
        tile_all()
      end
    end
  })

  mez.input.add_keymap("alt", "l", {
    press = function()
      if ctx.master_ratio < 0.85 then
        ctx.master_ratio = ctx.master_ratio + 0.05
        tile_all()
      end
    end
  })

  mez.input.add_keymap("alt", "Tab", {
    press = function ()
      local focused = mez.view.get_focused_id()
      local all = mez.view.get_all_ids()

      for _, id in ipairs(all) do
        if id ~= focused then
          mez.view.set_focused(id)
          return
        end
      end
    end
  })

  local fullscreen = function (view_id)
    mez.view.toggle_fullscreen(view_id)
    tile_all()
  end

  mez.input.add_keymap("alt|shift", "F", {
    press = function() fullscreen(0) end
  })

  mez.hook.add("ViewRequestFullscreen", {
    callback = fullscreen
  })

  mez.hook.add("ViewPointerMotion", {
    callback = function (view_id, cursor_x, cursor_y)
      mez.view.set_focused(view_id)
    end
  })

  for i = 1, 12 do
    mez.input.add_keymap("ctrl|alt", "XF86Switch_VT_"..i, {
      press = function() mez.api.change_vt(i) end
    })
  end

  mez.input.add_mousemap("alt", "BTN_LEFT", {
    drag = function(pos, drag)
      if drag.view ~= nil then
        mez.view.set_position(drag.view.id, pos.x - drag.view.offset.x, pos.y - drag.view.offset.y)
      end
    end,
  }, {})

  mez.input.add_mousemap("alt", "BTN_RIGHT", {
    press = function() return false end,
    drag = function(pos, drag)
      if drag.view ~= nil then
        mez.view.set_size(
          drag.view.id,
          (pos.x - drag.start.x) + drag.view.offset.x + (drag.view.dims.width - drag.view.offset.x),
          (pos.y - drag.start.y) + drag.view.offset.y + (drag.view.dims.height - drag.view.offset.y)
        )
      end
    end,
    release = function() return false end
  })
end

master()
