--[[
**********************************************************************
MagicQuestTracker - Tracker frame, rendering, scrolling and click handling.
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
local media = LibStub("LibSharedMedia-3.0")

local C_QuestLog = C_QuestLog
local InCombatLockdown = InCombatLockdown

----------------------------------------------------------------
-- Layout constants
----------------------------------------------------------------

local TITLE_PADDING = 6
-- Header art as in Blizzard's tracker: drawn at the atlas' natural height,
-- full alpha, in a header block at least this tall with the text centered.
local TITLE_ATLAS = "ui-questtracker-primary-objective-header"
local HEADER_ATLAS = "UI-QuestTracker-Secondary-Objective-Header"
local TITLE_MIN_HEIGHT = 30
local BLIZZARD_TRACKER_WIDTH = 260
local HEADER_MIN_HEIGHT = 24
local HEADER_TEXT_INDENT = 7
local SCROLLBAR_WIDTH = 4
local SCROLL_STEP = 40
local FADE_IN = 0.15   -- seconds (scrollbar and background hover fade)
local FADE_OUT = 0.6
local ZONE_INDENT = 4
local QUEST_INDENT = 6
local OBJECTIVE_INDENT = 16
-- With quest POI buttons (left of the title), like Blizzard's tracker.
local POI_QUEST_INDENT = 26
local POI_OBJECTIVE_INDENT = 30
local GROUP_BUTTON_SIZE = 24

local function Color(key, r, g, b)
   local c = OBJECTIVE_TRACKER_COLOR and OBJECTIVE_TRACKER_COLOR[key]
   if c then return c.r, c.g, c.b end
   return r, g, b
end

-- Shared color tables (never modified), so rendering doesn't allocate them.
local COLOR_NORMAL = { Color("Normal", 0.8, 0.8, 0.8) }
local COLOR_COMPLETE = { Color("Complete", 0.6, 0.6, 0.6) }
local COLOR_HEADER = { Color("Header", 0.75, 0.61, 0) }
local COLOR_FAILED = { Color("Failed", 1, 0.1, 0.1) }
local COLOR_TIME_LEFT = { Color("TimeLeft", 0.75, 0.1, 0.1) }
local COLOR_ZONE = { NORMAL_FONT_COLOR:GetRGB() }
local COLOR_WHITE = { 1, 1, 1 }

-- Line data for section headers (constant per section key).
local SECTION_DATA = setmetatable({}, { __index = function(t, key)
   local data = { key = key }
   t[key] = data
   return data
end })

----------------------------------------------------------------
-- Fonts: one Font object per role, updated from the profile.
----------------------------------------------------------------

local FONT_ROLES = { "title", "module", "zone", "quest", "objective" }
local fontObjects = {}

function mod:UpdateFonts()
   for _, role in ipairs(FONT_ROLES) do
      local cfg = self.db.profile.fonts[role]
      local font = fontObjects[role]
      if not font then
         font = CreateFont("MagicQuestTrackerFont_" .. role)
         fontObjects[role] = font
      end
      local path = media:Fetch("font", cfg.face) or STANDARD_TEXT_FONT
      font:SetFont(path, cfg.size, cfg.outline or "")
      if cfg.outline == nil or cfg.outline == "" then
         font:SetShadowColor(0, 0, 0, 1)
         font:SetShadowOffset(1, -1)
      else
         font:SetShadowOffset(0, 0)
      end
   end
end

----------------------------------------------------------------
-- Frame creation
----------------------------------------------------------------

local function OnScrollWheel(scroll, delta)
   -- Secure item buttons can't follow the scroll in combat.
   if mod:IsItemLayoutLocked() then return end
   local maxScroll = math.max(0, scroll.contentHeight - scroll.viewHeight)
   local value = math.min(maxScroll, math.max(0, scroll:GetVerticalScroll() - delta * SCROLL_STEP))
   scroll:SetVerticalScroll(value)
   mod:UpdateScrollBar()
   mod:RequestItemButtonLayout()
end

function mod:CreateTracker()
   if self.frame then return end
   self:UpdateFonts()

   local frame = CreateFrame("Frame", "MagicQuestTrackerFrame", UIParent)
   frame:SetFrameStrata("LOW")
   frame:SetClampedToScreen(true)
   frame:SetMovable(true)
   frame:SetDontSavePosition(true)
   self.frame = frame

   frame.bg = frame:CreateTexture(nil, "BACKGROUND")
   frame.bg:SetAllPoints()
   frame.bg:SetColorTexture(0, 0, 0, 1)
   frame.bg:SetAlpha(0)

   -- Title bar: quest count, minimize button. Moved and sized in Edit Mode.
   local title = CreateFrame("Button", nil, frame)
   title:SetPoint("TOPLEFT")
   title:SetPoint("TOPRIGHT")
   title:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
   title:SetScript("OnClick", function(_, button)
      if button == "RightButton" then
         mod:OpenConfig()
      elseif button == "MiddleButton" then
         mod:ToggleCurrentZoneOnly()
      end
   end)
   title:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:AddLine(L["Middle-click: Toggle current zone only"], 1, 1, 1)
      GameTooltip:AddLine(L["Right-click: Options"], 1, 1, 1)
      GameTooltip:Show()
   end)
   title:SetScript("OnLeave", GameTooltip_Hide)
   frame.title = title

   title.text = title:CreateFontString(nil, "OVERLAY")
   title.text:SetFontObject(fontObjects.title)
   title.text:SetJustifyH("LEFT")
   title.text:SetWordWrap(false)
   title.text:SetTextColor(NORMAL_FONT_COLOR:GetRGB())

   local minimize = CreateFrame("Button", nil, title)
   minimize:SetSize(20, 20)
   minimize:SetPoint("RIGHT", -2, 0)
   minimize:SetHighlightAtlas("ui-questtrackerbutton-red-highlight", "ADD")
   minimize:SetScript("OnClick", function() mod:ToggleMinimized() end)
   title.minimize = minimize
   title.text:SetPoint("LEFT", HEADER_TEXT_INDENT, 0)
   title.text:SetPoint("RIGHT", minimize, "LEFT", -4, 0)

   title.bg = title:CreateTexture(nil, "BACKGROUND")
   -- Natural size, centered: on Blizzard's 260 px header the art overhangs
   -- both ends (the swirl left of the text). ApplyLayout keeps that overhang.
   title.bg:SetAtlas(TITLE_ATLAS, true)
   title.bg:SetPoint("CENTER")
   title.bg.naturalWidth = title.bg:GetWidth()

   -- Scroll area
   local scroll = CreateFrame("ScrollFrame", nil, frame)
   scroll:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
   scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SCROLLBAR_WIDTH - 2, 0)
   scroll:EnableMouseWheel(true)
   scroll:SetScript("OnMouseWheel", OnScrollWheel)
   scroll.contentHeight = 0
   scroll.viewHeight = 0
   frame.scroll = scroll

   local child = CreateFrame("Frame", nil, scroll)
   child:SetSize(1, 1)
   scroll:SetScrollChild(child)
   frame.child = child

   local bar = frame:CreateTexture(nil, "OVERLAY")
   bar:SetColorTexture(1, 0.82, 0, 0.5)
   bar:SetWidth(SCROLLBAR_WIDTH)
   bar:SetAlpha(0)
   frame.scrollThumb = bar

   -- The tracker is click-through, so hover is polled rather than using OnEnter/OnLeave.
   local function FadeToward(region, target, elapsed, hovered)
      local alpha = region:GetAlpha()
      if alpha == target then return end
      local step = elapsed / (hovered and FADE_IN or FADE_OUT)
      if alpha < target then
         region:SetAlpha(math.min(target, alpha + step))
      else
         region:SetAlpha(math.max(target, alpha - step))
      end
   end

   frame:SetScript("OnUpdate", function(self, elapsed)
      mod:TickArrows(elapsed)
      local hovered = self:IsMouseOver()
      local profile = mod.db.profile
      FadeToward(self.bg, hovered and profile.backgroundHoverAlpha or profile.backgroundAlpha, elapsed, hovered)
      if bar:IsShown() then
         FadeToward(bar, hovered and 1 or 0, elapsed, hovered)
      end
   end)

   self.lines = {}
   self.numLinesUsed = 0
   self:SetupEditMode()
