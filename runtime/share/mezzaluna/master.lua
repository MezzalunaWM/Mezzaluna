mez.layout_manager.new_layout({
  name = "master",
  callback = function(output)
    local mw, my, ty;

    local mon = mez.output.get_resolution(output)
    local nmaster = 1
    local mfact = 0.5

    local view_ids = {}

    local ok, ids = pcall(mez.output.get_all_views, output)
    if not ok or ids == nil then
      print("nillllll")
      return
    end
    print("continue")

    print(mez.inspect(ids))
    for _, v in ipairs(ids) do
      view_ids[#view_ids + 1] = v
    end
    if #view_ids == 0 then
      return
    end

    if #view_ids > nmaster then
      mw = (nmaster and math.floor((mon.width * mfact) + 0.5)) or 0
    else
      mw = mon.width
    end

    print("slkdjflksdjflksjdflkjsdf"..mw)

    my, ty = 0, 0
	-- wl_list_for_each(c, &clients, link) {
	-- 	if (!VISIBLEON(c, m) || c->isfloating || c->isfullscreen)
	-- 		continue;
    for i, view in ipairs(view_ids) do
      if i <= nmaster then
        mez.view.set_position(view, 0, 0 + my)
        mez.view.set_size(view, mw, (mon.height - my) / (math.min(#view_ids, nmaster) - (i - 1)))
        my = my + mez.view.get_size(view).height
      else
        mez.view.set_position(view, 0 + mw, 0 + ty)
        mez.view.set_size(view, mon.width + mw, (mon.height - ty) / (#view_ids - i))
        ty = ty + mez.view.get_size(view).height
      end
    end
  end
})


-- mez.input.add_keymap("alt", "Return", {
--   press = function()
--     local focused = mez.view.get_focused_id()
--
--     if focused == ctx.tags[ctx.tag_id].master then return end
--
--     for i, id in ipairs(ctx.tags[ctx.tag_id].stack) do
--       if focused == id then
--         local t = ctx.tags[ctx.tag_id].master
--         ctx.tags[ctx.tag_id].master = ctx.tags[ctx.tag_id].stack[i]
--         ctx.tags[ctx.tag_id].stack[i] = t
--       end
--     end
--
--     tile_all()
--   end,
-- })
--
-- mez.input.add_keymap("alt", "j", {
--   press = function ()
--     local focused = mez.view.get_focused_id()
--
--     if focused == ctx.tags[ctx.tag_id].master then
--       mez.view.set_focused(ctx.tags[ctx.tag_id].stack[1])
--     elseif focused == ctx.tags[ctx.tag_id].stack[#ctx.tags[ctx.tag_id].stack] then
--       mez.view.set_focused(ctx.tags[ctx.tag_id].master)
--     else
--       for i, id in ipairs(ctx.tags[ctx.tag_id].stack) do
--         -- TODO: use table.find
--         if focused == id then
--           mez.view.set_focused(ctx.tags[ctx.tag_id].stack[i + 1])
--         end
--       end
--     end
--   end
-- })
--
-- mez.input.add_keymap("alt", "k", {
--   press = function ()
--     local focused = mez.view.get_focused_id()
--
--     if focused == ctx.tags[ctx.tag_id].master then
--       mez.view.set_focused(ctx.tags[ctx.tag_id].stack[#ctx.tags[ctx.tag_id].stack])
--     elseif focused == ctx.tags[ctx.tag_id].stack[1] then
--       mez.view.set_focused(ctx.tags[ctx.tag_id].master)
--     else
--       for i, id in ipairs(ctx.tags[ctx.tag_id].stack) do
--         -- TODO: use table.find
--         if focused == id then
--           mez.view.set_focused(ctx.tags[ctx.tag_id].stack[i - 1])
--         end
--       end
--     end
--   end
-- })
--
-- mez.input.add_keymap("alt", "h", {
--   press = function()
--     if ctx.master_ratio > 0.15 then
--       ctx.master_ratio = ctx.master_ratio - 0.05
--       tile_all()
--     end
--   end
-- })
--
-- mez.input.add_keymap("alt", "l", {
--   press = function()
--     if ctx.master_ratio < 0.85 then
--       ctx.master_ratio = ctx.master_ratio + 0.05
--       tile_all()
--     end
--   end
-- })



mez.layout_manager.set_layout("master")






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

mez.hook.add("ViewPointerMotion", {
  callback = function (view_id, cursor_x, cursor_y)
    mez.view.set_focused(view_id)
  end
})

mez.input.add_keymap("alt|shift", "q", {
  press = function ()
    mez.api.exit();
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

for i = 1, 12 do
  mez.input.add_keymap("ctrl|alt", "XF86Switch_VT_"..i, {
    press = function() mez.api.change_vt(i) end
  })
end
