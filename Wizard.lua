--[[
**********************************************************************
MagicQuestTracker - Setup wizard and "what's new" window.
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

local CreateFrame = CreateFrame
local UIParent = UIParent

----------------------------------------------------------------
-- Setup wizard
--
-- A multi page window that edits a copy of the current profile, shown in a
-- preview tracker with made-up quests (Preview.lua), so every option can be
-- seen whatever the quest log holds. Nothing is changed until Finish, which
-- writes the copy to the current profile, or to a new one.
--
-- "What's new" (below) lists features added since the user last looked, and
-- is where the wizard is offered to existing users. New features add an
-- entry to WHATS_NEW; a fresh install gets a small welcome prompt instead.
----------------------------------------------------------------

local PAGE_WIDTH = 500
local PREVIEW_WIDTH = 330
local FRAME_WIDTH, FRAME_HEIGHT = PAGE_WIDTH + PREVIEW_WIDTH + 96, 520
local CHECK_SIZE = 24

local function RawProfile()
   return mod.db.sv.profiles[mod.db.keys.profile]
end

local function DeepCopy(value)
   if type(value) ~= "table" then return value end
   local copy = {}
   for k, v in pairs(value) do
      copy[DeepCopy(k)] = DeepCopy(v)
   end
   return copy
end

local function ReplaceContents(target, source)
   wipe(target)
   for k, v in pairs(source) do
      target[k] = DeepCopy(v)
   end
end

----------------------------------------------------------------
-- Reading and writing settings
--
-- Keys are profile keys, plus the virtual keys "theme", "view" and
-- "autoTrack", which have their own storage.
----------------------------------------------------------------

local function CVarBool(name)
   return GetCVarBool and GetCVarBool(name) or false
end

local function SetCVarValue(name, value)
   (C_CVar and C_CVar.SetCVar or SetCVar)(name, value)
end

function mod:GetWizardOption(key)
   if key == "theme" then
      return self.db.profile.theme
   elseif key == "view" then
      return self:GetView()
   elseif key == "autoTrack" then
      return CVarBool("autoQuestWatch")
   elseif key == "zoneHeaders" then
      return self:GetZoneHeaderMode()
   end
   return self.db.profile[key]
end

function mod:SetWizardOption(key, value)
   local profile = self.db.profile
   if key == "theme" then
      self:SelectTheme(value)
      return
   elseif key == "view" then
      self:SetView(value)
      return
   elseif key == "autoTrack" then
      SetCVarValue("autoQuestWatch", value and "1" or "0")
      return
   elseif key == "zoneHeaders" then
      self:SetZoneHeaderMode(value)
      return
   end
   profile[key] = value
   if key == "showDistance" or key == "showDirection" then
      self:UpdateDistanceTimer()
   elseif key == "hideBlizzardTracker" then
      self:SetBlizzardTrackerHidden(value)
   elseif key == "hideInCombat" or key == "hideInInstances" then
      self:UpdateCombatVisibility()
   end
   self:RequestUpdate()
end

-- The look and behavior of the built-in objective tracker.
local BLIZZARD_STYLE = {
   theme = "blizzard",
   view = "tracked",
   zoneHeaders = "always",
   simpleSectionHeaders = true,
   simpleZoneHeaders = false,
   colorByDifficulty = false,
   colorCompleteQuests = false,
   showQuestTags = false,
   showLevel = mod.IS_FOREVER or false,
   focusedSection = "none",
   completedSort = "normal",
   completedSection = "none",
   zoneSort = "distance",
   questSort = "distance",
   showDistance = false,
   showDirection = false,
   markForeverQuests = false,
   markWatchedQuests = false,
   hideBlizzardTracker = true,
   hideInCombat = "never",
   hideInInstances = "never",
   showItemButtons = true,
   showPOIButtons = true,
   showFindGroupButton = true,
   buttonsOnHover = false,
   sectionFold = "blizzard",
   sectionFoldPosition = "right",
   autoTrack = true,
}

----------------------------------------------------------------
-- The working copy
--
-- The wizard edits `work`: the current profile with the defaults filled in,
-- and keeps the automatic quest tracking setting (a game setting) in
-- workAutoTrack. Finish writes them out.
----------------------------------------------------------------

local wizard   -- the window, created on first use
local work, workAutoTrack, matchBlizzard

local function Overlay(target, source)
   for k, v in pairs(source) do
      if type(v) == "table" and type(target[k]) == "table" then
         Overlay(target[k], v)
      else
         target[k] = DeepCopy(v)
      end
   end
   return target
end

local function StartWork()
   work = Overlay(CopyTable(mod.defaults.profile), RawProfile())
   workAutoTrack = CVarBool("autoQuestWatch")
   matchBlizzard = false
end

local function RefreshPreview()
   if wizard and wizard.preview then
      -- Pages can show the preview differently (e.g. zone headers always on
      -- while choosing their fold icon) without changing the settings.
      local pages = wizard.pages
      local page = pages and pages[wizard.pageIndex or 1]
      local overrides = page and page.previewOverrides
      wizard.preview.profile = overrides and setmetatable(CopyTable(overrides), { __index = work }) or work
      mod:UpdatePreview(wizard.preview)
   end
end

local function GetOpt(key)
   if key == "view" then
      if not work.showAllQuests then return "tracked" end
      return work.onlyCurrentZone and "zone" or "all"
   elseif key == "autoTrack" then
      return workAutoTrack
   elseif key == "completedPosition" then
      return work.completedPosition or (work.completedSort == "last" and "bottom" or "top")
   elseif key == "zoneHeaders" then
      local hidden = work.hideZoneHeaders
      if hidden == "single" then return "single" end
      return hidden and "always" or "never"
   elseif key == "sectionCounts" then
      -- See mod:GetSectionCountMode.
      local simple = work.simpleSectionHeaders
      if simple == "count" then return "count" end
      return simple and "none" or "full"
   end
   return work[key]
end

local function SetOpt(key, value)
   if key == "view" then
      work.showAllQuests = value ~= "tracked"
      work.onlyCurrentZone = value == "zone"
   elseif key == "autoTrack" then
      workAutoTrack = value and true or false
   elseif key == "zoneHeaders" then
      work.hideZoneHeaders = (value == "always") or (value == "single" and "single") or false
   elseif key == "sectionCounts" then
      work.simpleSectionHeaders = value == "none" or (value == "count" and "count") or false
   else
      work[key] = value
   end
   RefreshPreview()
end

--- Applies the built-in tracker's look and behavior (and, on Finish, its position).
local function ApplyBlizzardToWork()
   for key, value in pairs(BLIZZARD_STYLE) do
      SetOpt(key, value)
   end
   matchBlizzard = true
end

----------------------------------------------------------------
-- Widgets
----------------------------------------------------------------

local Page = {}
Page.__index = Page

local function NewPage(parent)
   local page = setmetatable({ y = 0, refreshers = {} }, Page)
   page.frame = CreateFrame("Frame", nil, parent)
   page.frame:SetAllPoints()
   page.frame:Hide()
   return page
end

function Page:Text(template, text, width, color)
   local fs = self.frame:CreateFontString(nil, "ARTWORK", template)
   fs:SetJustifyH("LEFT")
   fs:SetJustifyV("TOP")
   fs:SetWidth(width or PAGE_WIDTH)
   fs:SetPoint("TOPLEFT", 0, -self.y)
   fs:SetText(text)
   if color then fs:SetTextColor(unpack(color)) end
   return fs
end

function Page:Gap(height)
   self.y = self.y + height
end

function Page:Heading(text)
   local fs = self:Text("GameFontNormalLarge", text)
   self.y = self.y + fs:GetStringHeight() + 8
end

function Page:Paragraph(text)
   local fs = self:Text("GameFontHighlight", text)
   self.y = self.y + fs:GetStringHeight() + 10
end

function Page:Subheading(text)
   self:Gap(4)
   local fs = self:Text("GameFontNormal", text)
   self.y = self.y + fs:GetStringHeight() + 4
end

local function NewCheckButton(parent, x, y, label, width)
   local button = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
   button:SetSize(CHECK_SIZE, CHECK_SIZE)
   button:SetPoint("TOPLEFT", x, -y)
   local text = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
   text:SetJustifyH("LEFT")
   text:SetPoint("TOPLEFT", button, "TOPRIGHT", 2, -5)
   text:SetWidth(width)
   text:SetText(label)
   button.label = text
   return button, text
end

--- A checkbox with an optional description below it.
-- get() returns the checked state, set(checked) applies it.
function Page:Check(label, desc, get, set)
   local button, text = NewCheckButton(self.frame, 0, self.y, label, PAGE_WIDTH - CHECK_SIZE - 6)
   button:SetScript("OnClick", function(self)
      set(self:GetChecked() and true or false)
   end)
   local height = math.max(CHECK_SIZE, text:GetStringHeight() + 8)
   if desc and desc ~= "" then
      local d = self.frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
      d:SetJustifyH("LEFT")
      d:SetJustifyV("TOP")
      d:SetTextColor(0.6, 0.6, 0.6)
      d:SetWidth(PAGE_WIDTH - CHECK_SIZE - 6)
      d:SetPoint("TOPLEFT", button, "TOPLEFT", CHECK_SIZE + 2, -(text:GetStringHeight() + 7))
      d:SetText(desc)
      height = text:GetStringHeight() + d:GetStringHeight() + 12
   end
   self.y = self.y + math.max(CHECK_SIZE, height)
   self.refreshers[#self.refreshers + 1] = function()
      button:SetChecked(get() and true or false)
   end
end

--- A group of mutually exclusive choices: choices = { { value, label }, ... }.
-- Laid out in rows of columns of the given width (one per line by default).
function Page:Radio(label, choices, get, set, columnWidth)
   if label then self:Subheading(label) end
   local perRow = columnWidth and math.max(1, math.floor(PAGE_WIDTH / columnWidth)) or 1
   local width = columnWidth or PAGE_WIDTH
   local buttons = {}
   local column = 0
   for _, choice in ipairs(choices) do
      local x = column * width
      local button = NewCheckButton(self.frame, x, self.y, choice[2], width - CHECK_SIZE - 6)
      button.value = choice[1]
      button:SetScript("OnClick", function(self)
         set(self.value)
         for _, other in ipairs(buttons) do
            other:SetChecked(other.value == get())
         end
      end)
      buttons[#buttons + 1] = button
      column = column + 1
      if column >= perRow then
         column = 0
         self.y = self.y + CHECK_SIZE
      end
   end
   if column > 0 then self.y = self.y + CHECK_SIZE end
   self.y = self.y + 4
   self.refreshers[#self.refreshers + 1] = function()
      for _, button in ipairs(buttons) do
         button:SetChecked(button.value == get())
      end
   end
end

function Page:Refresh()
   for _, refresh in ipairs(self.refreshers) do refresh() end
end

--- A page checkbox bound to a wizard option key.
function Page:Option(label, desc, key)
   self:Check(label, desc,
      function() return GetOpt(key) end,
      function(value) SetOpt(key, value) end)
end

--- A page radio group bound to a wizard option key.
function Page:Choice(label, key, choices, columnWidth)
   self:Radio(label, choices,
      function() return GetOpt(key) end,
      function(value) SetOpt(key, value) end,
      columnWidth)
end

----------------------------------------------------------------
-- Pages
----------------------------------------------------------------

local function HasTasks()
   return not mod.IS_FOREVER and GetTasksTable ~= nil
end

local pageBuilders = {}

pageBuilders[1] = function(page)
   local icon = page.frame:CreateTexture(nil, "ARTWORK")
   icon:SetSize(72, 72)
   icon:SetPoint("TOPRIGHT", 0, 0)
   icon:SetTexture("Interface\\AddOns\\MagicQuestTracker\\Textures\\Icon.png")
   page:Heading(L["Welcome to Magic Quest Tracker"])
   -- Narrower than the page: the scroll is in the corner.
   local intro = page:Text("GameFontHighlight",
      L["This setup walks you through the look and the features of the tracker. The preview on the right shows every choice, with made-up quests so you can see all the options. Nothing changes until you finish. You can run it again from the settings, or with /mqt wizard."],
      PAGE_WIDTH - 84)
   page.y = page.y + math.max(intro:GetStringHeight(), 56) + 10
   -- A new install already starts out like Blizzard's tracker.
   if not mod.freshInstall then
      local button = CreateFrame("Button", nil, page.frame, "UIPanelButtonTemplate")
      button:SetSize(PAGE_WIDTH, 28)
      button:SetPoint("TOPLEFT", 0, -page.y)
      button:SetText(L["Match Blizzard's tracker"])
      button:SetScript("OnClick", function()
         ApplyBlizzardToWork()
         wizard:RefreshPages()
      end)
      page.y = page.y + 32
      local fs = page:Text("GameFontHighlightSmall",
         L["The look and behavior of the built-in objective tracker: tracked quests only, no zone headers, plain titles. Also moves the tracker to where Blizzard's sits. Or keep your current settings and just pick a theme."],
         PAGE_WIDTH, { 0.6, 0.6, 0.6 })
      page.y = page.y + fs:GetStringHeight() + 10
   end
   page:Subheading(L["Theme"])
   page:Paragraph(L["The preview shows the theme as you select it. Custom themes you made are listed too."])
   local scroll = CreateFrame("ScrollFrame", nil, page.frame, "UIPanelScrollFrameTemplate")
   scroll:SetPoint("TOPLEFT", 0, -page.y)
   scroll:SetSize(PAGE_WIDTH - 28, FRAME_HEIGHT - 52 - 60 - page.y)
   local content = CreateFrame("Frame", nil, scroll)
   content:SetSize(PAGE_WIDTH - 28, 1)
   scroll:SetScrollChild(content)

   local names = mod:GetThemeList()
   local keys = {}
   for key in pairs(names) do keys[#keys + 1] = key end
   table.sort(keys, function(a, b)
      if a == "blizzard" then return true end
      if b == "blizzard" then return false end
      return names[a] < names[b]
   end)
   local buttons = {}
   local rowHeight = 24
   for i, key in ipairs(keys) do
      local button = CreateFrame("Button", nil, content)
      button:SetSize(PAGE_WIDTH - 28, rowHeight)
      button:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
      button.value = key
      button.highlight = button:CreateTexture(nil, "BACKGROUND")
      button.highlight:SetAllPoints()
      button.highlight:SetColorTexture(1, 0.82, 0, 0.25)
      button.highlight:Hide()
      button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
      local text = button:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
      text:SetPoint("LEFT", 8, 0)
      text:SetText(names[key])
      button:SetScript("OnClick", function(self)
         SetOpt("theme", self.value)
         page:Refresh()
      end)
      buttons[#buttons + 1] = button
   end
   content:SetHeight(#keys * rowHeight)
   page.refreshers[#page.refreshers + 1] = function()
      local current = GetOpt("theme")
      for _, button in ipairs(buttons) do
         button.highlight:SetShown(button.value == current)
      end
   end
   page.y = page.y + scroll:GetHeight()
end

pageBuilders[2] = function(page)
   page:Heading(L["Which quests"])
   page:Choice(L["Quests shown"], "view", {
      { "tracked", L["Tracked quests only"] },
      { "zone", L["Current zone only"] },
      { "all", L["All quests"] },
   })
   page:Option(L["Automatically track new quests"],
      L["Add quests to the watch list when you accept them. This is the game's own automatic quest tracking setting."],
      "autoTrack")
   page:Gap(6)
   page:Choice(L["Zone headers"], "zoneHeaders", {
      { "never", L["Show"] },
      { "single", L["Hide when only one is shown"] },
      { "always", L["Hide"] },
   }, 170)
   page:Check(L["Quest counts in zone headers"],
      L["Show the number of quests and completed quests in zone headers."],
      function() return not GetOpt("simpleZoneHeaders") end,
      function(value) SetOpt("simpleZoneHeaders", not value) end)
   page:Choice(L["Section header counts"], "sectionCounts", {
      { "full", L["Count and maximum"] },
      { "count", L["Count only"] },
      { "none", L["None"] },
   }, 170)
end

pageBuilders[3] = function(page)
   page:Heading(L["Sections"])
   page:Paragraph(L["Choose what else the tracker lists besides quests."])
   if HasTasks() then
      page:Option(L["Show world quests"],
         L["Show world quests in the current area and tracked world quests in a separate section."], "showWorldQuests")
      page:Option(L["Show bonus objectives"],
         L["Show bonus objectives in the current area in a separate section."], "showBonusObjectives")
   end
   if not mod.IS_FOREVER then
      page:Option(L["Show tracked achievements"], nil, "showAchievements")
   end
   page:Option(L["Show tracked recipes"], nil, "showRecipes")
   page:Option(L["Show completed objectives"],
      L["Show finished objectives of incomplete quests, dimmed."], "showCompletedObjectives")
   page:Option(L["Show timer bars"],
      L["Show time limits as a bar that empties as time runs out, instead of a line of text."], "timerBars")
end

pageBuilders[4] = function(page)
   page:Heading(L["Focused and completed quests"])
   page:Paragraph(L["Give the quest you focus on, and the quests you have finished, a section of their own."])
   page:Choice(L["Focused / tracked section"], "focusedSection", {
      { "none", L["None"] },
      { "focused", L["Focused quest only"] },
      { "tracked", L["Tracked quests"] },
   }, 170)
   page:Choice(L["Position"], "focusedPosition", {
      { "top", L["Above the zones"] },
      { "bottom", L["Below the zones"] },
   }, 170)
   page:Gap(6)
   page:Choice(L["Completed quests"], "completedSection", {
      { "none", L["With their zone"] },
      { "all", L["Own section, all zones"] },
      { "current", L["Own section, current zone"] },
   }, 170)
   page:Choice(L["Position"], "completedPosition", {
      { "top", L["Above the zones"] },
      { "bottom", L["Below the zones"] },
   }, 170)
end

pageBuilders[5] = function(page)
   page:Heading(L["Details"])
   page:Paragraph(L["Extra information next to each quest. The built-in tracker shows none of these, except the level in Forever."])
   page:Option(L["Show quest level"], nil, "showLevel")
   page:Option(L["Show quest type tags"], L["Add tags like Elite, Daily or Group after the title."], "showQuestTags")
   page:Option(L["Color by difficulty"],
      L["Color quest titles by their difficulty relative to your level."], "colorByDifficulty")
   page:Option(L["Show distance"], L["Show the distance to the quest."], "showDistance")
   page:Option(L["Show direction arrow"], L["Show an arrow pointing toward the quest."], "showDirection")
   if mod.IS_FOREVER then
      page:Option(L["Mark Forever quests"], nil, "markForeverQuests")
   end
end

pageBuilders[6] = function(page)
   page:Heading(L["Buttons and behavior"])
   page:Option(L["Show quest POI buttons"],
      L["Show the quest map icon next to each quest, like the built-in tracker. Click it to focus the quest. Follows the game's quest POI setting."],
      "showPOIButtons")
   page:Option(L["Show quest item buttons"],
      L["Show a button to use the quest item next to quests that have one."], "showItemButtons")
   if not mod.IS_FOREVER then
      page:Option(L["Show find group buttons"],
         L["Show the group finder button on quests that support it, like the built-in tracker."], "showFindGroupButton")
   end
   page:Option(L["Show buttons on mouseover"],
      L["Hide the quest markers, find group and voiceover buttons until the mouse is over the tracker, for a cleaner look. The focused quest's marker and quest item buttons stay visible."],
      "buttonsOnHover")
   page:Option(L["Hide Blizzard tracker"],
      L["Hide the built-in objective tracker. Note that this hides all of its sections, including scenarios and bonus objectives."],
      "hideBlizzardTracker")
   page:Choice(L["Hide the tracker in combat"], "hideInCombat", {
      { "never", L["Never"] },
      { "instances", L["In instances"] },
      { "always", L["Always"] },
   }, 170)
end

pageBuilders[7] = function(page)
   page:Heading(L["Fold icons"])
   page.previewOverrides = {
      hideZoneHeaders = false, showAllQuests = true, onlyCurrentZone = false, showRecipes = true, previewFolded = true,
   }
   page:Paragraph(L["Headers can be folded by clicking them. Choose the icon and where it goes."])
   page:Choice(L["Zone headers"], "zoneFold", {
      { "triangle", L["Triangle"] },
      { "chevron", L["Chevron"] },
      { "box", L["Plus / minus box"] },
      { "plusminus", L["Plus / minus"] },
      { "blizzard", L["Blizzard"] },
      { "none", L["None"] },
   }, 170)
   page:Choice(L["Position"], "zoneFoldPosition", {
      { "left", L["Left"] },
      { "after", L["Right of title"] },
      { "right", L["Right"] },
   }, 170)
end

pageBuilders[8] = function(page)
   page:Heading(L["All done"])
   page:Paragraph(L["That's it. Keep these settings on the current profile, or save them to a new profile and leave the current one as it was."])
   local nameBox
   page:Radio(nil, {
      { "current", L["Keep them on this profile"] },
      { "new", L["Save them to a new profile"] },
   }, function() return wizard.saveNewProfile and "new" or "current" end,
   function(value)
      nameBox:SetShown(value == "new")
      wizard.saveNewProfile = value == "new" and nameBox or nil
   end)
   nameBox = CreateFrame("EditBox", nil, page.frame, "InputBoxTemplate")
   nameBox:SetSize(240, 24)
   nameBox:SetPoint("TOPLEFT", 36, -page.y)
   nameBox:SetAutoFocus(false)
   nameBox:SetText(L["Quest tracker wizard"])
   nameBox:Hide()
   wizard.nameBox = nameBox
   page.y = page.y + 34
   wizard.error = page:Text("GameFontNormal", "", PAGE_WIDTH, { 1, 0.3, 0.3 })
end

local NUM_PAGES = #pageBuilders

----------------------------------------------------------------
-- The window
----------------------------------------------------------------

-- Dialog border with an opaque backing: the dialog background texture alone
-- is see-through enough to make the text hard to read over the game world.
local function StyleDialog(frame)
   frame:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 11, right = 12, top = 12, bottom = 11 },
   })
   local backing = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
   backing:SetPoint("TOPLEFT", 11, -11)
   backing:SetPoint("BOTTOMRIGHT", -11, 11)
   backing:SetColorTexture(0.04, 0.04, 0.06, 0.96)
end

local function CreateWizard()
   local frame = CreateFrame("Frame", "MagicQuestTrackerWizard", UIParent, "BackdropTemplate")
   frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
   frame:SetPoint("CENTER")
   frame:SetFrameStrata("DIALOG")
   frame:SetToplevel(true)
   frame:EnableMouse(true)
   frame:SetMovable(true)
   frame:SetClampedToScreen(true)
   frame:RegisterForDrag("LeftButton")
   frame:SetScript("OnDragStart", frame.StartMoving)
   frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
   StyleDialog(frame)
   frame:Hide()
   wizard = frame

   local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
   title:SetPoint("TOP", 0, -18)
   title:SetText(L["Magic Quest Tracker setup"])

   local container = CreateFrame("Frame", nil, frame)
   container:SetPoint("TOPLEFT", 32, -52)
   container:SetPoint("BOTTOMLEFT", 32, 60)
   container:SetWidth(PAGE_WIDTH)

   -- The preview: a tracker over a plain backdrop, in a panel of its own.
   local panel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
   panel:SetPoint("TOPRIGHT", -32, -52)
   panel:SetPoint("BOTTOMRIGHT", -32, 60)
   panel:SetWidth(PREVIEW_WIDTH)
   panel:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 },
   })
   panel:SetBackdropColor(0.13, 0.15, 0.12, 1)
   panel:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
   panel.label = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
   panel.label:SetPoint("BOTTOM", 0, 8)
   panel.label:SetText(L["Preview with made-up quests"])
   frame.preview = mod:CreatePreview(panel)
   frame.preview.frame:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -20, -16)

   frame.pages = {}
   for i = 1, NUM_PAGES do
      local page = NewPage(container)
      pageBuilders[i](page)
      frame.pages[i] = page
   end

   local footer = frame:CreateFontString(nil, "ARTWORK", "GameFontDisable")
   footer:SetPoint("BOTTOM", 0, 24)

   local cancel = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
   cancel:SetSize(90, 24)
   cancel:SetPoint("BOTTOMLEFT", 24, 18)
   cancel:SetText(L["Cancel"])
   cancel:SetScript("OnClick", function() frame:Hide() end)

   local next = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
   next:SetSize(90, 24)
   next:SetPoint("BOTTOMRIGHT", -24, 18)
   local back = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
   back:SetSize(90, 24)
   back:SetPoint("RIGHT", next, "LEFT", -6, 0)
   back:SetText(L["Back"])

   function frame:ShowPage(index)
      self.pageIndex = index
      for i, page in ipairs(self.pages) do
         page.frame:SetShown(i == index)
      end
      self.pages[index]:Refresh()
      RefreshPreview()
      footer:SetText(format(L["Page %d of %d"], index, NUM_PAGES))
      back:SetEnabled(index > 1)
      next:SetText(index == NUM_PAGES and L["Finish"] or L["Next"])
   end

   function frame:RefreshPages()
      for _, page in ipairs(self.pages) do page:Refresh() end
   end

   back:SetScript("OnClick", function() frame:ShowPage(frame.pageIndex - 1) end)
   next:SetScript("OnClick", function()
      if frame.pageIndex < NUM_PAGES then
         frame:ShowPage(frame.pageIndex + 1)
      else
         frame:Finish()
      end
   end)

   -- Writes the working copy to the current profile, or to a new one.
   function frame:Finish()
      local box = self.saveNewProfile
      local name = box and strtrim(box:GetText()) or nil
      if box then
         local taken = false
         for _, existing in ipairs(mod.db:GetProfiles()) do
            if existing == name then taken = true end
         end
         if name == "" or taken then
            self.error:SetText(name == "" and L["Enter a name for the new profile."]
               or format(L["A profile named %s already exists."], name))
            return
         end
      end
      -- The whole copy: AceDB keeps defaults in the live profile (and drops
      -- them from the saved file itself).
      if name then mod.db:SetProfile(name) end
      ReplaceContents(RawProfile(), work)
      SetCVarValue("autoQuestWatch", workAutoTrack and "1" or "0")
      mod:ApplyProfile()
      if matchBlizzard and mod.MatchBlizzardTracker then
         mod:MatchBlizzardTracker()
      end
      self:Hide()
   end

   frame:SetScript("OnShow", function(self)
      self.saveNewProfile = nil
      self.nameBox:Hide()
      self.error:SetText("")
      StartWork()
      mod:MarkWhatsNewSeen()
      self:ShowPage(1)
   end)
   tinsert(UISpecialFrames, "MagicQuestTrackerWizard")
   return frame
end

function mod:ShowWizard()
   if InCombatLockdown() then
      self:info(L["The setup can't be started during combat."])
      return
   end
   if self.whatsNewFrame then self.whatsNewFrame:Hide() end
   if self.welcomeFrame then self.welcomeFrame:Hide() end
   local frame = wizard or CreateWizard()
   frame:Show()
end

----------------------------------------------------------------
-- What's new
--
-- Each feature is listed with a checkbox to switch it on right there
-- (where it has one), and the window offers the wizard. WHATS_NEW_VERSION
-- is bumped when features are added; the version last seen is kept for the
-- account. Existing profiles keep how they looked, so nothing listed here
-- is switched on by updating.
----------------------------------------------------------------

mod.WHATS_NEW_VERSION = 5

-- { version, title, desc, get, set, enabled, visible } (get and set only for
-- features with a switch; the switch is grayed out unless enabled() says so,
-- and the entry is skipped where visible() is false)
local WHATS_NEW = {
   { 1, L["Setup wizard"],
      L["Pick Blizzard's look or one of the themes, then choose the features. Run it from the button below, the settings, or /mqt wizard."] },
   { 1, L["Tracked quests only"],
      L["A new view that lists only the quests you track, like the built-in tracker. Middle-click the title to switch between all quests, the current zone and tracked quests."],
      function() return mod:GetWizardOption("view") == "tracked" end,
      function(value) mod:SetWizardOption("view", value and "tracked" or "all") end },
   -- No switch: this is the game's own setting, which is normally already on.
   { 1, L["Automatically track new quests"],
      L["The game adds quests to the watch list when you accept them. You can turn that off or on in the General settings."] },
   { 1, L["Hide zone headers"],
      L["List the quests of all zones together, without zone headers. The settings also let you hide them only while a single zone is shown."],
      function() return mod:GetWizardOption("zoneHeaders") == "always" end,
      function(value) mod:SetWizardOption("zoneHeaders", value and "always" or "never") end },
   { 1, L["Fold icons"],
      L["Choose how folded headers look: a triangle, chevron, plus / minus, or Blizzard's button, on the left, right or after the title. See the General settings."] },
   { 2, L["Spacing settings"],
      L["Zone spacing, zone header spacing and a new section header spacing now each control one gap: above a zone header, below it, and below a section header. Find them in the Theme settings, Layout tab."] },
   { 3, L["Timer bars"],
      L["Timed quests show the time left as a bar that empties as time runs out, red in the last minute. Turn it off for a line of text instead."],
      function() return mod:GetWizardOption("timerBars") end,
      function(value) mod:SetWizardOption("timerBars", value) end },
   { 1, L["Quest voiceover buttons"],
      L["Adds the play button of the Spoken Quests addon to quests that have a voiceover."],
      function() return mod:GetWizardOption("showPlayButton") end,
      function(value) mod:SetWizardOption("showPlayButton", value) end,
      function() return mod:GetQuestVoice() ~= nil end,
      function() return mod.IS_FOREVER end },
   -- Replaces the version 1 "Simple headers" switch (now a dropdown).
   { 4, L["Header counts"],
      L["Choose what section headers show: the count and maximum, like Quests (12/25), only the count, like Quests (12), or nothing. Zone header counts can be turned off separately. See the General settings, Quests tab."] },
   { 5, L["Hide red quests"],
      L["Hide quests that are too difficult for your level. Gray quests can be hidden too. Right-click the title or the Quests header to switch the filters and the view."],
      function() return mod:GetWizardOption("hideRedQuests") end,
      function(value) mod:SetWizardOption("hideRedQuests", value) end },
   { 5, L["Show buttons on mouseover"],
      L["Hide the quest markers, find group and voiceover buttons until the mouse is over the tracker, for a cleaner look. The focused quest's marker and quest item buttons stay visible."],
      function() return mod:GetWizardOption("buttonsOnHover") end,
      function(value) mod:SetWizardOption("buttonsOnHover", value) end },
}

function mod:MarkWhatsNewSeen()
   self.db.global.whatsNewSeen = self.WHATS_NEW_VERSION
end

local ICON_TEXTURE = "Interface\\AddOns\\MagicQuestTracker\\Textures\\Icon.png"

local function CreateSmallWindow(name, width, height)
   local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
   frame:SetSize(width, height)
   frame:SetPoint("CENTER", 0, 120)
   frame:SetFrameStrata("DIALOG")
   frame:SetToplevel(true)
   frame:EnableMouse(true)
   frame:SetMovable(true)
   frame:SetClampedToScreen(true)
   frame:RegisterForDrag("LeftButton")
   frame:SetScript("OnDragStart", frame.StartMoving)
   frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
   StyleDialog(frame)
   frame:Hide()
   return frame
end

local function AddButton(frame, label, point, x, onClick, width)
   local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
   button:SetSize(width or 130, 24)
   button:SetPoint(point, x, 18)
   button:SetText(label)
   button:SetScript("OnClick", onClick)
   return button
end

--- Small prompt for a fresh install: run the wizard or skip it.
function mod:ShowWelcome()
   local frame = self.welcomeFrame
   if not frame then
      frame = CreateSmallWindow("MagicQuestTrackerWelcome", 430, 160)
      self.welcomeFrame = frame
      local icon = frame:CreateTexture(nil, "ARTWORK")
      icon:SetSize(96, 96)
      icon:SetPoint("TOPRIGHT", -26, -24)
      icon:SetTexture(ICON_TEXTURE)
      local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
      title:SetPoint("TOPLEFT", 28, -30)
      title:SetText(L["Magic Quest Tracker"])
      local text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
      text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
      text:SetJustifyH("LEFT")
      text:SetWidth(260)
      text:SetText(L["Want to set up the tracker? Pick a look and the features you want in a few steps."])
      AddButton(frame, L["Run setup"], "BOTTOMLEFT", 28, function() mod:ShowWizard() end)
      AddButton(frame, L["Skip"], "BOTTOMRIGHT", -28, function() frame:Hide() end)
   end
   self:MarkWhatsNewSeen()
   frame:Show()
end

--- Lists the features added since the version last seen. all: every entry,
--- or a number to list those added after that version. showHidden also lists
--- entries for other game versions (for testing).
function mod:ShowWhatsNew(all, showHidden)
   local seen = type(all) == "number" and all or all and 0 or (self.db.global.whatsNewSeen or 0)
   local entries = {}
   for _, entry in ipairs(WHATS_NEW) do
      if entry[1] > seen and (showHidden or not entry[7] or entry[7]()) then entries[#entries + 1] = entry end
   end
   if #entries == 0 then return end

   local frame = self.whatsNewFrame
   if frame then
      frame:Hide()
      for _, child in ipairs(frame.entries or {}) do child:Hide() end
   else
      frame = CreateSmallWindow("MagicQuestTrackerWhatsNew", 480, 200)
      self.whatsNewFrame = frame
      local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
      title:SetPoint("TOP", 0, -18)
      title:SetText(L["What's new in Magic Quest Tracker"])
      AddButton(frame, L["Run setup wizard"], "BOTTOMLEFT", 28, function() mod:ShowWizard() end, 160)
      AddButton(frame, L["Close"], "BOTTOMRIGHT", -28, function() frame:Hide() end, 100)
      AddButton(frame, L["Don't show again"], "BOTTOM", 25, function()
         mod.db.global.whatsNewDisabled = true
         frame:Hide()
      end, 140)
      frame:SetScript("OnHide", function() mod:MarkWhatsNewSeen() end)
      tinsert(UISpecialFrames, "MagicQuestTrackerWhatsNew")
      -- Many releases' worth of features scroll instead of growing the window.
      local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
      scroll:SetPoint("TOPLEFT", 28, -52)
      scroll:SetPoint("BOTTOMRIGHT", -46, 56)
      frame.child = CreateFrame("Frame", nil, scroll)
      frame.child:SetSize(1, 1)
      scroll:SetScrollChild(frame.child)
      -- The template then hides the bar whenever there is nothing to scroll.
      scroll.scrollBarHideable = true
      frame.scroll = scroll
   end

   frame.entries = frame.entries or {}
   local width = 480 - 28 - 46
   local y = 0
   local refreshers = {}
   for i, entry in ipairs(entries) do
      local row = frame.entries[i]
      if not row then
         row = CreateFrame("Frame", nil, frame.child)
         row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
         row.check:SetSize(CHECK_SIZE, CHECK_SIZE)
         row.check:SetPoint("TOPLEFT", 0, 0)
         row.title = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
         row.title:SetJustifyH("LEFT")
         row.desc = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
         row.desc:SetJustifyH("LEFT")
         row.desc:SetJustifyV("TOP")
         row.desc:SetTextColor(0.7, 0.7, 0.7)
         frame.entries[i] = row
      end
      local get, set = entry[4], entry[5]
      row.check:SetShown(get ~= nil)
      local enabled = not entry[6] or entry[6]()
      row.check:SetEnabled(enabled)
      -- Entries without a switch line up with the others.
      local indent = CHECK_SIZE + 4
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", 0, -y)
      row.title:ClearAllPoints()
      row.title:SetPoint("TOPLEFT", indent, -4)
      row.title:SetWidth(width - indent)
      row.title:SetText(entry[2])
      row.desc:ClearAllPoints()
      row.desc:SetPoint("TOPLEFT", indent, -(row.title:GetStringHeight() + 8))
      row.desc:SetWidth(width - indent)
      row.desc:SetText(enabled and entry[3] or (entry[3] .. " " .. L["(Needs the Spoken Quests addon, which isn't installed.)"]))
      local height = row.title:GetStringHeight() + row.desc:GetStringHeight() + 14
      row:SetSize(width, height)
      row:Show()
      if get then
         row.check:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
         refreshers[#refreshers + 1] = function() row.check:SetChecked(get() and true or false) end
      end
      y = y + height + 4
   end
   for _, refresh in ipairs(refreshers) do refresh() end
   frame.child:SetSize(width, y)
   frame.scroll:SetVerticalScroll(0)
   -- Up to 3/4 of the screen; the scroll bar only when the list doesn't fit.
   local height = math.min(y + 112, math.floor(UIParent:GetHeight() * 0.75))
   frame:SetHeight(height)
   local scrollBar = frame.scroll.ScrollBar or _G[(frame.scroll:GetName() or "") .. "ScrollBar"]
   if scrollBar then scrollBar:SetShown(y > height - 108) end
   frame:Show()
end

--- Shown once after login: the welcome prompt on a fresh install, what's
--- new when there is something the user hasn't seen yet.
function mod:ShowStartupDialogs()
   if self.startupDialogShown then return end
   self.startupDialogShown = true
   if InCombatLockdown() then return end
   if self.freshInstall then
      self:ShowWelcome()
   elseif not self.db.global.whatsNewDisabled and (self.db.global.whatsNewSeen or 0) < self.WHATS_NEW_VERSION then
      self:ShowWhatsNew()
   end
end
