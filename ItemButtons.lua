--[[
**********************************************************************
MagicQuestTracker - Secure quest item buttons.
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
local mod = LibStub("AceAddon-3.0"):GetAddon("MagicQuestTracker")

local C_QuestLog = C_QuestLog
local InCombatLockdown = InCombatLockdown

----------------------------------------------------------------
-- Quest item buttons
--
-- Using a quest item is protected, so these are SecureActionButtons
-- (type=item). A protected frame restricts everything it is anchored to
-- or parented under during combat, so the buttons live in their own
-- holder parented to UIParent and are positioned with absolute screen
-- coordinates taken from the quest title lines. The holder's scale
-- matches the tracker's, so line coordinates can be used directly.
--
-- All button changes happen out of combat. While any button is shown in
-- combat, the tracker freezes rendering and scrolling (mod.layoutDeferred)
-- and re-syncs on PLAYER_REGEN_ENABLED.
----------------------------------------------------------------

local BUTTON_SIZE = 26
mod.ITEM_BUTTON_SIZE = BUTTON_SIZE

local RANGE_INTERVAL = 0.2
local holder
local buttons = {}

-- Quest log indexes shift when quests are added or removed, so resolve
-- them from the quest ID whenever needed.
local function GetLogIndex(button)
   return button.questID and C_QuestLog.GetLogIndexForQuestID(button.questID)
end

local function UpdateCooldown(button)
   local logIndex = GetLogIndex(button)
   if not logIndex then return end
   local start, duration, enable = GetQuestLogSpecialItemCooldown(logIndex)
   if start then
      CooldownFrame_Set(button.Cooldown, start, duration, enable)
      if duration > 0 and enable == 0 then
         button.icon:SetVertexColor(0.4, 0.4, 0.4)
      else
         button.icon:SetVertexColor(1, 1, 1)
      end
   end
end

local function Button_OnUpdate(button, elapsed)
   button.rangeTimer = button.rangeTimer - elapsed
   if button.rangeTimer > 0 then return end
   button.rangeTimer = RANGE_INTERVAL

   local logIndex = GetLogIndex(button)
   local inRange = logIndex and IsQuestLogSpecialItemInRange(logIndex)
   if inRange == 0 then
      button.HotKey:SetVertexColor(1.0, 0.1, 0.1)
      button.HotKey:Show()
   elseif inRange == 1 then
      button.HotKey:SetVertexColor(0.6, 0.6, 0.6)
      button.HotKey:Show()
   else
      button.HotKey:Hide()
   end
end

local function Button_OnEnter(button)
   local logIndex = GetLogIndex(button)
   if logIndex then
      GameTooltip:SetOwner(button, "ANCHOR_LEFT")
      GameTooltip:SetQuestLogSpecialItem(logIndex)
      GameTooltip:Show()
   end
end

local function CreateButton(index)
   local button = CreateFrame("Button", "MagicQuestTrackerItemButton" .. index, holder, "SecureActionButtonTemplate")
   button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
   button:RegisterForClicks("AnyUp", "AnyDown")
   button:SetAttribute("type1", "item")

   button.icon = button:CreateTexture(nil, "BORDER")
   button.icon:SetAllPoints()

   -- Same look as Blizzard's QuestObjectiveItemButtonTemplate.
   button:SetNormalAtlas("UI-QuestTrackerButton-QuestItem-Frame")
   local normal = button:GetNormalTexture()
   normal:ClearAllPoints()
   normal:SetPoint("CENTER")
   normal:SetSize(BUTTON_SIZE * 42 / 26, BUTTON_SIZE * 42 / 26)
   button:SetPushedAtlas("UI-QuestTrackerButton-QuestItem-Frame")
   button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

   button.Count = button:CreateFontString(nil, "ARTWORK", "NumberFontNormal")
   button.Count:SetPoint("BOTTOMRIGHT", -3, 2)
   button.Count:SetJustifyH("RIGHT")

   button.HotKey = button:CreateFontString(nil, "ARTWORK", "NumberFontNormalSmallGray")
   button.HotKey:SetPoint("TOPRIGHT", 2, -2)
   button.HotKey:SetText(RANGE_INDICATOR)
   button.HotKey:Hide()

   button.Cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
   button.Cooldown:SetAllPoints()

   button.rangeTimer = 0
   button:SetScript("OnUpdate", Button_OnUpdate)
   button:SetScript("OnEnter", Button_OnEnter)
   button:SetScript("OnLeave", GameTooltip_Hide)

   buttons[index] = button
   return button
end

local function SetupButton(button, quest)
   local item = "item:" .. quest.itemID
   if button:GetAttribute("item1") ~= item then
      button:SetAttribute("item1", item)
   end
   button.questID = quest.questID
   button.icon:SetTexture(quest.itemTexture)
   if quest.itemCharges and quest.itemCharges > 1 then
      button.Count:SetText(quest.itemCharges)
      button.Count:Show()
   else
      button.Count:Hide()
   end
   button.rangeTimer = 0
   UpdateCooldown(button)
end

local holderCombatHidden = false

--- Hides the item buttons in combat (via a state driver; call out of combat).
function mod:SetItemButtonsCombatHidden(hide)
   if hide == holderCombatHidden or not holder then
      holderCombatHidden = hide
      return
   end
   holderCombatHidden = hide
   if hide then
      RegisterStateDriver(holder, "visibility", "[combat] hide; show")
   else
      UnregisterStateDriver(holder, "visibility")
      holder:Show()
   end
end

local function CreateHolder()
   holder = CreateFrame("Frame", "MagicQuestTrackerItemHolder", UIParent)
   holder:SetSize(1, 1)
   holder:SetPoint("BOTTOMLEFT")
   holder:SetFrameStrata("LOW")
   if holderCombatHidden then
      RegisterStateDriver(holder, "visibility", "[combat] hide; show")
   end
   holder:RegisterEvent("BAG_UPDATE_COOLDOWN")
   holder:SetScript("OnEvent", function()
      for _, button in ipairs(buttons) do
         if button:IsShown() then
            UpdateCooldown(button)
         end
      end
   end)
end

----------------------------------------------------------------
-- Public API used by Tracker.lua
----------------------------------------------------------------

--- True when shown secure buttons would be left misplaced by a layout change in combat.
function mod:IsItemLayoutLocked()
   return self.itemButtonsActive and InCombatLockdown()
end

--- Position buttons on the next frame, once the new line layout has resolved.
local function RunPendingItemLayout()
   mod.itemLayoutPending = nil
   mod:LayoutItemButtons()
end

function mod:RequestItemButtonLayout()
   if self.itemLayoutPending then return end
   self.itemLayoutPending = true
   C_Timer.After(0, RunPendingItemLayout)
end

function mod:HideItemButtons()
   if InCombatLockdown() then
      self.layoutDeferred = true
      return
   end
   for _, button in ipairs(buttons) do
      button:Hide()
      button.questID = nil
   end
   self.itemButtonsActive = false
end

function mod:LayoutItemButtons()
   local entries = self.itemEntries
   if InCombatLockdown() then
      -- Combat may have started since the render; re-sync afterwards.
      if (entries and #entries > 0) or self.itemButtonsActive then
         self.layoutDeferred = true
      end
      return
   end
   if not holder then CreateHolder() end

   local frame = self.frame
   local profile = self.db.profile
   holder:SetScale(self:GetLayoutSettings().scale)
   holder:SetFrameLevel(frame:GetFrameLevel() + 20)

   local used = 0
   local scroll = frame.scroll
   local top, bottom = scroll:GetTop(), scroll:GetBottom()
   if entries and frame:IsShown() and scroll:IsShown() and profile.showItemButtons and top and bottom
      and not self:IsInEditMode() then
      for _, entry in ipairs(entries) do
         local lineTop, lineRight = entry.line:GetTop(), entry.line:GetRight()
         -- Only show buttons that are fully inside the visible scroll area.
         if lineTop and lineRight and lineTop <= top + 0.5 and lineTop - BUTTON_SIZE >= bottom - 0.5 then
            used = used + 1
            local button = buttons[used] or CreateButton(used)
            SetupButton(button, entry.quest)
            button:ClearAllPoints()
            button:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", lineRight, lineTop)
            button:Show()
         end
      end
   end

   for i = used + 1, #buttons do
      buttons[i]:Hide()
      buttons[i].questID = nil
   end
   self.itemButtonsActive = used > 0
end
