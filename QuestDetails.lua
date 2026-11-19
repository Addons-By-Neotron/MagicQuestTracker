--[[
MagicQuestTracker - Quest details window.

Our own window with a quest's objectives, description and rewards, opened
by left-clicking a quest or from the quest menu. Opening Blizzard's quest log / map details from addon
code runs Blizzard's map and quest panel code tainted, and the map is then
blocked in combat. This window is built only from quest log reads by quest
ID, so no Blizzard quest or map code runs from it, and it works in combat.
Its "Show on map" / "Complete quest" button is the exception: a secure click
on Blizzard's own tracker block (ClickOverlay.lua), so only for watched
quests, out of combat.
]]

local mod = LibStub("AceAddon-3.0"):GetAddon("MagicQuestTracker")
local L = LibStub("AceLocale-3.0"):GetLocale("MagicQuestTracker")

local WIDTH, HEIGHT = 380, 500
local PAD = 20
local TILE = 32
local TILE_GAP = 6
local SCROLL_STEP = 40
local CHECK_ICON = "Interface\\RaidFrame\\ReadyCheck-Ready"

local window, scroll, child, meta
local texts, tiles, checks = {}, {}, {}
local usedTexts, usedTiles, usedChecks = 0, 0, 0
local questID

----------------------------------------------------------------
-- Rewards
----------------------------------------------------------------

--- XP, money, currencies and items, and choices; nil when there are none.
local function GetRewards(id)
   if C_QuestLog.ShouldShowQuestRewards and not C_QuestLog.ShouldShowQuestRewards(id) then return end
   local r = {
      xp = GetQuestLogRewardXP and GetQuestLogRewardXP(id) or 0,
      money = GetQuestLogRewardMoney and GetQuestLogRewardMoney(id) or 0,
      rewards = {}, choices = {},
   }
   local currencies = C_QuestLog.GetQuestRewardCurrencies and C_QuestLog.GetQuestRewardCurrencies(id) or {}
   for i, cur in ipairs(currencies) do
      tinsert(r.rewards, { name = cur.name, texture = cur.texture, count = cur.totalRewardAmount,
         quality = cur.quality, kind = "reward", index = i, currency = true })
   end
   for i = 1, GetNumQuestLogRewards and GetNumQuestLogRewards(id) or 0 do
      local name, texture, count, quality, _, itemID = GetQuestLogRewardInfo(i, id)
      tinsert(r.rewards, { name = name, texture = texture, count = count, quality = quality,
         itemID = itemID, kind = "reward", index = i })
   end
   for i = 1, GetNumQuestLogChoices and GetNumQuestLogChoices(id) or 0 do
      local name, texture, count, quality, _, itemID = GetQuestLogChoiceInfo(i, id)
      tinsert(r.choices, { name = name, texture = texture, count = count, quality = quality,
         itemID = itemID, kind = "choice", index = i })
   end
   if r.xp <= 0 and r.money <= 0 and #r.rewards == 0 and #r.choices == 0 then return end
   return r
end

----------------------------------------------------------------
-- Content pools
----------------------------------------------------------------

