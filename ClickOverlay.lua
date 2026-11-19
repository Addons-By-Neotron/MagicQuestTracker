--[[
MagicQuestTracker - Secure click-through to Blizzard's tracker blocks.

Opening the map or the quest log, completing an auto-complete quest and
untracking a quest all run Blizzard UI code. Run from addon code, that code
and the state it leaves behind are tainted, and Blizzard's map is later
blocked in combat (SetPassThroughButtons and similar). Blizzard's own tracker
still has a block for every watched quest and tracked recipe, even while it
is hidden (alpha 0), and its header button does all of this from secure code.

So one SecureActionButton (type "click") is placed over the title text of
the hovered quest or recipe line and clicks that header button:

  * quests: the untrack modifier (QUESTWATCHTOGGLE) untracks it. A plain
    click opens our details window, whose "Show on map" / "Complete quest"
    button clicks the header the same way (PlaceQuestHeaderClick below).
  * recipes: a plain left click opens the recipe; the untrack modifier
    (RECIPEWATCHTOGGLE) untracks it.

Every other click (right click, Ctrl waypoint, ...) falls through to the
line's own click handler from PostClick. Out of combat only: secure frames
can't be moved in combat, so the overlay hides when combat starts and the
lines handle clicks themselves until it ends. Lines without a Blizzard block
(unwatched quests, bonus objectives, world quests) never get the overlay.

Placed by screen position under UIParent, never anchored to the tracker, so
the tracker stays free to move, scroll and hide in combat.
]]

local mod = LibStub("AceAddon-3.0"):GetAddon("MagicQuestTracker")

local InCombatLockdown = InCombatLockdown

local NOOP = ATTRIBUTE_NOOP or ""

-- Blizzard's quest modules, in lookup order.
local QUEST_MODULES = { "QuestObjectiveTracker", "CampaignQuestObjectiveTracker" }

-- Every modifier prefix a click can have (SecureButton_GetModifierPrefix).
local PREFIXES = {
   "", "shift-", "ctrl-", "alt-", "ctrl-shift-", "alt-shift-", "alt-ctrl-", "alt-ctrl-shift-",
}

-- A modified click binding (GetModifiedClick) as a prefix: single modifiers only.
local BINDING_PREFIX = { SHIFT = "shift-", CTRL = "ctrl-", ALT = "alt-" }

local overlay

-- The header button of Blizzard's block with this ID in a module, if any.
local function GetHeader(moduleName, id)
   local module = _G[moduleName]
   local block = module and module.GetExistingBlock and module:GetExistingBlock(id)
   return block and block.id == id and block.HeaderButton or nil
end

local function GetQuestHeader(questID)
   for _, name in ipairs(QUEST_MODULES) do
      local header = GetHeader(name, questID)
      if header then return header end
   end
end

-- Blizzard keys recraft recipe blocks by the negated recipe ID.
local function GetRecipeHeader(recipe)
   return GetHeader("ProfessionsRecipeTracker", recipe.isRecraft and -recipe.recipeID or recipe.recipeID)
end

--- The Blizzard header a line's clicks go to, and the prefixes (as a set)
--- whose left click it takes; nil when the line has none.
local function GetTarget(line)
   local data = line.data
   if not data then return end
   if line.kind == "quest" then
      if data.isTask or data.isWorldQuest then return end
      local header = GetQuestHeader(data.questID)
      if not header then return end
      -- A plain click opens our details window (from PostClick); the map
      -- and auto-complete are buttons there (PlaceQuestHeaderClick).
      local prefixes = {}
      local untrack = BINDING_PREFIX[GetModifiedClick("QUESTWATCHTOGGLE") or ""]
      if untrack then prefixes[untrack] = true end
      return header, prefixes
   elseif line.kind == "recipe" then
      local header = GetRecipeHeader(data)
      if not header then return end
      local prefixes = { [""] = true }
      local untrack = BINDING_PREFIX[GetModifiedClick("RECIPEWATCHTOGGLE") or ""]
      if untrack then prefixes[untrack] = true end
      return header, prefixes
   end
