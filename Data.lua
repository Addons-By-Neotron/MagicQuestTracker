--[[
**********************************************************************
MagicQuestTracker - Quest log and tracked recipe collection, filtering and sorting.
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

local C_QuestLog = C_QuestLog
local new, del = mod.new, mod.del

-- WoW Forever (Interface 16xxx) adds quests on top of original Classic.
-- The highest quest ID in original Classic is 9665 (per ForeverQuestTint's
-- vanilla quest list); anything above it is new to Forever.
local IS_FOREVER = (select(4, GetBuildInfo()) or 0) >= 16000 and (select(4, GetBuildInfo()) or 0) < 17000
local MAX_VANILLA_QUEST_ID = 9665
mod.IS_FOREVER = IS_FOREVER
local C_Map = C_Map
local tinsert, tremove, sort = table.insert, table.remove, table.sort

----------------------------------------------------------------
-- Current zone detection
-- Quest log headers are zone names for most quests, so the current
-- zone is matched against the zone text and the containing zone map
-- (climbing out of micro maps, but not out of instances).
----------------------------------------------------------------

-- Reused between calls; only valid until the next call.
local zoneNames = {}
local function add(name)
   if name and name ~= "" then
      zoneNames[name] = true
   end
end

local function GetCurrentZoneNames()
   wipe(zoneNames)
   add(GetRealZoneText())
   add(GetZoneText())

   local mapID = C_Map.GetBestMapForUnit("player")
   if IsInInstance() then
      -- Dungeon/raid maps have the outdoor zone as parent; don't climb into it.
      add((GetInstanceInfo()))
      local info = mapID and C_Map.GetMapInfo(mapID)
      add(info and info.name)
      return zoneNames
   end
   local zoneType = Enum.UIMapType and Enum.UIMapType.Zone or 3
   while mapID and mapID > 0 do
      local info = C_Map.GetMapInfo(mapID)
      if not info then break end
      add(info.name)
      if info.mapType <= zoneType then break end
      mapID = info.parentMapID
   end
   return zoneNames
end
mod.GetCurrentZoneNames = GetCurrentZoneNames

-- 2 = header is the current zone, 1 = header is a sub-area of it
-- (e.g. "Excavation Site: Wetlands" while in Wetlands), 0 = elsewhere.
-- CollectQuests raises 0 to 0.5 for zones that have quests here.
local function GetZoneRank(header, zoneNames)
   if zoneNames[header] then
      return 2
   end
   local parentZone = header:match(":%s*(.-)%s*$")
   if parentZone and zoneNames[parentZone] then
      return 1
   end
   return 0
end

----------------------------------------------------------------
-- Quests
----------------------------------------------------------------

local function ShouldTrackQuest(info)
   if info.isHidden or info.isTask then
      return false
   end
   if info.isBounty and not C_QuestLog.IsComplete(info.questID) then
      return false
   end
   return true
end

local function BuildObjectives(questID)
   local objectives = new()
   local list = C_QuestLog.GetQuestObjectives(questID)
   if not list then return objectives end
   for _, obj in ipairs(list) do
      local text = obj.text
      local percent
      if obj.type == "progressbar" and GetQuestProgressBarPercent then
         percent = GetQuestProgressBarPercent(questID) or 0
         -- The text usually ends in the percentage too; the bar shows it.
         text = text and text:gsub("%s*%(%d+%%%)%s*$", "")
      end
      if (text and text ~= "") or percent then
         local objective = new()
         objective.text = text
         objective.finished = obj.finished
         objective.percent = percent
         tinsert(objectives, objective)
      end
   end
   return objectives
end

-- Straight-line distance in yards to the quest's map POI (objective area,
-- or turn-in when complete). nil when the quest has no POI on this continent.
local function GetQuestDistance(questID)
   if not C_QuestLog.GetDistanceSqToQuest then return nil end
   local distanceSq, onContinent = C_QuestLog.GetDistanceSqToQuest(questID)
   if onContinent and distanceSq and distanceSq > 0 then
      return math.sqrt(distanceSq)
   end
end

local function BuildQuest(info)
   local questID = info.questID
   local logIndex = info.questLogIndex
   local quest = new()
   quest.questID = questID
   quest.logIndex = logIndex
   quest.title = info.title
   quest.level = info.level
   quest.difficultyLevel = (info.difficultyLevel and info.difficultyLevel > 0) and info.difficultyLevel or info.level
   quest.suggestedGroup = info.suggestedGroup
   quest.frequency = info.frequency
   quest.isOnMap = info.isOnMap
   quest.isAutoComplete = info.isAutoComplete
   quest.isComplete = C_QuestLog.IsComplete(questID)
   quest.isFailed = C_QuestLog.IsFailed(questID)
   quest.isWatched = C_QuestLog.GetQuestWatchType(questID) ~= nil
   quest.isSuperTracked = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID() == questID
   quest.distance = GetQuestDistance(questID)
   quest.isForeverQuest = IS_FOREVER and questID > MAX_VANILLA_QUEST_ID
   quest.objectives = BuildObjectives(questID)
   -- Time limit (escort and other timed quests): absolute GetTime() it runs out.
   local timeTotal, timeElapsed = C_QuestLog.GetTimeAllowed and C_QuestLog.GetTimeAllowed(questID)
   if timeTotal and timeElapsed and timeElapsed < timeTotal and not quest.isFailed then
      quest.timerEnd = GetTime() - timeElapsed + timeTotal
   end
   -- Quest tag: tag ID 1 is "Elite" in classic content ("Group" in the retail enum).
   local tagInfo = C_QuestLog.GetQuestTagInfo and C_QuestLog.GetQuestTagInfo(questID)
   if tagInfo then
      quest.tagID = tagInfo.tagID
      quest.tagName = tagInfo.tagName
      quest.isElite = tagInfo.isElite or tagInfo.tagID == ((Enum.QuestTag and Enum.QuestTag.Group) or 1)
   end
   if logIndex and quest.isComplete and GetQuestLogCompletionText then
      quest.completionText = GetQuestLogCompletionText(logIndex)
   end
   -- Usable quest item (shown as a secure item button).
   if logIndex and GetQuestLogSpecialItemInfo then
      local link, texture, charges, showItemWhenComplete = GetQuestLogSpecialItemInfo(logIndex)
      local itemID = link and tonumber(link:match("item:(%d+)"))
      if itemID and (not quest.isComplete or showItemWhenComplete) then
         quest.hasItem = true
         quest.itemID = itemID
         quest.itemTexture = texture
         quest.itemCharges = charges
      end
   end
   return quest
end

local questSorters = {
   level = function(a, b)
      if a.level ~= b.level then return a.level < b.level end
      if a.title ~= b.title then return a.title < b.title end
      return a.questID < b.questID
   end,
   name = function(a, b)
      if a.title ~= b.title then return a.title < b.title end
      return a.questID < b.questID
   end,
}

----------------------------------------------------------------
-- Distance sort with hysteresis: distances change as the player moves,
-- so start from the previous order and only swap neighbours when one is
-- clearly farther. Entries without a location go last, using the fallback.
----------------------------------------------------------------

local DISTANCE_SWAP_RATIO = 1.15
local DISTANCE_SWAP_MIN = 5   -- yards

-- list: entries with a .distance field; getKey(entry) identifies an entry
-- across updates; ranks: [key] = position from the previous sort (updated).
-- Comparator state for SortByDistance (module-level to avoid a closure per sort).
local sortRanks, sortGetKey, sortFallback
local function PreviousOrderFirst(a, b)
   local ra, rb = sortRanks[sortGetKey(a)], sortRanks[sortGetKey(b)]
   if ra and rb then return ra < rb end
   if ra or rb then return ra ~= nil end
   if (a.distance ~= nil) ~= (b.distance ~= nil) then return a.distance ~= nil end
   if a.distance and a.distance ~= b.distance then return a.distance < b.distance end
   return sortFallback(a, b)
end

local function SortByDistance(list, getKey, ranks, fallback)
   sortRanks, sortGetKey, sortFallback = ranks, getKey, fallback
   sort(list, PreviousOrderFirst)
   -- Bubble passes; a swap needs a clear margin, so it can't oscillate.
   local swapped = true
   while swapped do
      swapped = false
      for i = 1, #list - 1 do
         local a, b = list[i], list[i + 1]
         local swap
         if a.distance and b.distance then
            swap = a.distance > b.distance * DISTANCE_SWAP_RATIO + DISTANCE_SWAP_MIN
         elseif a.distance or b.distance then
            swap = b.distance ~= nil
         else
            swap = fallback(b, a)
         end
         if swap then
            list[i], list[i + 1] = b, a
            swapped = true
         end
      end
   end
   wipe(ranks)
   for i, entry in ipairs(list) do
      ranks[getKey(entry)] = i
   end
end

local questRanks, zoneRanks = {}, {}
local function QuestKey(quest) return quest.questID end
local function ZoneKey(section) return section.name end

local zoneSorters = {
   level = function(a, b)
      if a.minLevel ~= b.minLevel then return a.minLevel < b.minLevel end
      return a.name < b.name
   end,
   name = function(a, b)
      return a.name < b.name
   end,
}

-- Current zone (and sub-areas) first; comparators are module-level so
-- sorting doesn't create closures on every update.
local activeZoneSorter = zoneSorters.level
local function CurrentZoneFirst(a, b)
   if a.zoneRank ~= b.zoneRank then return a.zoneRank > b.zoneRank end
   return activeZoneSorter(a, b)
end
local function CurrentZoneFirstByLevel(a, b)
   if a.zoneRank ~= b.zoneRank then return a.zoneRank > b.zoneRank end
   return zoneSorters.level(a, b)
end

--- Returns a sorted list of zone sections:
--- { name, isCurrent, zoneRank, minLevel, quests = { quest, ... } }
--- plus the number of quests in the log and the number displayed.
-- Sorts a list of quests by the configured quest sort order.
local function SortQuests(quests, profile)
   if profile.questSort == "distance" then
      -- Ranks are per quest ID, so one table works across sections.
      SortByDistance(quests, QuestKey, questRanks, questSorters.level)
   else
      sort(quests, questSorters[profile.questSort] or questSorters.level)
   end
end

-- Fold keys of the sections on top, kept apart from zone names.
mod.FOCUSED_FOLD_KEY = "\001focused"
mod.COMPLETED_FOLD_KEY = "\001completed"

-- Moves the quests for which take(quest, section) is true out of their sections, in
-- the order they are listed. Sections left empty are dropped. Returns the
-- remaining sections and the moved quests.
local function TakeQuests(sections, take)
   local taken, kept = new(), new()
   for _, section in ipairs(sections) do
      local quests = new()
      local hasLocal = false
      for _, quest in ipairs(section.quests) do
         if take(quest, section) then
            tinsert(taken, quest)
         else
            tinsert(quests, quest)
            hasLocal = hasLocal or quest.inCurrentZone
         end
      end
      del(section.quests)
      section.quests = quests
      section.hasLocalQuests = hasLocal or nil
      if #quests > 0 then
         tinsert(kept, section)
      else
         mod.deepDel(section)
      end
   end
   del(sections)
   return kept, taken
end

-- A section that isn't a zone: always listed on top, folded on its own and
-- left alone by auto-fold.
local function NewSpecialSection(name, foldKey, quests)
   local section = new()
   section.name = name
   section.foldKey = foldKey
   section.isSpecial = true
   section.zoneRank = 0
   section.minLevel = math.huge
   section.quests = quests
   for _, quest in ipairs(quests) do
      if quest.inCurrentZone then section.hasLocalQuests = true end
      if quest.level < section.minLevel then section.minLevel = quest.level end
      if quest.distance and (not section.distance or quest.distance < section.distance) then
         section.distance = quest.distance
      end
   end
   return section
end

local function IsComplete(quest) return quest.isComplete end

-- Completed, and filed under the current zone or one of its sub-areas.
local function IsCompleteHere(quest, section)
   return quest.isComplete and section.isCurrent
end

-- Moves completed quests to the start ("first") or end ("last") of the
-- list, keeping the order within both groups. Other modes leave it alone.
local function GroupCompleted(quests, mode)
   if mode ~= "first" and mode ~= "last" then return end
   local done, rest = new(), new()
   for _, quest in ipairs(quests) do
      tinsert(quest.isComplete and done or rest, quest)
   end
   local first, second = done, rest
   if mode == "last" then first, second = rest, done end
   for i, quest in ipairs(first) do quests[i] = quest end
   for i, quest in ipairs(second) do quests[#first + i] = quest end
   del(done)
   del(rest)
end

-- Moves the focused (super tracked) quest, and with includeWatched the
-- quests on the built-in watch list, into one section on top: focused quest
-- first, the rest in the order they were listed.
local function PinFocusedQuests(sections, includeWatched, completedSort)
   local pinned
   sections, pinned = TakeQuests(sections, function(quest)
      return quest.isSuperTracked or (includeWatched and quest.isWatched)
   end)
   if #pinned == 0 then
      del(pinned)
      return sections
   end
   GroupCompleted(pinned, completedSort)
   for i, quest in ipairs(pinned) do
      if quest.isSuperTracked then
         tinsert(pinned, 1, tremove(pinned, i))
         break
      end
   end
   for _, quest in ipairs(pinned) do
      quest.isPinned = true
   end
   local section = NewSpecialSection(includeWatched and L["Tracked"] or L["Focused"], mod.FOCUSED_FOLD_KEY, pinned)
   section.isPinned = true
   tinsert(sections, 1, section)
   return sections
end

-- Moves the completed quests left in the zones (all of them, or only those
-- of the current zone) into a section of their own, right below the
-- focused / tracked section, sorted as one list by the quest sort order.
local function SeparateCompletedQuests(sections, profile, currentOnly)
   local pinned = sections[1] and sections[1].isPinned and tremove(sections, 1)
   local completed
   sections, completed = TakeQuests(sections, currentOnly and IsCompleteHere or IsComplete)
   if #completed > 0 then
      SortQuests(completed, profile)
      tinsert(sections, 1, NewSpecialSection(L["Completed"], mod.COMPLETED_FOLD_KEY, completed))
   else
      del(completed)
   end
   if pinned then
      tinsert(sections, 1, pinned)
   end
   return sections
end

function mod:CollectQuests()
   local profile = self.db.profile
   local zoneNames = GetCurrentZoneNames()
   -- In instances, isOnMap can be true for quests of the surrounding zone.
   local useOnMap = not IsInInstance()
   local pois = profile.showDirection and self:CollectQuestPOIs() or nil
   local sections, byName = new(), new()
   local header = L["Miscellaneous"]
   local numQuests, numShown = 0, 0
   -- With a section on top, the focused quest is always shown (in it).
   local pinMode = profile.focusedSection == "focused" or profile.focusedSection == "tracked"
   local focusedID = pinMode and C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID() or nil
   -- The "All" completed section lists every completed quest, whatever the filters.
   local allCompleted = profile.completedSection == "all"

   for i = 1, C_QuestLog.GetNumQuestLogEntries() do
      local info = C_QuestLog.GetInfo(i)
      if info then
         if info.isHeader then
            header = info.title
         elseif ShouldTrackQuest(info) then
            numQuests = numQuests + 1
            local zoneRank = GetZoneRank(header, zoneNames)
            local isCurrentZone = zoneRank > 0
            local visible = true
            if profile.onlyCurrentZone and not (isCurrentZone or (useOnMap and info.isOnMap)) then
               visible = false
            end
            if visible and not profile.showAllQuests and C_QuestLog.GetQuestWatchType(info.questID) == nil then
               visible = false
            end
            if info.questID == focusedID or (allCompleted and C_QuestLog.IsComplete(info.questID)) then
               visible = true
            end
            if visible then
               local section = byName[header]
               if not section then
                  section = new()
                  section.name = header
                  section.isCurrent = isCurrentZone
                  section.zoneRank = zoneRank
                  section.minLevel = math.huge
                  section.quests = new()
                  byName[header] = section
                  tinsert(sections, section)
               end
               local quest = BuildQuest(info)
               if pois then
                  -- Hand the POI over to the quest (recycled with it).
                  quest.poi = pois[quest.questID]
                  pois[quest.questID] = nil
               end
               quest.zoneName = header
               quest.inCurrentZone = isCurrentZone or (useOnMap and info.isOnMap) or false
               if quest.inCurrentZone then
                  -- e.g. a Stormwind quest with objectives in this zone
                  section.hasLocalQuests = true
               end
               tinsert(section.quests, quest)
               if quest.level < section.minLevel then
                  section.minLevel = quest.level
               end
               numShown = numShown + 1
            end
         end
      end
   end

   -- Zones with quests in the current zone (filed elsewhere) sort right
   -- after the current zone and its sub-areas.
   for _, section in ipairs(sections) do
      if section.zoneRank == 0 and section.hasLocalQuests then
         section.zoneRank = 0.5
      end
   end

   for _, section in ipairs(sections) do
      SortQuests(section.quests, profile)
   end

   for _, section in ipairs(sections) do
      GroupCompleted(section.quests, profile.completedSort)
   end

   -- A zone's distance is that of its nearest quest.
   for _, section in ipairs(sections) do
      for _, quest in ipairs(section.quests) do
         if quest.distance and (not section.distance or quest.distance < section.distance) then
            section.distance = quest.distance
         end
      end
   end

   local zoneSorter = zoneSorters[profile.zoneSort] or zoneSorters.level
   if profile.zoneSort == "distance" then
      if profile.currentZoneFirst then
         -- Current zone (and its sub-areas) first, then the rest by distance.
         local current, others = new(), new()
         for _, section in ipairs(sections) do
            tinsert(section.zoneRank > 0 and current or others, section)
         end
         sort(current, CurrentZoneFirstByLevel)
         SortByDistance(others, ZoneKey, zoneRanks, zoneSorters.level)
         for _, section in ipairs(others) do
            tinsert(current, section)
         end
         del(others)
         del(sections)
         sections = current
      else
         SortByDistance(sections, ZoneKey, zoneRanks, zoneSorters.level)
      end
   elseif profile.currentZoneFirst then
      activeZoneSorter = zoneSorter
      sort(sections, CurrentZoneFirst)
   else
      sort(sections, zoneSorter)
   end

   if pinMode then
      -- Showing only watched quests, Tracked would take every quest out of
      -- its zone: only the focused quest goes on top then.
      local includeWatched = profile.focusedSection == "tracked" and profile.showAllQuests
      sections = PinFocusedQuests(sections, includeWatched, profile.completedSort)
   end
   if profile.completedSection == "all" or profile.completedSection == "current" then
      sections = SeparateCompletedQuests(sections, profile, profile.completedSection == "current")
   end
   for _, section in ipairs(sections) do
      local numComplete = 0
      for _, quest in ipairs(section.quests) do
         if quest.isComplete then numComplete = numComplete + 1 end
      end
      section.numComplete = numComplete
   end

   del(byName)
   mod.deepDel(pois)  -- POIs of quests that weren't shown
   return sections, numQuests, numShown
end

----------------------------------------------------------------
-- World quests and bonus objectives (retail; mirrors Blizzard's
-- WorldQuest / BonusObjective trackers): tasks in the current area, plus
-- watched world quests anywhere.
----------------------------------------------------------------

local function GetTaskLocation(questID)
   local mapID = C_TaskQuest.GetQuestZoneID(questID)
   if not mapID then return nil end
   local x, y = C_TaskQuest.GetQuestLocation(questID, mapID)
   if x and y then
      return mod.newHash("mapID", mapID, "x", x, "y", y)
   end
end
mod.GetTaskLocation = GetTaskLocation

-- Scratch "quest log info" for BuildQuest when building tasks.
local taskInfo = {}
local EMPTY_TASKS = {}

local function TaskSorter(a, b)
   if a.inArea ~= b.inArea then return a.inArea end
   if (a.distance ~= nil) ~= (b.distance ~= nil) then return a.distance ~= nil end
   if a.distance and a.distance ~= b.distance then return a.distance < b.distance end
   if a.title ~= b.title then return a.title < b.title end
   return a.questID < b.questID
end

--- Returns { worldQuests = { quest, ... }, bonus = { quest, ... } } or nil when
--- the client has no tasks (e.g. Forever). Entries are quest records
--- (as from BuildQuest) without a level, flagged with isTask.
function mod:CollectTasks()
   -- Forever has the task API but no world quests or bonus objectives.
   if IS_FOREVER or not (GetTasksTable and GetTaskInfo and C_TaskQuest and QuestUtils_IsQuestWorldQuest) then
      return nil
   end
   local profile = self.db.profile
   local worldQuests, bonus, seen = new(), new(), new()

   local function add(list, questID, tracked)
      if not questID or seen[questID] then return end
      local isInArea, isOnMap, numObjectives, taskName = GetTaskInfo(questID)
      if not numObjectives or not (tracked or isInArea) then return end
      seen[questID] = true

      wipe(taskInfo)
      taskInfo.questID = questID
      taskInfo.questLogIndex = C_QuestLog.GetLogIndexForQuestID(questID)
      taskInfo.title = taskName or C_TaskQuest.GetQuestInfoByQuestID(questID) or ""
      taskInfo.isOnMap = isOnMap
      local task = BuildQuest(taskInfo)
      task.isTask = true
      task.isWorldQuest = list == worldQuests
      task.inArea = isInArea or false
      task.inCurrentZone = isInArea or isOnMap or false
      if profile.showDirection then
         task.poi = GetTaskLocation(questID)
      end
      if task.isWorldQuest and QuestUtils_ShouldDisplayExpirationWarning
         and QuestUtils_ShouldDisplayExpirationWarning(questID) then
         local minutes = C_TaskQuest.GetQuestTimeLeftMinutes(questID)
         if minutes and minutes > 0 and BONUS_OBJECTIVE_TIME_LEFT then
            task.timeLeftText = BONUS_OBJECTIVE_TIME_LEFT:format(SecondsToTime(minutes * 60))
         end
      end
      tinsert(list, task)
   end

   for _, questID in ipairs(GetTasksTable() or EMPTY_TASKS) do
      if QuestUtils_IsQuestWorldQuest(questID) then
         if profile.showWorldQuests then
            add(worldQuests, questID)
         end
      elseif profile.showBonusObjectives and not QuestUtils_IsQuestWatched(questID) then
         add(bonus, questID)
      end
   end
   if profile.showWorldQuests then
      for i = 1, C_QuestLog.GetNumWorldQuestWatches() do
         add(worldQuests, C_QuestLog.GetQuestIDForWorldQuestWatchIndex(i), true)
      end
   end

   del(seen)
   sort(worldQuests, TaskSorter)
   sort(bonus, TaskSorter)
   local tasks = new()
   tasks.worldQuests = worldQuests
   tasks.bonus = bonus
   return tasks
end

----------------------------------------------------------------
-- Tracked recipes (mirrors Blizzard_ProfessionsRecipeTracker)
----------------------------------------------------------------

local pendingItems = {}

local function GetReagentName(reagent)
   if reagent.itemID then
      local name = C_Item.GetItemNameByID(reagent.itemID)
      if not name and not pendingItems[reagent.itemID] then
         pendingItems[reagent.itemID] = true
         Item:CreateFromItemID(reagent.itemID):ContinueOnItemLoad(function()
            pendingItems[reagent.itemID] = nil
            mod:RequestUpdate()
         end)
      end
      return name or RETRIEVING_ITEM_INFO or "..."
   elseif reagent.currencyID then
      local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(reagent.currencyID)
      return currencyInfo and currencyInfo.name
   end
end

local function BuildRecipe(recipeID, isRecraft)
   local schematic = ProfessionsUtil.GetRecipeSchematic(recipeID, isRecraft)
   if not schematic then return nil end

   local name = schematic.name
   if isRecraft and PROFESSIONS_CRAFTING_FORM_RECRAFTING_HEADER then
      name = PROFESSIONS_CRAFTING_FORM_RECRAFTING_HEADER:format(name)
   end
   local recipe = mod.newHash("recipeID", recipeID, "isRecraft", isRecraft, "name", name, "reagents", new())

   for _, slot in ipairs(schematic.reagentSlotSchematics) do
      if ProfessionsUtil.IsReagentSlotRequired(slot) then
         local reagent = slot.reagents[1]
         local reagentName
         if ProfessionsUtil.IsReagentSlotBasicRequired(slot) then
            reagentName = GetReagentName(reagent)
         elseif ProfessionsUtil.IsReagentSlotModifyingRequired(slot) and slot.slotInfo then
            reagentName = slot.slotInfo.slotText
         end

         if reagentName then
            local entry = new()
            entry.name = reagentName
            if slot.IsVariableQuantityReagent and slot:IsVariableQuantityReagent(reagent) then
               local min, max = slot:GetVariableQuantityRange(reagent)
               entry.text = format("%d-%d %s", min, max, reagentName)
               entry.finished = false
            else
               local required = slot.GetQuantityRequired and slot:GetQuantityRequired(reagent) or slot.quantityRequired or 1
               local have = ProfessionsUtil.AccumulateReagentsInPossession(slot.reagents)
               entry.text = format("%d/%d %s", have, required, reagentName)
               entry.finished = have >= required
            end
            -- Modifying (required choice) slots first, like Blizzard does.
            if ProfessionsUtil.IsReagentSlotModifyingRequired(slot) then
               tinsert(recipe.reagents, 1, entry)
            else
               tinsert(recipe.reagents, entry)
            end
         end
      end
   end
   return recipe
end

local EMPTY = {}

--- Returns a list of { recipeID, isRecraft, name, reagents = { { text, finished } } }
function mod:CollectRecipes()
   if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipesTracked and ProfessionsUtil) then
      return nil
   end
   local recipes = new()
   for pass = 1, 2 do
      local isRecraft = pass == 2
      for _, recipeID in ipairs(C_TradeSkillUI.GetRecipesTracked(isRecraft) or EMPTY) do
         local recipe = BuildRecipe(recipeID, isRecraft)
         if recipe then
            tinsert(recipes, recipe)
         end
      end
   end
   return recipes
end

----------------------------------------------------------------
-- Scenarios (delves, open world scenarios, ...)
----------------------------------------------------------------

local issecretvalue = issecretvalue or function() return false end

-- Same text as Blizzard's scenario tracker; weighted criteria are a
-- percentage shown as a progress bar.
local function AddCriteria(list, info)
   if not info then return end
   local objective = new()
   local text = info.description
   if info.isWeightedProgress then
      if not info.completed then objective.percent = info.quantity or 0 end
   elseif not info.isFormatted then
      text = format("%d/%d %s", info.quantity or 0, info.totalQuantity or 0, text or "")
   end
   objective.text = text
   objective.finished = info.completed
   if info.duration and not issecretvalue(info.duration) and info.duration > 0
      and info.elapsed and info.elapsed <= info.duration then
      objective.timerEnd = GetTime() - info.elapsed + info.duration
   end
   tinsert(list, objective)
end

--- Returns { name, stage, numStages, stageName, widgetSetID, criteria = { objective, ... },
--- bonus = { { name, criteria }, ... } } for the current scenario, or nil
--- when not in one, or in one Blizzard's scenario block shows instead
--- (mod:IsBlizzardScenario). Objectives are { text, finished, percent, timerEnd }.
function mod:CollectScenario()
   if not self:IsInScenario() or self:IsBlizzardScenario() or not C_ScenarioInfo then
      return nil
   end
   local name, stage, numStages = C_Scenario.GetInfo()
   if not numStages or numStages == 0 then return nil end
   local scenario = new()
   scenario.name, scenario.stage, scenario.numStages = name, stage, numStages
   scenario.criteria = new()
   scenario.bonus = new()
   if stage > numStages then return scenario end  -- completed

   local stageName, description, numCriteria, _, _, _, _, _, _, weightedProgress, _, widgetSetID = C_Scenario.GetStepInfo()
   scenario.stageName = stageName
   scenario.widgetSetID = widgetSetID  -- stage widgets (timer, ...)
   if not C_Scenario.ShouldShowCriteria or C_Scenario.ShouldShowCriteria() then
      if weightedProgress then
         -- One bar for the whole stage.
         local objective = new()
         objective.text = description
         objective.percent = weightedProgress
         tinsert(scenario.criteria, objective)
      else
         for i = 1, numCriteria or 0 do
            AddCriteria(scenario.criteria, C_ScenarioInfo.GetCriteriaInfo(i))
         end
      end
   end

   for _, step in ipairs(C_Scenario.GetBonusSteps and C_Scenario.GetBonusSteps() or EMPTY) do
      local bonusName, _, numBonusCriteria, failed, _, _, shown = C_Scenario.GetStepInfo(step)
      if shown and not failed then
         local bonus = new()
         bonus.name = bonusName
         bonus.criteria = new()
         for i = 1, numBonusCriteria or 0 do
            AddCriteria(bonus.criteria, C_ScenarioInfo.GetCriteriaInfoByStep(step, i))
         end
         tinsert(scenario.bonus, bonus)
      end
   end
   return scenario
end

----------------------------------------------------------------
-- Tracked achievements
----------------------------------------------------------------

local MAX_ACHIEVEMENT_CRITERIA = 5  -- as Blizzard's tracker; "..." for the rest

--- Returns a list of { achievementID, name, objectives = { objective, ... } }
--- for the tracked achievements, or nil when the client has none.
--- Objectives are { text, failed, timerEnd }; completed criteria are left out.
function mod:CollectAchievements()
   local trackingType = Enum and Enum.ContentTrackingType and Enum.ContentTrackingType.Achievement
   if not (trackingType and C_ContentTracking and GetAchievementInfo) then
      return nil
   end
   local achievements = new()
   for _, achievementID in ipairs(C_ContentTracking.GetTrackedIDs(trackingType) or EMPTY) do
      local _, name, _, _, _, _, _, description, _, _, _, _, wasEarnedByMe = GetAchievementInfo(achievementID)
      if name and not wasEarnedByMe then
         local achievement = new()
         achievement.achievementID = achievementID
         achievement.name = name
         local objectives = new()
         achievement.objectives = objectives
         local numCriteria = GetAchievementNumCriteria(achievementID) or 0
         local numShown = 0
         for i = 1, numCriteria do
            local text, criteriaType, completed, _, _, _, flags, assetID, quantityString, _, eligible, duration, elapsed =
               GetAchievementCriteriaInfo(achievementID, i)
            if not completed then
               local objective = new()
               if numShown == MAX_ACHIEVEMENT_CRITERIA then
                  objective.text = "..."
                  tinsert(objectives, objective)
                  break
               end
               if description and flags and EVALUATION_TREE_FLAG_PROGRESS_BAR
                  and bit.band(flags, EVALUATION_TREE_FLAG_PROGRESS_BAR) == EVALUATION_TREE_FLAG_PROGRESS_BAR then
                  if quantityString and quantityString:lower():find("interface\\moneyframe", 1, true) then
                     text = quantityString .. " " .. description
                  else
                     text = (quantityString or ""):gsub(" / ", "/") .. " " .. description
                  end
               elseif criteriaType == CRITERIA_TYPE_ACHIEVEMENT and assetID then
                  -- Meta achievement: the criteria are achievements.
                  text = select(2, GetAchievementInfo(assetID)) or text
               end
               objective.text = text
               objective.failed = not eligible
               if duration and elapsed and elapsed < duration then
                  objective.timerEnd = GetTime() - elapsed + duration
               end
               tinsert(objectives, objective)
               numShown = numShown + 1
            end
         end
         if numCriteria == 0 then
            local objective = new()
            objective.text = description
            objective.failed = IsAchievementEligible and not IsAchievementEligible(achievementID)
            tinsert(objectives, objective)
         end
         tinsert(achievements, achievement)
      end
   end
   return achievements
end
