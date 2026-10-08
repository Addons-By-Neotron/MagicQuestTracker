--[[
**********************************************************************
MagicQuestTracker - Table recycling.
**********************************************************************
Copyright (C) 2026 NeoTron

This file is part of MagicQuestTracker, a World of Warcraft Addon

MagicQuestTracker is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

MagicQuestTracker is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with MagicQuestTracker.  If not, see <https://www.gnu.org/licenses/>.

**********************************************************************
]]
local mod = LibStub("AceAddon-3.0"):GetAddon("MagicQuestTracker")

----------------------------------------------------------------
-- Table recycling
--
-- The tracker rebuilds its quest data on every quest log update (and
-- every couple of seconds while distances are shown), so tables are
-- reused instead of left for the garbage collector. The pool is weak
-- keyed, so unused tables can still be collected.
----------------------------------------------------------------

local list = setmetatable({}, { __mode = "k" })

-- Debug builds: reading a recycled table raises an error, to catch data
-- that is still referenced after being returned to the pool.
local freedMeta
--@debug@
freedMeta = { __index = function(_, key)
   error("MagicQuestTracker: table used after del (key " .. tostring(key) .. ")", 2)
end }
--@end-debug@

--- Returns an empty table (or an array of the arguments).
function mod.new(...)
   local t = next(list)
   if t then
      list[t] = nil
      if freedMeta then setmetatable(t, nil) end
      for i = 1, select("#", ...) do
         t[i] = select(i, ...)
      end
      return t
   end
   return { ... }
end

--- Returns a table built from key, value argument pairs.
function mod.newHash(...)
   local t = next(list)
   if t then
      list[t] = nil
      if freedMeta then setmetatable(t, nil) end
   else
      t = {}
   end
   for i = 1, select("#", ...), 2 do
      t[select(i, ...)] = select(i + 1, ...)
   end
   return t
end

--- Clears a table and returns it to the pool. Returns nil, so it can be
--- used as `t = del(t)`.
function mod.del(t)
   if type(t) ~= "table" then
      return nil
   end
   wipe(t)
   if freedMeta then setmetatable(t, freedMeta) end
   list[t] = true
   return nil
end

--- Like del, but also recycles nested tables. Only use on tables whose
--- nested tables are not referenced from anywhere else.
function mod.deepDel(t)
   if type(t) ~= "table" then
      return nil
   end
   for k, v in pairs(t) do
      if type(v) == "table" then
         mod.deepDel(v)
      end
   end
   return mod.del(t)
end