end

----------------------------------------------------------------
-- Position / layout
----------------------------------------------------------------

function mod:ApplyLayout()
   local frame = self.frame
   if not frame then return end
   if self:IsItemLayoutLocked() then
      -- Would move the tracker out from under the frozen item buttons.
      self.applyLayoutDeferred = true
      return
   end
   local profile = self.db.profile
   self:UpdateFonts()

   frame:SetScale(profile.scale)
   frame:SetWidth(profile.width)
   self:ApplyPosition()
   local c = profile.backgroundColor
   frame.bg:SetColorTexture(c.r, c.g, c.b, 1)
   frame.bg:SetAlpha(frame:IsMouseOver() and profile.backgroundHoverAlpha or profile.backgroundAlpha)

   local titleHeight = math.max(TITLE_MIN_HEIGHT, profile.fonts.title.size + TITLE_PADDING)
   frame.title:SetHeight(titleHeight)
   frame.title.bg:SetWidth(frame.title.bg.naturalWidth + profile.width - BLIZZARD_TRACKER_WIDTH)
   frame.title:EnableMouse(true)
   self:UpdateMinimizeButton()
   self:RequestUpdate()
end

function mod:UpdateMinimizeButton()
   local button = self.frame.title.minimize
   local minimized = self.db.char.minimized
   local atlas = minimized and "ui-questtrackerbutton-expand-all" or "ui-questtrackerbutton-collapse-all"
   button:SetNormalAtlas(atlas)
   button:SetPushedAtlas(atlas .. "-pressed")
end

function mod:ToggleCurrentZoneOnly()
   self.db.profile.onlyCurrentZone = not self.db.profile.onlyCurrentZone
   self:NotifyOptionsChanged()
   self:RequestUpdate()
