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

local IS_FOREVER = (select(4, GetBuildInfo()) or 0) >= 16000 and (select(4, GetBuildInfo()) or 0) < 17000

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
   -- Progress bar objectives (Blizzard's tracker progress bar look)
   progressBar = {
      texture = "Blizzard",   -- LibSharedMedia statusbar
      color = { r = 0.26, g = 0.42, b = 1, a = 1 },
      background = { r = 0, g = 0, b = 0, a = 0.5 },
      textColor = { r = 1, g = 1, b = 1, a = 1 },
      markerColor = { r = 1, g = 1, b = 1, a = 0.45 },  -- lines at 25/50/75%
   },
   -- Content spacing (pixels)
   layout = {
      padding = 0,              -- between the tracker edges (border) and the content
      sectionSpacing = 24,      -- above each section header (Quests, World Quests, ...), but not the first
      sectionHeaderSpacing = 7, -- between a section header and the first line below it (usually a zone header)
      zoneSpacing = 7,          -- above each zone header, but not the first one below a section header
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
      completeQuest = RGB(0.25, 0.75, 0.25),  -- titles of completed quests, when enabled
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
      showAllQuests = false,         -- false = only quests on the built-in watch list (see mod:GetView)
      currentZoneFirst = true,
      onlyCurrentZone = false,
      hideRedQuests = false,         -- difficulty filters (the focused quest is always shown)
      hideGrayQuests = false,
      autoFoldZones = false,
      focusedSection = "none",       -- section pinned on top: none | focused | tracked
      completedSort = "normal",      -- completed quests within a section: normal | first | last
      completedSection = "none",     -- completed quests in their own section: none | all | current
      focusedPosition = "top",       -- the focused / tracked section: top | bottom (of the zones)
      -- completedPosition: top | bottom; unset follows completedSort ("last" = bottom)
      zoneSort = "distance",         -- level | name | distance
      questSort = "distance",        -- level | name | distance
      showDistance = false,
      distanceUnits = "yards",       -- yards | meters | imperial (yd/mi) | metric (m/km)
      showDirection = false,
      arrowSize = 16,
      arrowMaxDistance = 1000,       -- yards, 0 = no limit
      waypointMode = "both",         -- ctrl-click: tomtom | blizzard | both
      poiTomTom = true,              -- clicking a quest's POI button also sets the TomTom waypoint
      blizzardFocus = true,          -- focus (super track) quests; off avoids taint errors
      mapClicks = true,              -- left-click opens the quest on the map (taints the map)
      showLevel = IS_FOREVER,        -- like the built-in tracker: Forever shows levels, retail does not
      showQuestTags = false,
      markForeverQuests = false,
      markWatchedQuests = false,     -- check mark on quests on the built-in watch list
      colorByDifficulty = false,
      simpleSectionHeaders = true,  -- counts in section headers (Quests, World Quests, ...): true none, "count" no maximum, false all
      simpleZoneHeaders = false,     -- no quest counts in zone headers
      hideZoneHeaders = true,        -- no zone headers: true = always, "single" = when only one is shown, false = never
      zoneFold = "triangle",         -- fold icon of zone headers: none | blizzard | triangle | chevron | box | plusminus
      zoneFoldPosition = "left",     -- left | after (right of the title) | right
      sectionFold = "blizzard",      -- fold icon of section headers (Quests, World Quests, ...)
      sectionFoldPosition = "right",
      colorCompleteQuests = false,   -- completed quest titles use the completeQuest color
      showCompletedObjectives = true,
      timerBars = false,             -- time limits as a bar (else a text line)
      showRecipes = true,
      showAchievements = true,
      showDungeonBosses = false,     -- Forever: dungeon section with a line per boss
      showWorldQuests = true,
      showBonusObjectives = true,
      showItemButtons = true,
      showPOIButtons = true,
      showFindGroupButton = true,
      showPlayButton = false, -- Spoken Quests voiceover play button (Forever)
      buttonsOnHover = false, -- POI, find group and play buttons only while the mouse is over the tracker      questBar = false,       -- separate quest item bar (QuestBar.lua)
      questBarButtons = 5,
      questBarSpacing = 4,
      questBarVertical = false,
      questBarMaxDistance = 500, -- yards; items of quests farther away are hidden (0 = any distance)
      questBarAlign = "center", -- buttons when fewer than slots: start (left / top) | center | end
      questBarLayouts = {},   -- [layoutName] = { point, x, y, scale }
      questBarLastLayout = nil,

      -- Layout (position is per Edit Mode layout)
      layouts = {},           -- [layoutName] = { point, x, y, width, maxHeight, scale }
      lastLayout = nil,       -- layout last moved in, seeds new layouts

      -- Theme: "blizzard" or the name of a custom theme in global.themes
      theme = "blizzard",
   },
   global = {
      themes = {},  -- [name] = { title, section, zone, background, layout, fonts }, shared by all profiles
      questTimerDurations = {},  -- [questID] = seconds; Forever's quest timers only report the time left
   },
   char = {
      collapsedZones = {},    -- [zoneName] = true
      autoFoldZone = nil,     -- zone the auto-fold was last applied for
      collapsedSections = {}, -- [quests|worldQuests|bonus|recipes] = true
      minimized = false,
      fullLogWarned = nil,    -- quest ID list the "log almost full" warning was shown for
      dungeonKills = {},      -- [instanceID] = { name, time, bosses = { [bossName] = true } } (Forever)
   },
}

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