end

local function Overlay_PostClick(self, button)
   local line = self.line
   if not line then return end
   -- Blizzard's header took the click; the watch list events update the tracker.
   if SecureButton_GetModifiedAttribute(self, "type", button) == "click" then return end
   mod.LineOnClick(line, button)
end

local function Overlay_OnEnter(self)
   if self.line then mod.LineOnEnter(self.line) end
end

local function Overlay_OnLeave(self)
   local line = self.line
   if line then mod.LineOnLeave(line) end
end

local function CreateOverlay()
   overlay = CreateFrame("Button", "MagicQuestTrackerClickOverlay", UIParent, "SecureActionButtonTemplate")
   overlay:RegisterForClicks("LeftButtonUp", "RightButtonUp")
   overlay:SetAttribute("useOnKeyDown", false)
   overlay:SetScript("PostClick", Overlay_PostClick)
   overlay:SetScript("OnEnter", Overlay_OnEnter)
   overlay:SetScript("OnLeave", Overlay_OnLeave)
   overlay:Hide()
end

--- Hides the overlay. Out of combat only, except from PLAYER_REGEN_DISABLED
--- (force), where protected changes are still allowed.
function mod:HideClickOverlay(force)
   if not overlay or not overlay:IsShown() then return end
   if InCombatLockdown() and not force then return end
   overlay:Hide()
   overlay.line = nil
end

--- Places the overlay over a line's title text, if its clicks go to a
--- Blizzard block.
function mod:ShowClickOverlay(line)
   if InCombatLockdown() or self.previewing or self:IsInEditMode() then return end
   local header, prefixes = GetTarget(line)
   if header and not next(prefixes) then header = nil end
   if not header then
      if overlay and overlay.line ~= line then self:HideClickOverlay() end
      return
   end
   local scroll = self.frame and self.frame.scroll
   local left, width = line.text:GetLeft(), line.text:GetWidth()
   local lineTop, lineBottom = line:GetTop(), line:GetBottom()
   local viewTop, viewBottom = scroll and scroll:GetTop(), scroll and scroll:GetBottom()
   if not (left and width and lineTop and lineBottom and viewTop and viewBottom) then return end
   -- Only the part inside the scroll view.
   local top, bottom = math.min(lineTop, viewTop), math.max(lineBottom, viewBottom)
   if top <= bottom then
      self:HideClickOverlay()
      return
   end

   if not overlay then CreateOverlay() end
   local s = line:GetEffectiveScale() / overlay:GetEffectiveScale()
   overlay:SetFrameStrata(self.frame:GetFrameStrata())
   overlay:SetFrameLevel(line:GetFrameLevel() + 5)
   overlay:ClearAllPoints()
   overlay:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * s, top * s)
   overlay:SetSize(width * s, (top - bottom) * s)
   for _, prefix in ipairs(PREFIXES) do
      local on = prefixes[prefix]
      overlay:SetAttribute(prefix .. "type1", on and "click" or NOOP)
      overlay:SetAttribute(prefix .. "clickbutton1", on and header or nil)
   end
   overlay.line = line
   overlay:Show()
end

--- A line lost the mouse: the overlay goes too, unless the mouse moved onto it.
function mod:OnClickOverlayLineLeave(line)
   if overlay and overlay.line == line and not overlay:IsMouseOver() then
      self:HideClickOverlay()
   end
end

--- After a render or scroll the lines have moved or been reused: put the
--- overlay on the line now under the mouse, or hide it.
local function RefreshClickOverlay()
   mod.clickOverlayPending = nil
   if not overlay or not overlay:IsShown() or InCombatLockdown() then return end
   local frame = mod.frame
   if frame and frame:IsVisible() then
      for i = 1, mod.numLinesUsed do
         local line = mod.lines[i]
         if (line.kind == "quest" or line.kind == "recipe") and line:IsVisible() and line:IsMouseOver() then
            mod:ShowClickOverlay(line)
            return
         end
      end
   end
   mod:HideClickOverlay()
