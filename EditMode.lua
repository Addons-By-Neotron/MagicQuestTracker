--[[
**********************************************************************
MagicQuestTracker - Edit Mode integration for position and size.
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
local L = LibStub("AceLocale-3.0"):GetLocale("MagicQuestTracker")
local mod = LibStub("AceAddon-3.0"):GetAddon("MagicQuestTracker")
local LEM = LibStub("LibEditMode", true)

----------------------------------------------------------------
-- Edit Mode
--
-- The tracker is moved and sized in Blizzard's Edit Mode via LibEditMode.
-- Positions are stored per Edit Mode layout in profile.layouts; size and
-- scale are shared by all layouts and also editable in the options.
--
-- LibEditMode stores the nearest anchor (which may be CENTER or BOTTOM),
-- but the tracker's height follows its content, so positions are
-- re-anchored to the top edge to make it grow downward.
----------------------------------------------------------------

local DEFAULT_POSITION = { point = "TOPRIGHT", x = -80, y = -260 }

local function GetLayoutName()
   return LEM and LEM:GetActiveLayoutName()
end

--- Returns the stored { point, x, y } for the active layout.
function mod:GetPosition()
   local layouts = self.db.profile.layouts
   local name = GetLayoutName()
   local pos = name and layouts[name]
   if not pos then
      -- Unknown layout: start from where the tracker was last placed.
      pos = layouts[self.db.profile.lastLayout]
      local legacy = self.db.profile.point -- position saved before Edit Mode support
      if not pos and legacy then
         -- AceDB stripped values that matched the old default from this table.
         pos = {
            point = legacy[1] or DEFAULT_POSITION.point,
            x = legacy[4] or DEFAULT_POSITION.x,
            y = legacy[5] or DEFAULT_POSITION.y,
         }
      end
      pos = pos or DEFAULT_POSITION
      if name then
         pos = CopyTable(pos)
         layouts[name] = pos
      end
   end
   if not (pos.point and pos.x and pos.y) then
      -- Repair entries saved from an incomplete legacy position.
      pos.point = pos.point or DEFAULT_POSITION.point
      pos.x = pos.x or DEFAULT_POSITION.x
      pos.y = pos.y or DEFAULT_POSITION.y
   end
   return pos
end

function mod:ApplyPosition()
   local frame = self.frame
   local pos = self:GetPosition()
   frame:ClearAllPoints()
   frame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
end

-- Offsets are in the frame's own (scaled) coordinate space.
local function SaveTopAnchoredPosition(frame, layoutName)
   local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
   local top = frame:GetTop() * scale - UIParent:GetTop()
   local left, right = frame:GetLeft() * scale, frame:GetRight() * scale
   local pos
   if (left + right) / 2 < UIParent:GetWidth() / 2 then
      pos = { point = "TOPLEFT", x = left / scale, y = top / scale }
   else
      pos = { point = "TOPRIGHT", x = (right - UIParent:GetRight()) / scale, y = top / scale }
   end
   mod.db.profile.layouts[layoutName] = pos
   mod.db.profile.lastLayout = layoutName
   mod:ApplyPosition()
end

local function OnPositionChanged(frame, layoutName)
   if layoutName then
      SaveTopAnchoredPosition(frame, layoutName)
   end
end

local function SizeSetting(key, name, minValue, maxValue, valueStep, formatter)
   return {
      kind = LEM.SettingType.Slider,
      name = name,
      default = mod.defaults.profile[key],
      minValue = minValue,
      maxValue = maxValue,
      valueStep = valueStep,
      formatter = formatter,
      get = function()
         return mod.db.profile[key]
      end,
      set = function(_, value)
         mod.db.profile[key] = value
         mod:ApplyLayout()
         mod:NotifyOptionsChanged()
      end,
   }
end

--- Moves the tracker to where Blizzard's objective tracker sits in the
--- active layout, top-right aligned, and matches its height.
function mod:MatchBlizzardTracker()
   local blizzard = ObjectiveTrackerFrame
   local layoutName = GetLayoutName()
   local top, right = blizzard and blizzard:GetTop(), blizzard and blizzard:GetRight()
   if not (layoutName and top and right) or InCombatLockdown() then return end

   -- Convert Blizzard's edges to UIParent units, then to our scaled units.
   local uiScale = UIParent:GetEffectiveScale()
   local blizzardScale = blizzard:GetEffectiveScale() / uiScale
   local profile = self.db.profile
   local scale = profile.scale * self.frame:GetParent():GetEffectiveScale() / uiScale
   local height = math.floor(blizzard:GetHeight() * blizzardScale / scale + 0.5)
   profile.maxHeight = math.max(100, math.min(1200, height))
   profile.layouts[layoutName] = {
      point = "TOPRIGHT",
      x = (right * blizzardScale - UIParent:GetRight()) / scale,
      y = (top * blizzardScale - UIParent:GetTop()) / scale,
   }
   profile.lastLayout = layoutName
   self:ApplyLayout()
   self:NotifyOptionsChanged()
   LEM:RefreshFrameSettings(self.frame)
end

local function FormatPercent(value)
   return ("%d%%"):format(value * 100 + 0.5)
end

function mod:SetupEditMode()
   local frame = self.frame
   if not LEM or self.editModeRegistered then return end
   self.editModeRegistered = true

   frame.editModeName = "Magic Quest Tracker"
   LEM:AddFrame(frame, OnPositionChanged, DEFAULT_POSITION)
   LEM:AddFrameSettings(frame, {
      SizeSetting("width", L["Width"], 150, 600, 1),
      SizeSetting("maxHeight", L["Maximum height"], 100, 1200, 10),
      SizeSetting("scale", L["Scale"], 0.5, 2.0, 0.05, FormatPercent),
      {
         kind = LEM.SettingType.Dropdown,
         name = L["Theme"],
         default = mod.defaults.profile.theme,
         values = function()
            local values = {}
            for key, name in pairs(mod:GetThemeList()) do
               tinsert(values, { text = name, value = key })
            end
            table.sort(values, function(a, b) return a.text < b.text end)
            return values
         end,
         get = function()
            return mod:GetCustomTheme() and mod.db.profile.theme or "blizzard"
         end,
         set = function(_, value)
            mod:SelectTheme(value)
         end,
      },
   })
   LEM:AddFrameSettingsButtons(frame, {
      { text = L["Match Blizzard tracker"], click = function() mod:MatchBlizzardTracker() end },
      { text = L["Open settings"], click = function() mod:OpenConfig() end },
   })

   LEM:RegisterCallback("layout", function()
      mod:ApplyLayout()
   end)
   LEM:RegisterCallback("create", function(layoutName, _, sourceName)
      local layouts = mod.db.profile.layouts
      local source = sourceName and layouts[sourceName]
      if source then
         layouts[layoutName] = CopyTable(source)
      end
      mod:ApplyLayout()
   end)
   LEM:RegisterCallback("rename", function(oldName, newName)
      local layouts = mod.db.profile.layouts
      layouts[newName], layouts[oldName] = layouts[oldName], nil
      if mod.db.profile.lastLayout == oldName then
         mod.db.profile.lastLayout = newName
      end
   end)
   LEM:RegisterCallback("delete", function(layoutName)
      mod.db.profile.layouts[layoutName] = nil
   end)

   -- Keep the tracker visible (even when empty) while editing, and keep the
   -- secure item buttons out of the way while it is dragged around.
   LEM:RegisterCallback("enter", function()
      mod.inEditMode = true
      mod:HideItemButtons()
      mod:RequestUpdate()
   end)
   LEM:RegisterCallback("exit", function()
      mod.inEditMode = nil
      mod:RequestUpdate()
   end)
end

function mod:IsInEditMode()
   return self.inEditMode
end
