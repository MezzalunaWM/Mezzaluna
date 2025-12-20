--- This is a wrapper around mez's keymapping system to allow for data driven
--- keymaps. The advantage of using this over the raw keybinds is the ability
--- to unmap and map a list of keymaps at runtime without too much hassle.

---@class mapper.map
---@field modifiers string formatted like in mez.input.add_keymap
---@field keys string formatted like in mez.input.add_keymap
---@field options table formatted like in mez.input.add_keymap

local mapper = {}

--- map a table of maps
---@param maps mapper.map[]
function mapper.add(maps)
  for _, map in ipairs(maps) do
    mez.input.add_keymap(map.modifiers, map.keys, map.options)
  end
end

--- del a table of maps
---@param maps mapper.map[]
function mapper.del(maps)
  for _, map in ipairs(maps) do
    mez.input.del_keymap(map.modifiers, map.keys)
  end
end

return mapper
