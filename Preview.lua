--[[
**********************************************************************
MagicQuestTracker - Tracker preview for the setup wizard.
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

local CreateFrame = CreateFrame

----------------------------------------------------------------
-- A second tracker frame showing made-up quests, rendered with the real
-- renderer (see mod:RunInView) from a profile the wizard edits. The quest
-- log has everything the options can show: several zones, the zone the
-- player is in, completed quests, a focused and tracked ones, a progress
-- bar, an elite and a daily quest, world quests, recipes, achievements.
----------------------------------------------------------------

local PREVIEW_LAYOUT = { point = "TOPLEFT", x = 0, y = 0, width = 270, maxHeight = 340, scale = 1 }

--- Creates the preview frame inside parent. Returns the view to hand to
--- mod:UpdatePreview(); set view.profile to the profile to show.
function mod:CreatePreview(parent)
   local view = {
      lines = {}, numLinesUsed = 0, fontObjects = {}, layout = PREVIEW_LAYOUT,
      scrollbarReserved = false, headerBarExtend = 0,
   }
   local frame = CreateFrame("Frame", nil, parent)
   view.frame = frame

   frame.bg = frame:CreateTexture(nil, "BACKGROUND")
   frame.bg:SetAlpha(0)
   frame.border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
   frame.border:SetAllPoints()
   frame.border:SetAlpha(0)

   local title = CreateFrame("Button", nil, frame)
   title:EnableMouse(false)
   frame.title = title
   title.text = title:CreateFontString(nil, "OVERLAY")
   title.text:SetJustifyH("LEFT")
   title.text:SetWordWrap(false)
   local minimize = CreateFrame("Button", nil, title)
   minimize:SetSize(20, 20)
   minimize:SetPoint("RIGHT", -2, 0)
   minimize:SetHighlightAtlas("ui-questtrackerbutton-red-highlight", "ADD")
   minimize:EnableMouse(false)
   title.minimize = minimize
   title.bg = title:CreateTexture(nil, "BACKGROUND")

   local scroll = CreateFrame("ScrollFrame", nil, frame)
   scroll:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
   scroll.contentHeight = 0
   scroll.viewHeight = 0
   frame.scroll = scroll
   scroll:EnableMouseWheel(true)
   scroll:SetScript("OnMouseWheel", function(self, delta)
      local maxScroll = math.max(0, self.contentHeight - self.viewHeight)
      self:SetVerticalScroll(math.min(maxScroll, math.max(0, self:GetVerticalScroll() - delta * 30)))
      mod:RunInView(view, mod.UpdateScrollBar)
   end)
   local child = CreateFrame("Frame", nil, scroll)
   child:SetSize(1, 1)
   scroll:SetScrollChild(child)
   frame.child = child

   local bar = frame:CreateTexture(nil, "OVERLAY")
   bar:SetColorTexture(1, 1, 1, 1)
   bar:SetWidth(4)
   frame.scrollThumb = bar
   return view
end

----------------------------------------------------------------
-- The made-up quest log
----------------------------------------------------------------

local function Objective(text, finished, percent)
   return { text = text, finished = finished or false, percent = percent }
end

-- { zone, current zone, quest fields }; the quest tables are copied for
-- every render, as arranging them changes them.
local function QuestLog()
   local daily = Enum.QuestFrequency and Enum.QuestFrequency.Daily
   return {
      { "Elwynn Forest", true, {
         title = "Wolves Across the Border", level = 8, distance = 340, watched = true,
         hasItem = true, itemTexture = "Interface\\Icons\\INV_Misc_Note_01",
         objectives = { Objective("Prowler slain: 10/10", true), Objective("Princess slain: 0/1") } } },
      { "Elwynn Forest", true, {
         title = "Gold Dust Exchange", level = 9, distance = 120, watched = true, complete = true,
         focused = true, completionText = "Return to Remy \"Two Times\"" } },
      { "Elwynn Forest", true, {
         title = "The Fargodeep Mine", level = 10, distance = 810, elite = true, tag = "Group",
         forever = true, group = true, objectives = { Objective("Fargodeep Mine explored") } } },
      { "Westfall", false, {
         title = "The Defias Brotherhood", level = 12, distance = 2100, watched = true,
         objectives = { Objective("Defias Pillager slain: 4/8"), Objective("Progress", false, 45) } } },
      { "Westfall", false, {
         title = "Fishing Frenzy", level = 11, distance = 2600, frequency = daily,
         objectives = { Objective("Oil Covered Fish: 2/5") } } },
      { "Duskwood", false, {
         title = "Worgen in the Woods", level = 20, distance = 5200, watched = true, complete = true,
         completionText = "Return to Commander Althea Ebonlocke" } },
   }
end

-- Stable negative IDs: the sort order hysteresis remembers quests by ID.
local ids, numIDs = {}, 0
local function StableID(title)
   local id = ids[title]
   if not id then
      numIDs = numIDs + 1
      id = -(100000 + numIDs)
      ids[title] = id
   end
   return id
end

local function BuildQuest(zone, isCurrent, def)
   local quest = {
      questID = StableID(def.title),
      title = def.title, level = def.level, difficultyLevel = def.level,
      distance = def.distance, frequency = def.frequency,
      isComplete = def.complete or false, isFailed = false,
      isWatched = def.watched or false, isSuperTracked = def.focused or false,
      isElite = def.elite or false, tagName = def.tag,
      isForeverQuest = def.forever and mod.IS_FOREVER or false,
      completionText = def.completionText,
      hasItem = def.hasItem, itemTexture = def.itemTexture, previewGroup = def.group,
      objectives = def.objectives or {},
      zoneName = zone, inCurrentZone = isCurrent,
   }
   return quest
end

--- Returns what mod:Render() takes: sections, numQuests, numShown, recipes,
--- tasks, scenario, achievements.
local function BuildPreviewData(profile)
   local pinMode = profile.focusedSection == "focused" or profile.focusedSection == "tracked"
   local allCompleted = profile.completedSection == "all"
   local sections, byName = {}, {}
   local numQuests, numShown = 0, 0
   for _, entry in ipairs(QuestLog()) do
      local zone, isCurrent, def = entry[1], entry[2], entry[3]
      numQuests = numQuests + 1
      local quest = BuildQuest(zone, isCurrent, def)
      local visible = true
      if profile.onlyCurrentZone and not isCurrent then visible = false end
      if visible and not profile.showAllQuests and not quest.isWatched then visible = false end
      if (pinMode and quest.isSuperTracked) or (allCompleted and quest.isComplete) then visible = true end
      if visible then
         local section = byName[zone]
         if not section then
            section = {
               name = zone, isCurrent = isCurrent, zoneRank = isCurrent and 1 or 0,
               minLevel = math.huge, quests = {},
            }
            byName[zone] = section
            sections[#sections + 1] = section
         end
         if profile.showDirection then quest.poi = {} end
         if isCurrent then section.hasLocalQuests = true end
         section.quests[#section.quests + 1] = quest
         section.minLevel = math.min(section.minLevel, quest.level)
         numShown = numShown + 1
      end
   end
   sections = mod.ArrangeSections(sections, profile)

   local tasks
   if not mod.IS_FOREVER then
      tasks = { worldQuests = {}, bonus = {} }
      if profile.showWorldQuests then
         tasks.worldQuests[1] = {
            questID = StableID("Shadows of the Sea"), title = "Shadows of the Sea", isTask = true, isWorldQuest = true,
            inArea = true, inCurrentZone = true, isComplete = false, isWatched = false,
            timeLeftText = "3 hours 20 minutes remaining",
            objectives = { Objective("Smuggler slain: 3/8") },
         }
      end
      if profile.showBonusObjectives then
         tasks.bonus[1] = {
            questID = StableID("Hold the Line"), title = "Hold the Line", isTask = true, inArea = true,
            inCurrentZone = true, isComplete = false, isWatched = false,
            objectives = { Objective("Hold the Line", false, 60) },
         }
      end
   end

   local recipes = {
      { name = "Bolt of Linen Cloth", reagents = {
         { text = "Linen Cloth 3/5", finished = false }, { text = "Coarse Thread 1/1", finished = true } } },
   }
   local achievements
   if not mod.IS_FOREVER and profile.showAchievements then
      achievements = {
         { name = "Explore Elwynn Forest", objectives = { Objective("Fargodeep Mine"), Objective("Northshire Abbey", true) } },
      }
   end
   return sections, numQuests, numShown, recipes, tasks, nil, achievements
end

--- Draws the preview for the profile in view.profile.
function mod:UpdatePreview(view)
   if not view or not view.profile then return end
   self:RunInView(view, function(self)
      self:UpdateFonts()
      view.frame.title.text:SetFontObject(view.fontObjects.title)
      self:ApplyLayout()
      self:Render(BuildPreviewData(self.db.profile))
   end)
end
