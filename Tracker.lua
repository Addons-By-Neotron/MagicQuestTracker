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

-- Header art, heights and text insets come from the theme (Themes.lua).
local SCROLLBAR_WIDTH = 4
-- Space taken from the content width while the scrollbar is needed; header
-- bars extend into it to span the full width, like the title bar
-- (mod.headerBarExtend is that space, or 0 without a scrollbar).
local SCROLLBAR_RESERVE = SCROLLBAR_WIDTH + 4
local SCROLL_STEP = 40
local FADE_IN = 0.15   -- seconds (scrollbar and background hover fade)
local FADE_OUT = 0.6
local ZONE_INDENT = 4
local QUEST_INDENT = 6
local OBJECTIVE_INDENT = 16
-- With quest POI buttons (left of the title), like Blizzard's tracker. The
-- button is 20 wide but its icon is 32 and the focus glow 50, so the indent
-- (button center = indent - 14) leaves room for the glow to not be clipped
-- at the left edge.
local POI_QUEST_INDENT = 39
local POI_OBJECTIVE_INDENT = 43
local GROUP_BUTTON_SIZE = 24

-- Fold icons of zone and section headers. The icon always takes a slot of
-- FOLD_SLOT pixels (icon plus gap) so headers don't shift when toggled.
-- Texture styles are tinted with the header text color; the rotated ones
-- point right when folded and down when open.
local FOLD_SLOT = 18
local FOLD_TEXTURES = "Interface\\AddOns\\MagicQuestTracker\\Textures\\"
local FOLD_STYLES = {
   blizzard = { atlas = { "ui-questtrackerbutton-secondary-expand", "ui-questtrackerbutton-secondary-collapse" }, size = 16 },
   triangle = { texture = { FOLD_TEXTURES .. "FoldTriangle" }, rotate = true, size = 12 },
   chevron = { texture = { FOLD_TEXTURES .. "FoldChevron" }, rotate = true, size = 12 },
   box = { texture = { FOLD_TEXTURES .. "FoldPlusBox", FOLD_TEXTURES .. "FoldMinusBox" }, size = 14 },
   plusminus = { texture = { FOLD_TEXTURES .. "FoldPlus", FOLD_TEXTURES .. "FoldMinus" }, size = 12 },
}

-- Text colors come from the theme (mod:GetTextColors()); set by Render.
local colors

----------------------------------------------------------------
-- Quest timers: lines showing the time left on timed quests, updated
-- every second without a full render.
----------------------------------------------------------------

local TIMER_INTERVAL = 1
local TIMER_WARNING = 60  -- seconds; shown in the failed color from here
local timerLines = {}

local function FormatTimeLeft(seconds)
   local clock = SecondsToClock and SecondsToClock(seconds)
      or format("%d:%02d", math.floor(seconds / 60), seconds % 60)
   return format(L["Time left: %s"], clock)
end

-- Timer lines are progress bars (the fill is the time left) or text lines,
-- in the failed color under TIMER_WARNING. Returns false once the timer has
-- run out.
local function UpdateTimerLine(line)
   local remaining = math.max(0, math.floor(line.timerEnd - GetTime()))
   if not line.isTimerBar then
      line.text:SetText(FormatTimeLeft(remaining))
      line.color = remaining < TIMER_WARNING and colors.failed or colors.objective
      line.text:SetTextColor(unpack(line.color))
      return remaining > 0
   end
   local bar = line.bar
   local total = line.timerTotal
   bar:SetValue(total and total > 0 and math.min(100, remaining * 100 / total) or 100)
   bar.label:SetText(FormatTimeLeft(remaining))
   if remaining < TIMER_WARNING then
      bar:SetStatusBarColor(unpack(colors.failed))
   else
      local c = bar.fillColor
      bar:SetStatusBarColor(c.r, c.g, c.b, c.a)
   end
   return remaining > 0
end

function mod:TickTimers(elapsed)
   if #timerLines == 0 then return end
   self.timerElapsed = (self.timerElapsed or 0) + elapsed
   if self.timerElapsed < TIMER_INTERVAL then return end
   self.timerElapsed = 0
   for _, line in ipairs(timerLines) do
      if line.timerEnd and not UpdateTimerLine(line) then
         -- The quest fails now; let the quest log catch up.
         self:RequestUpdate()
      end
   end
end

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

-- Progress and timer bar labels: the objective font, a bit smaller.
local BAR_FONT_SHRINK = 2
local BAR_FONT_MIN = 8

function mod:UpdateFonts()
   for _, role in ipairs(FONT_ROLES) do
      self:UpdateFont(role, self:GetFonts()[role])
   end
   local cfg = self:GetFonts().objective
   self:UpdateFont("bar", cfg, math.max(BAR_FONT_MIN, cfg.size - BAR_FONT_SHRINK))
end

function mod:UpdateFont(role, cfg, size)
   local font = fontObjects[role]
   if not font then
      font = CreateFont((mod.fontPrefix or "MagicQuestTrackerFont_") .. role)
      fontObjects[role] = font
   end
   local path = media:Fetch("font", cfg.face) or STANDARD_TEXT_FONT
   font:SetFont(path, size or cfg.size, cfg.outline or "")
   if cfg.outline == nil or cfg.outline == "" then
      font:SetShadowColor(0, 0, 0, 1)
      font:SetShadowOffset(1, -1)
   else
      font:SetShadowOffset(0, 0)
   end
end

----------------------------------------------------------------
-- Preview views
--
-- The setup wizard shows a second tracker frame with made-up quests (see
-- Preview.lua). Rendering works on shared state: mod.frame, mod.lines, the
-- profile, the font objects and the theme colors. A preview is rendered by
-- swapping that state for the preview's while one function runs; mod.previewing
-- is set meanwhile, for the few places that must behave differently (no
-- secure buttons, no clicks, no combat or instance rules, no real fold state).
----------------------------------------------------------------

-- Fold state: the character's, or in a preview none, or with the profile's
-- previewFolded flag one zone and one section folded (to show both icons).
local PREVIEW_FOLDED = { collapsedZones = { Westfall = true }, collapsedSections = { recipes = true } }
local NOT_FOLDED = {}
function mod:GetCollapsedMap(name)
   if not self.previewing then return self.db.char[name] end
   return self.db.profile.previewFolded and PREVIEW_FOLDED[name] or NOT_FOLDED
end

