--[[
**********************************************************************
MagicQuestTracker - Quest item bar.
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
local LEM = LibStub("LibEditMode", true)

local C_QuestLog = C_QuestLog
local InCombatLockdown = InCombatLockdown

----------------------------------------------------------------
-- Quest item bar
--
-- A separate bar of up to MAX_BUTTONS secure quest item buttons, with key
-- bindings (Bindings.xml: CLICK MagicQuestTrackerBarButtonN:LeftButton).
-- It lists the items of every quest in the log, whatever the tracker shows.
-- Slot 1 is the "special" slot: the focused quest's item, or else the
-- nearest one. The other slots follow the quest log order, so their key
-- bindings stay on the same items while you move around.
--
-- Moved in Edit Mode; position and scale are saved per Edit Mode layout in
-- profile.questBarLayouts. Like the tracker's item buttons, everything
-- changes out of combat only; changes during combat wait for its end.
----------------------------------------------------------------

local MAX_BUTTONS = 5
mod.QUEST_BAR_MAX_BUTTONS = MAX_BUTTONS
local BUTTON_SIZE = 36
local UPDATE_INTERVAL = 2       -- seconds between nearest-item checks
-- Slot 1 only moves to a nearer quest when it is clearly nearer.
local SWAP_RATIO, SWAP_MIN = 1.25, 20

local DEFAULT_POSITION = { point = "BOTTOM", x = 0, y = 260, scale = 1 }

local holder
local buttons = {}
local placeholders = {}
local CreatePlaceholder
local entries = {}      -- reused { questID, itemID, itemTexture, itemCharges, distance }
local slotQuests = {}   -- questID per slot, as last applied
local specialQuestID    -- quest in slot 1
local pending           -- an update waits for combat to end

for i = 1, MAX_BUTTONS do
   _G["BINDING_NAME_CLICK MagicQuestTrackerBarButton" .. i .. ":LeftButton"] = format(L["Quest item %d"], i)
end
BINDING_HEADER_MAGICQUESTTRACKER = "Magic Quest Tracker"

--- Alignment labels for the bar's orientation (start / center / end).
function mod:GetQuestBarAlignLabels()
   if self.db.profile.questBarVertical then
      return { start = L["Top"], center = L["Center"], ["end"] = L["Bottom"] }
   end
   return { start = L["Left"], center = L["Center"], ["end"] = L["Right"] }
end

local function GetLayoutName()
   return LEM and LEM:GetActiveLayoutName()
end

--- Returns the { point, x, y, scale } of the bar in the active layout.
function mod:GetQuestBarLayout()
   local layouts = self.db.profile.questBarLayouts
   local name = GetLayoutName()
   local settings = name and layouts[name]
   if not settings then
      -- Unknown layout: start from where the bar was last placed.
      settings = CopyTable(layouts[self.db.profile.questBarLastLayout] or DEFAULT_POSITION)
      if name then layouts[name] = settings end
   end
   for key, value in pairs(DEFAULT_POSITION) do
      if settings[key] == nil then settings[key] = value end
   end
   return settings
end

local function NumButtons()
   return math.max(1, math.min(MAX_BUTTONS, mod.db.profile.questBarButtons or MAX_BUTTONS))
end

local function BindingCommand(index)
   return "CLICK MagicQuestTrackerBarButton" .. index .. ":LeftButton"
end

local function UpdateHotKey(button, index)
   local key = GetBindingKey(BindingCommand(index))
   if key then
      button.hasBinding = true
      button.HotKey:SetText(GetBindingText(key, 1))
      button.HotKey:Show()
   else
      button.hasBinding = nil
      button.HotKey:SetText(RANGE_INDICATOR)
      button.HotKey:Hide()
   end
end

----------------------------------------------------------------
-- Stand-ins for the secure buttons in Edit Mode and in Blizzard's quick
-- keybind mode: an empty slot frame for every button. In quick keybind
-- mode they take the hovered binding like action buttons (the secure
-- buttons are hidden, so clicking doesn't use an item).
----------------------------------------------------------------

local function InQuickKeybindMode()
   return KeybindFrames_InQuickKeybindMode and KeybindFrames_InQuickKeybindMode() or false
end

-- Called by QuickKeybindFrame (as mouseOverButton) after a key is bound.
local function Placeholder_SetTooltip(self)
   local mixin = QuickKeybindButtonTemplateMixin
   if mixin and mixin.QuickKeybindButtonSetTooltip then
      mixin.QuickKeybindButtonSetTooltip(self)
   end
   UpdateHotKey(self, self:GetID())
end

local function Placeholder_OnEnter(self)
   if not InQuickKeybindMode() then return end
   self.highlight:Show()
   QuickKeybindFrame:SetSelected(self.commandName, self)
   self:QuickKeybindButtonSetTooltip()
end

local function Placeholder_OnLeave(self)
   self.highlight:Hide()
   if InQuickKeybindMode() then
      QuickKeybindFrame:SetSelected(nil, nil)
   end
   if QuickKeybindTooltip then QuickKeybindTooltip:Hide() end
end

-- Mouse buttons other than left / right can be bound by clicking them.
local function Placeholder_OnClick(self, button)
   if InQuickKeybindMode() and button ~= "LeftButton" and button ~= "RightButton" then
      QuickKeybindFrame:OnKeyDown(button)
   end
end

local function Placeholder_OnMouseWheel(self, delta)
   if InQuickKeybindMode() then
      QuickKeybindFrame:OnMouseWheel(delta)
   end
end

CreatePlaceholder = function(index)
   local placeholder = CreateFrame("Button", nil, holder)
   placeholder:SetID(index)
   placeholder:SetSize(BUTTON_SIZE, BUTTON_SIZE)
   placeholder:SetFrameLevel(holder:GetFrameLevel() + 5)
   placeholder:RegisterForClicks("AnyUp")
   placeholder.commandName = BindingCommand(index)
   local border = placeholder:CreateTexture(nil, "ARTWORK")
   border:SetAtlas("UI-QuestTrackerButton-QuestItem-Frame")
   border:SetPoint("CENTER")
   border:SetSize(BUTTON_SIZE * 42 / 26, BUTTON_SIZE * 42 / 26)
   placeholder.highlight = placeholder:CreateTexture(nil, "HIGHLIGHT")
   placeholder.highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
   placeholder.highlight:SetBlendMode("ADD")
   placeholder.highlight:SetAllPoints()
   placeholder.highlight:Hide()
   placeholder.HotKey = placeholder:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
   placeholder.HotKey:SetPoint("TOPRIGHT", -2, -3)
   placeholder.QuickKeybindButtonSetTooltip = Placeholder_SetTooltip
   placeholder:SetScript("OnEnter", Placeholder_OnEnter)
   placeholder:SetScript("OnLeave", Placeholder_OnLeave)
   placeholder:SetScript("OnClick", Placeholder_OnClick)
   placeholder:SetScript("OnMouseWheel", Placeholder_OnMouseWheel)
   placeholder:EnableMouse(false)
   placeholder:Hide()
   UpdateHotKey(placeholder, index)
   return placeholder
end

local function CreateHolder()
   holder = CreateFrame("Frame", "MagicQuestTrackerQuestBar", UIParent)
   holder:SetFrameStrata("MEDIUM")
   holder:SetClampedToScreen(true)
   holder:SetMovable(true)
   holder:SetDontSavePosition(true)
   holder.editModeName = L["Quest item bar"]
   holder:Hide()
   for i = 1, MAX_BUTTONS do
      local button = mod:CreateQuestItemButton("MagicQuestTrackerBarButton" .. i, holder, BUTTON_SIZE)
      button.HotKey:ClearAllPoints()
      button.HotKey:SetPoint("TOPRIGHT", -2, -3)
      button:Hide()
      buttons[i] = button
      UpdateHotKey(button, i)

      placeholders[i] = CreatePlaceholder(i)
   end
   holder:RegisterEvent("BAG_UPDATE_COOLDOWN")
   holder:RegisterEvent("UPDATE_BINDINGS")
   holder:SetScript("OnEvent", function(_, event)
      for i, button in ipairs(buttons) do
         if event == "UPDATE_BINDINGS" then
            UpdateHotKey(button, i)
            UpdateHotKey(placeholders[i], i)
         elseif button:IsShown() then
            mod.UpdateQuestItemCooldown(button)
         end
      end
   end)
end

-- Slot positions: left to right, or top to bottom. `shift` slots moves the
-- buttons along the bar (to align fewer buttons than slots).
local function SlotOffset(index, shift)
   local profile = mod.db.profile
   local step = (BUTTON_SIZE + profile.questBarSpacing) * (index - 1 + (shift or 0))
   if profile.questBarVertical then return 0, -step end
   return step, 0
end

-- Positions the first `used` buttons per questBarAlign: start (left / top),
-- center or end (right / bottom) of the bar. Out of combat only.
local function PositionButtons(used)
   local align = mod.db.profile.questBarAlign
   local free = NumButtons() - used
   local shift = align == "end" and free or align == "center" and free / 2 or 0
   for i = 1, used do
      local x, y = SlotOffset(i, shift)
      buttons[i]:ClearAllPoints()
      buttons[i]:SetPoint("TOPLEFT", holder, "TOPLEFT", x, y)
   end
end

--- Applies position, scale, size and slot layout. Out of combat only.
function mod:ApplyQuestBarLayout()
   if not holder then return end
   if InCombatLockdown() then
      pending = true
      return
   end
   local profile = self.db.profile
   local pos = self:GetQuestBarLayout()
   local count = NumButtons()
   local length = count * BUTTON_SIZE + (count - 1) * profile.questBarSpacing
   holder:SetScale(pos.scale)
   if profile.questBarVertical then
      holder:SetSize(BUTTON_SIZE, length)
   else
      holder:SetSize(length, BUTTON_SIZE)
   end
   holder:ClearAllPoints()
   holder:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
   for i = 1, MAX_BUTTONS do
      local x, y = SlotOffset(i)
      placeholders[i]:ClearAllPoints()
      placeholders[i]:SetPoint("TOPLEFT", holder, "TOPLEFT", x, y)
   end
end

-- Fills `entries` with the usable quest items in the log, in log order.
local function CollectItems()
   local count = 0
   -- Only items of quests nearby (see IsNear), plus the focused quest's.
   local maxDistance = mod.db.profile.questBarMaxDistance or 0
   local focused = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
   local useOnMap = not IsInInstance()
   for i = 1, C_QuestLog.GetNumQuestLogEntries() do
      local info = C_QuestLog.GetInfo(i)
      if info and not info.isHeader and not info.isHidden then
         local link, texture, charges, showWhenComplete = GetQuestLogSpecialItemInfo(i)
         local itemID = link and tonumber(link:match("item:(%d+)"))
         local distance = itemID and mod.GetQuestDistance(info.questID)
         -- Near: within the distance of the quest's objective area (or turn-in
         -- when complete), or without a known distance, shown on this zone's map.
         local near = maxDistance <= 0 or info.questID == focused
            or (distance and distance <= maxDistance)
            or (not distance and useOnMap and info.isOnMap)
         if itemID and near and (showWhenComplete or not C_QuestLog.IsComplete(info.questID)) then
            count = count + 1
            local entry = entries[count] or {}
            entries[count] = entry
            entry.questID = info.questID
            entry.itemID = itemID
            entry.itemTexture = texture
            entry.itemCharges = charges
            entry.distance = distance
         end
      end
   end
   for i = count + 1, #entries do entries[i] = nil end
   return count
end

-- Test mode (/mqt testbar): bag items in place of quest items, to try the
-- bar, its bindings and layout without quests that have items.
local testMode
local TEST_ITEMS = { 6948, 5512, 159, 4540, 117 }  -- Hearthstone, Healthstone, water, bread, jerky

local function CollectTestItems()
   local count = 0
   for _, itemID in ipairs(TEST_ITEMS) do
      if C_Item.GetItemCount(itemID) > 0 then
         count = count + 1
         local entry = entries[count] or {}
         entries[count] = entry
         entry.questID = nil
         entry.itemID = itemID
         entry.itemTexture = C_Item.GetItemIconByID(itemID)
         entry.itemCharges = C_Item.GetItemCount(itemID)
         entry.distance = nil
      end
   end
   for i = count + 1, #entries do entries[i] = nil end
   return count
end

function mod:ToggleQuestBarTest()
   testMode = not testMode
   self:info(testMode and L["Quest item bar test on: it shows your Hearthstone and some food or water from your bags."]
      or L["Quest item bar test off."])
   if testMode and not self.db.profile.questBar then
      self:info(L["The quest item bar is turned off; turn it on in the settings or in Edit Mode."])
   end
   self:UpdateQuestBar()
end

-- The entry for slot 1: the focused quest, else the nearest (keeping the
-- current one unless another is clearly nearer).
local function PickSpecial(count)
   local focused = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
   local nearest, current
   for i = 1, count do
      local entry = entries[i]
      if entry.questID == focused then return entry end
      if entry.questID == specialQuestID then current = entry end
      if entry.distance and (not nearest or entry.distance < nearest.distance) then
         nearest = entry
      end
   end
   if current and current.distance and nearest
      and current.distance <= nearest.distance * SWAP_RATIO + SWAP_MIN then
      return current
   end
   return nearest or current or entries[1]
end

-- Shows the stand-ins in Edit Mode or quick keybind mode.
local function ShowPlaceholders(editing, binding)
   local count = NumButtons()
   -- Dimmed while the bar is turned off.
   local alpha = mod.db.profile.questBar and 1 or 0.4
   for i = 1, MAX_BUTTONS do
      local placeholder = placeholders[i]
      placeholder:SetShown((editing or binding) and i <= count)
      placeholder:SetAlpha(alpha)
      -- Edit Mode drags the bar by its selection frame, so no mouse there.
      placeholder:EnableMouse(binding and not editing)
      placeholder.HotKey:SetShown((binding or editing) and placeholder.hasBinding or false)
   end
end

--- Refreshes which items the bar shows. Out of combat only; in combat the
--- update waits for PLAYER_REGEN_ENABLED.
function mod:UpdateQuestBar()
   if not GetQuestLogSpecialItemInfo then return end
   local enabled = self.db.profile.questBar
   local editing = self:IsInEditMode()
   local binding = enabled and InQuickKeybindMode()
   if not holder and not (enabled or editing) then return end
   if InCombatLockdown() then
      pending = true
      return
   end
   pending = nil
   if not holder then
      CreateHolder()
      self:ApplyQuestBarLayout()
      self:SetupQuestBarEditMode()
      editing = self:IsInEditMode()
   end
   -- Shown in Edit Mode even when off, so it can be placed and turned on there.
   if not (enabled or editing) then
      holder:Hide()
      return
   end
   holder:Show()

   ShowPlaceholders(editing, binding)
   local numSlots = NumButtons()
   local count = (editing or binding or not enabled) and 0 or testMode and CollectTestItems() or CollectItems()
   local special = count > 0 and PickSpecial(count) or nil
   specialQuestID = special and special.questID or nil

   local slot = 0
   if special then
      slot = 1
      self.SetupQuestItemButton(buttons[1], special)
      slotQuests[1] = special.questID
      buttons[1]:Show()
   end
   for i = 1, count do
      if slot >= numSlots then break end
      local entry = entries[i]
      if entry ~= special then
         slot = slot + 1
         self.SetupQuestItemButton(buttons[slot], entry)
         slotQuests[slot] = entry.questID
         buttons[slot]:Show()
      end
   end
   for i = slot + 1, MAX_BUTTONS do
      buttons[i]:Hide()
      buttons[i].questID = nil
      slotQuests[i] = nil
   end
   PositionButtons(slot)
end

-- Quick keybind mode: QuickKeybindFrame (Blizzard_QuickKeybind, which may
-- load on demand) shown or hidden.
local quickKeybindHooked
local function HookQuickKeybind()
   if quickKeybindHooked or not QuickKeybindFrame then return end
   quickKeybindHooked = true
   local function Update() mod:UpdateQuestBar() end
   QuickKeybindFrame:HookScript("OnShow", Update)
   QuickKeybindFrame:HookScript("OnHide", Update)
end

function mod:SetupQuestBarQuickKeybind()
   HookQuickKeybind()
   if quickKeybindHooked then return end
   local watcher = CreateFrame("Frame")
   watcher:RegisterEvent("ADDON_LOADED")
   watcher:SetScript("OnEvent", function(self)
      HookQuickKeybind()
      if quickKeybindHooked then self:UnregisterAllEvents() end
   end)
end

--- /mqt bardebug: why the bar shows what it shows (for testing).
function mod:DumpQuestBar()
   local profile = self.db.profile
   local print = function(...) self:Print(...) end
   print(format("bar: enabled=%s api=%s holder=%s shown=%s editing=%s binding=%s combat=%s pending=%s test=%s",
      tostring(profile.questBar), tostring(GetQuestLogSpecialItemInfo ~= nil), tostring(holder ~= nil),
      tostring(holder and holder:IsShown()), tostring(self:IsInEditMode()), tostring(InQuickKeybindMode()),
      tostring(InCombatLockdown()), tostring(pending), tostring(testMode)))
   if holder then
      local pos = self:GetQuestBarLayout()
      print(format("layout=%s point=%s x=%.0f y=%.0f scale=%.2f size=%.0fx%.0f buttons=%d timer=%s",
         tostring(GetLayoutName()), pos.point, pos.x, pos.y, pos.scale, holder:GetWidth(), holder:GetHeight(),
         NumButtons(), tostring(self.questBarTimer ~= nil)))
   end
   local focused = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
   print(format("maxDistance=%s focused=%s instance=%s", tostring(profile.questBarMaxDistance), tostring(focused),
      tostring(IsInInstance())))
   local found = 0
   for i = 1, C_QuestLog.GetNumQuestLogEntries() do
      local info = C_QuestLog.GetInfo(i)
      if info and not info.isHeader then
         local link, _, charges, showWhenComplete = GetQuestLogSpecialItemInfo(i)
         if link then
            found = found + 1
            local distanceSq, onContinent
            if C_QuestLog.GetDistanceSqToQuest then
               distanceSq, onContinent = C_QuestLog.GetDistanceSqToQuest(info.questID)
            end
            print(format("  [%d] %d %s: item=%s charges=%s complete=%s showWhenComplete=%s hidden=%s onMap=%s distSq=%s onContinent=%s distance=%s inRange=%s",
               i, info.questID, info.title or "?", link, tostring(charges), tostring(C_QuestLog.IsComplete(info.questID)),
               tostring(showWhenComplete), tostring(info.isHidden), tostring(info.isOnMap), tostring(distanceSq),
               tostring(onContinent), tostring(self.GetQuestDistance(info.questID)),
               tostring(IsQuestLogSpecialItemInRange(i))))
         end
      end
   end
   print(format("%d quest(s) with items in the log", found))
   for i = 1, MAX_BUTTONS do
      local button = buttons[i]
      if button and button:IsShown() then
         print(format("  slot %d: quest=%s item=%s", i, tostring(button.questID), tostring(button:GetAttribute("item1"))))
      end
   end
end

function mod:QuestBarCombatEnded()
   if pending then
      self:ApplyQuestBarLayout()
      self:UpdateQuestBar()
   end
end

--- Starts or stops the bar (and its nearest-item timer) for the profile.
function mod:ApplyQuestBar()
   local enabled = self.db.profile.questBar and GetQuestLogSpecialItemInfo
   if enabled and not self.questBarTimer then
      self.questBarTimer = self:ScheduleRepeatingTimer("UpdateQuestBar", UPDATE_INTERVAL)
   elseif not enabled and self.questBarTimer then
      self:CancelTimer(self.questBarTimer)
      self.questBarTimer = nil
   end
   if not self.questBarQuickKeybind then
      self.questBarQuickKeybind = true
      self:SetupQuestBarQuickKeybind()
   end
   if not holder and LEM and GetQuestLogSpecialItemInfo and not InCombatLockdown() then
      -- Registered with Edit Mode even when off, to be turned on there.
      CreateHolder()
      self:SetupQuestBarEditMode()
   end
   self:ApplyQuestBarLayout()
   self:UpdateQuestBar()
end

----------------------------------------------------------------
-- Edit Mode
----------------------------------------------------------------

local function OnPositionChanged(frame, layoutName)
   if not layoutName then return end
   mod:SnapEditModeFrame(frame)
   local pos = mod:GetQuestBarLayout()
   pos.point, pos.x, pos.y = mod:GetNearestAnchor(frame)
   mod.db.profile.questBarLastLayout = layoutName
   mod:ApplyQuestBarLayout()
end

local function SetAndApply(key)
   return function(_, value)
      mod.db.profile[key] = value
      mod:ApplyQuestBarLayout()
      mod:UpdateQuestBar()
      mod:NotifyOptionsChanged()
   end
end

function mod:SetupQuestBarEditMode()
   if not LEM or self.questBarEditMode then return end
   self.questBarEditMode = true
   LEM:AddFrame(holder, OnPositionChanged, DEFAULT_POSITION)
   self:AddSnapGuides(holder)
   LEM:AddFrameSettings(holder, {
      {
         kind = LEM.SettingType.Checkbox,
         name = L["Show quest item bar"],
         default = false,
         get = function() return mod.db.profile.questBar end,
         set = function(_, value)
            mod.db.profile.questBar = value
            mod:ApplyQuestBar()
            mod:NotifyOptionsChanged()
         end,
      },
      {
         kind = LEM.SettingType.Slider,
         name = L["Scale"],
         default = DEFAULT_POSITION.scale,
         minValue = 0.5, maxValue = 2, valueStep = 0.05,
         formatter = function(value) return ("%d%%"):format(value * 100 + 0.5) end,
         get = function() return mod:GetQuestBarLayout().scale end,
         set = function(_, value)
            mod:GetQuestBarLayout().scale = value
            mod:ApplyQuestBarLayout()
            mod:NotifyOptionsChanged()
         end,
      },
      {
         kind = LEM.SettingType.Slider,
         name = L["Buttons"],
         default = MAX_BUTTONS,
         minValue = 1, maxValue = MAX_BUTTONS, valueStep = 1,
         get = function() return NumButtons() end,
         set = SetAndApply("questBarButtons"),
      },
      {
         kind = LEM.SettingType.Slider,
         name = L["Spacing"],
         default = 4,
         minValue = 0, maxValue = 20, valueStep = 1,
         get = function() return mod.db.profile.questBarSpacing end,
         set = SetAndApply("questBarSpacing"),
      },
      {
         kind = LEM.SettingType.Checkbox,
         name = L["Vertical"],
         default = false,
         get = function() return mod.db.profile.questBarVertical end,
         set = SetAndApply("questBarVertical"),
      },
      {
         kind = LEM.SettingType.Dropdown,
         name = L["Alignment"],
         default = "center",
         values = function()
            local values = {}
            for _, key in ipairs({ "start", "center", "end" }) do
               values[#values + 1] = { text = mod:GetQuestBarAlignLabels()[key], value = key }
            end
            return values
         end,
         get = function() return mod.db.profile.questBarAlign end,
         set = SetAndApply("questBarAlign"),
      },
   })
   LEM:RegisterCallback("layout", function() mod:ApplyQuestBarLayout() end)
   LEM:RegisterCallback("enter", function() mod:UpdateQuestBar() end)
   -- Registered after the tracker's callbacks, so mod.inEditMode is current.
   LEM:RegisterCallback("exit", function() mod:UpdateQuestBar() end)
   LEM:RegisterCallback("rename", function(oldName, newName)
      local layouts = mod.db.profile.questBarLayouts
      layouts[newName], layouts[oldName] = layouts[oldName], nil
   end)
   LEM:RegisterCallback("delete", function(layoutName)
      mod.db.profile.questBarLayouts[layoutName] = nil
   end)
end