end

function mod:ToggleMinimized()
   if self:IsItemLayoutLocked() then return end
   self.db.char.minimized = not self.db.char.minimized
   self:UpdateMinimizeButton()
   self:RequestUpdate()
end

function mod:UpdateScrollBar()
   local frame = self.frame
   local scroll = frame.scroll
   local viewHeight = scroll.viewHeight
   local contentHeight = scroll.contentHeight
   local thumb = frame.scrollThumb
   if self.db.char.minimized or contentHeight <= viewHeight + 0.5 or viewHeight <= 0 then
      thumb:Hide()
      return
   end
   local thumbHeight = math.max(12, viewHeight * viewHeight / contentHeight)
   local maxScroll = contentHeight - viewHeight
   local offset = (viewHeight - thumbHeight) * (scroll:GetVerticalScroll() / maxScroll)
   thumb:ClearAllPoints()
   thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", SCROLLBAR_WIDTH + 2, -offset)
   thumb:SetHeight(thumbHeight)
   thumb:Show()
end

----------------------------------------------------------------
-- Line pool
----------------------------------------------------------------

local function Line_OnEnter(line)
   if line.highlightColor then
      line.text:SetTextColor(unpack(line.highlightColor))
   end
   if line.kind == "quest" and IsInGroup() then
      GameTooltip:SetOwner(line, "ANCHOR_LEFT")
      GameTooltip:SetQuestPartyProgress(line.data.questID)
   end
end

local function Line_OnLeave(line)
   if line.color then
      line.text:SetTextColor(unpack(line.color))
   end
   GameTooltip:Hide()
end

local function Line_OnClick(line, button)
   local handler = mod.lineClickHandlers[line.kind]
   if handler then
      handler(mod, line, line.data, button)
   end
end

local function AcquireLine()
   mod.numLinesUsed = mod.numLinesUsed + 1
   local line = mod.lines[mod.numLinesUsed]
   if not line then
      line = CreateFrame("Button", nil, mod.frame.child)
      line:RegisterForClicks("LeftButtonUp", "RightButtonUp")
      line:SetScript("OnEnter", Line_OnEnter)
      line:SetScript("OnLeave", Line_OnLeave)
      line:SetScript("OnClick", Line_OnClick)
      line.text = line:CreateFontString(nil, "OVERLAY")
      line.text:SetJustifyH("LEFT")
      line.text:SetJustifyV("TOP")
      line.text:SetWordWrap(true)
      line.rightText = line:CreateFontString(nil, "OVERLAY")
      line.rightText:SetJustifyH("RIGHT")
      line.rightText:SetWordWrap(false)
      line.arrow = line:CreateTexture(nil, "OVERLAY")
      line.arrow:SetTexture("Interface\\AddOns\\MagicQuestTracker\\Textures\\Arrow")
      line.arrow:SetVertexColor(1, 0.82, 0)
      line.collapseIcon = line:CreateTexture(nil, "OVERLAY")
      line.collapseIcon:SetSize(16, 16)
      line.collapseIcon:SetPoint("RIGHT", -2, 0)
      line.bg = line:CreateTexture(nil, "BACKGROUND")
      line.bg:SetAtlas(HEADER_ATLAS, true)
      line.bg:SetPoint("LEFT")
      line.bg:SetPoint("RIGHT")
      mod.lines[mod.numLinesUsed] = line
   end
   line:Show()
   return line
end

local function ReleaseUnusedLines(numUsed)
   for i = numUsed + 1, #mod.lines do
      local line = mod.lines[i]
      line:Hide()
      line.data = nil
      line.kind = nil
      line.arrowTarget = nil
   end
end

----------------------------------------------------------------
-- Rendering
----------------------------------------------------------------

local layout = {}  -- reused render state

