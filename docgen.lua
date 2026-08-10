#!/usr/bin/env lua

local lua_api_dir = "./src/lua/"

---@param file_name string
---@return string?
local function generate_docs(file_name)
  local file = io.open(lua_api_dir .. file_name, "r")
  if file == nil then
    return nil
  end

  local first_line = file:read("l")
  local module_name = first_line:match("/// (%S+)")

  if module_name == nil then
    file:close()
    return nil
  end

  local output = "\n" .. module_name .. " = {}\n"
  local annotations = {}
  local params = {}

  for line in file:lines() do
    if line:match("^%s*/// %-%-%-") then
      local line = line:gsub("^%s*/// %-%-%-", "---")

      if line:match("@param %.%.%.") then
        params[#params + 1] = "..."
      elseif line:match("@param") then
        params[#params + 1] = line:match("@param%s([%a_]+)%s")
      end

      annotations[#annotations + 1] = line
    elseif #annotations ~= 0 then
      local doc = "\n" .. table.concat(annotations, "\n")


      if line:match("^%s*pub fn ") then
        doc = doc .. string.format(
          "\n%s.%s = function(%s) end",
          module_name,
          line:match("pub fn ([%w_]+)%("),
          table.concat(params, ", ")
        )
      end

      output = output .. doc .. "\n"
      annotations = {}
      params = {}
    end
  end

  file:close()
  return output
end

local files, err = io.popen("ls " .. lua_api_dir)
if files == nil then error(err) end

local docs = "---@meta [mez]\nmez = {}\n"

for filename in files:lines() do
  local d = generate_docs(filename)
  if d ~= nil then
    docs = docs .. d
  end
end

local out, err = io.open("./runtime/mez_types.lua", "w")
if out == nil then error(err) end
out:write(docs)
out:close()