function mod:RunInView(view, func, ...)
   local saved = {
      frame = self.frame, lines = self.lines, numLinesUsed = self.numLinesUsed,
      profile = self.db.profile, fontObjects = fontObjects, fontPrefix = self.fontPrefix,
      scrollbarReserved = self.scrollbarReserved, headerBarExtend = self.headerBarExtend,
      itemEntries = self.itemEntries,
   }
   self.frame, self.lines, self.numLinesUsed = view.frame, view.lines, view.numLinesUsed or 0
   self.db.profile = view.profile
   fontObjects = view.fontObjects
   self.fontPrefix = "MagicQuestTrackerPreviewFont_"
   self.scrollbarReserved, self.headerBarExtend = view.scrollbarReserved, view.headerBarExtend
   self.itemEntries = {}
   self.previewing, self.previewLayout = true, view.layout
   self:RefreshTheme()

   local ok, err = pcall(func, self, ...)

   view.numLinesUsed = self.numLinesUsed
   view.scrollbarReserved, view.headerBarExtend = self.scrollbarReserved, self.headerBarExtend
   self.frame, self.lines, self.numLinesUsed = saved.frame, saved.lines, saved.numLinesUsed
   self.db.profile = saved.profile
   fontObjects = saved.fontObjects
   self.fontPrefix = saved.fontPrefix
   self.scrollbarReserved, self.headerBarExtend = saved.scrollbarReserved, saved.headerBarExtend
   self.itemEntries = saved.itemEntries
   self.previewing, self.previewLayout = nil, nil
   self:RefreshTheme()
   if not ok then geterrorhandler()(err) end
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
   frame.bg:SetAlpha(0)
   -- Below the title and scroll area (they are one frame level higher).
   frame.border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
   frame.border:SetAllPoints()
   frame.border:SetAlpha(0)

   -- Title bar: quest count, minimize button. Moved and sized in Edit Mode.
   -- Anchored to the frame edges (with padding) in ApplyLayout.
   local title = CreateFrame("Button", nil, frame)
   title:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
   title:SetScript("OnClick", function(_, button)
      if button == "RightButton" then
         mod:ShowTitleMenu(title)
      elseif button == "MiddleButton" then
         mod:CycleView()
      end
   end)
   title:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:AddLine(L["Middle-click: Change view (all / current zone / tracked)"], 1, 1, 1)
      GameTooltip:AddLine(L["Right-click: Options"], 1, 1, 1)
      GameTooltip:Show()
   end)
   title:SetScript("OnLeave", GameTooltip_Hide)
   frame.title = title

   title.text = title:CreateFontString(nil, "OVERLAY")
   title.text:SetFontObject(fontObjects.title)
   title.text:SetJustifyH("LEFT")
   title.text:SetWordWrap(false)

   local minimize = CreateFrame("Button", nil, title)
   minimize:SetSize(20, 20)
   minimize:SetPoint("RIGHT", -2, 0)
   minimize:SetHighlightAtlas("ui-questtrackerbutton-red-highlight", "ADD")
   minimize:SetScript("OnClick", function() mod:ToggleMinimized() end)
   title.minimize = minimize
   title.bg = title:CreateTexture(nil, "BACKGROUND")

   -- Scroll area
   local scroll = CreateFrame("ScrollFrame", nil, frame)
   scroll:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
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
   bar:SetColorTexture(1, 1, 1, 1)  -- tinted with the theme color in ApplyLayout
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
      mod:TickTimers(elapsed)
      local hovered = self:IsMouseOver()
      local background = mod:GetBackground()
      FadeToward(self.bg, hovered and background.hoverAlpha or background.alpha, elapsed, hovered)
      self.border:SetAlpha(self.bg:GetAlpha())
      if bar:IsShown() then
         FadeToward(bar, hovered and 1 or 0, elapsed, hovered)
      end
      -- Quest buttons (POI, find group, voiceover) with buttonsOnHover.
      local target = (hovered or not mod.db.profile.buttonsOnHover) and 1 or 0
      local alpha = mod.buttonAlpha
      if alpha ~= target then
         local step = elapsed / (hovered and FADE_IN or FADE_OUT)
         alpha = alpha < target and math.min(target, alpha + step) or math.max(target, alpha - step)
         mod:SetQuestButtonAlpha(alpha)
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
   if not self.previewing and self:IsItemLayoutLocked() then
      -- Would move the tracker out from under the frozen item buttons.
      self.applyLayoutDeferred = true
      return
   end
   local profile = self.db.profile
   self:UpdateFonts()

   local size = self:GetLayoutSettings()
   frame:SetScale(size.scale)
   frame:SetWidth(size.width)
   self:ApplyPosition()
   self:ApplyBackground()

   self:RefreshTheme()
   local title = frame.title
   local titleHeight, textIndent = self:GetTheme().StyleTitle(title, profile)
   local textColors = self:GetTextColors()
   title.text:SetTextColor(unpack(textColors.title))
   frame.scrollThumb:SetVertexColor(textColors.scrollbar[1], textColors.scrollbar[2], textColors.scrollbar[3], 0.5)
   title.text:ClearAllPoints()
   title.text:SetPoint("LEFT", textIndent, 0)
   title.text:SetPoint("RIGHT", title.minimize, "LEFT", -4, 0)
   frame.title:SetHeight(titleHeight)

   -- Padding keeps the content clear of the background border.
   local padding = self:GetContentLayout().padding
   title:ClearAllPoints()
   title:SetPoint("TOPLEFT", padding, -padding)
   title:SetPoint("TOPRIGHT", -padding, -padding)
   frame.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -padding, padding)
   if self.previewing then return end
   frame.title:EnableMouse(true)
   self:UpdateMinimizeButton()
   self:RequestUpdate()
end

-- Background texture and optional border; the border fades with the background.
function mod:ApplyBackground()
   local frame = self.frame
   local settings = self:GetBackground()
   local edge = settings.border ~= "None" and media:Fetch("border", settings.border)
   if edge == "" then edge = nil end
   local inset = 0
   local border = frame.border
   if edge then
      -- SetBackdrop ignores the table it already has, so pass a new one.
      border:SetBackdrop({ edgeFile = edge, edgeSize = settings.borderSize })
      local bc = settings.borderColor
      border:SetBackdropBorderColor(bc.r, bc.g, bc.b, 1)
      border:SetFrameLevel(frame:GetFrameLevel())
      border:Show()
      inset = math.floor(settings.borderSize / 4 + 0.5)
   else
      border:Hide()
   end

   local bg = frame.bg
   local path = media:Fetch("background", settings.texture)
   bg:SetTexture(path ~= "" and path or nil)
   local c = settings.color
   bg:SetVertexColor(c.r, c.g, c.b, 1)
   bg:ClearAllPoints()
   bg:SetPoint("TOPLEFT", inset, -inset)
   bg:SetPoint("BOTTOMRIGHT", -inset, inset)
   bg:SetAlpha(frame:IsMouseOver() and settings.hoverAlpha or settings.alpha)
   border:SetAlpha(bg:GetAlpha())
end

function mod:UpdateMinimizeButton()
   local button = self.frame.title.minimize
   local minimized = self.db.char.minimized
   local atlas = self:GetTheme().MinimizeAtlas(minimized)
   button:SetNormalAtlas(atlas)
   button:SetPushedAtlas(atlas .. "-pressed")
end

-- Which quests are shown: "all", "zone" (current zone only) or "tracked"
-- (the built-in watch list only), kept in showAllQuests / onlyCurrentZone.
local VIEW_ORDER = { "all", "zone", "tracked" }

function mod:GetView()
   local profile = self.db.profile
   if not profile.showAllQuests then return "tracked" end
   return profile.onlyCurrentZone and "zone" or "all"
end

function mod:SetView(view)
   local profile = self.db.profile
   profile.showAllQuests = view ~= "tracked"
   profile.onlyCurrentZone = view == "zone"
   self:NotifyOptionsChanged()
   self:RequestUpdate()
end

-- Zone headers: "never" hidden, "single" hidden while only one is shown,
-- "always" hidden. Kept in profile.hideZoneHeaders (true / "single" / false).
function mod:GetZoneHeaderMode()
   local hidden = self.db.profile.hideZoneHeaders
   if hidden == "single" then return "single" end
   return hidden and "always" or "never"
end

function mod:SetZoneHeaderMode(mode)
   self.db.profile.hideZoneHeaders = (mode == "always") or (mode == "single" and "single") or false
   self:RequestUpdate()
end