local function AddLine(kind, data, text, role, indent, spacing, color, highlightColor, showHeaderBg, rightText, arrowTarget)
   local line = AcquireLine()
   line.kind = kind
   line.data = data
   line.color = color
   line.highlightColor = highlightColor
   line:EnableMouse(highlightColor ~= nil)

   local width = layout.width - indent - (layout.rightInset or 0)
   if rightText then
      local right = line.rightText
      right:SetFontObject(fontObjects.objective)
      right:SetText(rightText)
      right:SetTextColor(0.6, 0.6, 0.6)
      right:ClearAllPoints()
      right:SetPoint("TOPRIGHT", -(layout.rightInset or 0), 0)
      right:Show()
      width = width - right:GetStringWidth() - 4
   else
      line.rightText:Hide()
   end
   line.arrowTarget = arrowTarget
   line.collapseIcon:Hide()
   if line.poiButton then line.poiButton:Hide() end
   if line.groupButton then line.groupButton:Hide() end
   if arrowTarget then
      -- Arrow sits left of the distance text, centered on the first text
      -- line (it may be taller than the text); rotated by mod:UpdateArrows().
      local size = mod.db.profile.arrowSize
      local offset = (layout.rightInset or 0) + (rightText and line.rightText:GetStringWidth() + 3 or 0)
      local lineHeight = mod.db.profile.fonts[role].size
      line.arrow:SetSize(size, size)
      line.arrow:ClearAllPoints()
      line.arrow:SetPoint("CENTER", line, "TOPRIGHT", -offset - size / 2, -lineHeight / 2)
      width = width - size - 3
   else
      line.arrow:Hide()
   end
   line.text:SetFontObject(fontObjects[role])
   line.text:ClearAllPoints()
   if showHeaderBg then
      line.text:SetPoint("LEFT", indent + HEADER_TEXT_INDENT, 0)
      width = width - HEADER_TEXT_INDENT
   else
      line.text:SetPoint("TOPLEFT", indent, 0)
   end
   line.text:SetWidth(width)
   line.text:SetText(text)
   line.text:SetTextColor(unpack(color))
   line.bg:SetShown(showHeaderBg or false)

   local height = math.ceil(line.text:GetStringHeight())
   if showHeaderBg then
      height = math.max(HEADER_MIN_HEIGHT, height + 6)
   end
   -- A header can override the gap before the next line (layout.nextSpacing).
   if layout.y > 0 then
      layout.y = layout.y + (layout.nextSpacing or spacing)
   end
   layout.nextSpacing = nil
   line:ClearAllPoints()
   line:SetPoint("TOPLEFT", mod.frame.child, "TOPLEFT", 0, -layout.y)
   line:SetSize(layout.width, height)
   layout.y = layout.y + height
   return line
end

-- Difficulty colors depend on the player's level; cached per (quest, player) level.
local difficultyColors = {}
local function DifficultyColor(level)
   -- World quests / bonus objectives have no level.
   if not (level and GetQuestDifficultyColor) then return COLOR_HEADER end
   local key = level * 1000 + UnitLevel("player")
   local color = difficultyColors[key]
   if not color then
      local c = GetQuestDifficultyColor(level)
      color = c and { c.r, c.g, c.b } or COLOR_HEADER
      difficultyColors[key] = color
   end
   return color
end

-- Level suffix by quest tag ID (Enum.QuestTag values).
local TAG_SUFFIX = {
   [62] = "R",  -- Raid
   [88] = "R",  -- Raid (10)
   [89] = "R",  -- Raid (25)
   [81] = "D",  -- Dungeon
   [85] = "H",  -- Heroic
}

local function GetLevelSuffix(quest)
   local suffix = quest.tagID and TAG_SUFFIX[quest.tagID]
   if suffix then
      return suffix
   end
   if quest.isElite or (quest.suggestedGroup and quest.suggestedGroup > 0) then
      return "+"
   end
   return ""
end

-- Infinity sign from ForeverQuestTint; visible area inside the 64x64 image.
local INFINITY_PATH = "Interface\\AddOns\\MagicQuestTracker\\Textures\\Infinity"
local INFINITY_L, INFINITY_R, INFINITY_T, INFINITY_B = 1, 63, 12, 51

local function ForeverMarker(profile)
   local size = profile.fonts.quest.size
   local h = math.max(6, math.floor(size * 0.65 + 0.5))
   local w = math.floor(h * (INFINITY_R - INFINITY_L) / (INFINITY_B - INFINITY_T) + 0.5)
   -- Inline textures are centered on the line; drop it toward the text baseline.
   local offY = -math.floor(size * 0.25 + 0.5)
   -- |T path:height:width:offX:offY:texW:texH:left:right:top:bottom:r:g:b|t
   return format("|T%s:%d:%d:0:%d:64:64:%d:%d:%d:%d:153:230:242|t",
      INFINITY_PATH, h, w, offY, INFINITY_L, INFINITY_R, INFINITY_T, INFINITY_B)
end

local titleLabels = {}

local function FormatQuestTitle(quest, profile)
   local title = quest.title
   if profile.showLevel and quest.level then
      title = format("[%d%s] %s", quest.level, GetLevelSuffix(quest), title)
   end
   if quest.isForeverQuest and profile.markForeverQuests then
      title = title .. " " .. ForeverMarker(profile)
   end
   if profile.showQuestTags then
      local labels = titleLabels
      wipe(labels)
      if quest.tagName and quest.tagName ~= "" then
         tinsert(labels, quest.tagName)
      end
      if Enum.QuestFrequency then
         if quest.frequency == Enum.QuestFrequency.Daily then
            tinsert(labels, DAILY or L["Daily"])
         elseif quest.frequency == Enum.QuestFrequency.Weekly then
            tinsert(labels, WEEKLY or L["Weekly"])
         end
      end
      if #labels > 0 then
         title = format("%s |cffff8040(%s)|r", title, table.concat(labels, ", "))
      end
   end
   return title
end

-- Highlight colors, cached per (shared) color table.
local brightened = setmetatable({}, { __mode = "k" })
local function Brighten(color)
   local bright = brightened[color]
   if not bright then
      bright = { math.min(1, color[1] + 0.2), math.min(1, color[2] + 0.2), math.min(1, color[3] + 0.2) }
      brightened[color] = bright
   end
   return bright
