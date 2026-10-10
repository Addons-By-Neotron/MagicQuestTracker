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
      hideInCombat = "never",        -- never | instances | always
      hideInInstances = "never",     -- never | noQuests | always
      showAllQuests = true,          -- false = only quests on the built-in watch list
      currentZoneFirst = true,
      onlyCurrentZone = false,
      autoFoldZones = false,
      focusedSection = "none",       -- section pinned on top: none | focused | tracked
      zoneSort = "level",            -- level | name | distance
      questSort = "level",           -- level | name | distance
      showDistance = false,
      distanceUnits = "yards",       -- yards | meters | imperial (yd/mi) | metric (m/km)
      showDirection = false,
      arrowSize = 16,
      arrowMaxDistance = 1000,       -- yards, 0 = no limit
      waypointMode = "both",         -- ctrl-click: tomtom | blizzard | both
      blizzardFocus = true,          -- focus (super track) quests; off avoids taint errors
      showLevel = true,
      showQuestTags = true,
      markForeverQuests = true,
      markWatchedQuests = true,      -- check mark on quests on the built-in watch list
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
   "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
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
   self:RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
      mod:UpdateCombatVisibility()
      mod:RequestUpdate()
   end)
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
   self:UpdateCombatVisibility()
   self:ApplyLayout()
   self:SetBlizzardTrackerHidden(self.db.profile.hideBlizzardTracker)
   self:RequestUpdate()
end

function mod:PLAYER_ENTERING_WORLD()
   -- Blizzard's tracker initializes on PLAYER_ENTERING_WORLD; re-apply afterwards.
   self:SetBlizzardTrackerHidden(self.db.profile.hideBlizzardTracker)
   self:UpdateCombatVisibility()
   self:RequestUpdate()
end

function mod:PLAYER_REGEN_DISABLED()
   -- Still allowed to move secure frames here; place item buttons now if
   -- a render happened just before combat started.
   if self.itemLayoutPending then
      self:LayoutItemButtons()
   end
   if self:ShouldHideInCombat() and self.frame then
      self.combatHidden = true
      self.frame:Hide()
   end
end

----------------------------------------------------------------
-- Hide in combat. The tracker frame is hidden on PLAYER_REGEN_DISABLED;
-- the secure item buttons can't be hidden in combat by addon code, so their
-- holder gets a [combat] visibility state driver, set up out of combat.
----------------------------------------------------------------

local function InInstance()
   local inInstance, instanceType = IsInInstance()
   return inInstance and instanceType ~= "none" or false
end

--- True when the tracker should be hidden in the current instance: always,
--- or when none of the quests are for this instance (sections from CollectQuests).
function mod:ShouldHideInInstance(sections)
   local mode = self.db.profile.hideInInstances
   if mode == "never" or not InInstance() then return false end
   if mode == "noQuests" then
      for _, section in ipairs(sections) do
         if section.isCurrent or section.hasLocalQuests then return false end
      end
   end
   return true
end

function mod:ShouldHideInCombat()
   local mode = self.db.profile.hideInCombat
   if mode == "always" then return true end
   if mode == "instances" then
      return InInstance()
   end
   return false
end

function mod:UpdateCombatVisibility()
   if InCombatLockdown() then return end
   self:SetItemButtonsCombatHidden(self:ShouldHideInCombat())
end

function mod:PLAYER_REGEN_ENABLED()
   if self.combatHidden then
      self.combatHidden = nil
      self.layoutDeferred = true  -- render (and show) below
   end
   self:ApplyPendingSuperTrack()
   self:UpdateBlizzardTrackerMouse()
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
      if not section.isPinned then
         collapsed[section.name] = not isLocal or nil
      end
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
-- Hide(), Show() or Update() on ObjectiveTrackerFrame from addon code runs
-- its managed-frame and Edit Mode layout code tainted, which later breaks
-- secret aura reads in the tracker's own updates (Forever and retail). So
-- the tracker is made invisible with alpha only: no Blizzard script runs,
-- and SetAlpha is allowed in combat. A secure hook keeps it at 0 if
-- Blizzard restores the alpha.
----------------------------------------------------------------

-- Frames whose mouse we turned off, so un-hiding can turn it back on.
local mouseDisabled = setmetatable({}, { __mode = "k" })

-- An invisible tracker would still take hovers and clicks (its quest item
-- buttons are secure and would even fire), so its frames stop receiving the
-- mouse. EnableMouse writes no Lua state, so it taints nothing. Protected
-- frames can't be changed in combat; they are caught when combat ends.
local function SetTrackerMouse(enabled, inCombat, ...)
   for i = 1, select("#", ...) do
      local frame = select(i, ...)
      if inCombat and frame:IsProtected() then
         mod.trackerMousePending = true
      else
         if enabled then
            if mouseDisabled[frame] then
               mouseDisabled[frame] = nil
               frame:EnableMouse(true)
            end
         elseif frame:IsMouseEnabled() then
            mouseDisabled[frame] = true
            frame:EnableMouse(false)
         end
      end
      SetTrackerMouse(enabled, inCombat, frame:GetChildren())
   end
end

-- Blocks are (re)filled as quests change and handed to their module's
-- AddBlock during layout: only that block's frames need the mouse turned
-- off, and only when Blizzard actually lays the tracker out.
local hookedModules = {}

local function OnAddBlock(_, block)
   if mod.blizzardHidden then
      SetTrackerMouse(false, InCombatLockdown(), block)
   end
end

local function HookModule(_, module)
   if module and module.AddBlock and not hookedModules[module] then
      hookedModules[module] = true
      hooksecurefunc(module, "AddBlock", OnAddBlock)
   end
end

-- Catches protected frames skipped during combat.
function mod:UpdateBlizzardTrackerMouse()
   local tracker = ObjectiveTrackerFrame
   if tracker and self.trackerMousePending then
      self.trackerMousePending = nil
      SetTrackerMouse(not self.blizzardHidden, false, tracker)
   end
end

function mod:SetBlizzardTrackerHidden(hide)
   local tracker = ObjectiveTrackerFrame
   if not tracker then return end

   -- Never hidden by us: leave it alone.
   if not hide and not self.blizzardHidden then return end

   self.blizzardHidden = hide
   if hide and not self.blizzardHooked then
      self.blizzardHooked = true
      hooksecurefunc(tracker, "SetAlpha", function(frame, alpha)
         if mod.blizzardHidden and alpha ~= 0 then
            frame:SetAlpha(0)
         end
      end)
      for _, module in ipairs(tracker.modules or {}) do
         HookModule(nil, module)
      end
      if tracker.AddModule then
         hooksecurefunc(tracker, "AddModule", HookModule)
      end
   end
   tracker:SetAlpha(hide and 0 or 1)
   SetTrackerMouse(not hide, InCombatLockdown(), tracker)
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
