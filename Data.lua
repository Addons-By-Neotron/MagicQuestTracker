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

-- Quest log header of every quest seen (CollectQuests), so a quest can be
-- matched to its dungeon, and whether the quests in the log are complete
-- (refreshed per collect).
local questHeaders = {}
local questComplete = {}

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

-- Dungeons whose quest log header (the old zone name) differs from the
-- instance name: instance ID (GetInstanceInfo) -> area IDs, so the
-- localized header comes from C_Map.GetAreaInfo.
local INSTANCE_AREAS = {
   [34] = { 717 },    -- Stormwind Stockade: "The Stockade"
   [36] = { 1581 },   -- Deadmines: "The Deadmines"
   [109] = { 1477 },  -- Sunken Temple: "The Temple of Atal'Hakkar"
}

-- Last word of the instance name, for headers like "The Stockade" in
-- "Stormwind Stockade" that the alias table doesn't know (in instances only).
local instanceTail

local function LastWord(name)
   return name and name:match("([^%s]+)%s*$")
end

local function GetCurrentZoneNames()
   wipe(zoneNames)
   instanceTail = nil
   -- Neighborhood quests are filed under a generic "Neighborhood" header;
   -- the global is a label with a trailing colon.
   if C_Housing and C_Housing.IsOnNeighborhoodMap() and HOUSING_CORNERSTONE_NEIGHBORHOOD then
      add((HOUSING_CORNERSTONE_NEIGHBORHOOD:gsub("%s*[:：]%s*$", "")))
   end
   add(GetRealZoneText())
   add(GetZoneText())

   local mapID = C_Map.GetBestMapForUnit("player")
   if IsInInstance() then
      -- Dungeon/raid maps have the outdoor zone as parent; don't climb into it.
      local instanceName, _, _, _, _, _, _, instanceID = GetInstanceInfo()
      add(instanceName)
      local info = mapID and C_Map.GetMapInfo(mapID)
      add(info and info.name)
      local areas = instanceID and INSTANCE_AREAS[instanceID]
      if areas and C_Map.GetAreaInfo then
         for _, areaID in ipairs(areas) do
            add(C_Map.GetAreaInfo(areaID))
         end
      end
      local tail = LastWord(instanceName)
      if tail and #tail >= 4 then instanceTail = tail:lower() end
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
   local tail = instanceTail and LastWord(header)
   if tail and tail:lower() == instanceTail then
      return 2
   end
   return 0
end

--- /mqt dungeondebug: what the Encounter Journal knows about the current
--- instance (for a Forever dungeon block like Retail's).
function mod:DumpDungeon()
   local print = function(...) self:Print(...) end
   local name, itype, diff, _, _, _, _, instanceID = GetInstanceInfo()
   print(format("instance: %s type=%s difficulty=%s id=%s", tostring(name), tostring(itype),
      tostring(diff), tostring(instanceID)))
   local EJ = C_EncounterJournal
   local journalID = EJ and EJ.GetInstanceForGameMap and instanceID and EJ.GetInstanceForGameMap(instanceID)
   print(format("journal instance=%s scenario=%s", tostring(journalID),
      tostring(C_Scenario and C_Scenario.IsInScenario and C_Scenario.IsInScenario())))
   if GetInstanceLockTimeRemaining then
      local reset, _, numEncounters, completed = GetInstanceLockTimeRemaining()
      print(format("lock: reset=%s encounters=%s completed=%s", tostring(reset), tostring(numEncounters),
         tostring(completed)))
      for i = 1, numEncounters or 0 do
         print(format("  lock %d: %s killed=%s", i, tostring((GetInstanceLockTimeRemainingEncounter(i))),
            tostring(select(3, GetInstanceLockTimeRemainingEncounter(i)))))
      end
   end
   local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
   local mapInfo = mapID and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
   print(format("rooms: subzone=%s minimap=%s map=%s %s", tostring(GetSubZoneText and GetSubZoneText()),
      tostring(GetMinimapZoneText and GetMinimapZoneText()), tostring(mapID), tostring(mapInfo and mapInfo.name)))
   local run = instanceID and self.db.char.dungeonKills[instanceID]
   if run then
      local kills = {}
      for boss in pairs(run.bosses or {}) do tinsert(kills, boss) end
      print(format("run: wing=%s known=%s all=%s entry=%s copy=%s kills=%s", tostring(run.wing), tostring(run.wingKnown),
         tostring(run.crossedWings and table.concat(GetKeysArray and GetKeysArray(run.crossedWings) or {}, "+")), tostring(run.entry ~= nil), tostring(run.copy), table.concat(kills, ", ")))
   else
      print("run: none")
   end
   local guid = UnitGUID("target")
   print(format("target guid=%s", issecretvalue and guid and issecretvalue(guid) and "<secret>" or tostring(guid)))
   if not (journalID and EJ_SelectInstance and EJ_GetEncounterInfoByIndex) then return end
   EJ_SelectInstance(journalID)
   for i = 1, 40 do
      local ename, _, encounterID, _, _, _, dungeonEncounterID = EJ_GetEncounterInfoByIndex(i, journalID)
      if not ename then break end
      print(format("  %d %s journal=%s encounter=%s complete=%s", i, ename, tostring(encounterID),
         tostring(dungeonEncounterID),
         tostring(EJ.IsEncounterComplete and encounterID and EJ.IsEncounterComplete(encounterID))))
   end
end

--- /mqt zonedebug: what the current zone is matched against, and how
--- each quest log header ranks (for testing).
function mod:DumpZones()
   local print = function(...) self:Print(...) end
   local names = {}
   for name in pairs(GetCurrentZoneNames()) do tinsert(names, name) end
   sort(names)
   print("zone names: " .. table.concat(names, " | "))
   print(format("real=%s zone=%s sub=%s inInstance=%s", tostring(GetRealZoneText()),
      tostring(GetZoneText()), tostring(GetSubZoneText()), tostring(IsInInstance())))
   local iname, itype, diff, _, _, _, _, instanceID, _, lfgID = GetInstanceInfo()
   print(format("instance: name=%s type=%s difficulty=%s id=%s lfg=%s", tostring(iname),
      tostring(itype), tostring(diff), tostring(instanceID), tostring(lfgID)))
   local mapID = C_Map.GetBestMapForUnit("player")
   while mapID and mapID > 0 do
      local info = C_Map.GetMapInfo(mapID)
      if not info then break end
      print(format("map %d: %s (type %s)", mapID, tostring(info.name), tostring(info.mapType)))
      mapID = info.parentMapID
   end
   local header
   for i = 1, C_QuestLog.GetNumQuestLogEntries() do
      local info = C_QuestLog.GetInfo(i)
      if info and info.isHeader then
         header = info.title
         print(format("header '%s' rank=%d", tostring(header), GetZoneRank(header or "", zoneNames)))
      elseif info and not info.isHidden then
         local questMap = GetQuestUiMapID and GetQuestUiMapID(info.questID)
         local mapInfo = questMap and questMap > 0 and C_Map.GetMapInfo(questMap)
         print(format("  %d %s onMap=%s questMap=%s (%s)", info.questID, tostring(info.title),
            tostring(info.isOnMap), tostring(questMap), tostring(mapInfo and mapInfo.name)))
      end
   end
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
mod.GetQuestDistance = GetQuestDistance

-- Classic-style quest timers (Forever): questID -> absolute GetTime() end.
-- C_QuestLog.GetTimeAllowed returns nothing for these; Blizzard's quest timer
-- frame reads them from C_QuestLog.GetQuestTimers. Refreshed per collect.
-- Only the time left is known; the duration is the most ever seen for the
-- quest (the full time once it was tracked when accepted), saved globally.
local questTimerEnds = {}
local function RefreshQuestTimers()
   wipe(questTimerEnds)
   local timers = C_QuestLog.GetQuestTimers and C_QuestLog.GetQuestTimers()
   if not timers then return end
   local now = GetTime()
   for _, timer in ipairs(timers) do
      if timer.questID and timer.questTimer and timer.questTimer > 0 then
         questTimerEnds[timer.questID] = now + timer.questTimer
         local durations = mod.db.global.questTimerDurations
         durations[timer.questID] = math.max(durations[timer.questID] or 0, timer.questTimer)
      end
   end
end

-- True for quests with a running time limit (the Timed section shows them
-- whatever the filters). Same sources as BuildQuest's timerEnd.
local function HasTimeLimit(questID)
   if questTimerEnds[questID] then return true end
   local timeTotal, timeElapsed = C_QuestLog.GetTimeAllowed and C_QuestLog.GetTimeAllowed(questID)
   return timeTotal and timeElapsed and timeElapsed < timeTotal and not C_QuestLog.IsFailed(questID) or false
end

-- Difficulty (a QuestDifficultyColors key such as "impossible" or "trivial")
-- as Blizzard's quest log computes it: the server-side
-- C_PlayerInfo.GetContentDifficultyQuestForPlayer, mapped through
-- GetDifficultyColor. Falls back to the level based GetQuestDifficultyColor.
-- Not cached: both calls are cheap and the result changes with player level
-- and quest state.
local difficultyByColor
local function DifficultyName(color)
   if not color then return nil end
   if not difficultyByColor then
      difficultyByColor = {}
      for name, c in pairs(QuestDifficultyColors or {}) do
         difficultyByColor[c] = name
      end
   end
   return difficultyByColor[color]
end

--- Returns the difficulty name of a quest, or nil (world quests and bonus
--- objectives have no level). levelOnly skips the server lookup (previews).
function mod:GetQuestDifficulty(questID, difficultyLevel, isScaling, levelOnly)
   local name
   if questID and not levelOnly and GetDifficultyColor and C_PlayerInfo and C_PlayerInfo.GetContentDifficultyQuestForPlayer then
      local ok, difficulty = pcall(C_PlayerInfo.GetContentDifficultyQuestForPlayer, questID)
      if ok and difficulty ~= nil then
         name = DifficultyName((GetDifficultyColor(difficulty)))
      end
   end
   if not name and difficultyLevel and GetQuestDifficultyColor then
      name = DifficultyName((GetQuestDifficultyColor(difficultyLevel, isScaling)))
   end
   return name
end

--- True when the difficulty filters (hideRedQuests / hideGrayQuests) hide a
--- quest of this difficulty.
function mod:IsDifficultyFiltered(difficulty, profile)
   return (difficulty == "impossible" and profile.hideRedQuests)
      or (difficulty == "trivial" and profile.hideGrayQuests) or false
end

local function NormalizeText(text)
   return (text:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""):lower())
