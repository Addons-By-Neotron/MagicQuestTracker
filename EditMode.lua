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

-- Position and size of the tracker in one Edit Mode layout.
local DEFAULT_LAYOUT = { point = "TOPRIGHT", x = -80, y = -260, width = 260, maxHeight = 450, scale = 1 }
mod.DEFAULT_LAYOUT = DEFAULT_LAYOUT

local function GetLayoutName()
   return LEM and LEM:GetActiveLayoutName()
end

-- Position and size saved before Edit Mode support, or nil.
local function GetLegacyLayout(profile)
   local legacy = profile.point
   if not (legacy or profile.width or profile.maxHeight or profile.scale) then return nil end
   -- AceDB stripped values that matched the old defaults; filled in below.
   return {
      point = legacy and legacy[1],
      x = legacy and legacy[4],
      y = legacy and legacy[5],
      width = profile.width,
      maxHeight = profile.maxHeight,
      scale = profile.scale,
   }
end

--- Returns the { point, x, y, width, maxHeight, scale } of the active layout.
function mod:GetLayoutSettings()
   local profile = self.db.profile
   local layouts = profile.layouts
   local name = GetLayoutName()
   local settings = name and layouts[name]
   if not settings then
      -- Unknown layout: start from where the tracker was last placed.
      local source = layouts[profile.lastLayout] or GetLegacyLayout(profile) or DEFAULT_LAYOUT
      settings = CopyTable(source)
      if name then
         layouts[name] = settings
      end
   end
   for key, value in pairs(DEFAULT_LAYOUT) do
      if settings[key] == nil then settings[key] = value end
   end
   return settings
end

function mod:ApplyPosition()
   local frame = self.frame
   local pos = self:GetLayoutSettings()
   frame:ClearAllPoints()
   frame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
end

-- Offsets are in the frame's own (scaled) coordinate space.
local function SaveTopAnchoredPosition(frame, layoutName)
   local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
   local top = frame:GetTop() * scale - UIParent:GetTop()
   local left, right = frame:GetLeft() * scale, frame:GetRight() * scale
   local pos = mod:GetLayoutSettings()
   if (left + right) / 2 < UIParent:GetWidth() / 2 then
      pos.point, pos.x, pos.y = "TOPLEFT", left / scale, top / scale
   else
      pos.point, pos.x, pos.y = "TOPRIGHT", (right - UIParent:GetRight()) / scale, top / scale
   end
   mod.db.profile.lastLayout = layoutName
   mod:ApplyPosition()
end

local function OnPositionChanged(frame, layoutName)
   if layoutName then
      SaveTopAnchoredPosition(frame, layoutName)
   end
end

-- Size settings are saved per Edit Mode layout, like the position.
local function SizeSetting(key, name, minValue, maxValue, valueStep, formatter, desc)
   return {
      kind = LEM.SettingType.Slider,
      name = name,
      desc = desc,
      default = DEFAULT_LAYOUT[key],
      minValue = minValue,
      maxValue = maxValue,
      valueStep = valueStep,
      formatter = formatter,
      get = function()
         return mod:GetLayoutSettings()[key]
      end,
      set = function(_, value)
         mod:GetLayoutSettings()[key] = value
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
   local settings = self:GetLayoutSettings()
   local scale = settings.scale * self.frame:GetParent():GetEffectiveScale() / uiScale
   local height = math.floor(blizzard:GetHeight() * blizzardScale / scale + 0.5)
   settings.maxHeight = math.max(100, math.min(1200, height))
   settings.point = "TOPRIGHT"
   settings.x = (right * blizzardScale - UIParent:GetRight()) / scale
   settings.y = (top * blizzardScale - UIParent:GetTop()) / scale
   self.db.profile.lastLayout = layoutName
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
   LEM:AddFrame(frame, OnPositionChanged, DEFAULT_LAYOUT)
   LEM:AddFrameSettings(frame, {
      SizeSetting("width", L["Width"], 150, 600, 1),
      SizeSetting("maxHeight", L["Maximum height"], 100, 1200, 10, nil,
         L["The tracker grows with its contents up to this height, then becomes scrollable."]),
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
            return mod:GetThemeSettings() and mod.db.profile.theme or "blizzard"
         end,
         set = function(_, value)
            mod:SelectTheme(value)
         end,
      },
   })
   LEM:AddFrameSettingsButtons(frame, {
      { text = L["Match Blizzard tracker"], click = function() mod:MatchBlizzardTracker() end },
   })

   LEM:RegisterCallback("layout", function()
      mod:ApplyLayout()
      mod:NotifyOptionsChanged()
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

function mod:GetEditModeLayoutName()
   return GetLayoutName()
end

-- Edit Mode is never opened or closed from here: entering and leaving it
-- runs protected code (target/focus and party frame resets) that is
-- blocked and taints Blizzard's frames when started by an addon.

function mod:IsInEditMode()
   return self.inEditMode
end