-- The defaults above follow the built-in tracker. These are the values they
-- replaced (defaults version 1); profiles that existed before keep them, so an
-- update doesn't change how the tracker looks for anyone already using it.
local DEFAULTS_VERSION = 1
local OLD_DEFAULTS = {
   showAllQuests = true,
   focusedSection = "focused",
   completedSort = "first",
   zoneSort = "level",
   questSort = "level",
   showLevel = true,
   showQuestTags = true,
   colorByDifficulty = true,
   simpleSectionHeaders = false,
   hideZoneHeaders = false,
   markForeverQuests = true,
   markWatchedQuests = true,
}

-- Returns true for a profile that was never used (a fresh install).
function mod:MigrateDefaults()
   local profile = self.db.profile
   if profile.defaultsVersion then return false end
   local saved = self.db.sv.profiles[self.db.keys.profile]
   local fresh = not (saved and next(saved) ~= nil)
   if not fresh then
      for key, value in pairs(OLD_DEFAULTS) do
         if saved[key] == nil then saved[key] = value end
      end
   end
   profile.defaultsVersion = DEFAULTS_VERSION
   return fresh
end

function mod:OnInitialize()
   self.db = LibStub("AceDB-3.0"):New("MagicQuestTrackerDB", self.defaults, "Default")
   self.db.RegisterCallback(self, "OnProfileChanged", "ApplyProfile")
   self.db.RegisterCallback(self, "OnProfileCopied", "ApplyProfile")
   self.db.RegisterCallback(self, "OnProfileReset", "ApplyProfile")
   -- A fresh install gets the welcome prompt; anyone else who hasn't seen the
   -- "what's new" window yet gets that (see Wizard.lua).
   local fresh = self:MigrateDefaults()
   self.freshInstall = fresh and self.db.global.whatsNewSeen == nil
   self:InitGeometryFlag()

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

-- Not on every client (Forever has no achievements).
local ACHIEVEMENT_EVENTS = {
   "CONTENT_TRACKING_UPDATE", "TRACKED_ACHIEVEMENT_LIST_CHANGED", "ACHIEVEMENT_EARNED",
}

local function IsEventValid(event)
   return not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(event)
end

local SCENARIO_EVENTS = {
   "SCENARIO_UPDATE", "SCENARIO_COMPLETED", "SCENARIO_CRITERIA_UPDATE",
   "SCENARIO_CRITERIA_SHOW_STATE_UPDATE", "SCENARIO_BONUS_VISIBILITY_UPDATE",
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
      mod:UpdateScenarioVisibility()
      mod:RequestUpdate()
   end)
   -- Scenarios (delves, ...): the Scenario section, or Blizzard's scenario
   -- block for the ones MQT doesn't show.
   for _, event in ipairs(SCENARIO_EVENTS) do
      if IsEventValid(event) then
         self:RegisterEvent(event, "UpdateScenarioVisibility")
      end
   end
   for _, event in ipairs(ACHIEVEMENT_EVENTS) do
      if IsEventValid(event) then
         self:RegisterEvent(event, "RequestUpdate")
      end
   end
   if IsEventValid("TRACKED_ACHIEVEMENT_UPDATE") then
      self:RegisterEvent("TRACKED_ACHIEVEMENT_UPDATE")
   end
   -- Forever dungeon bosses: kills aren't in the lock info, record them.
   if IS_FOREVER then
      self:RegisterEvent("ENCOUNTER_END", function(_, _, encounterName, _, _, success)
         if success == 1 then mod:RecordBossKill(encounterName) end
      end)
      self:RegisterEvent("BOSS_KILL", function(_, _, encounterName)
         mod:RecordBossKill(encounterName)
      end)
      self:RegisterEvent("UPDATE_INSTANCE_INFO", "RequestUpdate")
      self:RegisterEvent("CHAT_MSG_SYSTEM", function(_, msg) mod:CheckInstanceReset(msg) end)
   end
   self:ApplyProfile()