end

-- Phrases (normalized) to look for in quest texts for the quest items in
-- the bags, other than ones that start a quest: the whole name, and every
-- run of two or more of its words, as the text may leave words out
-- ("Miniature Platinum Discs" are "the platinum discs"). Collected once per
-- update (reset by CollectQuests).
local bagQuestItems
local bagQuestItemIDs = {}  -- [itemID] = true, filled with bagQuestItems
local bagUsableIDs = {}     -- [itemID] = true for any item that has a use effect or opens
local NUM_BAGS = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
local QUEST_ITEM_CLASS = Enum.ItemClass and Enum.ItemClass.Questitem or 12

local function GetBagQuestItems()
   if bagQuestItems then return bagQuestItems end
   bagQuestItems = {}
   wipe(bagQuestItemIDs)
   wipe(bagUsableIDs)
   if not (C_Container and C_Container.GetContainerNumSlots) then return bagQuestItems end
   for bag = 0, NUM_BAGS do
      for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
         local itemID = C_Container.GetContainerItemID(bag, slot)
         if itemID then
            local info = C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)
            if (info and info.hasLoot) or C_Item.GetItemSpell(itemID) then bagUsableIDs[itemID] = true end
            local questInfo = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
            local classID = select(6, C_Item.GetItemInfoInstant(itemID))
            local isQuestItem = classID == QUEST_ITEM_CLASS or (questInfo and questInfo.isQuestItem)
            -- Items that start a quest aren't carried for one.
            if isQuestItem and not (questInfo and questInfo.questID) then
               bagQuestItemIDs[itemID] = true
               local name = C_Item.GetItemNameByID(itemID)
               if name and name ~= "" then
                  name = NormalizeText(name)
                  bagQuestItems[name] = true
                  local words = {}
                  for word in name:gmatch("%S+") do words[#words + 1] = word end
                  for first = 1, #words - 1 do
                     for last = first + 1, #words do
                        bagQuestItems[table.concat(words, " ", first, last)] = true
                     end
                  end
               end
            end
         end
      end
   end
   return bagQuestItems
end
--- Bags changed: scan them again on next use.
function mod.ResetBagQuestItems() bagQuestItems = nil end

-- QuestieDB (the database addon Questie uses, with a public API): the item
-- a quest gives you when you accept it. nil when QuestieDB isn't loaded,
-- is an incompatible version, or doesn't know the quest.
local QUESTIEDB_CONTRACT = 4
local questieDBUsable  -- nil until checked
local function QuestieDB()
   local lib = LibQuestieDB
   if not lib then return nil end
   if questieDBUsable == nil then
      local ok, compatible = pcall(lib.RequireContract, QUESTIEDB_CONTRACT)
      questieDBUsable = ok and compatible and lib.Quest ~= nil and lib.Npc ~= nil
         and lib.Object ~= nil and lib.Item ~= nil or false
   end
   return questieDBUsable and lib or nil
end

function mod.HasQuestieDB() return QuestieDB() ~= nil end

local function QuestieSourceItem(questID)
   local lib = QuestieDB()
   if not lib then return nil end
   local ok, itemID = pcall(lib.Quest.sourceItemId, questID)
   return ok and type(itemID) == "number" and itemID or nil
end

-- QuestieDB again: the zones where a quest's objectives are (mob, object
-- and item drop spawns, explore triggers), for quests whose objectives are
-- in another zone than the quest log header and Blizzard doesn't put on
-- that zone's map. The data is static, so it's looked up once per quest.
local MAX_DROP_SOURCES = 25  -- items dropped by everything are no clue
local areaNames = {}
local questObjectiveZones = {}  -- [questID] = { [zoneName] = true } or false

local function AddSpawnZones(zones, spawns)
   if type(spawns) ~= "table" then return end
   for areaID in pairs(spawns) do
      local name = areaNames[areaID]
      if name == nil then
         name = type(areaID) == "number" and C_Map.GetAreaInfo(areaID) or false
         areaNames[areaID] = name
      end
      if name then zones[name] = true end
   end
end

local function AddEntityZones(zones, db, id)
   local ok, spawns = pcall(db.spawns, id)
   if ok then AddSpawnZones(zones, spawns) end
end

local function AddDropZones(zones, lib, itemID)
   local ok, npcs = pcall(lib.Item.npcDrops, itemID)
   if ok and type(npcs) == "table" and #npcs <= MAX_DROP_SOURCES then
      for _, npcID in ipairs(npcs) do AddEntityZones(zones, lib.Npc, npcID) end
   end
   local objects
   ok, objects = pcall(lib.Item.objectDrops, itemID)
   if ok and type(objects) == "table" and #objects <= MAX_DROP_SOURCES then
      for _, objectID in ipairs(objects) do AddEntityZones(zones, lib.Object, objectID) end
   end
end

local function LookupObjectiveZones(lib, questID)
   local ok, objectives = pcall(lib.Quest.objectives, questID)
   if not ok or type(objectives) ~= "table" then return false end
   local zones = {}
   for _, o in ipairs(objectives[1] or {}) do AddEntityZones(zones, lib.Npc, o[1]) end
   for _, o in ipairs(objectives[2] or {}) do AddEntityZones(zones, lib.Object, o[1]) end
   for _, o in ipairs(objectives[3] or {}) do AddDropZones(zones, lib, o[1]) end
   for _, o in ipairs(objectives[5] or {}) do
      if type(o[1]) == "table" then
         for _, npcID in ipairs(o[1]) do AddEntityZones(zones, lib.Npc, npcID) end
      end
   end
   local trigger
   ok, trigger = pcall(lib.Quest.triggerEnd, questID)
   if ok and type(trigger) == "table" then AddSpawnZones(zones, trigger[2]) end
   local extra
   ok, extra = pcall(lib.Quest.extraObjectives, questID)
   if ok and type(extra) == "table" then
      for _, o in ipairs(extra) do AddSpawnZones(zones, o[1]) end
   end
   return next(zones) and zones or false
end

--- True when QuestieDB places one of the quest's objectives in the current zone.
local function HasObjectiveInZone(questID, currentZones)
   local zones = questObjectiveZones[questID]
   if zones == nil then
      local lib = QuestieDB()
      if not lib then return false end
      zones = LookupObjectiveZones(lib, questID)
      questObjectiveZones[questID] = zones
   end
   if not zones then return false end
   for name in pairs(zones) do
      if currentZones[name] then return true end
   end
   return false
end

-- QuestieDB once more: a usable item for quests the game gives no quest
-- item button, e.g. a jar to fill from a mob. Candidates are the items the
-- quest needs (a flare gun that summons the one to turn it in to), the
-- item it gives on accepting, the items of "use item" objectives, and
-- items in the bags that come out of the item it gives (a chest of jars;
-- not always quest items). Once complete, only the items it needs count. The first one in the bags that has a use effect or opens is it,
-- so the chest comes before what's in it.
local questItemCandidates = {}  -- [questID] = { source = itemID?, numRequired = n, itemID, ... } or false
local itemContainers = {}       -- [itemID] = { [containerItemID] = true } or false

