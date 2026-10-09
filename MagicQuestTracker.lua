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

-- Bar settings for one header kind of a custom theme.
local function CustomDefaults(texture, a, borderedButton)
   return {
      borderedButton = borderedButton,  -- title only: Blizzard's bordered minimize button
      texture = texture,   -- LibSharedMedia statusbar or Blizzard art (Themes.lua)
      color = { r = 1, g = 1, b = 1, a = a },
      border = "None",     -- LibSharedMedia border
      borderSize = 12,
      borderColor = { r = 0.5, g = 0.5, b = 0.5, a = 1 },
   }
end

local function RGB(r, g, b)
   return { r = r, g = g, b = b }
end

-- New custom themes start out like the Blizzard theme.
mod.themeDefaults = {
   title = CustomDefaults("Blizzard Tracker Title", 1, true),
   section = CustomDefaults("Blizzard Tracker Header", 1),
   zone = CustomDefaults("Solid", 0),  -- alpha 0 and no border = plain text
   -- Tracker background; none, like Blizzard's tracker.
   background = {
      texture = "Solid",   -- LibSharedMedia background
      color = { r = 0, g = 0, b = 0 },
      alpha = 0,           -- when the mouse is not over the tracker
      hoverAlpha = 0,
      border = "None",     -- LibSharedMedia border
      borderSize = 12,
      borderColor = { r = 0.6, g = 0.6, b = 0.6 },  -- opacity follows the background
   },
   -- Content spacing (pixels)
   layout = {
      padding = 0,              -- between the tracker edges (border) and the content
      sectionSpacing = 24,      -- above each section header (Quests, World Quests, ...)
      zoneSpacing = 7,          -- above each zone header
      zoneHeaderSpacing = 7,    -- between a zone header and its first quest
      questSpacing = 6,         -- above each quest title
      objectiveSpacing = 1,     -- between objective lines
   },
   fonts = {
      title = FontDefaults(14),
      module = FontDefaults(13),
      zone = FontDefaults(12),
      quest = FontDefaults(12),
      objective = FontDefaults(11),
   },
   -- Text colors (Blizzard's objective tracker colors)
   colors = {
      title = RGB(1, 0.82, 0),
      section = RGB(1, 0.82, 0),
      zone = RGB(1, 0.82, 0),
      currentZone = RGB(1, 1, 1),
      quest = RGB(0.75, 0.61, 0),        -- quest titles when not colored by difficulty
      objective = RGB(0.8, 0.8, 0.8),
      complete = RGB(0.6, 0.6, 0.6),     -- completed objectives
      failed = RGB(1, 0.1, 0.1),
      timeLeft = RGB(0.75, 0.1, 0.1),
      questTag = RGB(1, 0.5, 0.25),      -- "(Elite, Daily)" after the title
      distance = RGB(0.6, 0.6, 0.6),
      arrow = RGB(1, 0.82, 0),
      scrollbar = RGB(1, 0.82, 0),
      -- Quest titles by difficulty (QuestDifficultyColors keys)
      trivial = RGB(0.5, 0.5, 0.5),
      standard = RGB(0.25, 0.75, 0.25),
      difficult = RGB(1, 0.82, 0),
      verydifficult = RGB(1, 0.5, 0.25),
      impossible = RGB(1, 0.1, 0.1),
   },
}

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

      -- Layout (position is per Edit Mode layout)
      layouts = {},           -- [layoutName] = { point, x, y, width, maxHeight, scale }
      lastLayout = nil,       -- layout last moved in, seeds new layouts

      -- Theme: "blizzard" or the name of a custom theme in global.themes
      theme = "blizzard",
   },
   global = {
      themes = {},  -- [name] = { title, section, zone, background, layout, fonts }, shared by all profiles
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
   self:MigrateCustomTheme()
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
   local recipes = self.db.profile.showRecipes and self:CollectRecipes() or nil
   local tasks = self:CollectTasks()
   self:AutoFoldZones(sections, tasks)

   -- The rendered lines reference the data they show, so the previous data
   -- is only recycled once a render has replaced it. A deferred render (item
   -- buttons in combat) keeps the old data on screen; recycle the new instead.
   local data = self.dataPool or {}
   self.dataPool = data
   if self:Render(sections, numQuests, numShown, recipes, tasks) then
      self.deepDel(data.sections)
      self.deepDel(data.recipes)
      self.deepDel(data.tasks)
      data.sections, data.recipes, data.tasks = sections, recipes, tasks
   else
      self.deepDel(sections)
      self.deepDel(recipes)
      self.deepDel(tasks)
   end
end

----------------------------------------------------------------
-- Auto-fold: when all objectives are shown, fold zones other than the
-- current one and unfold the sections with objectives here, but only when
-- the player changes zone, so folding done by hand stays until the next
-- zone change.
----------------------------------------------------------------

local function HasLocalTask(list)
   for _, task in ipairs(list) do
      if task.inCurrentZone then return true end
   end
   return false
end

function mod:AutoFoldZones(sections, tasks)
   local profile = self.db.profile
   if not profile.autoFoldZones or profile.onlyCurrentZone then return end
   local zone = GetRealZoneText()
   if not zone or zone == "" or zone == self.db.char.autoFoldZone then return end
   self.db.char.autoFoldZone = zone

   local collapsed = self.db.char.collapsedZones
   local hasLocal = false
   for _, section in ipairs(sections) do
      -- Keep zones open that have quests here, even if filed elsewhere.
      local isLocal = section.isCurrent or section.hasLocalQuests
      collapsed[section.name] = not isLocal or nil
      hasLocal = hasLocal or isLocal
   end

   local collapsedSections = self.db.char.collapsedSections
   if hasLocal then collapsedSections.quests = nil end
   if tasks then
      if HasLocalTask(tasks.worldQuests) then collapsedSections.worldQuests = nil end
      if HasLocalTask(tasks.bonus) then collapsedSections.bonus = nil end
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
   self:info(L["/mqt config  - open settings"])
end

function mod:ChatCommand(input)
   local cmd = strtrim(input or ""):lower()
   if cmd == "toggle" then
      self:ToggleMinimized()
   elseif cmd == "config" then
      self:OpenConfig()
   else
      self:PrintHelp()
   end
end