function mod:CycleView()
   local current = self:GetView()
   for i, view in ipairs(VIEW_ORDER) do
      if view == current then
         return self:SetView(VIEW_ORDER[i % #VIEW_ORDER + 1])
      end
   end
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
   thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, -offset)
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
      line.collapseIcon = line:CreateTexture(nil, "OVERLAY")
      line.collapseIcon:SetSize(16, 16)
      line.collapseIcon:SetPoint("RIGHT", -2, 0)
      line.bg = line:CreateTexture(nil, "BACKGROUND")
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
      line.timerEnd = nil
   end
end

----------------------------------------------------------------
-- Rendering
----------------------------------------------------------------

local layout = {}  -- reused render state
local spacing      -- content spacing of the theme, set by Render

-- headerKind: nil, "section" or "zone"; the theme decides how headers look.
-- Places the fold icon of a header line. x is where the text starts: the
-- slot is there on the left side, and right after the text (textWidth wide)
-- with "after". On the right the slot ends at the line's right edge plus the
-- theme's line.foldRight overhang.
local function ApplyFoldIcon(line, def, side, collapsed, color, isBar, x, textWidth, role)
   local icon = line.collapseIcon
   icon:ClearAllPoints()
   icon:SetRotation(0)
   icon:SetSize(def.size, def.size)
   if def.atlas then
      icon:SetAtlas(collapsed and def.atlas[1] or def.atlas[2])
      icon:SetVertexColor(1, 1, 1, 1)
   else
      icon:SetTexture(collapsed and def.texture[1] or def.texture[#def.texture])
      icon:SetTexCoord(0, 1, 0, 1)
      icon:SetVertexColor(unpack(color))
      if def.rotate and not collapsed then
         icon:SetRotation(-math.pi / 2)
      end
   end
   local center = FOLD_SLOT / 2 - 1
   local y = isBar and 0 or -(mod:GetFonts()[role].size - 2) / 2
   -- A down pointing triangle / chevron sits visually high: nudge it down.
   if def.rotate and not collapsed then y = y - 2 end
   local anchor = isBar and "" or "TOP"
   if side == "left" then
      icon:SetPoint("CENTER", line, anchor .. "LEFT", x + center, y)
   elseif side == "after" then
      icon:SetPoint("CENTER", line, anchor .. "LEFT", x + textWidth + 2 + center, y)
   else
      icon:SetPoint("CENTER", line, anchor .. "RIGHT", (line.foldRight or 0) - center, y)
   end
   icon:Show()
end

-- collapsed: true / false for headers that can be folded, nil otherwise.
local function AddLine(kind, data, text, role, indent, spacing, color, highlightColor, headerKind, rightText, arrowTarget, collapsed)
   local line = AcquireLine()
   local theme = mod:GetTheme()
   local isBar, minHeight, textIndent, padding
   if headerKind then
      isBar, minHeight, textIndent, padding = theme.HeaderLayout(headerKind, mod.db.profile)
   end
   if isBar then
      if line.styleVersion ~= mod.themeVersion or line.styleKind ~= headerKind then
         theme.StyleHeader(line, headerKind, indent)
         line.styleVersion, line.styleKind = mod.themeVersion, headerKind
      end
   else
      line.styleKind = nil
      line.foldRight = 0
      if line.border then line.border:Hide() end
   end
   local foldDef, foldSide
   if collapsed ~= nil and headerKind then
      local profile = mod.db.profile
      foldDef = FOLD_STYLES[profile[headerKind .. "Fold"]]
      foldSide = profile[headerKind .. "FoldPosition"]
   end
   local foldLeft = foldDef and foldSide == "left" and FOLD_SLOT or 0
   -- "after" (right of the text) reserves its slot at the right end, so the text never wraps into it.
   local foldRight = foldDef and foldSide ~= "left" and FOLD_SLOT or 0
   line.kind = kind
   line.data = data
   line.color = color
   line.highlightColor = highlightColor
   line:EnableMouse(highlightColor ~= nil and not mod.previewing)

   local width = layout.width - indent - (layout.rightInset or 0) - foldLeft - foldRight
   if rightText then
      local right = line.rightText
      right:SetFontObject(fontObjects.objective)
      right:SetText(rightText)
      right:SetTextColor(unpack(colors.distance))
      right:ClearAllPoints()
      right:SetPoint("TOPRIGHT", -(layout.rightInset or 0), 0)
      right:Show()
      width = width - right:GetStringWidth() - 4
   else
      line.rightText:Hide()
   end
   line.arrowTarget = arrowTarget
   line.timerEnd = nil
   line.collapseIcon:Hide()
   if line.poiButton then line.poiButton:Hide() end
   if line.groupButton then line.groupButton:Hide() end
   if line.playButton then line.playButton:Hide() end
   if line.previewItem then line.previewItem:Hide() end
   if line.bar then line.bar:Hide() end
   if arrowTarget then
      -- Arrow sits left of the distance text, centered on the first text
      -- line (it may be taller than the text); rotated by mod:UpdateArrows().
      local size = mod.db.profile.arrowSize
      local offset = (layout.rightInset or 0) + (rightText and line.rightText:GetStringWidth() + 3 or 0)
      local lineHeight = mod:GetFonts()[role].size
      line.arrow:SetSize(size, size)
      line.arrow:SetVertexColor(unpack(colors.arrow))
      line.arrow:ClearAllPoints()
      line.arrow:SetPoint("CENTER", line, "TOPRIGHT", -offset - size / 2, -lineHeight / 2)
      if mod.previewing then
         -- Not updated by UpdateArrows: show it pointing somewhere.
         line.arrow:SetRotation(math.pi / 4)
         line.arrow:Show()
      end
      width = width - size - 3
   else
      line.arrow:Hide()
   end
   line.text:SetFontObject(fontObjects[role])
   line.text:ClearAllPoints()
   if isBar then
      line.text:SetPoint("LEFT", indent + textIndent + foldLeft, 0)
      width = width - textIndent
   else
      line.text:SetPoint("TOPLEFT", indent + foldLeft, 0)
   end
   line.text:SetWidth(width)
   line.text:SetText(text)
   line.text:SetTextColor(unpack(color))
   if foldDef then
      ApplyFoldIcon(line, foldDef, foldSide, collapsed, color, isBar, indent + (isBar and textIndent or 0),
         math.min(line.text:GetStringWidth(), width), role)
   end
   mod.SetBarShown(line, isBar or false)

   local height = math.ceil(line.text:GetStringHeight())
   if isBar then
      height = math.max(minHeight, height + padding)
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

-- Progress bar objectives (percentage based) get a bar like Blizzard's
-- tracker; texture and colors come from the theme.
local BAR_MAX_WIDTH = 200
local BAR_PADDING = 4
local BAR_MARKERS = { 0.25, 0.5, 0.75 }  -- like Blizzard's bars
local BAR_MARKER_WIDTH = 1

-- The Blizzard theme uses the scenario tracker's bar: fixed size, segmented
-- frame (the segments are its markers), Blizzard's fill and font.
local BLIZZARD_BAR = {
   width = 191, height = 17,
   lineHeight = 25,  -- the frame atlas is much taller than what it draws; overlap it
   frameAtlas = "bonusobjectives-bar-frame-5",
   frameOffsetX = -8, frameOffsetY = -1,  -- frame relative to the bar's left edge
   texture = [[Interface\TargetingFrame\UI-StatusBar]],
   color = { r = 0.26, g = 0.42, b = 1, a = 1 },
   background = { r = 0.04, g = 0.07, b = 0.18, a = 1 },
   textColor = { r = 1, g = 1, b = 1, a = 1 },
}

-- label: bar text, defaults to the percentage.
local function AddProgressBar(data, percent, indent, gap, label)
   local line = AddLine("objective", data, "", "objective", indent, gap, colors.objective)
   local bar = line.bar
   if not bar then
      bar = CreateFrame("StatusBar", nil, line)
      bar:SetMinMaxValues(0, 100)
      bar.bg = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
      bar.bg:SetAllPoints()
      bar.label = bar:CreateFontString(nil, "OVERLAY")
      bar.label:SetPoint("CENTER")
      bar.markers = {}
      for i in ipairs(BAR_MARKERS) do
         local marker = bar:CreateTexture(nil, "OVERLAY", nil, -1)
         marker:SetWidth(BAR_MARKER_WIDTH)
         bar.markers[i] = marker
      end
      line.bar = bar
   end
   if bar.styleVersion ~= mod.themeVersion then
      local frameInfo = not mod:GetThemeSettings() and C_Texture and C_Texture.GetAtlasInfo
         and C_Texture.GetAtlasInfo(BLIZZARD_BAR.frameAtlas)
      bar.frameInfo = frameInfo or nil
      local settings = frameInfo and BLIZZARD_BAR or mod:GetProgressBarSettings()
      local texture = frameInfo and BLIZZARD_BAR.texture
         or media:Fetch("statusbar", settings.texture) or media:Fetch("statusbar", "Blizzard")
      local c, bg, tc = settings.color, settings.background, settings.textColor
      if frameInfo then
         if not bar.frame then
            bar.frame = bar:CreateTexture(nil, "ARTWORK")
         end
         bar.frame:SetAtlas(BLIZZARD_BAR.frameAtlas)
      end
      if bar.frame then bar.frame:SetShown(frameInfo and true or false) end
      bar:SetStatusBarTexture(texture)
      -- Fill under the frame (ARTWORK), like Blizzard's drawLayer="BACKGROUND".
      bar:GetStatusBarTexture():SetDrawLayer("BACKGROUND", 0)
      bar.fillColor = c
      bar.bg:SetTexture(texture)
      bar.bg:SetVertexColor(bg.r, bg.g, bg.b, bg.a)
      bar.label:SetTextColor(tc.r, tc.g, tc.b, tc.a)
      local mc = settings.markerColor
      for _, marker in ipairs(bar.markers) do
         if mc then marker:SetColorTexture(mc.r, mc.g, mc.b, mc.a) end
         marker:SetShown(mc ~= nil)
      end
      bar.styleVersion = mod.themeVersion
   end
   local frameInfo = bar.frameInfo
   bar.label:SetFontObject(frameInfo and GameFontHighlight or fontObjects.bar)
   local tc = (frameInfo and BLIZZARD_BAR or mod:GetProgressBarSettings()).textColor
   bar.label:SetTextColor(tc.r, tc.g, tc.b, tc.a)
   local fc = bar.fillColor
   bar:SetStatusBarColor(fc.r, fc.g, fc.b, fc.a)
   bar.label:SetText(label or format("%d%%", percent))
   bar:SetValue(percent)
   local available = layout.width - indent - (layout.rightInset or 0)
   local width, height, lineHeight
   bar:ClearAllPoints()
   if frameInfo then
      -- The frame reaches past the bar; keep it inside the line.
      local scale = math.min(1, available / frameInfo.width)
      width, height = BLIZZARD_BAR.width * scale, BLIZZARD_BAR.height
      lineHeight = BLIZZARD_BAR.lineHeight
      local left = -BLIZZARD_BAR.frameOffsetX * scale
      bar:SetPoint("TOPLEFT", indent + left, -(lineHeight - height) / 2)
      bar.frame:SetSize(frameInfo.width * scale, frameInfo.height)
      bar.frame:ClearAllPoints()
      bar.frame:SetPoint("LEFT", bar, "LEFT", BLIZZARD_BAR.frameOffsetX * scale, BLIZZARD_BAR.frameOffsetY)
   else
      height = math.ceil(bar.label:GetStringHeight()) + BAR_PADDING
      width = math.min(BAR_MAX_WIDTH, available)
      lineHeight = height
      bar:SetPoint("TOPLEFT", indent, 0)
   end
   bar:SetSize(width, height)
   for i, marker in ipairs(bar.markers) do
      local x = math.floor(width * BAR_MARKERS[i] - BAR_MARKER_WIDTH / 2 + 0.5)
      marker:ClearAllPoints()
      marker:SetPoint("TOPLEFT", x, 0)
      marker:SetPoint("BOTTOMLEFT", x, 0)
   end
   bar:Show()
   layout.y = layout.y - line:GetHeight() + lineHeight
   line:SetHeight(lineHeight)
   return line
end

-- Title color by difficulty (see mod:GetQuestDifficulty); the theme supplies
-- the color.
local function DifficultyColor(quest, previewing)
   local name = mod:GetQuestDifficulty(quest.questID, quest.difficultyLevel, quest.isScaling, previewing)
   return name and colors[name] or colors.quest
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
   local size = mod:GetFonts().quest.size
   local h = math.max(6, math.floor(size * 0.65 + 0.5))
   local w = math.floor(h * (INFINITY_R - INFINITY_L) / (INFINITY_B - INFINITY_T) + 0.5)
   -- Inline textures are centered on the line; drop it toward the text baseline.
   local offY = -math.floor(size * 0.25 + 0.5)
   -- |T path:height:width:offX:offY:texW:texH:left:right:top:bottom:r:g:b|t
   return format("|T%s:%d:%d:0:%d:64:64:%d:%d:%d:%d:153:230:242|t",
      INFINITY_PATH, h, w, offY, INFINITY_L, INFINITY_R, INFINITY_T, INFINITY_B)
end

-- Check mark for quests on the built-in watch list.
local WATCHED_PATH = "Interface\\Buttons\\UI-CheckBox-Check"

local function WatchedMarker()
   local size = mod:GetFonts().quest.size
   local h = math.max(8, math.floor(size * 0.9 + 0.5))
   return format("|T%s:%d:%d:0:%d|t", WATCHED_PATH, h, h, -math.floor(size * 0.1 + 0.5))
end

-- Not needed when only watched quests are listed, nor in the section on top.
local function ShowWatchedMarker(quest, profile)
   return quest.isWatched and profile.markWatchedQuests and profile.showAllQuests and not quest.isPinned
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
   if ShowWatchedMarker(quest, profile) then
      title = title .. " " .. WatchedMarker()
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
         title = format("%s %s(%s)|r", title, colors.questTagCode, table.concat(labels, ", "))
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
   if not (profile.showPOIButtons and profile.blizzardFocus and POIButtonUtil) then return false end
   -- Blizzard's tracker hides POI buttons when the questPOI CVar is off.
   local cvar = GetCVar("questPOI")
   return cvar == nil or cvar == "1"
end

local function CanFindGroup(quest)
   return QuestUtil and QuestUtil.CanCreateQuestGroup and C_LFGList
      and QuestUtil.CanCreateQuestGroup(quest.questID) or false
end

local function SetPOIWaypoint(quest)
   if quest and mod:HasTomTom() and mod.db.profile.poiTomTom then
      mod:SetQuestWaypoint(quest, "tomtom")
   end
end

-- Blizzard's click handler super tracks right away; in combat, defer the
-- focus change instead (see mod:SetSuperTrackedQuest).
local function POIButton_OnClick(button, mouseButton)
   local quest = button:GetParent().data
   local leftClick = mouseButton == "LeftButton" and not IsShiftKeyDown()
   -- Shift-click (chat link / untrack) goes to Blizzard as usual.
   if leftClick and InCombatLockdown() then
      local questID = button:GetQuestID()
      if questID then
         local focusing = not button:IsSelected()
         mod:SetSuperTrackedQuest(focusing and questID or 0)
         -- Unfocusing leaves the TomTom waypoint alone.
         if focusing then
            SetPOIWaypoint(quest)
         end
      end
      return
   end
   POIButtonMixin.OnClick(button, mouseButton)
   if leftClick and quest and C_SuperTrack.GetSuperTrackedQuestID() == quest.questID then
      SetPOIWaypoint(quest)
   end
end

-- Alpha of the quest buttons on the tracker (faded by buttonsOnHover). Quest
-- item buttons are not faded, so usable items are never missed.
mod.buttonAlpha = 1
local function QuestButtonAlpha()
   return mod.previewing and 1 or mod.buttonAlpha
end

function mod:SetQuestButtonAlpha(alpha)
   self.buttonAlpha = alpha
   for i = 1, self.numLinesUsed do
      local line = self.lines[i]
      if line.groupButton then line.groupButton:SetAlpha(alpha) end
      if line.playButton then line.playButton:SetAlpha(alpha) end
      if line.poiButton and not line.poiButton.keepVisible then line.poiButton:SetAlpha(alpha) end
   end
end

-- Quest POI button (same as Blizzard's tracker): shows in progress / complete,
-- highlighted when focused; clicking it focuses (super tracks) the quest.
local function AttachPOIButton(line, quest)
   local button = line.poiButton
   if not button then
      button = CreateFrame("Button", nil, line, "POIButtonTemplate")
      button:SetScript("OnClick", POIButton_OnClick)
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
   button:EnableMouse(not mod.previewing)
   -- The focused quest's button stays visible with buttonsOnHover.
   button.keepVisible = quest.isSuperTracked
   button:SetAlpha(button.keepVisible and 1 or QuestButtonAlpha())
   button:Show()
end

-- Preview only: the quest item button without the secure parts.
local function AttachPreviewItemButton(line, quest)
   local size = mod.ITEM_BUTTON_SIZE
   local button = line.previewItem
   if not button then
      button = CreateFrame("Button", nil, line)
      button:SetSize(size, size)
      button.icon = button:CreateTexture(nil, "BORDER")
      button.icon:SetAllPoints()
      button:SetNormalAtlas("UI-QuestTrackerButton-QuestItem-Frame")
      local normal = button:GetNormalTexture()
      normal:ClearAllPoints()
      normal:SetPoint("CENTER")
      normal:SetSize(size * 42 / 26, size * 42 / 26)
      button:EnableMouse(false)
      line.previewItem = button
   end
   button.icon:SetTexture(quest.itemTexture)
   button:ClearAllPoints()
   button:SetPoint("TOPRIGHT", line, "TOPRIGHT", 0, 0)
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
   if not mod.previewing then button:SetUp(quest.questID) end
   button:EnableMouse(not mod.previewing)
   button:ClearAllPoints()
   button:SetPoint("TOPRIGHT", line, "TOPRIGHT", -rightOffset, 4)
   button:SetAlpha(QuestButtonAlpha())
   button:Show()
end

-- The Spoken Quests addon (Forever / Classic) voices quests and exposes the
-- UI it adds play buttons with. Returns that, or nil when it isn't loaded.
function mod:GetQuestVoice()
   local voiceOver = rawget(_G, "VoiceOver")
   local ui = type(voiceOver) == "table" and voiceOver.QuestOverlayUI
   if ui and ui.MakePlayButton and ui.BindPlayButton and ui.ShowsTrackerButton and ui.SetPlayButtonState then
      return ui
   end
end

local PLAY_BUTTON_SIZE = 16

-- Whether the quest has a voiceover to play (and Spoken wants a tracker button for it).
local function HasQuestVoice(ui, questID)
   local ok, voiced = pcall(ui.ShowsTrackerButton, ui, questID)
   return ok and voiced and true or false
end

-- Spoken Quests' play button, left of the group and item buttons. It is
-- Spoken's own button: it plays, stops and replays the quest's line.
local function AttachPlayButton(ui, line, quest, rightOffset)
   local button = line.playButton
   if not button then
      local ok
      ok, button = pcall(ui.MakePlayButton, ui, line)
      if not ok or not button then return end
      button:SetSize(PLAY_BUTTON_SIZE, PLAY_BUTTON_SIZE)
      button.setPlayState = ui.FollowQueue
      line.playButton = button
   end
   if button.questID ~= quest.questID then
      button.soundData = nil
      if not pcall(ui.BindPlayButton, ui, button, quest.questID, quest.title, "Magic Quest Tracker") then
         button:Hide()
         return
      end
   end
   button:ClearAllPoints()
   button:SetPoint("TOPRIGHT", line, "TOPRIGHT", -rightOffset, 2)
   button:SetAlpha(QuestButtonAlpha())
   button:Show()
   pcall(ui.SetPlayButtonState, ui, button)
end

local YARDS_PER_MILE = 1760
local METERS_PER_YARD = 0.9144

-- Distance in yards, formatted per the distanceUnits setting: yards / meters
-- only, or switching to miles / kilometers for long distances.
local function FormatDistance(yards, units)
   if units == "meters" or units == "metric" then
      local meters = yards * METERS_PER_YARD
      if units == "metric" and meters >= 1000 then
         return format(L["%.1f km"], meters / 1000)
      end
      return format(L["%d m"], math.floor(meters + 0.5))
   end
   if units == "imperial" and yards >= YARDS_PER_MILE then
      return format(L["%.1f mi"], yards / YARDS_PER_MILE)
   end
   return format(L["%d yd"], math.floor(yards + 0.5))
end

-- timerTotal: full duration in seconds, nil if unknown (the bar shows full).
local function AddTimerLine(data, timerEnd, timerTotal, indent)
   local text = FormatTimeLeft(math.max(0, timerEnd - GetTime()))
   local line
   if mod.db.profile.timerBars then
      line = AddProgressBar(data, 100, indent, spacing.objectiveSpacing, text)
   else
      line = AddLine("objective", data, text, "objective", indent, spacing.objectiveSpacing, colors.objective)
   end
   line.isTimerBar = mod.db.profile.timerBars
   line.timerEnd = timerEnd
   line.timerTotal = timerTotal
   UpdateTimerLine(line)
   tinsert(timerLines, line)
end

-- Objectives ({ text, finished, percent, timerEnd }) of a quest or scenario.
local function RenderObjectives(data, objectives, indent, profile)
   local normal, complete = colors.objective, colors.complete
   for _, objective in ipairs(objectives) do
      local hasText = objective.text and objective.text ~= ""
      if not objective.finished then
         if hasText then
            AddLine("objective", data, "- " .. objective.text, "objective", indent, spacing.objectiveSpacing,
               objective.failed and colors.failed or normal)
         end
         if objective.percent then
            AddProgressBar(data, objective.percent, indent, spacing.objectiveSpacing)
         end
         if objective.timerEnd then
            AddTimerLine(data, objective.timerEnd, objective.timerTotal, indent)
         end
      elseif hasText and profile.showCompletedObjectives then
         AddLine("objective", data, "- " .. objective.text, "objective", indent, spacing.objectiveSpacing, complete)
      end
   end
end

function mod:RenderQuest(quest, profile)
   local normal = colors.objective
   local titleColor = profile.colorByDifficulty and DifficultyColor(quest, self.previewing) or colors.quest
   if profile.colorCompleteQuests and quest.isComplete then
      titleColor = colors.completeQuest
   end
   local itemSize = (profile.showItemButtons and quest.hasItem) and self.ITEM_BUTTON_SIZE or 0
   local groupSize = (profile.showFindGroupButton and not self.IS_FOREVER and (self.previewing and quest.previewGroup or not self.previewing and CanFindGroup(quest))) and GROUP_BUTTON_SIZE or 0
   local voiceUI = profile.showPlayButton and not self.previewing and self:GetQuestVoice()
   local playSize = (voiceUI and HasQuestVoice(voiceUI, quest.questID)) and PLAY_BUTTON_SIZE or 0
   layout.rightInset = itemSize + groupSize + playSize
   local showPOI = POIButtonsEnabled(profile)
   local questIndent = showPOI and POI_QUEST_INDENT or QUEST_INDENT
   local objectiveIndent = showPOI and POI_OBJECTIVE_INDENT or OBJECTIVE_INDENT

   local distanceText = profile.showDistance and quest.distance and FormatDistance(quest.distance, profile.distanceUnits) or nil
   local arrowTarget = profile.showDirection and quest.poi or nil
   -- Quests in the current zone always get an arrow; the limit is for other zones.
   if arrowTarget and profile.arrowMaxDistance > 0 and not quest.inCurrentZone then
      local distance = quest.distance or self:GetPOIDistance(arrowTarget)
      if not distance or distance > profile.arrowMaxDistance then
         arrowTarget = nil
      end
   end
   local titleLine = AddLine("quest", quest, FormatQuestTitle(quest, profile), "quest", questIndent, spacing.questSpacing,
      titleColor, Brighten(titleColor), nil, distanceText, arrowTarget)
   local questTop = layout.y - titleLine:GetHeight()
   if showPOI then
      AttachPOIButton(titleLine, quest)
   end
   if groupSize > 0 then
      AttachGroupButton(titleLine, quest, itemSize)
   end
   if playSize > 0 then
      AttachPlayButton(voiceUI, titleLine, quest, itemSize + groupSize)
   end
   if itemSize > 0 and self.previewing then
      AttachPreviewItemButton(titleLine, quest)
   elseif itemSize > 0 then
      tinsert(self.itemEntries, self.newHash("line", titleLine, "quest", quest))
   end

   if quest.isFailed then
      AddLine("objective", quest, FAILED or L["Failed"], "objective", objectiveIndent, spacing.objectiveSpacing,
         colors.failed)
   elseif quest.isComplete then
      local text = quest.completionText
      if not text or text == "" then
         text = QUEST_WATCH_QUEST_READY or L["Ready for turn-in"]
      end
      AddLine("objective", quest, text, "objective", objectiveIndent, spacing.objectiveSpacing, normal)
   else
      RenderObjectives(quest, quest.objectives, objectiveIndent, profile)
   end
   if quest.timerEnd then
      AddTimerLine(quest, quest.timerEnd, quest.timerTotal, objectiveIndent)
   end
   if quest.timeLeftText then
      AddLine("objective", quest, quest.timeLeftText, "objective", objectiveIndent, spacing.objectiveSpacing,
         colors.timeLeft)
   end
   -- Make room for the whole item / group button before the next quest.
   local buttonSize = math.max(itemSize, groupSize, playSize)
   if buttonSize > 0 and layout.y - questTop < buttonSize then
      layout.y = questTop + buttonSize
   end
   layout.rightInset = 0
end

-- Section headers (Quests, World Quests, ...) look like Blizzard's module
-- headers: header bar, fold icon (see FOLD_STYLES), click to fold.
-- Returns true when the section is expanded.
-- Section header counts: "none", "count" (no maximum) or "full". Kept in
-- profile.simpleSectionHeaders (true / "count" / false).
function mod:GetSectionCountMode()
   local simple = self.db.profile.simpleSectionHeaders
   if simple == "count" then return "count" end
   return simple and "none" or "full"
end

function mod:SetSectionCountMode(mode)
   self.db.profile.simpleSectionHeaders = mode == "none" or (mode == "count" and "count") or false
   self:RequestUpdate()
end

-- Section header text, with the number of entries unless headers are simple.
function mod:HeaderWithCount(name, count)
   if self:GetSectionCountMode() == "none" then return name end
   return format("%s (%d)", name, count)
end

function mod:RenderSectionHeader(key, text, profile)
   local collapsed = self:GetCollapsedMap("collapsedSections")[key]
   AddLine("section", SECTION_DATA[key], text, "module", 0, spacing.sectionSpacing, colors.section, Brighten(colors.section),
      "section", nil, nil, collapsed and true or false)
   if not collapsed then
      layout.nextSpacing = spacing.sectionHeaderSpacing or spacing.zoneHeaderSpacing
   end
   return not collapsed
end

-- Blizzard UI widgets (stage timer, wagon health, ...) in the Scenario
-- section, one container per spot, each registered for a widget set.
-- Widgets change size on their own; that triggers a re-render.
local SCENARIO_TRACKER_WIDGET_SET = 252      -- Blizzard's bottom widget block
local SCENARIO_TRACKER_TOP_WIDGET_SET = 514  -- below the objectives
local widgetBlocks = {}

local function WidgetLayout(container, sortedWidgets)
   DefaultWidgetLayout(container, sortedWidgets)
   local showing = container:HasAnyWidgetsShowing()
   if showing ~= container.renderedShowing
      or (showing and math.abs(container:GetHeight() - (container.renderedHeight or 0)) > 0.5) then
      mod:RequestUpdate()
   end
end

local function AddWidgetBlock(key, widgetSetID, gap)
   local container = widgetBlocks[key]
   if not container then
      container = CreateFrame("Frame", nil, mod.frame.child, "UIWidgetContainerTemplate")
      widgetBlocks[key] = container
   end
   container.used = true
   container:RegisterForWidgetSet(widgetSetID, WidgetLayout)
   local showing = container:HasAnyWidgetsShowing()
   container.renderedShowing = showing
   container.renderedHeight = showing and container:GetHeight() or 0
   if not showing then
      container:Hide()
      return
   end
   -- Scale down widgets wider than the tracker; anchor offsets are in the
   -- container's (scaled) coordinates.
   local width, height = container:GetWidth(), container:GetHeight()
   local scale = (width > layout.width and width > 0) and layout.width / width or 1
   layout.y = layout.y + gap
   container:SetScale(scale)
   container:ClearAllPoints()
   container:SetPoint("TOPLEFT", mod.frame.child, "TOPLEFT", (layout.width - width * scale) / 2 / scale, -layout.y / scale)
   container:Show()
   layout.y = layout.y + height * scale
end

-- Unregistered when not shown, so hidden widgets don't keep updating.
local function ReleaseUnusedWidgetBlocks()
   if mod.previewing then return end
   for _, container in pairs(widgetBlocks) do
      if not container.used then
         container:UnregisterForWidgetSet()
         container:Hide()
      end
      container.used = nil
   end
end

-- Scenario (delve, ...) on top: stage, its widgets and objectives, then
-- bonus steps.
function mod:RenderScenario(scenario, profile)
   if not scenario then return end
   local name = scenario.name
   if not name or name == "" then name = L["Scenario"] end
   if not self:RenderSectionHeader("scenario", name, profile) then return end
   local titleColor = colors.quest
   -- Stage widgets show the stage name themselves (as Blizzard's do).
   local title = not scenario.widgetSetID and scenario.stageName or nil
   if scenario.stage > scenario.numStages then
      title = L["Complete"]
   elseif scenario.numStages > 1 then
      title = title and format(L["Stage %d/%d: %s"], scenario.stage, scenario.numStages, title)
         or format(L["Stage %d/%d"], scenario.stage, scenario.numStages)
   end
   if title and title ~= "" then
      AddLine("scenario", scenario, title, "quest", QUEST_INDENT, spacing.questSpacing, titleColor)
   end
   if scenario.widgetSetID then
      AddWidgetBlock("stage", scenario.widgetSetID, spacing.objectiveSpacing)
   end
   RenderObjectives(scenario, scenario.criteria, OBJECTIVE_INDENT, profile)
   AddWidgetBlock("top", SCENARIO_TRACKER_TOP_WIDGET_SET, spacing.objectiveSpacing)
   for _, bonus in ipairs(scenario.bonus) do
      AddLine("scenario", bonus, bonus.name or "", "quest", QUEST_INDENT, spacing.questSpacing, titleColor)
      RenderObjectives(bonus, bonus.criteria, OBJECTIVE_INDENT, profile)
   end
   AddWidgetBlock("bottom", SCENARIO_TRACKER_WIDGET_SET, spacing.objectiveSpacing)
end

function mod:RenderTaskSection(key, name, tasks, profile)
   if not tasks or #tasks == 0 then return end
   if not self:RenderSectionHeader(key, self:HeaderWithCount(name, #tasks), profile) then return end
   for _, task in ipairs(tasks) do
      self:RenderQuest(task, profile)
   end
end

function mod:RenderAchievements(achievements, profile)
   if not achievements or #achievements == 0 then return end
   local header = self:HeaderWithCount(TRACKER_HEADER_ACHIEVEMENTS or L["Achievements"], #achievements)
   if not self:RenderSectionHeader("achievements", header, profile) then return end
   local titleColor = colors.quest
   for _, achievement in ipairs(achievements) do
      AddLine("achievement", achievement, achievement.name, "quest", QUEST_INDENT, spacing.questSpacing, titleColor, Brighten(titleColor))
      RenderObjectives(achievement, achievement.objectives, OBJECTIVE_INDENT, profile)
   end
end

function mod:RenderRecipes(recipes, profile)
   if not recipes or #recipes == 0 then return end
   local header = self:HeaderWithCount(PROFESSIONS_TRACKER_HEADER_PROFESSION or L["Professions"], #recipes)
   if not self:RenderSectionHeader("recipes", header, profile) then return end

   local titleColor, normal, complete = colors.quest, colors.objective, colors.complete
   for _, recipe in ipairs(recipes) do
      AddLine("recipe", recipe, recipe.name, "quest", QUEST_INDENT, spacing.questSpacing, titleColor, Brighten(titleColor))
      for _, reagent in ipairs(recipe.reagents) do
         AddLine("objective", recipe, "- " .. reagent.text, "objective", OBJECTIVE_INDENT, spacing.objectiveSpacing,
            reagent.finished and complete or normal)
      end
   end
end

-- Renders once; reserveScrollbar takes the scrollbar's space from the content
-- width. Returns whether it rendered and, when it did, whether the content
-- needs a scrollbar.
function mod:RenderPass(reserveScrollbar, sections, numQuests, numShown, recipes, tasks, scenario, achievements)
   local frame = self.frame
   local profile = self.db.profile

   local preview = self.previewing
   if self.combatHidden and not preview then
      -- Hidden for combat; render when it ends.
      self.layoutDeferred = true
      return false
   end
   -- Scenarios MQT doesn't show (Mythic+, ...): Blizzard's scenario block
   -- takes this spot, so hide fully, even when item buttons hold the layout
   -- during combat.
   if not preview and self:IsBlizzardScenario() and not self:IsInEditMode() then
      frame:Hide()
      if self:IsItemLayoutLocked() then
         self.layoutDeferred = true  -- item buttons follow once combat ends
         return false
      end
      self.numLinesUsed = 0
      ReleaseUnusedLines(0)
      ReleaseUnusedWidgetBlocks()
      self:RequestItemButtonLayout()
      return true
   end
   if not preview and self:IsItemLayoutLocked() then
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

   local view = self:GetView()
   frame.title.text:SetText(view == "tracked" and L["Tracked Objectives"]
      or view == "zone" and L["Zone Objectives"] or L["All Objectives"])
   if not preview then wipe(timerLines) end

   local hasContent = numQuests > 0 or scenario or (recipes and #recipes > 0)
      or (achievements and #achievements > 0)
      or (tasks and (#tasks.worldQuests > 0 or #tasks.bonus > 0))
   if (not hasContent or (not preview and self:ShouldHideInInstance(sections, scenario))) and not self:IsInEditMode() then
      frame:Hide()
      self.numLinesUsed = 0
      ReleaseUnusedLines(0)
      ReleaseUnusedWidgetBlocks()
      self:RequestItemButtonLayout()
      return true
   end
   frame:Show()

   self.numLinesUsed = 0
   layout.y = 0
   layout.nextSpacing = nil
   layout.rightInset = 0
   spacing = self:GetContentLayout()
   colors = self:GetTextColors()
   local size = self:GetLayoutSettings()
   local reserve = reserveScrollbar and SCROLLBAR_RESERVE or 0
   if reserve ~= self.headerBarExtend then
      -- Header art depends on the width: restyle the lines.
      self.headerBarExtend = reserve
      self.themeVersion = self.themeVersion + 1
   end
   layout.width = size.width - reserve - 2 * spacing.padding

   -- Title, gap below it and the padding on both ends.
   local titleHeight = frame.title:GetHeight() + 4 + 2 * spacing.padding
   if self.db.char.minimized and not preview then
      ReleaseUnusedLines(0)
      ReleaseUnusedWidgetBlocks()
      frame.scroll:Hide()
      frame:SetHeight(titleHeight)
      self:UpdateScrollBar()
      self:RequestItemButtonLayout()
      return true
   end
   frame.scroll:Show()

   self:RenderScenario(scenario, profile)

   if numQuests > 0 then
      local maxQuests = C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept() or numQuests
      local questsLabel = TRACKER_HEADER_QUESTS or L["Quests"]
      local header
      local countMode = self:GetSectionCountMode()
      if countMode == "none" then
         header = questsLabel
      elseif countMode == "count" then
         -- No maximum: shown / in the log when filtered, else the log count.
         if numShown ~= numQuests then
            header = format("%s (%d/%d)", questsLabel, numShown, numQuests)
         else
            header = format("%s (%d)", questsLabel, numQuests)
         end
      elseif view == "tracked" then
         -- Tracked quests count against the game's watch limit, not the log's.
         local maxWatches = Constants and Constants.QuestWatchConsts and Constants.QuestWatchConsts.MAX_QUEST_WATCHES or 25
         header = format("%s (%d/%d)", questsLabel, numShown, maxWatches)
      elseif numShown ~= numQuests then
         header = format(L["%s (%d of %d/%d)"], questsLabel, numShown, numQuests, maxQuests)
      else
         header = format("%s (%d/%d)", questsLabel, numQuests, maxQuests)
      end
      if self:RenderSectionHeader("quests", header, profile) then
         -- Zone headers: plain text under the section bar.
         local collapsedZones = self:GetCollapsedMap("collapsedZones")
         local zoneColor, currentZoneColor = colors.zone, colors.currentZone
         local headerMode = self:GetZoneHeaderMode()
         local hideHeader = headerMode == "always" or (headerMode == "single" and #sections == 1)
         for _, section in ipairs(sections) do
            local collapsed = not hideHeader and collapsedZones[section.foldKey or section.name]
            local count = #section.quests
            if section.foldKey ~= mod.COMPLETED_FOLD_KEY and section.numComplete and section.numComplete > 0 then
               count = format("%d, %s", count, format(L["%d complete"], section.numComplete))
            end
            local text = profile.simpleZoneHeaders and section.name or format("%s (%s)", section.name, count)
            local color = section.isCurrent and currentZoneColor or zoneColor
            if not hideHeader then
               AddLine("zone", section, text, "zone", ZONE_INDENT, spacing.zoneSpacing, color, Brighten(color), "zone",
                  nil, nil, collapsed and true or false)
            end
            if not collapsed then
               if not hideHeader then
                  layout.nextSpacing = spacing.zoneHeaderSpacing
               end
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

   self:RenderAchievements(achievements, profile)

   if profile.showRecipes then
      self:RenderRecipes(recipes, profile)
   end

   ReleaseUnusedLines(self.numLinesUsed)
   ReleaseUnusedWidgetBlocks()

   local contentHeight = layout.y + 4
   local child = frame.child
   child:SetSize(layout.width, math.max(1, contentHeight))

   local maxContent = math.max(20, size.maxHeight - titleHeight)
   local viewHeight = math.min(contentHeight, maxContent)
   if self:IsInEditMode() then
      -- Show the full maximum height while sizing the tracker.
      viewHeight = maxContent
   end
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
   if profile.showDirection and not preview then
      self:UpdateArrows()
   end
   return true, contentHeight > maxContent
end

-- The scrollbar only takes space while the content doesn't fit. The width
-- changes the wrapping and so the height: render with the last known state
-- and once more if the content turns out to need the other one (it can't
-- flip back, as a narrower width never makes the content shorter).
function mod:Render(...)
   local reserve = self.scrollbarReserved or false
   local ok, needsScrollbar = self:RenderPass(reserve, ...)
   if ok and needsScrollbar ~= nil then
      self.scrollbarReserved = needsScrollbar
      if needsScrollbar ~= reserve then
         ok = self:RenderPass(needsScrollbar, ...)
      end
   end
   return ok
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

-- "Focus quest" / "Stop focusing quest", unless Blizzard quest focus is off.
local function AddFocusButton(root, questID)
   if not mod.db.profile.blizzardFocus then return end
   if C_SuperTrack.GetSuperTrackedQuestID() ~= questID then
      root:CreateButton(SUPER_TRACK_QUEST or L["Focus quest"], function()
         mod:SetSuperTrackedQuest(questID)
      end)
   else
      root:CreateButton(STOP_SUPER_TRACK_QUEST or L["Stop focusing quest"], function()
         mod:SetSuperTrackedQuest(0)
      end)
   end
end

-- Title bar menu: the view (which quests are shown), then the settings.
local VIEW_LABELS = {
   all = L["All quests"],
   zone = L["Current zone only"],
   tracked = L["Tracked quests only"],
}
local function ToggleFilter(key)
   mod.db.profile[key] = not mod.db.profile[key]
   mod:RequestUpdate()
end

-- View radios and the quest filters, shared by the title and Quests header menus.
local function AddQuestFilterItems(root)
   root:CreateTitle(L["Quests shown"])
   for _, view in ipairs(VIEW_ORDER) do
      root:CreateRadio(VIEW_LABELS[view],
         function() return mod:GetView() == view end,
         function() mod:SetView(view) end)
   end
   root:CreateDivider()
   root:CreateCheckbox(L["Hide red quests"],
      function() return mod.db.profile.hideRedQuests end,
      function() ToggleFilter("hideRedQuests") end)
   root:CreateCheckbox(L["Hide gray quests"],
      function() return mod.db.profile.hideGrayQuests end,
      function() ToggleFilter("hideGrayQuests") end)
end

function mod:ShowTitleMenu(owner)
   MenuUtil.CreateContextMenu(owner, function(_, root)
      AddQuestFilterItems(root)
      root:CreateDivider()
      root:CreateButton(L["Open settings"], function() mod:OpenConfig() end)
   end)
end

local function ShowQuestsHeaderMenu(owner)
   MenuUtil.CreateContextMenu(owner, function(_, root)
      AddQuestFilterItems(root)
      root:CreateDivider()
      if ToggleQuestLog then
         root:CreateButton(L["Open quest log"], function() ToggleQuestLog() end)
      end
      root:CreateButton(L["Open settings"], function() mod:OpenConfig() end)
   end)
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
      AddFocusButton(root, questID)
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

      AddFocusButton(root, questID)

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

local function UntrackAchievement(achievementID)
   C_ContentTracking.StopTracking(Enum.ContentTrackingType.Achievement, achievementID, Enum.ContentTrackingStopType.Manual)
   if AchievementFrameAchievements_ForceUpdate then
      AchievementFrameAchievements_ForceUpdate()
   end
end

local function ShowAchievement(achievementID)
   if not AchievementFrame and AchievementFrame_LoadUI then
      AchievementFrame_LoadUI()
   end
   if not AchievementFrame then return end
   if not AchievementFrame:IsShown() then
      AchievementFrame_ToggleAchievementFrame()
      AchievementFrame_SelectAchievement(achievementID)
   elseif AchievementFrameAchievements.selection ~= achievementID then
      AchievementFrame_SelectAchievement(achievementID)
   else
      AchievementFrame_ToggleAchievementFrame()
   end
end

local function ShowAchievementMenu(owner, achievement)
   -- Copy the fields: the achievement table is recycled on the next update.
   local achievementID, name = achievement.achievementID, achievement.name
   MenuUtil.CreateContextMenu(owner, function(_, root)
      root:CreateTitle(name)
      root:CreateButton(OBJECTIVES_VIEW_ACHIEVEMENT or L["View achievement"], function()
         ShowAchievementFrameForAchievement(achievementID)
      end)
      root:CreateButton(OBJECTIVES_STOP_TRACKING or L["Stop tracking"], function()
         UntrackAchievement(achievementID)
      end)
   end)
end

mod.lineClickHandlers = {
   zone = function(self, _, section)
      local collapsed = self.db.char.collapsedZones
      local key = section.foldKey or section.name
      collapsed[key] = not collapsed[key] or nil
      self:RequestUpdate()
   end,

   section = function(self, line, section, button)
      -- Right-click on the Quests header: views, filters and the quest log.
      if button == "RightButton" and section.key == "quests" then
         ShowQuestsHeaderMenu(line)
         return
      end
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
      elseif quest.isAutoComplete and quest.isComplete and ShowQuestComplete then
         ShowQuestComplete(questID)
      elseif self.db.profile.mapClicks then
         -- Opening the map from addon code taints it, and Blizzard's map
         -- code is then blocked when the map is next opened in combat.
         if quest.isTask then
            OpenTaskOnMap(questID)
         else
            OpenQuestOnMap(questID)
         end
      end
   end,

   achievement = function(self, line, achievement, button)
      local achievementID = achievement.achievementID
      if IsModifiedClick("CHATLINK") then
         InsertChatLink(GetAchievementLink(achievementID))
      elseif button == "RightButton" then
         ShowAchievementMenu(line, achievement)
      elseif IsModifiedClick("QUESTWATCHTOGGLE") then
         UntrackAchievement(achievementID)
      else
         ShowAchievement(achievementID)
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
