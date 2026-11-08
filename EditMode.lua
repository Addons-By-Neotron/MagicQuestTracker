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
   if self.previewing then return self.previewLayout end
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
   if self.previewing then return end
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

-- Closest snap line to any of the sources (edges and center): the offset
-- and the line, or nil when none is within range.
local function SnapDelta(sources, targets, range)
   local best, line
   for _, source in ipairs(sources) do
      for _, target in pairs(targets) do
         local delta = target - source
         if math.abs(delta) <= range and (not best or math.abs(delta) < math.abs(best)) then
            best, line = delta, target
         end
      end
   end
   return best, line
end

-- Snap offsets and lines (in UIParent units) for a frame where it is now, or
-- nil while Blizzard's "Snap" option is off. Like Blizzard's frames: edges or
-- center to the screen edges and center lines, and to the grid when shown.
local function GetSnap(frame)
   local manager = EditModeManagerFrame
   if not (manager and manager.IsSnapEnabled and manager:IsSnapEnabled()) then return end
   local left, bottom, width, height = frame:GetRect()
   if not left then return end
   local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
   left, bottom, width, height = left * scale, bottom * scale, width * scale, height * scale
   local screenWidth, screenHeight = UIParent:GetSize()
   local magnetism = EditModeMagnetismManager
   local range = (magnetism and magnetism.magnetismRange or 8) / UIParent:GetEffectiveScale()

   local xTargets = { 0, screenWidth / 2, screenWidth }
   local yTargets = { 0, screenHeight / 2, screenHeight }
   local grid = magnetism and magnetism.magneticGridLines
   if grid then
      for _, x in pairs(grid.vertical) do xTargets[#xTargets + 1] = x end
      for _, y in pairs(grid.horizontal) do yTargets[#yTargets + 1] = y end
   end
   local dx, xLine = SnapDelta({ left, left + width / 2, left + width }, xTargets, range)
   local dy, yLine = SnapDelta({ bottom, bottom + height / 2, bottom + height }, yTargets, range)
   return left, bottom, scale, dx, xLine, dy, yLine
end

--- Snaps a dropped Edit Mode frame (LibEditMode doesn't). Leaves the frame
--- anchored BOTTOMLEFT; callers re-save it.
function mod:SnapEditModeFrame(frame)
   local left, bottom, scale, dx, _, dy = GetSnap(frame)
   if not left or not (dx or dy) then return end
   frame:ClearAllPoints()
   frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (left + (dx or 0)) / scale, (bottom + (dy or 0)) / scale)
end

-- Snap guide lines shown while a frame is dragged, like Blizzard's.
local snapOverlay
local SNAP_LINE_COLOR = { 0.35, 0.75, 1, 0.9 }
local function GetSnapOverlay()
   if snapOverlay then return snapOverlay end
   snapOverlay = CreateFrame("Frame", nil, UIParent)
   snapOverlay:SetAllPoints()
   snapOverlay:SetFrameStrata("TOOLTIP")
   snapOverlay:Hide()
   local function Line()
      local line = snapOverlay:CreateTexture(nil, "OVERLAY")
      line:SetColorTexture(unpack(SNAP_LINE_COLOR))
      line:Hide()
      return line
   end
   snapOverlay.vertical, snapOverlay.horizontal = Line(), Line()
   snapOverlay:SetScript("OnUpdate", function(self)
      local _, _, _, _, xLine, _, yLine = GetSnap(self.target)
      local vertical, horizontal = self.vertical, self.horizontal
      local thickness = 2 / UIParent:GetEffectiveScale()  -- pixels
      if xLine then
         vertical:ClearAllPoints()
         vertical:SetPoint("TOPLEFT", UIParent, "TOPLEFT", xLine - thickness / 2, 0)
         vertical:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", xLine - thickness / 2, 0)
         vertical:SetWidth(thickness)
      end
      if yLine then
         horizontal:ClearAllPoints()
         horizontal:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, yLine - thickness / 2)
         horizontal:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, yLine - thickness / 2)
         horizontal:SetHeight(thickness)
      end
      vertical:SetShown(xLine ~= nil)
      horizontal:SetShown(yLine ~= nil)
   end)
   return snapOverlay
end

--- Shows snap guide lines while LibEditMode drags the frame.
function mod:AddSnapGuides(frame)
   local selection = LEM and LEM.frameSelections and LEM.frameSelections[frame]
   if not selection then return end
   selection:HookScript("OnDragStart", function()
      if InCombatLockdown() then return end
      local overlay = GetSnapOverlay()
      overlay.target = frame
      overlay:Show()
   end)
   selection:HookScript("OnDragStop", function()
      if snapOverlay then snapOverlay:Hide() end
   end)
end

--- The nearest anchor (corner, edge or center of the screen) and offsets for
--- a frame, in its own scaled units, so it keeps its place when the screen
--- size changes.
function mod:GetNearestAnchor(frame)
   local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
   local left, right = frame:GetLeft() * scale, frame:GetRight() * scale
   local bottom, top = frame:GetBottom() * scale, frame:GetTop() * scale
   local screenWidth, screenHeight = UIParent:GetSize()
   local centerX, centerY = (left + right) / 2, (bottom + top) / 2
   local h, x, v, y
   -- Within a few pixels of the center line counts as centered.
   if math.abs(centerX - screenWidth / 2) < 1 or (left >= screenWidth / 3 and right <= screenWidth * 2 / 3) then
      h, x = "", centerX - screenWidth / 2
   elseif centerX < screenWidth / 2 then
      h, x = "LEFT", left
   else
      h, x = "RIGHT", right - screenWidth
   end
   if math.abs(centerY - screenHeight / 2) < 1 or (bottom >= screenHeight / 3 and top <= screenHeight * 2 / 3) then
      v, y = "", centerY - screenHeight / 2
   elseif centerY < screenHeight / 2 then
      v, y = "BOTTOM", bottom
   else
      v, y = "TOP", top - screenHeight
   end
   local point = v .. h
   if point == "" then point = "CENTER" end
   return point, x / scale, y / scale
end

local function OnPositionChanged(frame, layoutName)
   if layoutName then
      mod:SnapEditModeFrame(frame)
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
   settings.width = math.max(150, math.min(600, math.floor(blizzard:GetWidth() * blizzardScale / scale + 0.5)))
   settings.point = "TOPRIGHT"
   settings.x = (right * blizzardScale - UIParent:GetRight()) / scale
   settings.y = (top * blizzardScale - UIParent:GetTop()) / scale
   self.db.profile.lastLayout = layoutName
   self:ApplyLayout()
   self:NotifyOptionsChanged()
   LEM:RefreshFrameSettings(self.frame)
   return true
end

--- True when the profile already has a saved position or size.
function mod:HasSavedGeometry()
   local profile = self.db.profile
   return next(profile.layouts) ~= nil or GetLegacyLayout(profile) ~= nil
end

--- On first load (no saved geometry), takes over the position and size of
--- Blizzard's tracker. Retries until its position is known.
function mod:MatchBlizzardOnFirstLoad()
   local profile = self.db.profile
   if profile.geometryMatched ~= false then return end
   if self:MatchBlizzardTracker() then
      profile.geometryMatched = true
      profile.hideBlizzardTracker = true
   end
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
   self:AddSnapGuides(frame)
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
      mod:MatchBlizzardOnFirstLoad()
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