end

-- Timers of achievements without criteria are only known from this event
-- (as in Blizzard's tracker); timed achievements with criteria have them
-- in the criteria info. Kept for the session, like Blizzard does, so a
-- timer that ran out shows the achievement as failed.
mod.achievementTimers = {}

function mod:TRACKED_ACHIEVEMENT_UPDATE(_, achievementID, criteriaID, elapsed, duration)
   if criteriaID and elapsed and duration and GetAchievementNumCriteria(achievementID) == 0 then
      local timer = self.achievementTimers[criteriaID] or {}
      timer.achievementID = achievementID
      timer.timerEnd = GetTime() - elapsed + duration
      timer.duration = duration
      self.achievementTimers[criteriaID] = timer
   end
   self:RequestUpdate()
end

function mod:OnDisable()
   self:UnregisterAllEvents()
   self:SetBlizzardTrackerHidden(false)
   self.itemEntries = nil
   self:HideItemButtons()
   if self.frame then self.frame:Hide() end
end

-- Profiles without saved geometry are placed over Blizzard's tracker once
-- its position is known (see MatchBlizzardOnFirstLoad).
function mod:InitGeometryFlag()
   if self.db.profile.geometryMatched == nil then
      self.db.profile.geometryMatched = self:HasSavedGeometry()
   end
end

function mod:ApplyProfile()
   self:MigrateDefaults()
   -- A profile created while playing gets the same treatment as a new install.
   self:InitGeometryFlag()
   self:MatchBlizzardOnFirstLoad()
   -- "log" sort order was removed; fall back to level.
   local profile = self.db.profile
   if profile.zoneSort ~= "name" and profile.zoneSort ~= "distance" then profile.zoneSort = "level" end
   if profile.questSort ~= "name" and profile.questSort ~= "distance" then profile.questSort = "level" end
   self:MigrateCustomTheme()
   self:UpdateDistanceTimer()
   self:UpdateCombatVisibility()
   self:ApplyLayout()
   self:ApplyQuestBar()
   self:SetBlizzardTrackerHidden(self.db.profile.hideBlizzardTracker)
   self:RequestUpdate()
end

function mod:PLAYER_ENTERING_WORLD()
   self:MatchBlizzardOnFirstLoad()
   if not self.startupDialogShown then
      C_Timer.After(3, function() self:ShowStartupDialogs() end)
   end
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
function mod:ShouldHideInInstance(sections, scenario)
   -- The Scenario section replaces Blizzard's scenario block (delves, ...).
   if scenario then return false end
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
   self:QuestBarCombatEnded()
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

-- Warns once per session when only this many quest slots are left, unless
-- the quest log is the same as when the warning was last shown.
local LOG_WARN_SLOTS = 2

-- force: show the warning whatever the log holds (for testing).
function mod:CheckQuestLogFull(force)
   if not force and self.logFullChecked then return end
   if not C_QuestLog.GetMaxNumQuestsCanAccept then return end
   local _, count = C_QuestLog.GetNumQuestLogEntries()
   local max = C_QuestLog.GetMaxNumQuestsCanAccept()
   if not count or not max or max <= 0 then return end
   if force then count = max - LOG_WARN_SLOTS
   elseif count < max - LOG_WARN_SLOTS then return end
   if not force then self.logFullChecked = true end
   local ids = {}
   for i = 1, C_QuestLog.GetNumQuestLogEntries() do
      local info = C_QuestLog.GetInfo(i)
      if info and not info.isHeader and not info.isHidden then ids[#ids + 1] = info.questID end
   end
   table.sort(ids)
   local signature = table.concat(ids, ",")
   if not force then
      if self.db.char.fullLogWarned == signature then return end
      self.db.char.fullLogWarned = signature
   end
   local text = format(L["Your quest log is almost full (%d/%d)."], count, max)
   self:Print("|cffffd100" .. text .. "|r")
   self:Print(L["With a full quest log you can't accept escort or shared quests."])
   if UIErrorsFrame then UIErrorsFrame:AddMessage(text, 1, 0.82, 0) end
   local sound = SOUNDKIT and (SOUNDKIT.ALARM_CLOCK_WARNING_2 or SOUNDKIT.RAID_WARNING)
   if sound then PlaySound(sound) end
end

function mod:RunUpdate()
   self.updateTimer = nil
   if not self.frame then return end
   self:CheckQuestLogFull()
   local sections, numQuests, numShown = self:CollectQuests()
   self:UpdateQuestBar()
   local recipes = self.db.profile.showRecipes and self:CollectRecipes() or nil
   local tasks = self:CollectTasks()
   local scenario = self:CollectScenario() or self:CollectDungeon()
   local achievements = self.db.profile.showAchievements and self:CollectAchievements() or nil
   self:AutoFoldZones(sections, tasks)

   -- The rendered lines reference the data they show, so the previous data
   -- is only recycled once a render has replaced it. A deferred render (item
   -- buttons in combat) keeps the old data on screen; recycle the new instead.
   local data = self.dataPool or {}
   self.dataPool = data
   if self:Render(sections, numQuests, numShown, recipes, tasks, scenario, achievements) then
      self.deepDel(data.sections)
      self.deepDel(data.recipes)
      self.deepDel(data.tasks)
      self.deepDel(data.scenario)
      self.deepDel(data.achievements)
      data.sections, data.recipes, data.tasks = sections, recipes, tasks
      data.scenario, data.achievements = scenario, achievements
   else
      self.deepDel(sections)
      self.deepDel(recipes)
      self.deepDel(tasks)
      self.deepDel(scenario)
      self.deepDel(achievements)
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
      if not section.isSpecial then
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

function mod:IsInScenario()
   return C_Scenario and C_Scenario.IsInScenario and C_Scenario.IsInScenario() or false
end

--- True in scenarios MQT doesn't show (Mythic+, Proving Grounds): Blizzard's
--- tracker stays visible for its scenario module only, and MQT hides fully.
--- Its other modules are hidden the same way as the whole tracker otherwise.
function mod:IsBlizzardScenario()
   if not self:IsInScenario() then return false end
   local scenarioType = select(10, C_Scenario.GetInfo())
   return scenarioType ~= nil and (scenarioType == LE_SCENARIO_TYPE_CHALLENGE_MODE
      or scenarioType == LE_SCENARIO_TYPE_PROVING_GROUNDS)
end

local function IsHiddenModule(module)
   if not mod.blizzardHidden then return false end
   return not mod.scenarioShown or module ~= ScenarioObjectiveTracker
end

-- Applies the hidden / scenario-only state to the tracker and its modules.
local function ApplyTrackerVisibility(tracker)
   local inCombat = InCombatLockdown()
   local scenarioOnly = mod.blizzardHidden and mod.scenarioShown
   tracker:SetAlpha((mod.blizzardHidden and not scenarioOnly) and 0 or 1)
   for _, module in ipairs(tracker.modules or {}) do
      module:SetAlpha((scenarioOnly and IsHiddenModule(module)) and 0 or 1)
   end
   -- Mouse back on wherever we turned it off, then off where hidden.
   SetTrackerMouse(true, inCombat, tracker)
   if not mod.blizzardHidden then return end
   if not scenarioOnly then
      SetTrackerMouse(false, inCombat, tracker)
      return
   end
   for _, module in ipairs(tracker.modules or {}) do
      if IsHiddenModule(module) then
         SetTrackerMouse(false, inCombat, module)
      end
   end
end

-- Blocks are (re)filled as quests change and handed to their module's
-- AddBlock during layout: only that block's frames need the mouse turned
-- off, and only when Blizzard actually lays the tracker out.
local hookedModules = {}

local function OnAddBlock(module, block)
   if IsHiddenModule(module) then
      SetTrackerMouse(false, InCombatLockdown(), block)
   end
end

-- Modules come and go (the scenario module is added when one starts).
local function HookModule(_, module)
   if not module then return end
   if module.AddBlock and not hookedModules[module] then
      hookedModules[module] = true
      hooksecurefunc(module, "AddBlock", OnAddBlock)
   end
   if mod.blizzardHidden and mod.scenarioShown then
      module:SetAlpha(IsHiddenModule(module) and 0 or 1)
   end
end

-- Blizzard's quest timer box (Blizzard_QuestTimer, Forever / Classic) lists
-- the same timers MQT shows. Its parent differs by build (the tracker or
-- UIParent), so it is hidden on its own, the same alpha-only way. Its timer
-- buttons are pooled and appear when a timer starts, so their mouse is turned
-- off again after each update.
local function ApplyQuestTimerVisibility()
   local frame = QuestTimerFrame
   if not frame then return end
   if not mod.questTimerHooked then
      mod.questTimerHooked = true
      hooksecurefunc(frame, "SetAlpha", function(f, alpha)
         if mod.blizzardHidden and alpha ~= 0 then f:SetAlpha(0) end
      end)
      if frame.UpdateQuestTimers then
         hooksecurefunc(frame, "UpdateQuestTimers", function(f)
            if mod.blizzardHidden then SetTrackerMouse(false, InCombatLockdown(), f) end
         end)
      end
   end
   local inCombat = InCombatLockdown()
   frame:SetAlpha(mod.blizzardHidden and 0 or 1)
   SetTrackerMouse(true, inCombat, frame)
   if mod.blizzardHidden then
      SetTrackerMouse(false, inCombat, frame)
   end
end

-- Catches protected frames skipped during combat.
function mod:UpdateBlizzardTrackerMouse()
   local tracker = ObjectiveTrackerFrame
   if tracker and self.trackerMousePending then
      self.trackerMousePending = nil
      ApplyTrackerVisibility(tracker)
      ApplyQuestTimerVisibility()
   end
end

-- Scenario progress updates the Scenario section; entering or leaving one
-- MQT doesn't show switches between hiding the whole Blizzard tracker and
-- showing only its scenario module.
function mod:UpdateScenarioVisibility()
   self:RequestUpdate()
   local shown = self:IsBlizzardScenario()
   if shown == self.scenarioShown then return end
   self.scenarioShown = shown
   local tracker = ObjectiveTrackerFrame
   if tracker and self.blizzardHidden then
      ApplyTrackerVisibility(tracker)
   end
end

function mod:SetBlizzardTrackerHidden(hide)
   local tracker = ObjectiveTrackerFrame
   if not tracker then return end

   -- Never hidden by us: leave it alone.
   if not hide and not self.blizzardHidden then return end

   self.blizzardHidden = hide
   self.scenarioShown = self:IsBlizzardScenario()
   if hide and not self.blizzardHooked then
      self.blizzardHooked = true
      hooksecurefunc(tracker, "SetAlpha", function(frame, alpha)
         if mod.blizzardHidden and not mod.scenarioShown and alpha ~= 0 then
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
   ApplyTrackerVisibility(tracker)
   ApplyQuestTimerVisibility()
end

----------------------------------------------------------------
-- Slash command
----------------------------------------------------------------

function mod:CloseConfig()
   if SettingsPanel and SettingsPanel:IsShown() then
      HideUIPanel(SettingsPanel)
   end
   if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then
      InterfaceOptionsFrame:Hide()
   end
end

function mod:OpenConfig()
   self:InterfaceOptionsFrame_OpenToCategory(self.optionsEnd)
   self:InterfaceOptionsFrame_OpenToCategory(self.optionsMain)
end

function mod:PrintHelp()
   self:info(L["Available commands:"])
   self:info(L["/mqt toggle  - show/hide the tracker"])
   self:info(L["/mqt config  - open settings"])
   self:info(L["/mqt wizard  - run the setup wizard"])
   self:info(L["/mqt new     - show what's new"])
end

function mod:ChatCommand(input)
   local cmd = strtrim(input or ""):lower()
   if cmd == "toggle" then
      self:ToggleMinimized()
   elseif cmd == "config" then
      self:OpenConfig()
   elseif cmd == "wizard" or cmd == "setup" then
      self:ShowWizard()
   elseif cmd == "new" or cmd == "whatsnew" then
      self:ShowWhatsNew(true)
   elseif cmd == "newdebug" or cmd:match("^newdebug %d+$") then
      -- Every entry, including those for other game versions, or only the
      -- ones after the given version (what an update from it shows). For testing.
      self:ShowWhatsNew(tonumber(cmd:match("%d+")) or true, true)
   elseif cmd == "welcome" then
      -- The popup new installs get (for testing).
      self:ShowWelcome()
   elseif cmd == "logfull" then
      -- The quest log warning, shown whatever the log holds (for testing).
      self:CheckQuestLogFull(true)
   elseif cmd == "bardebug" then
      self:DumpQuestBar()
   elseif cmd == "dungeondebug" then
      self:DumpDungeon()
   elseif cmd == "zonedebug" then
      self:DumpZones()
   elseif cmd == "testbar" then
      -- The quest item bar filled with bag items (for testing without quests).
      self:ToggleQuestBarTest()
   else
      self:PrintHelp()
   end
end
