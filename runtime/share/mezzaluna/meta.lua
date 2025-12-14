--- This file is an example of what I hope the docgen can create

---@meta mez
--       ^^^ the name here would be taken from the `zlua.Lua.setGlobal` call

---Create a new hook on an event
---@param events string|string[]
---@param options table
function mez.hook.add(events, options) end
--                ^^^
-- the name here would be created from the comptime stack + the function name
-- and the arguments names would be taken from a user provided doc-comment



function mez.hook.del(a, b) end
--                ^^^
-- same thing as with the last one for the name, however for this one there is
-- no doc-comment to guide us and as such all we can reason is that the function
-- takes in two arguments (I'm not sure how feasible type inferring is) and
-- returns none.



-- I'm not sure how feasible this is at all because we'd somehow need to run
-- code that is, at runtime, calling c functions at comptime. I don't know that
-- zig will allow us to do this.
--
-- Maybe we need to look into how the normal docgen is done. If it's done by
-- just parsing the zig code I'm not sure this will be possible.
