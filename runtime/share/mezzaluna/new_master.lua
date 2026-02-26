---@module 'master'

---@class Master
---@field default_config MasterConfig
---@field config MasterConfig
---@field state MasterState
---@field builtins MasterBuiltins
local M = {};

M.builtins = {
}

---@class MasterConfig
---@field master_ratio number
---@field tag_count number
local default_config = {
  master_ratio = 0.5,
  tag_count = 5,

}

---@class Tag
---@field floating number[]
---@field stack number[]

---@class MasterState
---@field tag_id number
M.state = {
  tag_id = 1
}

M.setup = function(config)

end

return M

