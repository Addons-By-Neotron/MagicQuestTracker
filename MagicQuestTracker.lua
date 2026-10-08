--[[
**********************************************************************
MagicQuestTracker - Addon setup, events, update scheduling and slash commands.
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

local mod = LibStub("AceAddon-3.0"):NewAddon("MagicQuestTracker", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0", "LibMagicUtil-1.0")
LibStub("LibLogger-1.0"):Embed(mod)

local InCombatLockdown = InCombatLockdown

----------------------------------------------------------------
-- Saved variable defaults
----------------------------------------------------------------

local function FontDefaults(size, outline)
   return { face = "Friz Quadrata TT", size = size, outline = outline or "" }
end

mod.defaults = {
   profile = {
      -- Behaviour
      hideBlizzardTracker = true,
      showAllQuests = true,          -- false = only quests on the built-in watch list
      currentZoneFirst = true,
      onlyCurrentZone = false,
      autoFoldZones = false,
      zoneSort = "level",            -- level | name | distance
      questSort = "level",           -- level | name | distance
      showDistance = false,
      showDirection = false,
      arrowSize = 16,
      arrowMaxDistance = 1000,       -- yards, 0 = no limit
      waypointMode = "both",         -- ctrl-click: tomtom | blizzard | both
      showLevel = true,
      showQuestTags = true,
      markForeverQuests = true,
      colorByDifficulty = true,
      showCompletedObjectives = true,
      showRecipes = true,
      showWorldQuests = true,
      showBonusObjectives = true,
      showItemButtons = true,
      showPOIButtons = true,
      showFindGroupButton = true,

      -- Layout
      locked = false,
      width = 260,
      maxHeight = 450,
      scale = 1.0,
      backgroundColor = { r = 0, g = 0, b = 0 },
      backgroundAlpha = 0.0,
      backgroundHoverAlpha = 0.4,

      -- Spacing (pixels)
      sectionSpacing = 10,      -- above each section header (Quests, World Quests, ...)
      zoneSpacing = 8,          -- above each zone header
      zoneHeaderSpacing = 2,    -- between a zone header and its first quest
      questSpacing = 6,         -- above each quest title
      objectiveSpacing = 1,     -- between objective lines
      point = { "TOPRIGHT", "UIParent", "TOPRIGHT", -80, -260 },

      -- Fonts
      fonts = {
         title = FontDefaults(14),
         module = FontDefaults(13),
         zone = FontDefaults(12),
         quest = FontDefaults(12),
         objective = FontDefaults(11),
      },
   },
   char = {
      collapsedZones = {},    -- [zoneName] = true
      autoFoldZone = nil,     -- zone the auto-fold was last applied for
      collapsedSections = {}, -- [quests|worldQuests|bonus|recipes] = true
      minimized = false,
   },
}

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

function mod:OnInitialize()
   self.db = LibStub("AceDB-3.0"):New("MagicQuestTrackerDB", self.defaults, "Default")
   self.db.RegisterCallback(self, "OnProfileChanged", "ApplyProfile")
   self.db.RegisterCallback(self, "OnProfileCopied", "ApplyProfile")
   self.db.RegisterCallback(self, "OnProfileReset", "ApplyProfile")

   self:SetupOptions()
   self:RegisterChatCommand("mqt", "ChatCommand")
   self:RegisterChatCommand("questtracker", "ChatCommand")
end

local QUEST_EVENTS = {
   "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED",
   "QUEST_TURNED_IN", "SUPER_TRACKING_CHANGED", "PLAYER_LEVEL_UP",
   "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
   "TRACKED_RECIPE_UPDATE", "BAG_UPDATE_DELAYED", "CURRENCY_DISPLAY_UPDATE",
}

function mod:OnEnable()
   self:CreateTracker()
   for _, event in ipairs(QUEST_EVENTS) do
      self:RegisterEvent(event, "RequestUpdate")
   end
   self:RegisterEvent("PLAYER_ENTERING_WORLD")
   self:RegisterEvent("PLAYER_REGEN_ENABLED")
   self:RegisterEvent("PLAYER_REGEN_DISABLED")
   self:ApplyProfile()
end

function mod:OnDisable()
   self:UnregisterAllEvents()
   self:SetBlizzardTrackerHidden(false)
   self.itemEntries = nil
   self:HideItemButtons()
   if self.frame then self.frame:Hide() end
end

function mod:ApplyProfile()
   -- "log" sort order was removed; fall back to level.
   local profile = self.db.profile
   if profile.zoneSort ~= "name" and profile.zoneSort ~= "distance" then profile.zoneSort = "level" end
   if profile.questSort ~= "name" and profile.questSort ~= "distance" then profile.questSort = "level" end
   self:UpdateDistanceTimer()
   self:ApplyLayout()
   self:SetBlizzardTrackerHidden(self.db.profile.hideBlizzardTracker)
   self:RequestUpdate()
end

function mod:PLAYER_ENTERING_WORLD()
   -- Blizzard's tracker initializes on PLAYER_ENTERING_WORLD; re-apply afterwards.
   self:SetBlizzardTrackerHidden(self.db.profile.hideBlizzardTracker)
   self:RequestUpdate()
end

function mod:PLAYER_REGEN_DISABLED()
   -- Still allowed to move secure frames here; place item buttons now if
   -- a render happened just before combat started.
   if self.itemLayoutPending then
      self:LayoutItemButtons()
   end
end

function mod:PLAYER_REGEN_ENABLED()
   if self.pendingBlizzardVisibility ~= nil then
      self:SetBlizzardTrackerHidden(self.pendingBlizzardVisibility)
   end
   if self.applyLayoutDeferred then
      self.applyLayoutDeferred = nil
      self:ApplyLayout()
   end
   if self.layoutDeferred then
      self.layoutDeferred = nil
      self:RequestUpdate()
   end
end

----------------------------------------------------------------
-- Update coalescing: QUEST_LOG_UPDATE and BAG_UPDATE fire in bursts.
----------------------------------------------------------------

local UPDATE_DELAY = 0.1

function mod:RequestUpdate()
   if self.updateTimer then return end
   self.updateTimer = self:ScheduleTimer("RunUpdate", UPDATE_DELAY)
end

function mod:RunUpdate()
   self.updateTimer = nil
   if not self.frame then return end
   local sections, numQuests, numShown = self:CollectQuests()
   self:AutoFoldZones(sections)
   local recipes = self.db.profile.showRecipes and self:CollectRecipes() or nil
   local tasks = self:CollectTasks()
   self:Render(sections, numQuests, numShown, recipes, tasks)
end

----------------------------------------------------------------
-- Auto-fold: when all objectives are shown, fold zones other than the
-- current one, but only when the player changes zone, so zones unfolded
-- by hand stay open until the next zone change.
----------------------------------------------------------------

function mod:AutoFoldZones(sections)
   local profile = self.db.profile
   if not profile.autoFoldZones or profile.onlyCurrentZone then return end
   local zone = GetRealZoneText()
   if not zone or zone == "" or zone == self.db.char.autoFoldZone then return end
   self.db.char.autoFoldZone = zone

   local collapsed = self.db.char.collapsedZones
   for _, section in ipairs(sections) do
      collapsed[section.name] = (not section.isCurrent) or nil
   end
end

----------------------------------------------------------------
-- Distances change as the player moves; refresh periodically while
-- they are shown or used for sorting.
----------------------------------------------------------------

local DISTANCE_INTERVAL = 2

function mod:UpdateDistanceTimer()
   local profile = self.db.profile
   local needed = profile.showDistance or profile.showDirection
      or profile.questSort == "distance" or profile.zoneSort == "distance"
   if needed and not self.distanceTimer then
      self.distanceTimer = self:ScheduleRepeatingTimer("OnDistanceTimer", DISTANCE_INTERVAL)
   elseif not needed and self.distanceTimer then
      self:CancelTimer(self.distanceTimer)
      self.distanceTimer = nil
   end
end

function mod:OnDistanceTimer()
   if self.frame and self.frame:IsShown() and not self.db.char.minimized then
      self:RequestUpdate()
   end
end

----------------------------------------------------------------
-- Blizzard objective tracker visibility
-- Hides the whole ObjectiveTrackerFrame (same approach as Questie on Forever).
-- Protected state changes wait for combat to end.
----------------------------------------------------------------

function mod:SetBlizzardTrackerHidden(hide)
   local tracker = ObjectiveTrackerFrame
   if not tracker then return end

   self.blizzardHidden = hide
   if not self.blizzardHooked then
      self.blizzardHooked = true
      tracker:HookScript("OnShow", function()
         if mod.blizzardHidden then
            mod:SetBlizzardTrackerHidden(true)
         end
      end)
   end

   if InCombatLockdown() and (not hide or tracker:IsProtected()) then
      self.pendingBlizzardVisibility = hide
      return
   end
   self.pendingBlizzardVisibility = nil

   if hide then
      tracker:Hide()
   elseif tracker.Update then
      -- Let Blizzard decide whether it should be visible.
      tracker:Update()
   end
end

----------------------------------------------------------------
-- Slash command
----------------------------------------------------------------

function mod:OpenConfig()
   self:InterfaceOptionsFrame_OpenToCategory(self.optionsEnd)
   self:InterfaceOptionsFrame_OpenToCategory(self.optionsMain)
end

function mod:PrintHelp()
   self:info(L["Available commands:"])
   self:info(L["/mqt toggle  - show/hide the tracker"])
   self:info(L["/mqt lock  - lock/unlock the tracker position"])
   self:info(L["/mqt reset  - reset the tracker position"])
   self:info(L["/mqt config  - open settings"])
end

function mod:ChatCommand(input)
   local cmd = strtrim(input or ""):lower()
   if cmd == "toggle" then
      self:ToggleMinimized()
   elseif cmd == "lock" then
      self.db.profile.locked = not self.db.profile.locked
      self:ApplyLayout()
      self:NotifyOptionsChanged()
   elseif cmd == "reset" then
      self.db.profile.point = CopyTable(self.defaults.profile.point)
      self:ApplyLayout()
   elseif cmd == "config" then
      self:OpenConfig()
   else
      self:PrintHelp()
   end
end
