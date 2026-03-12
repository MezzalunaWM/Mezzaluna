---@module "mez_types"

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
for _, plugin_name in ipairs(mez.fs.subdirs(plugin_dir)) do
  package.path = package.path .. ";" .. mez.fs.joinpath(plugin_dir, plugin_name, "lua", "?", "init.lua")
  package.path = package.path .. ";" .. mez.fs.joinpath(plugin_dir, plugin_name, "lua", "?.lua")
end

-- allow loading files in the runtime directory
package.path = package.path .. ";" .. mez.fs.joinpath(mez.path.runtime, "?.lua")

-- add the inspect function to mez
mez.inspect = require("inspect").inspect

-- setup the base_config and config paths to be loaded through zig
mez.path.base_config = mez.fs.joinpath(mez.path.runtime, "base_config.lua")

package.path = package.path..";"..mez.fs.joinpath(mez.path.config, "lua", "?.lua")
mez.path.config = mez.fs.joinpath(mez.path.config, "init.lua")
