---@module "mez_types"

-- load any lua libraries first
do
  -- allow loading files in the runtime directory
  package.path = package.path .. ";" .. mez.fs.joinpath(mez.path.runtime, "?.lua")

  mez.inspect = require("inspect").inspect
end

-- don't find the config directory if one was provided already
if not mez.path.config then
  local env_conf = os.getenv("XDG_CONFIG_HOME")
  if not env_conf then
    env_conf = os.getenv("HOME")
    if not env_conf then
      error("Couldn't determine potential config directory is $HOME set?")
    end
    env_conf = mez.fs.joinpath(env_conf, ".config")
  end
  mez.path.config = mez.fs.joinpath(env_conf, "mez")
end

local env_data = os.getenv("XDG_DATA_HOME")
if not env_data then
  env_data = os.getenv("HOME")
  if not env_data then
    error("Couldn't determine potential data directory is $HOME set?")
  end

  env_data = mez.fs.joinpath(env_data, ".local", "share")
end

-- allow plugin loading in .local/share/mez/plugins
local plugin_dir = mez.fs.joinpath(env_data, "mez", "plugins")
-- TODO: we should make a function for this in mez.fs instead of using the shell
os.execute("mkdir -p " .. plugin_dir)


-- New `package.loaders` searcher that changes the behaviour of "." in `require`
-- Tokenize `require` argument over ".", and token by token, replace "?" for
-- each entry in `package.path`. This gives a printf effect for require file finding
local printf_searcher = function (virtual_file)
  local tokens = {}
  for t in string.gmatch(virtual_file, "[^%.]+") do
    tokens[#tokens+1] = t
  end

  for path in string.gmatch(package.path, "[^;]+") do
    -- Only accept a path if all the tokens were exausted
    local exausted = true
    for _, tok in ipairs(tokens) do
      if string.find(path, "?") == nil then
        exausted = false
        break
      end

      path = string.gsub(path, "?", tok, 1)
    end

    if exausted and io.open(path) ~= nil then
      print("loading " .. path)
      return function ()
        return dofile(path)
      end
    end
  end

  return nil
end

-- Insert just BEFORE standard lua file searcher
table.insert(package.loaders, 2, printf_searcher)

package.path = package.path .. ";" .. mez.fs.joinpath(plugin_dir, "?", "init.lua")
package.path = package.path .. ";" .. mez.fs.joinpath(plugin_dir, "?", "lua/?.lua")

-- setup the base_config and config paths to be loaded through zig
mez.path.base_config = mez.fs.joinpath(mez.path.runtime, "base_config.lua")

package.path = package.path..";"..mez.fs.joinpath(mez.path.config, "lua", "?.lua")
mez.path.config = mez.fs.joinpath(mez.path.config, "init.lua")