end

function mod:RequestClickOverlayRefresh()
   if not overlay or not overlay:IsShown() or self.clickOverlayPending then return end
   self.clickOverlayPending = true
   C_Timer.After(0, RefreshClickOverlay)
end

----------------------------------------------------------------
-- Secure click on a details window button
--
-- The quest details window's "Show on map" / "Complete quest" button is a
-- plain button; while it can work, a second SecureActionButton sits over it
-- and clicks the quest's Blizzard header button (same as the line overlay).
-- Placed by screen position under UIParent, out of combat only, and hidden
-- while the window is dragged, so the window itself stays unprotected and
-- free to show, hide and move in combat.
----------------------------------------------------------------

local headerClick

local function HeaderClick_OnEnter(self)
   local target = self.target
   if target then
      target:LockHighlight()
      local onEnter = target:GetScript("OnEnter")
      if onEnter then onEnter(target) end
   end
end

local function HeaderClick_OnLeave(self)
   local target = self.target
   if target then
      target:UnlockHighlight()
      local onLeave = target:GetScript("OnLeave")
      if onLeave then onLeave(target) end
   end
end

local function CreateHeaderClick()
   headerClick = CreateFrame("Button", "MagicQuestTrackerDetailsHeaderClick", UIParent, "SecureActionButtonTemplate")
   headerClick:RegisterForClicks("LeftButtonUp")
   headerClick:SetAttribute("useOnKeyDown", false)
   for _, prefix in ipairs(PREFIXES) do
      headerClick:SetAttribute(prefix .. "type1", NOOP)
   end
   headerClick:SetScript("OnEnter", HeaderClick_OnEnter)
   headerClick:SetScript("OnLeave", HeaderClick_OnLeave)
   headerClick:SetScript("PostClick", function(self)
      if self.target then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
   end)
   headerClick:Hide()
end

--- True when a plain click on the quest's Blizzard header can be sent from
--- a details window button: out of combat, and Blizzard's tracker has a
--- block for it (a watched quest).
function mod:CanClickQuestHeader(questID)
   return not InCombatLockdown() and GetQuestHeader(questID) ~= nil
end

--- Hides the secure click (force: from PLAYER_REGEN_DISABLED).
function mod:HideQuestHeaderClick(force)
   if not headerClick or not headerClick:IsShown() then return end
   if InCombatLockdown() and not force then return end
   if headerClick:IsMouseOver() then HeaderClick_OnLeave(headerClick) end
   headerClick:Hide()
   headerClick.target = nil
end

--- Covers a button with a secure plain left click on the quest's Blizzard
--- header (opens the map, or completes an auto-complete quest). Returns
--- false (and hides it) when that isn't possible. allowLog: without a
--- header (not tracked, or past the bottom of Blizzard's tracker) click
--- the quest log micro button instead; the second return is then true.
function mod:PlaceQuestHeaderClick(button, questID, allowLog)
   if InCombatLockdown() then
      self:HideQuestHeaderClick()
      return false
   end
   local header = GetQuestHeader(questID)
   local viaLog = false
   if not header and allowLog and QuestLogMicroButton then
      header, viaLog = QuestLogMicroButton, true
   end
   local left, bottom, width, height = button:GetRect()
   if not header or not left or not button:IsVisible() then
      self:HideQuestHeaderClick()
      return false
   end
   if not headerClick then CreateHeaderClick() end
   local s = button:GetEffectiveScale() / headerClick:GetEffectiveScale()
   headerClick:SetFrameStrata("FULLSCREEN")
   headerClick:ClearAllPoints()
   headerClick:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * s, bottom * s)
   headerClick:SetSize(width * s, height * s)
   headerClick:SetAttribute("type1", "click")
   headerClick:SetAttribute("clickbutton1", header)
   headerClick.target = button
   headerClick:Show()
   return true, viaLog
end
