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
      zoneSort = "level",            -- level | name | log
      questSort = "level",           -- level | name | log
      showLevel = true,
      colorByDifficulty = true,
      showCompletedObjectives = true,
      showRecipes = true,
      showItemButtons = true,        -- reserved: secure quest item buttons (not implemented yet)

      -- Layout
      locked = false,
      width = 260,
      maxHeight = 450,
      scale = 1.0,
      backgroundAlpha = 0.0,
      point = { "TOPRIGHT", "UIParent", "TOPRIGHT", -80, -260 },

      -- Fonts
      fonts = {
         title = FontDefaults(14),
         zone = FontDefaults(13),
         quest = FontDefaults(12),
         objective = FontDefaults(11),
      },
   },
   char = {
      collapsedZones = {},    -- [zoneName] = true
      collapsedRecipes = false,
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
   self:ApplyProfile()
end

function mod:OnDisable()
   self:UnregisterAllEvents()
   self:SetBlizzardTrackerHidden(false)
   if self.frame then self.frame:Hide() end
end

function mod:ApplyProfile()
   self:ApplyLayout()
   self:SetBlizzardTrackerHidden(self.db.profile.hideBlizzardTracker)
   self:RequestUpdate()
end

function mod:PLAYER_ENTERING_WORLD()
   -- Blizzard's tracker initializes on PLAYER_ENTERING_WORLD; re-apply afterwards.
   self:SetBlizzardTrackerHidden(self.db.profile.hideBlizzardTracker)
   self:RequestUpdate()
end

function mod:PLAYER_REGEN_ENABLED()
   if self.pendingBlizzardVisibility ~= nil then
      self:SetBlizzardTrackerHidden(self.pendingBlizzardVisibility)
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
   self:Render(sections, numQuests, numShown, recipes)
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