local function LookupItemCandidates(lib, questID)
   local list = {}
   local ok, required = pcall(lib.Quest.requiredSourceItems, questID)
   if ok and type(required) == "table" then
      for _, itemID in ipairs(required) do
         if type(itemID) == "number" then list[#list + 1] = itemID end
      end
   end
   list.numRequired = #list
   local sourceItem
   ok, sourceItem = pcall(lib.Quest.sourceItemId, questID)
   if ok and type(sourceItem) == "number" then
      list.source = sourceItem
      list[#list + 1] = sourceItem
   end
   local objectives
   ok, objectives = pcall(lib.Quest.objectives, questID)
   if ok and type(objectives) == "table" and type(objectives[6]) == "table" then
      for _, o in ipairs(objectives[6]) do
         if type(o[3]) == "number" then list[#list + 1] = o[3] end
      end
   end
   return (list.source or #list > 0) and list or false
end

local function ComesFrom(lib, itemID, containerID)
   local containers = itemContainers[itemID]
   if containers == nil then
      local ok, drops = pcall(lib.Item.itemDrops, itemID)
      containers = false
      if ok and type(drops) == "table" and #drops > 0 then
         containers = {}
         for _, id in ipairs(drops) do containers[id] = true end
      end
      itemContainers[itemID] = containers
   end
   return containers and containers[containerID] or false
end

-- In the bags, with a use effect or opening (a chest). Needs GetBagQuestItems.
local function IsUsableInBags(itemID)
   return bagUsableIDs[itemID] or false
end

local function QuestieUsableItem(questID, isComplete)
   local lib = QuestieDB()
   if not lib then return nil end
   local list = questItemCandidates[questID]
   if list == nil then
      list = LookupItemCandidates(lib, questID)
      questItemCandidates[questID] = list
   end
   if not list then return nil end
   GetBagQuestItems()
   for i, itemID in ipairs(list) do
      if isComplete and i > list.numRequired then return nil end
      if IsUsableInBags(itemID) then return itemID end
   end
   if list.source and not isComplete then
      local found
      for itemID in pairs(bagUsableIDs) do
         -- Lowest ID when there are several, so the button doesn't flip.
         if (not found or itemID < found) and ComesFrom(lib, itemID, list.source) then
            found = itemID
         end
      end
      return found
   end
end

--- The quest's usable item: { itemID, texture, charges, fromBags } from
--- the quest log, or from the bags via QuestieDB. nil if none to show.
function mod.GetQuestItem(questID, logIndex, isComplete)
   if logIndex and GetQuestLogSpecialItemInfo then
      local link, texture, charges, showItemWhenComplete = GetQuestLogSpecialItemInfo(logIndex)
      local itemID = link and tonumber(link:match("item:(%d+)"))
      -- Done with once complete; QuestieDB may know of one still needed.
      if itemID and (not isComplete or showItemWhenComplete) then
         return itemID, texture, charges, false
      end
   end
   local itemID = QuestieUsableItem(questID, isComplete)
   if itemID then
      return itemID, C_Item.GetItemIconByID(itemID), C_Item.GetItemCount(itemID), true
   end
end

mod.HasObjectiveInZone = HasObjectiveInZone

-- A complete quest that was complete from the moment it was accepted: just
-- go and talk to someone (breadcrumbs, deliveries). Either it has no
-- objectives, or only "log" ones that repeat the quest's summary ("Take
-- the letter to ..."), which the game marks done on accepting. Quests that
-- have you carry an item (named in their text) count as completed
-- instead: the item takes a bag slot until they are turned in. The item is
-- known exactly from QuestieDB when installed, else (and for quests it
-- doesn't cover) guessed from item names in the quest's text.
local function IsTravelQuest(questID, logIndex)
   local list = C_QuestLog.GetQuestObjectives(questID)
   local description, summary
   if logIndex and GetQuestLogQuestText then
      description, summary = GetQuestLogQuestText(logIndex)
   end
   description = description and description ~= "" and NormalizeText(description) or ""
   summary = summary and summary ~= "" and NormalizeText(summary) or false
   if list then
      for _, obj in ipairs(list) do
         if obj.type ~= "log" or not obj.text or obj.text == "" then return false end
         if not summary or NormalizeText(obj.text) ~= summary then return false end
      end
   end
   local items = GetBagQuestItems()
   local sourceItem = QuestieSourceItem(questID)
   if sourceItem and bagQuestItemIDs[sourceItem] then return false end
   for name in pairs(items) do
      if description:find(name, 1, true) or (summary and summary:find(name, 1, true)) then
         return false
      end
   end
   return true
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
   quest.isScaling = info.isScaling
   quest.suggestedGroup = info.suggestedGroup
   quest.frequency = info.frequency
   quest.isOnMap = info.isOnMap
   quest.isAutoComplete = info.isAutoComplete
   quest.isComplete = C_QuestLog.IsComplete(questID)
   quest.isFailed = C_QuestLog.IsFailed(questID)
   quest.isWatched = C_QuestLog.GetQuestWatchType(questID) ~= nil
   quest.isSuperTracked = mod:GetFocusedQuestID() == questID
   quest.distance = GetQuestDistance(questID)
   quest.isForeverQuest = IS_FOREVER and questID > MAX_VANILLA_QUEST_ID
   quest.objectives = BuildObjectives(questID)
   quest.isTravel = quest.isComplete and mod.db.profile.travelSection and IsTravelQuest(questID, logIndex) or nil
   -- Time limit (escort and other timed quests): absolute GetTime() it runs out.
   local timeTotal, timeElapsed = C_QuestLog.GetTimeAllowed and C_QuestLog.GetTimeAllowed(questID)
   if timeTotal and timeElapsed and timeElapsed < timeTotal and not quest.isFailed then
      quest.timerEnd = GetTime() - timeElapsed + timeTotal
      quest.timerTotal = timeTotal
   elseif not quest.isFailed and questTimerEnds[questID] then
      quest.timerEnd = questTimerEnds[questID]
      quest.timerTotal = mod.db.global.questTimerDurations[questID]
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
   local itemID, texture, charges, fromBags = mod.GetQuestItem(questID, logIndex, quest.isComplete)
   if itemID then
      quest.hasItem = true
      quest.itemID = itemID
      quest.itemTexture = texture
      quest.itemCharges = charges
      quest.itemFromBags = fromBags
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
mod.TIMED_FOLD_KEY = "\001timed"
mod.TRAVEL_FOLD_KEY = "\001travel"

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
            if not section.isSpecial then
               -- For grouping by zone again (separate sections).
               quest.zoneRank = section.zoneRank
               quest.zoneIsCurrent = section.isCurrent
            end
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

-- Completed, in a zone (the Travel section keeps its quests).
local function IsComplete(quest, section)
   return quest.isComplete and not section.isSpecial
end

-- Completed, and filed under the current zone or one of its sub-areas.
local function IsCompleteHere(quest, section)
   return quest.isComplete and section.isCurrent and not section.isSpecial
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
-- focused / tracked section (or at the very end with completedSort "last"),
-- sorted as one list by the quest sort order.
local function SeparateCompletedQuests(sections, profile, currentOnly)
   local pinned = sections[1] and sections[1].isPinned and tremove(sections, 1)
   local completed
   sections, completed = TakeQuests(sections, currentOnly and IsCompleteHere or IsComplete)
   if #completed > 0 then
      SortQuests(completed, profile)
      local section = NewSpecialSection(L["Completed"], mod.COMPLETED_FOLD_KEY, completed)
      if profile.completedSort == "last" then
         tinsert(sections, section)
      else
         tinsert(sections, 1, section)
      end
   else
      del(completed)
   end
   if pinned then
      tinsert(sections, 1, pinned)
   end
   return sections
end

local function IsTimed(quest) return quest.timerEnd ~= nil end

local function IsTravel(quest) return quest.isTravel end

-- Moves the quests that were complete when accepted (nothing to do but
-- talk to someone) into a section of their own. Placed by
-- PlaceSpecialSections.
local function SeparateTravelQuests(sections, profile)
   local pinned = sections[1] and sections[1].isPinned and tremove(sections, 1)
   local travel
   sections, travel = TakeQuests(sections, IsTravel)
   if #travel > 0 then
      SortQuests(travel, profile)
      tinsert(sections, NewSpecialSection(L["Travel"], mod.TRAVEL_FOLD_KEY, travel))
   else
      del(travel)
   end
   if pinned then
      tinsert(sections, 1, pinned)
   end
   return sections
end

-- With zone headers always hidden the zones read as one list, so they are
-- merged into one section and sorted as a whole (current zone first if
-- set). Sections on top stay apart.
local function MergeZones(sections, profile)
   local merged
   local result = new()
   for _, section in ipairs(sections) do
      if section.isSpecial then
         tinsert(result, section)
      elseif not merged then
         merged = section
         tinsert(result, section)
      else
         for _, quest in ipairs(section.quests) do tinsert(merged.quests, quest) end
         merged.isCurrent = merged.isCurrent or section.isCurrent
         merged.hasLocalQuests = merged.hasLocalQuests or section.hasLocalQuests
         merged.zoneRank = math.max(merged.zoneRank, section.zoneRank)
         merged.minLevel = math.min(merged.minLevel, section.minLevel)
         if section.distance and (not merged.distance or section.distance < merged.distance) then
            merged.distance = section.distance
         end
         wipe(section.quests)
         mod.deepDel(section)
      end
   end
   del(sections)
   if merged then
      local quests = merged.quests
      SortQuests(quests, profile)
      if profile.currentZoneFirst then
         -- Stable: current zone quests first, each group keeping its order.
         local here, rest = new(), new()
         for _, quest in ipairs(quests) do tinsert(quest.inCurrentZone and here or rest, quest) end
         for i, quest in ipairs(here) do quests[i] = quest end
         for i, quest in ipairs(rest) do quests[#here + i] = quest end
         del(here)
         del(rest)
      end
      GroupCompleted(quests, profile.completedSort)
   end
   return result
end

-- Puts the timed section on top of all, and the focused / tracked and the
-- completed section above or below the zones, as the profile says
-- (together, the focused one comes first), and the travel section after
-- the completed one.
local function PlaceSpecialSections(sections, profile, timed)
   local pinned, completed, travel
   local zones = new()
   for _, section in ipairs(sections) do
      if section.isPinned then
         pinned = section
      elseif section.foldKey == mod.COMPLETED_FOLD_KEY then
         completed = section
      elseif section.foldKey == mod.TRAVEL_FOLD_KEY then
         travel = section
      else
         tinsert(zones, section)
      end
   end
   local completedBottom = profile.completedPosition == "bottom"
      or (profile.completedPosition == nil and profile.completedSort == "last")
   local travelBottom = profile.travelPosition ~= "top"
   -- For separate sections: below Quests instead of above.
   if completed then completed.placeBottom = completedBottom end
   if travel then travel.placeBottom = travelBottom end
   local result = new()
   if timed then tinsert(result, timed) end
   if pinned and profile.focusedPosition ~= "bottom" then tinsert(result, pinned) end
   if completed and not completedBottom then tinsert(result, completed) end
   if travel and not travelBottom then tinsert(result, travel) end
   for _, section in ipairs(zones) do tinsert(result, section) end
   if pinned and profile.focusedPosition == "bottom" then tinsert(result, pinned) end
   if completed and completedBottom then tinsert(result, completed) end
   if travel and travelBottom then tinsert(result, travel) end
   del(sections)
   del(zones)
   return result
end

-- Sorts zone sections by the zone sort order (current zone first if set).
-- ranks: the distance sort's memory of the previous order. Returns the
-- sorted list (may be a new table).
local function SortZones(sections, profile, ranks)
   local zoneSorter = zoneSorters[profile.zoneSort] or zoneSorters.level
   if profile.zoneSort == "distance" then
      if profile.currentZoneFirst then
         -- Current zone (and its sub-areas) first, then the rest by distance.
         local current, others = new(), new()
         for _, section in ipairs(sections) do
            tinsert(section.zoneRank > 0 and current or others, section)
         end
         sort(current, CurrentZoneFirstByLevel)
         SortByDistance(others, ZoneKey, ranks, zoneSorters.level)
         for _, section in ipairs(others) do
            tinsert(current, section)
         end
         del(others)
         del(sections)
         sections = current
      else
         SortByDistance(sections, ZoneKey, ranks, zoneSorters.level)
      end
   elseif profile.currentZoneFirst then
      activeZoneSorter = zoneSorter
      sort(sections, CurrentZoneFirst)
   else
      sort(sections, zoneSorter)
   end
   return sections
end

-- Distance sort memory of the zones inside the separate sections, per section.
local subZoneRanks = {}

-- Separate sections (profile.separateSections): Completed and Travel are
-- shown next to Quests instead of inside it, with their quests grouped by
-- zone again. Moves section.quests into section.zones (sub-sections, like
-- zone sections); with zone headers always hidden, one unnamed group in the
-- section's own order.
local function SplitIntoZones(section, profile)
   local quests = section.quests
   section.quests = nil
   section.numQuests = #quests
   section.isTopLevel = true
   local zones = new()
   if profile.hideZoneHeaders == true then
      local zone = new()
      zone.quests = quests
      zone.zoneRank = 0
      tinsert(zones, zone)
      section.zones = zones
      return
   end
   local byName = new()
   for _, quest in ipairs(quests) do
      local name = quest.zoneName or L["Miscellaneous"]
      local zone = byName[name]
      if not zone then
         zone = new()
         zone.name = name
         zone.foldKey = section.foldKey .. "\001" .. name
         zone.isCurrent = quest.zoneIsCurrent or false
         zone.zoneRank = quest.zoneRank or 0
         zone.minLevel = math.huge
         zone.quests = new()
         byName[name] = zone
         tinsert(zones, zone)
      end
      tinsert(zone.quests, quest)
      if quest.inCurrentZone then zone.hasLocalQuests = true end
      if quest.level < zone.minLevel then zone.minLevel = quest.level end
      if quest.distance and (not zone.distance or quest.distance < zone.distance) then
         zone.distance = quest.distance
      end
   end
   del(byName)
   del(quests)
   local ranks = subZoneRanks[section.foldKey]
   if not ranks then
      ranks = {}
      subZoneRanks[section.foldKey] = ranks
   end
   section.zones = SortZones(zones, profile, ranks)
end

-- Sorts the zones and their quests, pins the focused / tracked quests and
-- separates the completed ones, as the profile says. Also used by the setup
-- wizard's preview with made-up quests.
local function ArrangeSections(sections, profile)
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

   sections = SortZones(sections, profile, zoneRanks)

   -- Timed quests first, so a timed focused quest goes there too.
   local timed
   if profile.timedSection then
      local quests
      sections, quests = TakeQuests(sections, IsTimed)
      if #quests > 0 then
         sort(quests, function(a, b) return a.timerEnd < b.timerEnd end)  -- least time left first
         timed = NewSpecialSection(L["Timed"], mod.TIMED_FOLD_KEY, quests)
      else
         del(quests)
      end
   end
   local pinMode = profile.focusedSection == "focused" or profile.focusedSection == "tracked"
   if pinMode then
      -- Showing only watched quests, Tracked would take every quest out of
      -- its zone: only the focused quest goes on top then.
      local includeWatched = profile.focusedSection == "tracked" and profile.showAllQuests
      sections = PinFocusedQuests(sections, includeWatched, profile.completedSort)
   end
   -- Before the completed section, which would take them too.
   if profile.travelSection then
      sections = SeparateTravelQuests(sections, profile)
   end
   if profile.completedSection == "all" or profile.completedSection == "current" then
      sections = SeparateCompletedQuests(sections, profile, profile.completedSection == "current")
   end
   if profile.hideZoneHeaders == true then
      sections = MergeZones(sections, profile)
   end
   sections = PlaceSpecialSections(sections, profile, timed)
   for _, section in ipairs(sections) do
      local numComplete = 0
      for _, quest in ipairs(section.quests) do
         if quest.isComplete then numComplete = numComplete + 1 end
      end
      section.numComplete = numComplete
      if profile.separateSections and (section.foldKey == mod.COMPLETED_FOLD_KEY or section.foldKey == mod.TRAVEL_FOLD_KEY) then
         SplitIntoZones(section, profile)
      end
   end
   return sections
end
mod.ArrangeSections = ArrangeSections

function mod:CollectQuests()
   local profile = self.db.profile
   mod.ResetBagQuestItems()  -- bags may have changed
   wipe(questComplete)
   RefreshQuestTimers()
   local zoneNames = GetCurrentZoneNames()
   -- In instances, isOnMap can be true for quests of the surrounding zone.
   local useOnMap = not IsInInstance()
   local pois = profile.showDirection and self:CollectQuestPOIs() or nil
   local sections, byName = new(), new()
   local header = L["Miscellaneous"]
   local numQuests, numShown = 0, 0
   -- With a section on top, the focused quest is always shown (in it).
   local pinMode = profile.focusedSection == "focused" or profile.focusedSection == "tracked"
   local focusedID = pinMode and self:GetFocusedQuestID() or nil
   -- The "All" completed section lists every completed quest, whatever the filters.
   local allCompleted = profile.completedSection == "all"
   local filterDifficulty = profile.hideRedQuests or profile.hideGrayQuests

   for i = 1, C_QuestLog.GetNumQuestLogEntries() do
      local info = C_QuestLog.GetInfo(i)
      if info then
         if info.isHeader then
            header = info.title
         elseif ShouldTrackQuest(info) then
            questHeaders[info.questID] = header
            questComplete[info.questID] = C_QuestLog.IsComplete(info.questID) or false
            numQuests = numQuests + 1
            local zoneRank = GetZoneRank(header, zoneNames)
            local isCurrentZone = zoneRank > 0
            -- Objectives here although the quest is filed elsewhere.
            local objectivesHere = not isCurrentZone and useOnMap
               and (info.isOnMap or (not questComplete[info.questID] and HasObjectiveInZone(info.questID, zoneNames)))
            local visible = true
            if profile.onlyCurrentZone and not (isCurrentZone or objectivesHere) then
               visible = false
            end
            if visible and not profile.showAllQuests and C_QuestLog.GetQuestWatchType(info.questID) == nil then
               visible = false
            end
            if visible and filterDifficulty then
               local level = (info.difficultyLevel and info.difficultyLevel > 0) and info.difficultyLevel or info.level
               if mod:IsDifficultyFiltered(mod:GetQuestDifficulty(info.questID, level, info.isScaling), profile) then
                  visible = false
               end
            end
            if info.questID == focusedID or (allCompleted and C_QuestLog.IsComplete(info.questID))
               or (profile.timedSection and HasTimeLimit(info.questID)) then
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
               quest.inCurrentZone = isCurrentZone or objectivesHere or false
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

   sections = ArrangeSections(sections, profile)

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
      objective.timerTotal = info.duration
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
   local name, stage, numStages, _, _, _, _, _, _, scenarioType = C_Scenario.GetInfo()
   if not numStages or numStages == 0 then return nil end
   local scenario = new()
   scenario.name, scenario.stage, scenario.numStages = name, stage, numStages
   -- Section header, as Blizzard's: "Dungeon" for dungeons (the stage line
   -- shows the name), "Proving Grounds", else the scenario name.
   if scenarioType and scenarioType == LE_SCENARIO_TYPE_USE_DUNGEON_DISPLAY and TRACKER_HEADER_DUNGEON then
      scenario.header = TRACKER_HEADER_DUNGEON
   elseif scenarioType and scenarioType == LE_SCENARIO_TYPE_PROVING_GROUNDS and TRACKER_HEADER_PROVINGGROUNDS then
      scenario.header = TRACKER_HEADER_PROVINGGROUNDS
   end
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
-- Dungeon bosses (Forever): Retail shows dungeons as a scenario with a
-- "Boss defeated" line per boss; Forever has no scenario there. The boss
-- list comes from the instance lock info, which doesn't flag kills in
-- normal dungeons, so kills are recorded from ENCOUNTER_END / BOSS_KILL.
----------------------------------------------------------------

-- Runs are kept per instance ID until the instance is reset ("X has been
-- reset."). Resets that aren't seen (another group leader's, a new group's
-- copy) end a run too: a run not seen for this long is from an earlier one;
-- walking back in after all bosses died starts a new one; and so does a
-- boss dying again (RecordBossKill). Like the Dungeon Journal addon.
local DUNGEON_RUN_EXPIRE = 90 * 60

-- Run record: { name, time (last activity), bosses = { [bossName] = true },
-- names = { zone names }, tail, started, finished (time()), xp, turnInXP,
-- quests = { [questID] = xp }, questsBefore = { [questID] = true }, money,
-- deaths }. Stored in db.char.dungeonKills.
local function DungeonRun(self, instanceID, name)
   local all = self.db.char.dungeonKills
   local run = all[instanceID]
   if not run or time() - (run.time or 0) > DUNGEON_RUN_EXPIRE then
      run = { time = time(), bosses = {}, quests = {}, questsBefore = {} }
      -- Quests already complete on entering don't count for the run.
      for questID, complete in pairs(questComplete) do
         if complete then run.questsBefore[questID] = true end
      end
      all[instanceID] = run
   end
   run.name, run.instanceID = name, instanceID
   if not run.names then
      -- What this dungeon's quest log header can be called (see GetZoneRank).
      run.names = {}
      for zone in pairs(GetCurrentZoneNames()) do tinsert(run.names, zone) end
      run.tail = instanceTail
   end
   return run
end

-- Dungeons whose wings share one instance (and one boss list): each wing
-- is its own dungeon. Boss and room names are the English ones; on other
-- clients the bosses don't match and the whole list shows.
local DUNGEON_WINGS = {
   [189] = {  -- Scarlet Monastery
      { title = L["Scarlet Monastery: Graveyard"],
        bosses = { "Interrogator Vishas", "Azshir the Sleepless", "Fallen Champion", "Ironspine", "Bloodmage Thalnos" },
        maps = { 302 },
        rooms = { "Chamber of Atonement", "Forlorn Cloister", "Honor's Tomb" } },
      { title = L["Scarlet Monastery: Library"],
        bosses = { "Houndmaster Loksey", "Arcanist Doan" },
        maps = { 303 },
        rooms = { "Huntsman's Cloister", "Gallery of Treasures", "Athenaeum" } },
      { title = L["Scarlet Monastery: Armory"],
        bosses = { "Herod" },
        maps = { 304 },
        rooms = { "Training Grounds", "Footman's Armory", "Crusader's Armory", "Hall of Champions" } },
      { title = L["Scarlet Monastery: Cathedral"],
        bosses = { "High Inquisitor Fairbanks", "Scarlet Commander Mograine", "High Inquisitor Whitemane" },
        -- Not in Forever's lock info: listed before Whitemane, kill seen
        -- in the combat log (or implied by hers: he dies first).
        extra = { ["Scarlet Commander Mograine"] = "High Inquisitor Whitemane" },
        maps = { 305 },
        rooms = { "Chapel Gardens", "Crusader's Chapel" } },
   },
   [429] = {  -- Dire Maul
      { title = L["Dire Maul: East"],
        bosses = { "Pusillin", "Zevrim Thornhoof", "Hydrospawn", "Lethtendris", "Alzzin the Wildshaper" } },
      { title = L["Dire Maul: West"],
        bosses = { "Tendris Warpwood", "Illyanna Ravenoak", "Tsu'zee", "Magister Kalendris", "Immol'thar",
                   "Lord Hel'nurath", "Prince Tortheldrin" } },
      { title = L["Dire Maul: North"],
        bosses = { "Guard Mol'dar", "Stomper Kreeg", "Guard Fengus", "Guard Slip'kik", "Captain Kromcrush",
                   "Cho'Rush the Observer", "King Gordok" } },
   },
   [329] = {  -- Stratholme
      { title = L["Stratholme: Main Gate"],
        bosses = { "Skul", "Hearthsinger Forresten", "The Unforgiven", "Timmy the Cruel", "Malor the Zealous",
                   "Postmaster Malown", "Cannon Master Willey", "Archivist Galford", "Balnazzar" } },
      { title = L["Stratholme: Service Entrance"],
        bosses = { "Stonespine", "Magistrate Barthilas", "Nerub'enkan", "Baroness Anastari", "Maleki the Pallid",
                   "Ramstein the Gorger", "Baron Rivendare" } },
   },
   [229] = {  -- Blackrock Spire
      { title = L["Lower Blackrock Spire"],
        bosses = { "Spirestone Butcher", "Spirestone Battle Lord", "Spirestone Lord Magus", "Highlord Omokk",
                   "Shadow Hunter Vosh'gajin", "War Master Voone", "Mother Smolderweb", "Crystal Fang",
                   "Urok Doomhowl", "Bannok Grimaxe", "Quartermaster Zigris", "Halycon", "Gizrul the Slavener",
                   "Ghok Bashguud", "Overlord Wyrmthalak" } },
      { title = L["Upper Blackrock Spire"],
        bosses = { "Pyroguard Emberseer", "Solakar Flamewreath", "Jed Runewatcher", "Goraluk Anvilcrack", "Gyth",
                   "Warchief Rend Blackhand", "The Beast", "Lord Valthalak", "General Drakkisath" } },
   },
}

-- Wings a group can do in one run (walking through inside, or out one door
-- and in another): crossing over makes it one run of the wings visited.
local CROSSABLE_WINGS = {
   [429] = true,  -- Dire Maul
   [329] = true,  -- Stratholme
}

--- The wing whose bosses are shown: its index, a set of indexes for a run
--- that crossed over, or nil for all of them (not winged, not known yet).
local function ShownWing(run, wings)
   if not wings then return nil end
   if run.crossedWings then return run.crossedWings end
   return run.wingKnown and run.wing or nil
end

--- Whether a boss of bossWing is shown for ShownWing's wing.
local function WingShown(wing, bossWing)
   if not bossWing or not wing then return true end
   if type(wing) == "table" then return wing[bossWing] or false end
   return bossWing == wing
end

-- Lookups built on first use: wingOfBoss[instanceID][boss] and
-- wingOfRoom[instanceID][room:lower()] = wing index.
local wingOfBoss, wingOfRoom, wingOfMap
local function WingLookups()
   if wingOfBoss then return end
   wingOfBoss, wingOfRoom, wingOfMap = {}, {}, {}
   for instanceID, wings in pairs(DUNGEON_WINGS) do
      local bosses, rooms, maps = {}, {}, {}
      for index, wing in ipairs(wings) do
         for _, boss in ipairs(wing.bosses) do bosses[boss] = index end
         for _, room in ipairs(wing.rooms or EMPTY) do rooms[room:lower()] = index end
         for _, mapID in ipairs(wing.maps or EMPTY) do maps[mapID] = index end
      end
      wingOfBoss[instanceID], wingOfRoom[instanceID], wingOfMap[instanceID] = bosses, rooms, maps
   end
end

-- Bosses missing from the lock info, by name.
local extraBosses = {}
for _, wings in pairs(DUNGEON_WINGS) do
   for _, wing in ipairs(wings) do
      for boss in pairs(wing.extra or EMPTY) do extraBosses[boss] = true end
   end
end

--- Records the death of a boss missing from the lock info (combat log).
function mod:OnRunUnitDied(destName)
   if destName and not issecretvalue(destName) and extraBosses[destName] then
      self:RecordBossKill(destName)
   end
end

--- Wing index of a boss in a winged dungeon, or nil.
local function BossWing(instanceID, boss)
   if not DUNGEON_WINGS[instanceID] then return end
   WingLookups()
   return wingOfBoss[instanceID][boss]
end

-- The wings' doors outside: inside the game names neither room nor map of a
-- wing at first, but the portal walked through tells it. Zone map, its
-- size in yards (w, h) and each portal's spot and wing index (classic
-- AreaTrigger positions, as ForeverDungeonRoutes has them).
local WING_PORTALS = {
   [189] = { map = 1420, w = 4518.7499, h = 3012.4998,  -- Tirisfal Glades
      { x = 0.848, y = 0.3031, wing = 1 },   -- Graveyard
      { x = 0.8529, y = 0.3028, wing = 4 },  -- Cathedral
      { x = 0.857, y = 0.3185, wing = 3 },   -- Armory
      { x = 0.8538, y = 0.3246, wing = 2 },  -- Library
   },
   [429] = { map = 1444, w = 6949.9998, h = 4633.333,  -- Feralas
      { x = 0.6486, y = 0.2943, wing = 1 },  -- East
      { x = 0.672, y = 0.3485, wing = 1 },
      { x = 0.7651, y = 0.3586, wing = 1 },
      { x = 0.6031, y = 0.3175, wing = 2 },  -- West
      { x = 0.6032, y = 0.2968, wing = 2 },
      { x = 0.6292, y = 0.2491, wing = 3 },  -- North
   },
}
local PORTAL_NEAR, PORTAL_FRESH = 15, 120  -- yards, seconds
local outside  -- { map, x, y, t }: last spot on a zone map with wing portals

--- Notes where the player stands outside (before loading screens and
--- now and then), for telling the wing by the door used.
function mod:NoteOutside()
   if IsInInstance() or not (C_Map and C_Map.GetPlayerMapPosition) then return end
   for _, portals in pairs(WING_PORTALS) do
      local pos = C_Map.GetPlayerMapPosition(portals.map, "player")
      local x, y = pos and pos.x, pos and pos.y
      if type(x) == "number" and type(y) == "number" and not issecretvalue(x) and not issecretvalue(y)
         and (x > 0 or y > 0) then
         outside = { map = portals.map, x = x, y = y, t = time() }
         return
      end
   end
end

-- Wing index of the portal just walked through, or nil. Used once.
local function PortalWing(instanceID)
   local portals = WING_PORTALS[instanceID]
   local seen = outside
   outside = nil
   if not (portals and seen) or seen.map ~= portals.map or time() - seen.t > PORTAL_FRESH then return end
   local best, bestDist
   for _, portal in ipairs(portals) do
      local d = math.sqrt(((seen.x - portal.x) * portals.w) ^ 2 + ((seen.y - portal.y) * portals.h) ^ 2)
      if not bestDist or d < bestDist then best, bestDist = portal.wing, d end
   end
   if bestDist and bestDist <= PORTAL_NEAR then return best end
end

-- Wing index from the room the player stands in, or nil.
local function RoomWing(instanceID)
   if not DUNGEON_WINGS[instanceID] then return end
   WingLookups()
   local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
   if mapID and not issecretvalue(mapID) and wingOfMap[instanceID][mapID] then
      return wingOfMap[instanceID][mapID]
   end
   local rooms = wingOfRoom[instanceID]
   for _, text in ipairs({ GetSubZoneText and GetSubZoneText(), GetMinimapZoneText and GetMinimapZoneText() }) do
      local wing = type(text) == "string" and not issecretvalue(text) and rooms[text:lower()]
      if wing then return wing end
   end
end

local function InDungeon()
   if not mod.IS_FOREVER then return end
   local name, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
   if instanceType == "party" or instanceType == "raid" then return instanceID, name end
end

-- The run of the dungeon the player is in, or nil.
local function CurrentRun(self)
   local instanceID, name = InDungeon()
   if not instanceID then return end
   local run = DungeonRun(self, instanceID, name)
   run.time = time()
   return run
end

function mod:RecordBossKill(boss)
   if not boss or issecretvalue(boss) then return end
   local run = CurrentRun(self)
   if not run then return end
   run.killedAt = run.killedAt or {}
   -- Killed before (not this kill's other event): the dungeon was reset, a
   -- new run since walking in.
   if run.bosses[boss] and time() - (run.killedAt[boss] or 0) > 60 then
      self:StartRunOver(run)
   end
   run.bosses[boss] = true
   run.killedAt[boss] = time()
   local wing = BossWing(run.instanceID, boss)
   if wing then self:SetRunWing(run, wing) end
   self:RequestUpdate()
end

local resetPattern
--- Clears the recorded run of the instance a system message says was reset.
function mod:CheckInstanceReset(msg)
   -- Chat messages can be secret (Forever, in instances).
   if not msg or issecretvalue(msg) or not INSTANCE_RESET_SUCCESS then return end
   if not resetPattern then
      resetPattern = "^" .. INSTANCE_RESET_SUCCESS:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0"):gsub("%%s", "(.+)") .. "$"
   end
   local name = msg:match(resetPattern)
   if not name then return end
   local all = self.db.char.dungeonKills
   for instanceID, run in pairs(all) do
      if run.name == name then all[instanceID] = nil end
   end
   self:RequestUpdate()
end

----------------------------------------------------------------
-- Dungeon run stats (Forever): XP, quest XP, money, deaths and time of
-- the current run, like the Dungeon Journal addon's run log (simplified:
-- XP is the change of UnitXP while inside).
----------------------------------------------------------------

local lastXP, lastXPMax, lastLevel
local lastMoney

-- Stats show as part of the Dungeon section: off with it. They are always
-- recorded (Forever), so turning them on mid-run shows the whole run.
local function StatsOn(self)
   local profile = self.db.profile
   return mod.IS_FOREVER and profile.showDungeonBosses and profile.showDungeonStats
end

local function Tracking()
   return mod.IS_FOREVER
end

-- "X dies." / "X dies, you gain N experience." / "You have slain X!": kills
-- of the bosses missing from the lock info. (Forever closes the combat log
-- to addons.)
local deathPatterns
function mod:OnRunDeathMessage(msg)
   if not msg or issecretvalue(msg) or not Tracking() or not IsInInstance() then return end
   if not deathPatterns then
      deathPatterns = {}
      for _, text in ipairs({ UNITDIESOTHER, SELFKILLOTHER, COMBATLOG_XPGAIN_FIRSTPERSON,
                              COMBATLOG_XPGAIN_EXHAUSTION1, COMBATLOG_XPGAIN_EXHAUSTION2 }) do
         if type(text) == "string" then
            -- Only the name is captured: "%s" first, the rest matched loosely.
            local pattern = "^" .. text:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0")
               :gsub("%%s", "(.+)", 1):gsub("%%s", ".+"):gsub("%%d", "[%%d,%%.]+")
               :gsub("%%%.1f", "[%%d,%%.]+")
            tinsert(deathPatterns, pattern)
         end
      end
   end
   for _, pattern in ipairs(deathPatterns) do
      local name = msg:match(pattern)
      if name then
         self:OnRunUnitDied(name)
         return
      end
   end
end

--- Baselines for the XP and money deltas; call on entering the world.
function mod:ResetRunBaselines()
   lastXP, lastXPMax, lastLevel = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
   lastMoney = GetMoney()
end

function mod:OnRunXP()
   local xp, max, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
   local delta = 0
   if lastXP then
      if level > lastLevel then
         delta = (lastXPMax - lastXP) + xp  -- one level up
      elseif level == lastLevel then
         delta = xp - lastXP
      end
   end
   lastXP, lastXPMax, lastLevel = xp, max, level
   if delta <= 0 or not Tracking() then return end
   local run = CurrentRun(self)
   if not run then return end
   run.xp = (run.xp or 0) + delta
   self:RequestUpdate()
end

function mod:OnRunMoney()
   local money = GetMoney()
   local before = lastMoney
   lastMoney = money
   -- Gains only: buying or repairing doesn't take it back. Selling at a
   -- vendor isn't counted, the loot's vendor value already is.
   if not before or money <= before or not Tracking() then return end
   if MerchantFrame and MerchantFrame:IsShown() then return end
   local run = CurrentRun(self)
   if not run then return end
   run.money = (run.money or 0) + (money - before)
   self:RequestUpdate()
end

-- "You receive loot: [item]x2." (own loot only, not quest rewards).
local lootPatterns
local function LootPattern(text)
   return "^" .. text:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0"):gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)") .. "$"
end

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo

local function AddItemValue(self, run, link, count)
   local price = select(11, GetItemInfo(link))
   if price then
      if price > 0 then
         run.itemValue = (run.itemValue or 0) + price * count
         self:RequestUpdate()
      end
   elseif Item and Item.CreateFromItemLink then
      -- Not cached yet: count it once the item data is in.
      Item:CreateFromItemLink(link):ContinueOnItemLoad(function()
         local loaded = select(11, GetItemInfo(link))
         if loaded and loaded > 0 then
            run.itemValue = (run.itemValue or 0) + loaded * count
            self:RequestUpdate()
         end
      end)
   end
end

--- Vendor value of the items looted in the run (added to the money).
function mod:OnRunLoot(msg)
   if not msg or issecretvalue(msg) or not Tracking() or not LOOT_ITEM_SELF then return end
   if not lootPatterns then
      lootPatterns = {}
      if LOOT_ITEM_SELF_MULTIPLE then tinsert(lootPatterns, LootPattern(LOOT_ITEM_SELF_MULTIPLE)) end
      tinsert(lootPatterns, LootPattern(LOOT_ITEM_SELF))
   end
   for _, pattern in ipairs(lootPatterns) do
      local link, count = msg:match(pattern)
      if link then
         local run = CurrentRun(self)
         if run then AddItemValue(self, run, link, tonumber(count) or 1) end
         return
      end
   end
end

function mod:OnRunDeath()
   local run = Tracking() and CurrentRun(self)
   if not run then return end
   run.deaths = (run.deaths or 0) + 1
   self:RequestUpdate()
end

--- The run's clock starts with the first fight inside.
function mod:OnRunCombat()
   local run = Tracking() and CurrentRun(self)
   if not run then return end
   if run.entry and not run.entry.combat then run.entry.combat = time() end
   if not run.started then
      run.started = time()
      self:RequestUpdate()
   end
end

-- Winged dungeons: the stats are the current wing's. Walking in starts a
-- visit of a wing not known yet (shown with all bosses) and notes the
-- stats so far; once the wing is known (room name or a boss kill) and it
-- isn't the run's last one, the stats start over from that note.
local RUN_COUNTERS = { "xp", "turnInXP", "money", "itemValue", "deaths" }

--- Called on walking into an instance (not on /reload).
local enteredWing  -- { instanceID, wing } from the door, applied on collect
-- Name of the group's leader (the player when alone), or nil.
local function GroupLeader()
   if not IsInGroup() then return UnitName("player") end
   local prefix, count = "party", GetNumSubgroupMembers()
   if IsInRaid() then prefix, count = "raid", GetNumGroupMembers() end
   if UnitIsGroupLeader("player") then return UnitName("player") end
   for i = 1, count do
      local unit = prefix .. i
      if UnitIsGroupLeader(unit) then
         local name, realm = UnitName(unit)
         if name and not issecretvalue(name) then
            return realm and realm ~= "" and not issecretvalue(realm) and (name .. "-" .. realm) or name
         end
      end
   end
end

-- Instance copy (see NoteRunCopy) not seen yet since walking in.
local copyUnknown = false

function mod:OnRunEnter()
   local instanceID = InDungeon()
   copyUnknown = instanceID ~= nil
   if not instanceID then return end
   if DUNGEON_WINGS[instanceID] then
      local wing = PortalWing(instanceID)
      enteredWing = wing and { instanceID = instanceID, wing = wing } or nil
   end
   -- A new run has nothing to note (and is made once the quest log is in).
   local all = self.db.char.dungeonKills
   local run = all[instanceID]
   if not run or time() - (run.time or 0) > DUNGEON_RUN_EXPIRE then return end
   if run.finished and (not DUNGEON_WINGS[instanceID] or run.crossedWings) then
      -- Done: back in is the next run. (Winged: per wing, by SetRunWing;
      -- a run of all wings is done as a whole.)
      all[instanceID] = nil
      return
   end
   local leader = GroupLeader()
   if run.leader and leader and run.leader ~= leader then
      -- Another leader's instance (a new group): the next run.
      all[instanceID] = nil
      return
   end
   local entry = {}
   for _, key in ipairs(RUN_COUNTERS) do entry[key] = run[key] or 0 end
   entry.quests = {}
   for questID in pairs(run.quests or EMPTY) do entry.quests[questID] = true end
   run.entry = entry
   if DUNGEON_WINGS[instanceID] then run.wingKnown = false end
end

-- Stats start over from walking in (another wing or instance copy).
local function StartOver(run)
   local entry = run.entry
   if not entry then
      -- Nothing noted on walking in: all from now.
      entry = { quests = {} }
      for _, key in ipairs(RUN_COUNTERS) do entry[key] = run[key] or 0 end
      for questID in pairs(run.quests or EMPTY) do entry.quests[questID] = true end
      run.entry = entry
   end
   for _, key in ipairs(RUN_COUNTERS) do
      run[key] = math.max(0, (run[key] or 0) - (entry[key] or 0))
   end
   run.quests, run.questsBefore = run.quests or {}, run.questsBefore or {}
   for questID in pairs(entry.quests) do
      run.quests[questID] = nil
      run.questsBefore[questID] = true
   end
   run.started, run.finished = entry.combat, nil
   for key in pairs(entry) do entry[key] = nil end
   entry.quests = {}
   for _, key in ipairs(RUN_COUNTERS) do entry[key] = 0 end
end

--- /mqt newrun, the Dungeon header menu: the current dungeon's run starts
--- over from now (for a reset or new group not seen). The wing stays.
function mod:NewDungeonRun()
   local instanceID = InDungeon()
   if not instanceID then return false end
   local all = self.db.char.dungeonKills
   local run = all[instanceID]
   if run and run.wingKnown then enteredWing = { instanceID = instanceID, wing = run.wing } end
   all[instanceID] = nil
   self:RequestUpdate()
   return true
end

--- Whether the player is in a Forever dungeon (with a run to start over).
function mod:InForeverDungeon()
   return InDungeon() ~= nil
end

--- New run from walking in on: no kills, stats since then.
function mod:StartRunOver(run)
   StartOver(run)
   run.crossedWings = nil
   wipe(run.bosses)
   if run.killedAt then wipe(run.killedAt) end
   self:RequestUpdate()
end

function mod:SetRunWing(run, wing)
   local crossed = run.crossedWings
   if crossed then
      -- Already crossed over: another wing joins the run.
      if not crossed[wing] then
         crossed[wing] = true
         run.finished = nil
      end
      run.wing, run.wingKnown = wing, true
      self:RequestUpdate()
      return
   end
   if run.wingKnown and run.wing == wing then return end
   if run.wing and run.wing ~= wing then
      if CROSSABLE_WINGS[run.instanceID] and run.started then
         -- Crossed over into another wing mid-run: one run of the wings
         -- visited, their bosses shown.
         run.crossedWings = { [run.wing] = true, [wing] = true }
         run.wing, run.wingKnown, run.finished = wing, true, nil
         self:RequestUpdate()
         return
      end
      StartOver(run)
   elseif run.wing == wing and run.finished then
      -- Walked back into a finished wing: the next run.
      self:StartRunOver(run)
   end
   run.wing, run.wingKnown = wing, true
   self:RequestUpdate()
end

--- Whether the instance copy is still to be found (watch mob GUIDs).
function mod:RunCopyUnknown()
   return copyUnknown
end

--- Notes the instance copy from a mob's GUID
--- (Creature-0-server-map-zoneUID-npcID-spawnUID). Another group's copy of
--- the same dungeon (same instance ID) is a new run: no kills, stats from
--- walking in.
function mod:NoteRunCopy(guid)
   if not copyUnknown or not guid or issecretvalue(guid) then return end
   local kind, _, server, _, zone = strsplit("-", guid)
   if kind ~= "Creature" and kind ~= "Vehicle" or not zone then return end
   local run = CurrentRun(self)
   if not run then return end
   copyUnknown = false
   local copy = server .. ":" .. zone
   if run.copy and run.copy ~= copy then self:StartRunOver(run) end
   run.copy = copy
   self:RequestUpdate()
end

local function RunMatchesHeader(run, header)
   if not header then return false end
   for _, zone in ipairs(run.names or EMPTY) do
      if zone == header then return true end
   end
   local tail = run.tail and LastWord(header)
   return tail and tail:lower() == run.tail or false
end

--- Quest turned in inside: its XP is taken out of the kill XP (the UnitXP
--- change includes it). Dungeon quests count as Quest XP once complete.
function mod:OnRunQuestTurnedIn(questID, xp)
   if not Tracking() or not xp or xp <= 0 then return end
   local run = CurrentRun(self)
   if run then
      run.turnInXP = (run.turnInXP or 0) + xp
   end
end

-- Quest XP: the reward of this dungeon's quests completed during the run,
-- counted when complete (kept after turning them in).
local function UpdateRunQuests(run)
   run.quests = run.quests or {}
   run.questsBefore = run.questsBefore or {}
   local total = 0
   for questID, complete in pairs(questComplete) do
      if complete and not run.quests[questID] and not run.questsBefore[questID]
         and RunMatchesHeader(run, questHeaders[questID]) then
         run.quests[questID] = GetQuestLogRewardXP and GetQuestLogRewardXP(questID) or 0
      end
   end
   for _, xp in pairs(run.quests) do total = total + xp end
   return total
end

local SEPARATOR = "  \194\183  "  -- " · " between stats on a line

local function Number(n)
   return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

-- Joins parts into a stats line ({ text, elapsedFrom }); a part with "%s"
-- is the run time, filled in (and kept ticking) by the tracker.
local function AddStatLine(dungeon, parts, elapsedFrom)
   if #parts == 0 then
      del(parts)
      return
   end
   local line = new()
   line.text = table.concat(parts, SEPARATOR)
   line.elapsedFrom = elapsedFrom
   del(parts)
   tinsert(dungeon.stats, line)
end

local function Coins(copper)
   return GetCoinTextureString and GetCoinTextureString(copper) or GetMoneyString(copper)
end

-- Lines below the bosses: XP, money (coins and items' vendor value), then
-- time and deaths.
local function AddRunStats(self, dungeon, run, profile, stoppedAt)
   dungeon.stats = new()
   local parts = new()
   local killXP = math.max(0, (run.xp or 0) - (run.turnInXP or 0))
   if profile.dungeonStatsXP then
      tinsert(parts, format(L["XP: %s"], Number(killXP)))
   end
   local questXP = UpdateRunQuests(run)
   -- Totals for the per hour tooltip.
   dungeon.runKillXP, dungeon.runQuestXP = killXP, questXP
   dungeon.runCoins, dungeon.runItems = run.money or 0, run.itemValue or 0
   dungeon.runStarted, dungeon.runFinished = run.started, run.finished or stoppedAt
   if profile.dungeonStatsQuestXP and questXP > 0 then
      tinsert(parts, format(L["Quest XP: %s"], Number(questXP)))
   end
   AddStatLine(dungeon, parts)

   parts = new()
   if profile.dungeonStatsMoney then
      tinsert(parts, format(L["Coins: %s"], Coins(run.money or 0)))
      tinsert(parts, format(L["Items: %s"], Coins(run.itemValue or 0)))
   end
   AddStatLine(dungeon, parts)

   parts = new()
   local elapsedFrom
   if profile.dungeonStatsTime and run.started then
      local ended = run.finished or stoppedAt
      if ended then
         tinsert(parts, format(L["Time: %s"], mod.FormatClock(math.max(0, ended - run.started))))
      else
         -- A format template: the tracker fills in the time and keeps it
         -- ticking (other parts escaped).
         tinsert(parts, L["Time: %s"])
         elapsedFrom = run.started
      end
   end
   if profile.dungeonStatsDeaths then
      local deaths = format(L["Deaths: %d"], run.deaths or 0)
      tinsert(parts, elapsedFrom and deaths:gsub("%%", "%%%%") or deaths)
   end
   AddStatLine(dungeon, parts, elapsedFrom)
end

-- Calls fn(boss, killed) for each boss of the lock (of the current wing in
-- a winged dungeon) and the wing's extra bosses, in order.
local function ForEachBoss(encounters, run, wing, wingInfo, fn)
   local extra = wingInfo and wingInfo.extra
   local shown = extra and new()
   for _, encounter in ipairs(encounters) do
      local boss, isKilled = encounter[1], encounter[2]
      local bossWing = boss and wing and BossWing(run.instanceID, boss)
      if boss and WingShown(wing, bossWing) then
         local killed = isKilled or run.bosses[boss] or false
         for name, before in pairs(extra or EMPTY) do
            if before == boss and not shown[name] then
               shown[name] = true
               fn(name, killed or run.bosses[name] or false)
            end
         end
         fn(boss, killed)
      end
   end
   for name in pairs(extra or EMPTY) do
      if not shown[name] then fn(name, run.bosses[name] or false) end
   end
   if shown then del(shown) end
end

-- The dungeon last seen inside: { instanceID, name, encounters = { { boss,
-- killed }, ... }, left = time() }. Shown for a while after leaving, with
-- its run summary printed.
local LINGER_TIME = 60
local lastDungeon

-- The lock's bosses now, kept for after leaving.
local function SaveEncounters(instanceID, name)
   local encounters
   if lastDungeon and lastDungeon.instanceID == instanceID then
      encounters = lastDungeon.encounters
      wipe(encounters)
   else
      encounters = {}
   end
   local numEncounters = GetInstanceLockTimeRemaining and select(3, GetInstanceLockTimeRemaining()) or 0
   for i = 1, numEncounters do
      local boss, _, isKilled = GetInstanceLockTimeRemainingEncounter(i)
      if boss then tinsert(encounters, { boss, isKilled or false }) end
   end
   lastDungeon = { instanceID = instanceID, name = name, encounters = encounters }
   return encounters
end

--- time() the dungeon last seen was left, while it's still shown; nil once
--- closed or after LINGER_TIME. The first call after leaving prints the
--- run summary (when enabled).
function mod:LingeringDungeon()
   if not lastDungeon or lastDungeon.closed then return end
   if not lastDungeon.left then
      lastDungeon.left = time()
      self:ScheduleTimer("RequestUpdate", LINGER_TIME + 1)
      if self.db.profile.dungeonSummaryOnLeave then self:PrintRunSummary() end
   end
   if time() - lastDungeon.left > LINGER_TIME then
      lastDungeon.closed = true
      return
   end
   return lastDungeon.left
end

--- Hides the dungeon kept shown after leaving.
function mod:CloseLingeringDungeon()
   if lastDungeon then lastDungeon.closed = true end
   self:RequestUpdate()
end

--- Whether a run summary can be printed: inside or just left.
function mod:CanPrintRunSummary()
   return lastDungeon ~= nil and self.db.char.dungeonKills[lastDungeon.instanceID] ~= nil
end

-- Money as plain text ("1g 20s 5c") for chat messages (no textures).
local function PlainCoins(copper)
   local gold, silver = math.floor(copper / 10000), math.floor(copper / 100) % 100
   local text = format(L["%dc"], copper % 100)
   if silver > 0 or gold > 0 then text = format(L["%ds"], silver) .. " " .. text end
   if gold > 0 then text = format(L["%dg"], gold) .. " " .. text end
   return text
end

-- Lines of the run summary of the dungeon inside (or last left), nil
-- without one. plain: money as text, for chat messages.
local function RunSummaryLines(self, plain)
   local info = lastDungeon
   local run = info and self.db.char.dungeonKills[info.instanceID]
   if not run then return end
   local money = plain and PlainCoins or Coins
   local wings = DUNGEON_WINGS[info.instanceID]
   local wing = ShownWing(run, wings)
   local wingInfo = wing and wings[wing]
   local name = wingInfo and wingInfo.title or info.name
   local numKilled, numBosses = 0, 0
   ForEachBoss(info.encounters, run, wing, wingInfo, function(_, killed)
      numBosses = numBosses + 1
      if killed then numKilled = numKilled + 1 end
   end)
   local killXP = math.max(0, (run.xp or 0) - (run.turnInXP or 0))
   local questXP = UpdateRunQuests(run)
   local coins, items = run.money or 0, run.itemValue or 0
   local ended = run.finished or info.left or time()
   local seconds = run.started and math.max(0, ended - run.started) or 0
   local lines = {}
   tinsert(lines, format(L["Run summary: %s (%d/%d bosses)"], name, numKilled, numBosses))
   tinsert(lines, format(L["XP: %s"], Number(killXP)) .. SEPARATOR .. format(L["Quest XP: %s"], Number(questXP)))
   tinsert(lines, format(L["Coins: %s"], money(coins)) .. SEPARATOR .. format(L["Items: %s"], money(items)))
   local line = format(L["Deaths: %d"], run.deaths or 0)
   if run.started then line = format(L["Time: %s"], mod.FormatClock(seconds)) .. SEPARATOR .. line end
   tinsert(lines, line)
   if seconds >= 60 then
      local hours = seconds / 3600
      tinsert(lines, format(L["%s XP per hour"], Number(math.floor((killXP + questXP) / hours + 0.5)))
         .. SEPARATOR .. format(L["%s per hour"], money(math.floor((coins + items) / hours + 0.5))))
   end
   return lines
end

--- Prints the run summary to the chat frame.
function mod:PrintRunSummary()
   local lines = RunSummaryLines(self)
   if not lines then
      self:Print(L["Not in a dungeon."])
      return
   end
   self:Print(lines[1])
   for i = 2, #lines do print("  " .. lines[i]) end
end

--- Posts the run summary to the group's chat (instance, raid or party).
function mod:PostRunSummary()
   local lines = RunSummaryLines(self, true)
   local channel = IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT"
      or IsInRaid() and "RAID" or IsInGroup() and "PARTY"
   if not lines or not channel then
      self:PrintRunSummary()
      return
   end
   for _, line in ipairs(lines) do
      SendChatMessage(line, channel)
   end
end

--- Returns a scenario-shaped table (see CollectScenario) for the current
--- Forever dungeon: one "0/1 Boss defeated" objective per boss and the run
--- stats, as enabled. Nil when not in one or both are off.
function mod:CollectDungeon()
   local profile = self.db.profile
   local instanceID, name = InDungeon()
   local left  -- time() the dungeon shown was left, nil inside
   if not instanceID then
      left = self:LingeringDungeon()
      if not left then return end
      instanceID, name = lastDungeon.instanceID, lastDungeon.name
   end
   local run = left and self.db.char.dungeonKills[instanceID] or DungeonRun(self, instanceID, name)
   if not run then return end
   local wings = DUNGEON_WINGS[instanceID]
   if not left then
      -- The leader inside (a leader change in the group keeps the instance).
      run.leader = GroupLeader() or run.leader
   end
   if wings and not left then
      local wing = RoomWing(instanceID)
      if not wing and enteredWing and enteredWing.instanceID == instanceID then
         wing = enteredWing.wing
      end
      enteredWing = nil
      if not wing and not run.wingKnown and not run.wing then
         -- No wing seen in this run yet: the wing of the kills so far, if
         -- they're all in one; kills in more than one crossed over.
         local killWings, count = {}, 0
         for boss in pairs(run.bosses) do
            local bossWing = BossWing(instanceID, boss)
            if bossWing and not killWings[bossWing] then
               killWings[bossWing] = true
               count = count + 1
               wing = bossWing
            end
         end
         if count > 1 then
            wing = nil
            if CROSSABLE_WINGS[instanceID] then run.crossedWings = killWings end
         end
      end
      if wing then self:SetRunWing(run, wing) end
   end
   -- Winged dungeon: only the current wing's bosses (all while not known).
   local wing = ShownWing(run, wings)
   local wingInfo = wing and wings[wing]
   if wingInfo then name = wingInfo.title end
   -- Recorded even while not shown: completed quests and the end of the run.
   UpdateRunQuests(run)
   local encounters
   if left then
      encounters = lastDungeon.encounters
   else
      encounters = SaveEncounters(instanceID, name)
   end
   if not left and run.started and not run.finished and #encounters > 0 and (wing or not wings) then
      local allKilled = true
      ForEachBoss(encounters, run, wing, wingInfo, function(_, killed)
         if not killed then allKilled = false end
      end)
      if allKilled then run.finished = time() end  -- the clock stops
   end
   if not profile.showDungeonBosses then return end
   local showBosses = GetInstanceLockTimeRemaining ~= nil
   local showStats = StatsOn(self)
   local dungeon = new()
   dungeon.name, dungeon.header, dungeon.stageName = name, TRACKER_HEADER_DUNGEON or L["Dungeon"], name
   dungeon.criteria = new()
   dungeon.bonus = new()
   dungeon.numStages, dungeon.stage = 1, 1
   local numKilled, numBosses = 0, 0
   ForEachBoss(encounters, run, wing, wingInfo, function(boss, killed)
      numBosses = numBosses + 1
      if killed then numKilled = numKilled + 1 end
      if showBosses then
         local objective = new()
         objective.text = format("%d/1 %s", killed and 1 or 0, format(L["%s defeated"], boss))
         objective.finished = killed
         objective.alwaysShow = true  -- killed bosses stay listed
         tinsert(dungeon.criteria, objective)
      end
   end)
   local done = numBosses > 0 and numKilled == numBosses
   if done then dungeon.stage = 2 end
   if showStats then
      AddRunStats(self, dungeon, run, profile, left)
   end
   dungeon.closable = left and true or nil
   dungeon.canPostSummary = run.started and true or nil
   if #dungeon.criteria == 0 and not (dungeon.stats and #dungeon.stats > 0) and not done then
      self.deepDel(dungeon)
      return
   end
   return dungeon
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
                  objective.timerTotal = duration
               end
               tinsert(objectives, objective)
               numShown = numShown + 1
            end
         end
         if numCriteria == 0 then
            local objective = new()
            objective.text = description
            objective.failed = IsAchievementEligible and not IsAchievementEligible(achievementID)
            for _, timer in pairs(self.achievementTimers) do
               if timer.achievementID == achievementID then
                  if GetTime() <= timer.timerEnd then
                     objective.timerEnd = timer.timerEnd
                     objective.timerTotal = timer.duration
                  else
                     objective.failed = true
                  end
                  break
               end
            end
            tinsert(objectives, objective)
         end
         tinsert(achievements, achievement)
      end
   end
   return achievements
end
