local L = LibStub("AceLocale-3.0"):GetLocale("MagicQuestTracker")
local mod = LibStub("AceAddon-3.0"):GetAddon("MagicQuestTracker")

local C_QuestLog = C_QuestLog
local C_Map = C_Map
local tinsert, sort = table.insert, table.sort

----------------------------------------------------------------
-- Current zone detection
-- Quest log headers are zone names for most quests, so the current
-- zone is matched against the zone text and the containing zone map
-- (climbing out of micro maps, but not out of instances).
----------------------------------------------------------------

local function GetCurrentZoneNames()
   local names = {}
   local function add(name)
      if name and name ~= "" then
         names[name] = true
      end
   end
   add(GetRealZoneText())
   add(GetZoneText())

   local mapID = C_Map.GetBestMapForUnit("player")
   if IsInInstance() then
      -- Dungeon/raid maps have the outdoor zone as parent; don't climb into it.
      add((GetInstanceInfo()))
      local info = mapID and C_Map.GetMapInfo(mapID)
      add(info and info.name)
      return names
   end
   local zoneType = Enum.UIMapType and Enum.UIMapType.Zone or 3
   while mapID and mapID > 0 do
      local info = C_Map.GetMapInfo(mapID)
      if not info then break end
      add(info.name)
      if info.mapType <= zoneType then break end
      mapID = info.parentMapID
   end
   return names
end
mod.GetCurrentZoneNames = GetCurrentZoneNames

-- 2 = header is the current zone, 1 = header is a sub-area of it
-- (e.g. "Excavation Site: Wetlands" while in Wetlands), 0 = elsewhere.
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
   local objectives = {}
   local list = C_QuestLog.GetQuestObjectives(questID)
   if not list then return objectives end
   for _, obj in ipairs(list) do
      local text = obj.text
      if obj.type == "progressbar" and GetQuestProgressBarPercent then
         local pct = GetQuestProgressBarPercent(questID) or 0
         text = (text and text ~= "") and format("%s (%d%%)", text, pct) or format("%d%%", pct)
      end
      if text and text ~= "" then
         tinsert(objectives, { text = text, finished = obj.finished })
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
   local quest = {
      questID = questID,
      logIndex = logIndex,
      title = info.title,
      level = info.level,
      difficultyLevel = (info.difficultyLevel and info.difficultyLevel > 0) and info.difficultyLevel or info.level,
      suggestedGroup = info.suggestedGroup,
      frequency = info.frequency,
      isOnMap = info.isOnMap,
      isAutoComplete = info.isAutoComplete,
      isComplete = C_QuestLog.IsComplete(questID),
      isFailed = C_QuestLog.IsFailed(questID),
      isWatched = C_QuestLog.GetQuestWatchType(questID) ~= nil,
      isSuperTracked = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID() == questID,
      distance = GetQuestDistance(questID),
      objectives = BuildObjectives(questID),
   }
   -- Quest tag: tag ID 1 is "Elite" in classic content ("Group" in the retail enum).
   local tagInfo = C_QuestLog.GetQuestTagInfo and C_QuestLog.GetQuestTagInfo(questID)
   if tagInfo then
      quest.tagID = tagInfo.tagID
      quest.tagName = tagInfo.tagName
      quest.isElite = tagInfo.isElite or tagInfo.tagID == ((Enum.QuestTag and Enum.QuestTag.Group) or 1)
   end
   if quest.isComplete and GetQuestLogCompletionText then
      quest.completionText = GetQuestLogCompletionText(logIndex)
   end
   -- Usable quest item (shown as a secure item button).
   if GetQuestLogSpecialItemInfo then
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
local function SortByDistance(list, getKey, ranks, fallback)
   sort(list, function(a, b)
      local ra, rb = ranks[getKey(a)], ranks[getKey(b)]
      if ra and rb then return ra < rb end
      if ra or rb then return ra ~= nil end
      if (a.distance ~= nil) ~= (b.distance ~= nil) then return a.distance ~= nil end
      if a.distance and a.distance ~= b.distance then return a.distance < b.distance end
      return fallback(a, b)
   end)
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

--- Returns a sorted list of zone sections:
--- { name, isCurrent, zoneRank, minLevel, quests = { quest, ... } }
--- plus the number of quests in the log and the number displayed.
function mod:CollectQuests()
   local profile = self.db.profile
   local zoneNames = GetCurrentZoneNames()
   -- In instances, isOnMap can be true for quests of the surrounding zone.
   local useOnMap = not IsInInstance()
   local pois = profile.showDirection and self:CollectQuestPOIs() or nil
   local sections, byName = {}, {}
   local header = L["Miscellaneous"]
   local numQuests, numShown = 0, 0

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
            if visible then
               local section = byName[header]
               if not section then
                  section = { name = header, isCurrent = isCurrentZone, zoneRank = zoneRank, minLevel = math.huge, quests = {} }
                  byName[header] = section
                  tinsert(sections, section)
               end
               local quest = BuildQuest(info)
               quest.poi = pois and pois[quest.questID]
               tinsert(section.quests, quest)
               if quest.level < section.minLevel then
                  section.minLevel = quest.level
               end
               numShown = numShown + 1
            end
         end
      end
   end

   if profile.questSort == "distance" then
      for _, section in ipairs(sections) do
         -- Ranks are per quest ID, so one table works across sections.
         SortByDistance(section.quests, QuestKey, questRanks, questSorters.level)
      end
   else
      local questSorter = questSorters[profile.questSort] or questSorters.level
      for _, section in ipairs(sections) do
         sort(section.quests, questSorter)
      end
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
         local current, others = {}, {}
         for _, section in ipairs(sections) do
            tinsert(section.isCurrent and current or others, section)
         end
         sort(current, function(a, b)
            if a.zoneRank ~= b.zoneRank then return a.zoneRank > b.zoneRank end
            return zoneSorters.level(a, b)
         end)
         SortByDistance(others, ZoneKey, zoneRanks, zoneSorters.level)
         for _, section in ipairs(others) do
            tinsert(current, section)
         end
         sections = current
      else
         SortByDistance(sections, ZoneKey, zoneRanks, zoneSorters.level)
      end
   elseif profile.currentZoneFirst then
      sort(sections, function(a, b)
         if a.zoneRank ~= b.zoneRank then return a.zoneRank > b.zoneRank end
         return zoneSorter(a, b)
      end)
   else
      sort(sections, zoneSorter)
   end

   return sections, numQuests, numShown
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
   local recipe = { recipeID = recipeID, isRecraft = isRecraft, name = name, reagents = {} }

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
            local entry = { name = reagentName }
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

--- Returns a list of { recipeID, isRecraft, name, reagents = { { text, finished } } }
function mod:CollectRecipes()
   if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipesTracked and ProfessionsUtil) then
      return nil
   end
   local recipes = {}
   for _, isRecraft in ipairs({ false, true }) do
      for _, recipeID in ipairs(C_TradeSkillUI.GetRecipesTracked(isRecraft) or {}) do
         local recipe = BuildRecipe(recipeID, isRecraft)
         if recipe then
            tinsert(recipes, recipe)
         end
      end
   end
   return recipes
end