--- A note for a reward XP the game has reduced (6+ levels below you), or
--- nil. How much varies (Forever's dungeon quests keep more), so no figure.
local function ReducedXPNote()
   local level = C_QuestLog.GetQuestDifficultyLevel and C_QuestLog.GetQuestDifficultyLevel(questID)
   if not level or level <= 0 then return end
   local below = UnitLevel("player") - level
   if below < 6 then return end
   return format(L["Reduced XP: the quest is %d levels below you."], below)
end

local function AddText(text, x, y, font, r, g, b)
   usedTexts = usedTexts + 1
   local fs = texts[usedTexts]
   if not fs then
      fs = child:CreateFontString(nil, "ARTWORK")
      fs:SetJustifyH("LEFT")
      fs:SetWordWrap(true)
      texts[usedTexts] = fs
   end
   fs:SetFontObject(font or GameFontHighlight)
   fs:ClearAllPoints()
   fs:SetPoint("TOPLEFT", x, -y)
   fs:SetWidth(child:GetWidth() - x)
   fs:SetText(text)
   fs:SetTextColor(r or 1, g or 1, b or 1)
   fs:Show()
   return math.ceil(fs:GetStringHeight())
end

local function AddSection(text, y)
   return AddText(text, 0, y, GameFontNormalLarge, NORMAL_FONT_COLOR:GetRGB()) + 6
end

local function AddCheck(y)
   usedChecks = usedChecks + 1
   local tex = checks[usedChecks]
   if not tex then
      tex = child:CreateTexture(nil, "ARTWORK")
      tex:SetTexture(CHECK_ICON)
      tex:SetSize(14, 14)
      checks[usedChecks] = tex
   end
   tex:ClearAllPoints()
   tex:SetPoint("TOPLEFT", 0, -y)
   tex:Show()
end

local function Tile_OnEnter(tile)
   local e = tile.entry
   if not e then return end
   GameTooltip:SetOwner(tile, "ANCHOR_RIGHT")
   if e.currency and GameTooltip.SetQuestLogCurrency then
      GameTooltip:SetQuestLogCurrency(e.kind, e.index, questID)
   elseif GameTooltip.SetQuestLogItem then
      GameTooltip:SetQuestLogItem(e.kind, e.index, questID)
   end
   GameTooltip:Show()
end

local function AcquireTile()
   usedTiles = usedTiles + 1
   local tile = tiles[usedTiles]
   if not tile then
      tile = CreateFrame("Button", nil, child)
      tile:SetSize(TILE, TILE)
      tile.icon = tile:CreateTexture(nil, "ARTWORK")
      tile.icon:SetAllPoints()
      tile.count = tile:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
      tile.count:SetPoint("BOTTOMRIGHT", -2, 2)
      tile.name = tile:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
      tile.name:SetPoint("LEFT", tile, "RIGHT", 6, 0)
      tile.name:SetJustifyH("LEFT")
      tile:SetScript("OnEnter", Tile_OnEnter)
      tile:SetScript("OnLeave", GameTooltip_Hide)
      tiles[usedTiles] = tile
   end
   return tile
end

-- Two tiles per row, icon and name. Returns the height used.
local function AddTiles(list, y)
   local colWidth = (child:GetWidth() - TILE_GAP) / 2
   for i, e in ipairs(list) do
      local tile = AcquireTile()
      local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
      tile:ClearAllPoints()
      tile:SetPoint("TOPLEFT", col * (colWidth + TILE_GAP), -(y + row * (TILE + TILE_GAP)))
      tile.entry = e
      tile.icon:SetTexture(e.texture)
      tile.count:SetText((e.count and e.count > 1) and e.count or "")
      tile.name:SetWidth(colWidth - TILE - 8)
      tile.name:SetText(e.name or "")
      local color = e.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[e.quality]
      if color then
         tile.name:SetTextColor(color.r, color.g, color.b)
      else
         tile.name:SetTextColor(1, 1, 1)
      end
      tile:Show()
   end
   local rows = math.ceil(#list / 2)
   return rows * TILE + math.max(0, rows - 1) * TILE_GAP
end

local function ReleaseUnused()
   for i = usedTexts + 1, #texts do texts[i]:Hide() end
   for i = usedTiles + 1, #tiles do tiles[i]:Hide(); tiles[i].entry = nil end
   for i = usedChecks + 1, #checks do checks[i]:Hide() end
end

----------------------------------------------------------------
-- Window
----------------------------------------------------------------

-- Level (difficulty colored), quest type and complete, e.g. "Level 12   Elite".
local function MetaText()
   local parts = {}
   local level = C_QuestLog.GetQuestDifficultyLevel and C_QuestLog.GetQuestDifficultyLevel(questID)
   if level and level > 0 then
      local c = GetQuestDifficultyColor(level)
      tinsert(parts, format("|cff%02x%02x%02x%s %d|r", c.r * 255, c.g * 255, c.b * 255, LEVEL, level))
   end
   local tag = C_QuestLog.GetQuestTagInfo(questID)
   if tag and tag.tagName then tinsert(parts, tag.tagName) end
   if C_QuestLog.IsComplete(questID) then tinsert(parts, COMPLETE) end
   return table.concat(parts, "   ")
end

local function SetButtonEnabled(button, enabled)
   button:SetEnabled(enabled)
end

-- Blizzard's header click completes an auto-complete quest that's done,
-- and opens the map otherwise.
local function IsAutoCompleteReady()
   local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
   local info = logIndex and C_QuestLog.GetInfo(logIndex)
   return info and info.isAutoComplete and C_QuestLog.IsComplete(questID)
end

local function UpdateMapButton(inCombat)
   local button = window.map
   local autoComplete = IsAutoCompleteReady()
   local placed, viaLog = false, false
   if not inCombat and window:IsShown() and not window.dragging then
      -- No Blizzard header: the quest log instead (not for completing).
      placed, viaLog = mod:PlaceQuestHeaderClick(button, questID, not autoComplete)
   end
   if not placed and not inCombat then mod:HideQuestHeaderClick() end
   if autoComplete then
      button:SetText(COMPLETE_QUEST or L["Complete quest"])
   elseif viaLog then
      button:SetText(L["Open quest log"])
   else
      button:SetText(OBJECTIVES_SHOW_QUEST_MAP or L["Show on map"])
   end
   SetButtonEnabled(button, placed and true or false)
   window.viaLog = placed and viaLog
   window.mapHelp:SetShown(not placed or viaLog)
end

-- inCombat: the combat events pass their own state (InCombatLockdown is
-- already true in PLAYER_REGEN_DISABLED, still true in PLAYER_REGEN_ENABLED).
local function UpdateButtons(inCombat)
   if inCombat == nil then inCombat = InCombatLockdown() end
   local focus = window.focus
   focus:SetShown(mod.db.profile.blizzardFocus)
   local focused = mod:GetFocusedQuestID() == questID
   focus:SetText(focused and (STOP_SUPER_TRACK_QUEST or L["Stop focusing quest"])
      or (SUPER_TRACK_QUEST or L["Focus quest"]))
   local watched = C_QuestLog.GetQuestWatchType(questID) ~= nil
   window.track:SetText(watched and (OBJECTIVES_STOP_TRACKING or L["Stop tracking"])
      or (TRACK_QUEST or L["Track quest"]))
   SetButtonEnabled(window.share, not inCombat and IsInGroup() and C_QuestLog.IsPushableQuest(questID))
   SetButtonEnabled(window.abandon, not C_QuestLog.CanAbandonQuest or C_QuestLog.CanAbandonQuest(questID))
   UpdateMapButton(inCombat)
end

local Refresh

-- Redraws once an uncached reward item loads, if still on that quest.
local function WatchItemLoads(list)
   local shown = questID
   for _, e in ipairs(list) do
      local item = e.itemID and Item:CreateFromItemID(e.itemID)
      if item and not item:IsItemEmpty() and not item:IsItemDataCached() then
         item:ContinueOnItemLoad(function()
            if questID == shown then Refresh() end
         end)
      end
   end
end

function Refresh(inCombat)
   if not (window and window:IsShown() and questID) then return end
   local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
   if not logIndex then
      window:Hide()
      return
   end
   usedTexts, usedTiles, usedChecks = 0, 0, 0
   window:SetTitle(C_QuestLog.GetTitleForQuestID(questID) or "")
   meta:SetText(MetaText())

   local dim = 0.6
   local description, objectivesText = GetQuestLogQuestText(logIndex)
   local y = 0
   local objectives = C_QuestLog.GetQuestObjectives(questID) or {}
   if #objectives > 0 or (objectivesText and objectivesText ~= "") then
      y = y + AddSection(QUEST_OBJECTIVES or L["Objectives"], y)
      for _, o in ipairs(objectives) do
         if o.text and o.text ~= "" then
            if o.finished then
               AddCheck(y)
               y = y + AddText(o.text, 18, y, nil, dim, dim, dim) + 4
            else
               y = y + AddText(o.text, 18, y) + 4
            end
         end
      end
      if objectivesText and objectivesText ~= "" then
         y = y + 4 + AddText(objectivesText, 0, y + 4, nil, 0.8, 0.8, 0.8)
      end
      y = y + 16
   end
   if description and description ~= "" then
      y = y + AddSection(QUEST_DESCRIPTION or L["Description"], y)
      y = y + AddText(description, 0, y, nil, 0.9, 0.9, 0.9) + 16
   end

   local r = GetRewards(questID)
   if r then
      y = y + AddSection(QUEST_REWARDS or L["Rewards"], y)
      if r.xp > 0 then
         y = y + AddText(format(BONUS_OBJECTIVE_EXPERIENCE_FORMAT or "%d XP", r.xp), 0, y) + 4
         local note = ReducedXPNote()
         if note then y = y + AddText(note, 0, y, GameFontNormalSmall, 0.8, 0.8, 0.8) + 4 end
      end
      if r.money > 0 then
         y = y + AddText(GetMoneyString(r.money), 0, y) + 4
      end
      if #r.rewards > 0 then
         y = y + 4 + AddTiles(r.rewards, y + 4) + 4
         WatchItemLoads(r.rewards)
      end
      if #r.choices > 0 then
         y = y + 8
         y = y + AddText(REWARD_CHOICES or L["You will be able to choose one of these rewards:"], 0, y,
            nil, 0.8, 0.8, 0.8) + 6
         y = y + AddTiles(r.choices, y)
         WatchItemLoads(r.choices)
      end
   end
   ReleaseUnused()
   child:SetHeight(math.max(1, y))
   local maxScroll = math.max(0, y - scroll:GetHeight())
   if scroll:GetVerticalScroll() > maxScroll then scroll:SetVerticalScroll(maxScroll) end
   UpdateButtons(inCombat)
end

local function OnEvent(_, event, arg1)
   if event == "QUEST_REMOVED" then
      if arg1 == questID then window:Hide() end
   elseif event == "PLAYER_REGEN_DISABLED" then
      mod:HideQuestHeaderClick(true)
      UpdateButtons(true)
   elseif event == "PLAYER_REGEN_ENABLED" then
      UpdateButtons(false)
      -- Lockdown may still be on during the event; place the secure click after.
      C_Timer.After(0, function() if questID then UpdateButtons() end end)
   elseif event == "QUEST_WATCH_LIST_CHANGED" then
      UpdateButtons()
      -- Blizzard's tracker lays out the new block a little later.
      C_Timer.After(0.2, function() if questID then UpdateButtons() end end)
   elseif event == "SUPER_TRACKING_CHANGED" or event == "GROUP_ROSTER_UPDATE" then
      UpdateButtons()
   else
      Refresh()
   end
end

local EVENTS = {
   "QUEST_LOG_UPDATE", "QUEST_REMOVED", "SUPER_TRACKING_CHANGED", "QUEST_WATCH_LIST_CHANGED",
   "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
}

local function OnScrollWheel(self, delta)
   local maxScroll = math.max(0, child:GetHeight() - self:GetHeight())
   self:SetVerticalScroll(math.min(maxScroll, math.max(0, self:GetVerticalScroll() - delta * SCROLL_STEP)))
end

local function CreateWindow()
   window = mod:CreateDialogWindow("MagicQuestTrackerQuestDetails", WIDTH, HEIGHT,
      { title = "", header = true, closeButton = true, opaque = true })
   window:SetScript("OnShow", function(self)
      for _, event in ipairs(EVENTS) do self:RegisterEvent(event) end
   end)
   window:SetScript("OnHide", function(self)
      self:UnregisterAllEvents()
      mod:HideQuestHeaderClick()
      questID = nil
   end)
   -- The secure click is placed by screen position: off while dragging,
   -- back where the button ends up.
   window:HookScript("OnDragStart", function(self)
      self.dragging = true
      if questID then UpdateButtons() end
   end)
   window:HookScript("OnDragStop", function(self)
      self.dragging = nil
      if questID then UpdateButtons() end
   end)
   window:SetScript("OnEvent", OnEvent)

   meta = window:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
   meta:SetPoint("TOPLEFT", PAD, -30)
   meta:SetPoint("RIGHT", -PAD, 0)
   meta:SetJustifyH("LEFT")

   scroll = CreateFrame("ScrollFrame", nil, window)
   scroll:SetPoint("TOPLEFT", PAD, -52)
   scroll:SetPoint("BOTTOMRIGHT", -PAD, 106)
   scroll:EnableMouseWheel(true)
   scroll:SetScript("OnMouseWheel", OnScrollWheel)
   child = CreateFrame("Frame", nil, scroll)
   child:SetSize(WIDTH - 2 * PAD, 1)
   scroll:SetScrollChild(child)

   local buttonWidth = (WIDTH - 2 * PAD - 8) / 2
   local function AddButton(point, x, y, onClick)
      local button = mod:CreateDialogButton(window, "", buttonWidth, onClick, 22)
      button:SetPoint(point, x, y)
      return button
   end
   window.focus = AddButton("BOTTOMLEFT", PAD, 46, function()
      local focused = mod:GetFocusedQuestID() == questID
      mod:SetSuperTrackedQuest(focused and 0 or questID)
   end)
   window.track = AddButton("BOTTOMRIGHT", -PAD, 46, function()
      mod.ToggleQuestWatch(questID)
   end)
   window.share = AddButton("BOTTOMLEFT", PAD, 18, function()
      mod.ShareQuest(questID)
   end)
   window.share:SetText(SHARE_QUEST or L["Share quest"])
   window.abandon = AddButton("BOTTOMRIGHT", -PAD, 18, function()
      mod.AbandonQuest(questID)
   end)
   window.abandon:SetText(ABANDON_QUEST_ABBREV or L["Abandon quest"])

   -- Clicks come from the secure click placed over it, never from here.
   window.map = mod:CreateDialogButton(window, "", WIDTH - 2 * PAD - 28, nil, 22)
   window.map:SetPoint("BOTTOMLEFT", PAD, 74)
   window.map:SetMotionScriptsWhileDisabled(true)

   local help = CreateFrame("Button", nil, window)
   help:SetSize(22, 22)
   help:SetPoint("LEFT", window.map, "RIGHT", 6, 0)
   help:SetNormalTexture("Interface\\Common\\help-i")
   help:SetHighlightTexture("Interface\\Common\\help-i", "ADD")
   help:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(OBJECTIVES_SHOW_QUEST_MAP or L["Show on map"])
      GameTooltip:AddLine(L["Only works for tracked quests, out of combat. It goes through Blizzard's own quest tracker, since opening the map from an addon causes errors in combat later."], 1, 1, 1, true)
      if window.viaLog then
         local watched = C_QuestLog.GetQuestWatchType(questID) ~= nil
         GameTooltip:AddLine(" ")
         GameTooltip:AddLine(watched
            and L["Blizzard's tracker has no room for this quest (too many tracked quests), so this opens the quest log instead."]
            or L["This quest isn't tracked, so this opens the quest log instead."], 1, 0.82, 0, true)
      end
      GameTooltip:Show()
   end)
   help:SetScript("OnLeave", GameTooltip_Hide)
   window.mapHelp = help
end

--- Kerzo Classic Quest Log (third-party quest log window) and its public API.
function mod:HasKerzoQuestLog()
   local api = KerzosQuestLogAPI
   return api and type(api.OpenQuest) == "function"
end

--- True when left-clicks go to Kerzo Classic Quest Log.
function mod:UseKerzoQuestLog()
   return self.db.profile.kerzoQuestLog and self:HasKerzoQuestLog() and true or false
end

--- Opens the quest in Kerzo Classic Quest Log. Returns true if it did.
--- Its API's OpenQuest selects the quest but neither shows the details panel
--- nor refreshes, so with the window already open nothing changes. Its own
--- "open quest details" hook does both, a frame later: the quest text
--- follows the selection a frame late.
function mod:OpenInKerzoQuestLog(id)
   if not self:HasKerzoQuestLog() then return false end
   local ok, opened = pcall(KerzosQuestLogAPI.OpenQuest, KerzosQuestLogAPI, id)
   if not (ok and opened) then return false end
   local kql = KerzosQuestLog
   if kql then
      if kql.Raise then kql:Raise() end
      if kql.ActivarPanel then pcall(kql.ActivarPanel, kql, "VisorDetalle") end
      if kql.Refrescar then
         pcall(kql.Refrescar, kql)
         C_Timer.After(0, function() pcall(kql.Refrescar, kql) end)
      end
   end
   return true
end

--- Shows the details window for a quest in the log (toggles it off when
--- that quest is already showing).
function mod:ShowQuestDetails(id)
   if not id or not C_QuestLog.GetLogIndexForQuestID(id) then return end
   if not window then CreateWindow() end
   if window:IsShown() and questID == id then
      window:Hide()
      return
   end
   questID = id
   scroll:SetVerticalScroll(0)
   window:Show()
   Refresh()
end
