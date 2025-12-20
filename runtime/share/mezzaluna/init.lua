local env_conf = os.getenv("XDG_CONFIG_HOME")

if not env_conf then
  env_conf = os.getenv("HOME")
  if not env_conf then
    error("Couldn't determine potential config directory is $HOME set?")
  end
  env_conf = mez.fs.joinpath(env_conf, ".config")
end

-- allow loading files in the runtime directory
package.path = package.path..";"..mez.fs.joinpath(mez.path.runtime, "?.lua")
mez.inspect = require("inspect").inspect
mez.layout_manager = require("layout_manager")

mez.path.base_config = mez.fs.joinpath(mez.path.runtime, "master.lua")

if not mez.path.config then
  mez.path.config = mez.fs.joinpath(env_conf, "mez", "init.lua")
  package.path = package.path..";"..mez.fs.joinpath(env_conf, "mez", "lua", "?.lua")
end
