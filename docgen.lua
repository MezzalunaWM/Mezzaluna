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
  local module_name = first_line:match("//! (%S+)")

  if module_name == nil then
    file:close()
    return nil
  end

  local output = "\n" .. module_name .. " = {}\n"
  local comments = {}

  for line in file:lines() do
    if line:match("^%s*/// %-%-%-") then
      local doc_line = line:gsub("^%s*/// %-%-%-", "---")
      table.insert(comments, doc_line)
    elseif line:match("^%s*///") then
      comments = {}
    elseif line:match("^%s*pub fn ") then
      local func_name = line:match("pub fn ([%w_]+)%(")
      if func_name then
        local comment_block = table.concat(comments, "\n")
        if comment_block ~= "" then
          comment_block = comment_block .. "\n"
        end
        output = output .. "\n" .. comment_block .. module_name .. "." .. func_name .. " = function() end\n"
      end
      comments = {}
    end
  end

  file:close()
  return output
end

local files = io.popen("ls " .. lua_api_dir)
local docs = "---@meta [mez]\nmez = {}\n"

for filename in files:lines() do
  local d = generate_docs(filename)
  if d ~= nil then
    docs = docs .. d
  end
end

local out = io.open("mez_types.lua", "w")
out:write(docs)
out:close()