end

local function POIButtonsEnabled(profile)
   if not (profile.showPOIButtons and POIButtonUtil) then return false end
   -- Blizzard's tracker hides POI buttons when the questPOI CVar is off.
   local cvar = GetCVar("questPOI")
   return cvar == nil or cvar == "1"
end

local function CanFindGroup(quest)
   return QuestUtil and QuestUtil.CanCreateQuestGroup and C_LFGList
      and QuestUtil.CanCreateQuestGroup(quest.questID) or false
end

-- Quest POI button (same as Blizzard's tracker): shows in progress / complete,
-- highlighted when focused; clicking it focuses (super tracks) the quest.
local function AttachPOIButton(line, quest)
   local button = line.poiButton
   if not button then
      button = CreateFrame("Button", nil, line, "POIButtonTemplate")
      line.poiButton = button
   end
   button:SetQuestID(quest.questID)
   local style
   if quest.isWorldQuest then
      style = POIButtonUtil.Style.WorldQuest
   elseif quest.isTask then
      style = POIButtonUtil.Style.BonusObjective
   elseif quest.isComplete then
      style = POIButtonUtil.Style.QuestComplete
   else
      style = POIButtonUtil.Style.QuestInProgress
   end
   button:SetStyle(style)
   button:SetSelected(quest.isSuperTracked)
   button:SetPingWorldMap(quest.isWorldQuest or false)
   button:UpdateButtonStyle()
   button:ClearAllPoints()
   button:SetPoint("TOPRIGHT", line.text, "TOPLEFT", -4, 4)
   button:Show()
end

-- Blizzard's "find group" button, left of the item button.
local function AttachGroupButton(line, quest, rightOffset)
   local button = line.groupButton
   if not button then
      button = CreateFrame("Button", nil, line, "QuestObjectiveFindGroupButtonTemplate")
      button:SetSize(GROUP_BUTTON_SIZE, GROUP_BUTTON_SIZE)
      line.groupButton = button
   end
   button:SetUp(quest.questID)
   button:ClearAllPoints()
   button:SetPoint("TOPRIGHT", line, "TOPRIGHT", -rightOffset, 4)
   button:Show()
end

function mod:RenderQuest(quest, profile)
   local normal, complete = COLOR_NORMAL, COLOR_COMPLETE
   local titleColor = profile.colorByDifficulty and DifficultyColor(quest.difficultyLevel) or COLOR_HEADER
   local itemSize = (profile.showItemButtons and quest.hasItem) and self.ITEM_BUTTON_SIZE or 0
   local groupSize = (profile.showFindGroupButton and CanFindGroup(quest)) and GROUP_BUTTON_SIZE or 0
   layout.rightInset = itemSize + groupSize
   local showPOI = POIButtonsEnabled(profile)
   local questIndent = showPOI and POI_QUEST_INDENT or QUEST_INDENT
   local objectiveIndent = showPOI and POI_OBJECTIVE_INDENT or OBJECTIVE_INDENT

   local distanceText = profile.showDistance and quest.distance and format(L["%d yd"], math.floor(quest.distance + 0.5)) or nil
   local arrowTarget = profile.showDirection and quest.poi or nil
   -- Quests in the current zone always get an arrow; the limit is for other zones.
   if arrowTarget and profile.arrowMaxDistance > 0 and not quest.inCurrentZone then
      local distance = quest.distance or self:GetPOIDistance(arrowTarget)
      if not distance or distance > profile.arrowMaxDistance then
         arrowTarget = nil
      end
   end
   local titleLine = AddLine("quest", quest, FormatQuestTitle(quest, profile), "quest", questIndent, profile.questSpacing,
      titleColor, Brighten(titleColor), nil, distanceText, arrowTarget)
   local questTop = layout.y - titleLine:GetHeight()
   if showPOI then
      AttachPOIButton(titleLine, quest)
   end
   if groupSize > 0 then
      AttachGroupButton(titleLine, quest, itemSize)
   end
   if itemSize > 0 then
      tinsert(self.itemEntries, self.newHash("line", titleLine, "quest", quest))
   end

   if quest.isFailed then
      AddLine("objective", quest, FAILED or L["Failed"], "objective", objectiveIndent, profile.objectiveSpacing,
         COLOR_FAILED)
   elseif quest.isComplete then
      local text = quest.completionText
      if not text or text == "" then
         text = QUEST_WATCH_QUEST_READY or L["Ready for turn-in"]
      end
      AddLine("objective", quest, text, "objective", objectiveIndent, profile.objectiveSpacing, normal)
   else
      for _, objective in ipairs(quest.objectives) do
         if not objective.finished then
            AddLine("objective", quest, "- " .. objective.text, "objective", objectiveIndent, profile.objectiveSpacing, normal)
         elseif profile.showCompletedObjectives then
            AddLine("objective", quest, "- " .. objective.text, "objective", objectiveIndent, profile.objectiveSpacing, complete)
         end
      end
   end
   if quest.timeLeftText then
      AddLine("objective", quest, quest.timeLeftText, "objective", objectiveIndent, profile.objectiveSpacing,
         COLOR_TIME_LEFT)
   end
   -- Make room for the whole item / group button before the next quest.
   local buttonSize = math.max(itemSize, groupSize)
   if buttonSize > 0 and layout.y - questTop < buttonSize then
      layout.y = questTop + buttonSize
   end
   layout.rightInset = 0
end

-- Section headers (Quests, World Quests, ...) look like Blizzard's module
-- headers: header bar, collapse icon on the right, click to fold.
-- Returns true when the section is expanded.
function mod:RenderSectionHeader(key, text, profile)
   local collapsed = self.db.char.collapsedSections[key]
   local line = AddLine("section", SECTION_DATA[key], text, "module", 0, profile.sectionSpacing, COLOR_ZONE, Brighten(COLOR_ZONE), true)
   local icon = line.collapseIcon
   icon:SetAtlas(collapsed and "ui-questtrackerbutton-secondary-expand" or "ui-questtrackerbutton-secondary-collapse")
   icon:Show()
   if not collapsed then
      layout.nextSpacing = profile.zoneHeaderSpacing
   end
   return not collapsed
end

function mod:RenderTaskSection(key, name, tasks, profile)
   if not tasks or #tasks == 0 then return end
   if not self:RenderSectionHeader(key, format("%s (%d)", name, #tasks), profile) then return end
   for _, task in ipairs(tasks) do
      self:RenderQuest(task, profile)
   end
end

function mod:RenderRecipes(recipes, profile)
   if not recipes or #recipes == 0 then return end
   local header = format("%s (%d)", PROFESSIONS_TRACKER_HEADER_PROFESSION or L["Professions"], #recipes)
   if not self:RenderSectionHeader("recipes", header, profile) then return end

   local titleColor, normal, complete = COLOR_HEADER, COLOR_NORMAL, COLOR_COMPLETE
   for _, recipe in ipairs(recipes) do
      AddLine("recipe", recipe, recipe.name, "quest", QUEST_INDENT, profile.questSpacing, titleColor, Brighten(titleColor))
      for _, reagent in ipairs(recipe.reagents) do
         AddLine("objective", recipe, "- " .. reagent.text, "objective", OBJECTIVE_INDENT, profile.objectiveSpacing,
            reagent.finished and complete or normal)
      end
   end
end

function mod:Render(sections, numQuests, numShown, recipes, tasks)
   local frame = self.frame
   local profile = self.db.profile

   if self:IsItemLayoutLocked() then
      -- Secure item buttons can't move during combat; re-render afterwards.
      -- The caller keeps the previous data, which the lines still show.
      self.layoutDeferred = true
      return false
   end
   -- Reuse the item button entry list (entries are pooled).
   local entries = self.itemEntries or {}
   for i, entry in ipairs(entries) do
      entries[i] = self.del(entry)
   end
   self.itemEntries = entries

   frame.title.text:SetText(profile.onlyCurrentZone and L["Zone Objectives"] or L["All Objectives"])

   local hasContent = numQuests > 0 or (recipes and #recipes > 0)
      or (tasks and (#tasks.worldQuests > 0 or #tasks.bonus > 0))
   if not hasContent and not self:IsInEditMode() then
      frame:Hide()
      self.numLinesUsed = 0
      ReleaseUnusedLines(0)
      self:RequestItemButtonLayout()
      return true
   end
   frame:Show()

   self.numLinesUsed = 0
   layout.y = 0
   layout.nextSpacing = nil
   layout.rightInset = 0
   layout.width = profile.width - SCROLLBAR_WIDTH - 4

   local titleHeight = frame.title:GetHeight() + 4
   if self.db.char.minimized then
      ReleaseUnusedLines(0)
      frame.scroll:Hide()
      frame:SetHeight(titleHeight)
      self:UpdateScrollBar()
      self:RequestItemButtonLayout()
      return true
   end
   frame.scroll:Show()

   if numQuests > 0 then
      local maxQuests = C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept() or numQuests
      local questsLabel = TRACKER_HEADER_QUESTS or L["Quests"]
      local header
      if numShown ~= numQuests then
         header = format(L["%s (%d of %d/%d)"], questsLabel, numShown, numQuests, maxQuests)
      else
         header = format("%s (%d/%d)", questsLabel, numQuests, maxQuests)
      end
      if self:RenderSectionHeader("quests", header, profile) then
         -- Zone headers: plain text under the section bar.
         local collapsedZones = self.db.char.collapsedZones
         local zoneColor, currentZoneColor = COLOR_ZONE, COLOR_WHITE
         for _, section in ipairs(sections) do
            local collapsed = collapsedZones[section.name]
            local text = format("%s %s (%d)", collapsed and "+" or "-", section.name, #section.quests)
            local color = section.isCurrent and currentZoneColor or zoneColor
            AddLine("zone", section, text, "zone", ZONE_INDENT, profile.zoneSpacing, color, Brighten(color))
            if not collapsed then
               layout.nextSpacing = profile.zoneHeaderSpacing
               for _, quest in ipairs(section.quests) do
                  self:RenderQuest(quest, profile)
               end
            end
         end
      end
   end

   if tasks then
      self:RenderTaskSection("worldQuests", TRACKER_HEADER_WORLD_QUESTS or L["World Quests"], tasks.worldQuests, profile)
      self:RenderTaskSection("bonus", TRACKER_HEADER_BONUS_OBJECTIVES or L["Bonus Objectives"], tasks.bonus, profile)
   end

   if profile.showRecipes then
      self:RenderRecipes(recipes, profile)
   end

   ReleaseUnusedLines(self.numLinesUsed)

   local contentHeight = layout.y + 4
   local child = frame.child
   child:SetSize(layout.width, math.max(1, contentHeight))

   local maxContent = math.max(20, profile.maxHeight - titleHeight)
   local viewHeight = math.min(contentHeight, maxContent)
   frame:SetHeight(titleHeight + viewHeight)
   frame.scroll.contentHeight = contentHeight
   frame.scroll.viewHeight = viewHeight

   -- Keep scroll position valid after content shrinks.
   local maxScroll = math.max(0, contentHeight - viewHeight)
   if frame.scroll:GetVerticalScroll() > maxScroll then
      frame.scroll:SetVerticalScroll(maxScroll)
   end
   self:UpdateScrollBar()
   self:RequestItemButtonLayout()
   if profile.showDirection then
      self:UpdateArrows()
   end
   return true
end

----------------------------------------------------------------
-- Click handling (mirrors Blizzard's quest/recipe tracker behaviour)
----------------------------------------------------------------

local function InsertChatLink(link)
   if not link then return false end
   if ChatFrameUtil and ChatFrameUtil.InsertLink then
      return ChatFrameUtil.InsertLink(link)
   elseif ChatEdit_InsertLink then
      return ChatEdit_InsertLink(link)
   end
   return false
end

local function OpenQuestOnMap(questID)
   if QuestMapFrame_OpenToQuestDetails then
      QuestMapFrame_OpenToQuestDetails(questID)
   elseif ToggleQuestLog then
      ToggleQuestLog()
   end
end

local function ToggleQuestWatch(questID, isWorldQuest)
   if isWorldQuest then
      if QuestUtils_IsQuestWatched(questID) then
         C_QuestLog.RemoveWorldQuestWatch(questID)
      else
         C_QuestLog.AddWorldQuestWatch(questID)
      end
   elseif C_QuestLog.GetQuestWatchType(questID) ~= nil then
      C_QuestLog.RemoveQuestWatch(questID)
   else
      C_QuestLog.AddQuestWatch(questID)
   end
end

local function OpenTaskOnMap(questID)
   local mapID = C_TaskQuest.GetQuestZoneID(questID)
   if mapID and OpenQuestLog then
      OpenQuestLog(mapID)
      if EventRegistry then
         EventRegistry:TriggerEvent("MapCanvas.PingQuestID", questID)
      end
   end
end

-- Menus can stay open across updates, which recycle the quest tables, so
-- menu actions work on a copy of the fields they need.
local function SnapshotQuest(quest)
   local poi = quest.poi
   return {
      questID = quest.questID,
      title = quest.title,
      isTask = quest.isTask,
      isWorldQuest = quest.isWorldQuest,
      zoneName = quest.zoneName,
      poi = poi and { mapID = poi.mapID, x = poi.x, y = poi.y },
   }
end

local function ShowTaskMenu(owner, quest)
   local questID = quest.questID
   MenuUtil.CreateContextMenu(owner, function(_, root)
      root:CreateTitle(quest.title)
      if mod:HasTomTom() then
         root:CreateButton(L["Set TomTom waypoint"], function()
            mod:SetQuestWaypoint(quest, "tomtom")
         end)
      end
      if C_SuperTrack.GetSuperTrackedQuestID() ~= questID then
         root:CreateButton(SUPER_TRACK_QUEST or L["Focus quest"], function()
            C_SuperTrack.SetSuperTrackedQuestID(questID)
         end)
      else
         root:CreateButton(STOP_SUPER_TRACK_QUEST or L["Stop focusing quest"], function()
            C_SuperTrack.SetSuperTrackedQuestID(0)
         end)
      end
      root:CreateButton(OBJECTIVES_SHOW_QUEST_MAP or L["Show on map"], function()
         OpenTaskOnMap(questID)
      end)
      if quest.isWorldQuest then
         local watched = QuestUtils_IsQuestWatched(questID)
         root:CreateButton(watched and (OBJECTIVES_STOP_TRACKING or L["Stop tracking"]) or (TRACK_QUEST or L["Track quest"]), function()
            ToggleQuestWatch(questID, true)
         end)
      end
   end)
end

local function ShowQuestMenu(owner, quest)
   quest = SnapshotQuest(quest)
   if quest.isTask then
      return ShowTaskMenu(owner, quest)
   end
   local questID = quest.questID
   MenuUtil.CreateContextMenu(owner, function(_, root)
      root:CreateTitle(C_QuestLog.GetTitleForQuestID(questID) or "")

      if mod:HasTomTom() then
         root:CreateButton(L["Set TomTom waypoint"], function()
            mod:SetQuestWaypoint(quest, "tomtom")
         end)
      end

      if C_SuperTrack.GetSuperTrackedQuestID() ~= questID then
         root:CreateButton(SUPER_TRACK_QUEST or L["Focus quest"], function()
            C_SuperTrack.SetSuperTrackedQuestID(questID)
         end)
      else
         root:CreateButton(STOP_SUPER_TRACK_QUEST or L["Stop focusing quest"], function()
            C_SuperTrack.SetSuperTrackedQuestID(0)
         end)
      end

      if QuestUtil and QuestUtil.OpenQuestDetails then
         root:CreateButton(OBJECTIVES_VIEW_IN_QUESTLOG or L["Open quest details"], function()
            QuestUtil.OpenQuestDetails(questID)
         end)
      end

      root:CreateButton(OBJECTIVES_SHOW_QUEST_MAP or L["Show on map"], function()
         OpenQuestOnMap(questID)
      end)

      local watched = C_QuestLog.GetQuestWatchType(questID) ~= nil
      root:CreateButton(watched and (OBJECTIVES_STOP_TRACKING or L["Stop tracking"]) or (TRACK_QUEST or L["Track quest"]), function()
         ToggleQuestWatch(questID)
      end)

      if C_QuestLog.IsPushableQuest(questID) and IsInGroup() then
         root:CreateButton(SHARE_QUEST or L["Share quest"], function()
            QuestUtil.ShareQuest(questID)
         end)
      end

      if QuestMapQuestOptions_AbandonQuest then
         root:CreateButton(ABANDON_QUEST_ABBREV or L["Abandon quest"], function()
            QuestMapQuestOptions_AbandonQuest(questID)
         end)
      end
   end)
end

local function OpenRecipe(recipeID, isRecraft)
   if isRecraft then return end
   if not ProfessionsFrame and ProfessionsFrame_LoadUI then
      ProfessionsFrame_LoadUI()
   end
   if C_TradeSkillUI.IsRecipeProfessionLearned(recipeID) then
      C_TradeSkillUI.OpenRecipe(recipeID)
   elseif Professions and Professions.InspectRecipe then
      Professions.InspectRecipe(recipeID)
   end
end

local function ShowRecipeMenu(owner, recipe)
   -- Copy the fields: the recipe table is recycled on the next update.
   local recipeID, isRecraft, name = recipe.recipeID, recipe.isRecraft, recipe.name
   MenuUtil.CreateContextMenu(owner, function(_, root)
      root:CreateTitle(name)
      if not isRecraft then
         root:CreateButton(PROFESSIONS_TRACKING_VIEW_RECIPE or L["View recipe"], function()
            OpenRecipe(recipeID, isRecraft)
         end)
      end
      root:CreateButton(PROFESSIONS_UNTRACK_RECIPE or L["Untrack recipe"], function()
         C_TradeSkillUI.SetRecipeTracked(recipeID, false, isRecraft)
      end)
   end)
end

mod.lineClickHandlers = {
   zone = function(self, _, section)
      local collapsed = self.db.char.collapsedZones
      collapsed[section.name] = not collapsed[section.name] or nil
      self:RequestUpdate()
   end,

   section = function(self, _, section)
      local collapsed = self.db.char.collapsedSections
      collapsed[section.key] = not collapsed[section.key] or nil
      self:RequestUpdate()
   end,

   quest = function(self, line, quest, button)
      local questID = quest.questID
      if ChatFrameUtil and ChatFrameUtil.TryInsertQuestLinkForQuestID
         and ChatFrameUtil.TryInsertQuestLinkForQuestID(questID) then
         return
      end
      if button == "RightButton" then
         ShowQuestMenu(line, quest)
      elseif IsModifiedClick("QUESTWATCHTOGGLE") then
         if not quest.isTask or quest.isWorldQuest then
            ToggleQuestWatch(questID, quest.isWorldQuest)
         end
      elseif IsControlKeyDown() then
         self:SetQuestWaypoint(quest)
      elseif quest.isTask then
         OpenTaskOnMap(questID)
      elseif quest.isAutoComplete and quest.isComplete and ShowQuestComplete then
         ShowQuestComplete(questID)
      else
         OpenQuestOnMap(questID)
      end
   end,

   recipe = function(self, line, recipe, button)
      if IsModifiedClick("CHATLINK") then
         InsertChatLink(C_TradeSkillUI.GetRecipeLink(recipe.recipeID))
      elseif button == "RightButton" then
         ShowRecipeMenu(line, recipe)
      elseif IsModifiedClick("RECIPEWATCHTOGGLE") then
         C_TradeSkillUI.SetRecipeTracked(recipe.recipeID, false, recipe.isRecraft)
      else
         OpenRecipe(recipe.recipeID, recipe.isRecraft)
      end
   end,
}
