local L = LibStub("AceLocale-3.0"):GetLocale("MagicQuestTracker")
local mod = LibStub("AceAddon-3.0"):GetAddon("MagicQuestTracker")
local media = LibStub("LibSharedMedia-3.0")

local C_QuestLog = C_QuestLog
local InCombatLockdown = InCombatLockdown

----------------------------------------------------------------
-- Layout constants
----------------------------------------------------------------

local TITLE_PADDING = 6
local SCROLLBAR_WIDTH = 4
local SCROLL_STEP = 40
local FADE_IN = 0.15   -- seconds (scrollbar and background hover fade)
local FADE_OUT = 0.6
local QUEST_INDENT = 6
local OBJECTIVE_INDENT = 16

local function Color(key, r, g, b)
   local c = OBJECTIVE_TRACKER_COLOR and OBJECTIVE_TRACKER_COLOR[key]
   if c then return c.r, c.g, c.b end
   return r, g, b
end

----------------------------------------------------------------
-- Fonts: one Font object per role, updated from the profile.
----------------------------------------------------------------

local FONT_ROLES = { "title", "zone", "quest", "objective" }
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

   -- Title bar: drag handle, quest count, minimize button
   local title = CreateFrame("Button", nil, frame)
   title:SetPoint("TOPLEFT")
   title:SetPoint("TOPRIGHT")
   title:RegisterForDrag("LeftButton")
   title:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
   title:SetScript("OnDragStart", function()
      if mod.db.profile.locked or mod:IsItemLayoutLocked() then return end
      mod:HideItemButtons()
      frame:StartMoving()
      frame.isMoving = true
   end)
   title:SetScript("OnDragStop", function()
      if not frame.isMoving then return end
      frame.isMoving = nil
      frame:StopMovingOrSizing()
      mod:SavePosition()
      mod:RequestItemButtonLayout()
   end)
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
      if not mod.db.profile.locked then
         GameTooltip:AddLine(L["Drag to move"], 1, 1, 1)
      end
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
   minimize:SetSize(16, 16)
   minimize:SetPoint("RIGHT", -2, 0)
   minimize:SetHighlightAtlas("ui-questtrackerbutton-yellow-highlight", "ADD")
   minimize:SetScript("OnClick", function() mod:ToggleMinimized() end)
   title.minimize = minimize
   title.text:SetPoint("LEFT", 4, 0)
   title.text:SetPoint("RIGHT", minimize, "LEFT", -4, 0)

   title.line = title:CreateTexture(nil, "ARTWORK")
   title.line:SetAtlas("UI-QuestTracker-Secondary-Objective-Header")
   title.line:SetPoint("BOTTOMLEFT", 0, -4)
   title.line:SetPoint("BOTTOMRIGHT", 0, -4)
   title.line:SetHeight(16)
   title.line:SetAlpha(0.6)

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
      local hovered = self:IsMouseOver()
      local profile = mod.db.profile
      FadeToward(self.bg, hovered and profile.backgroundHoverAlpha or profile.backgroundAlpha, elapsed, hovered)
      if bar:IsShown() then
         FadeToward(bar, hovered and 1 or 0, elapsed, hovered)
      end
   end)

   self.lines = {}
   self.numLinesUsed = 0
end

----------------------------------------------------------------
-- Position / layout
----------------------------------------------------------------

-- Always store a top-based anchor so the tracker grows downward as content changes.
-- Offsets are in the frame's own (scaled) coordinate space.
function mod:SavePosition()
   local frame = self.frame
   local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
   local top = frame:GetTop() * scale - UIParent:GetTop()
   local left, right = frame:GetLeft() * scale, frame:GetRight() * scale
   if (left + right) / 2 < UIParent:GetWidth() / 2 then
      self.db.profile.point = { "TOPLEFT", "UIParent", "TOPLEFT", left / scale, top / scale }
   else
      self.db.profile.point = { "TOPRIGHT", "UIParent", "TOPRIGHT", (right - UIParent:GetRight()) / scale, top / scale }
   end
   frame:ClearAllPoints()
   local p = self.db.profile.point
   frame:SetPoint(p[1], UIParent, p[3], p[4], p[5])
end

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
   frame:ClearAllPoints()
   local p = profile.point
   frame:SetPoint(p[1], UIParent, p[3], p[4], p[5])
   local c = profile.backgroundColor
   frame.bg:SetColorTexture(c.r, c.g, c.b, 1)
   frame.bg:SetAlpha(frame:IsMouseOver() and profile.backgroundHoverAlpha or profile.backgroundAlpha)

   local titleHeight = profile.fonts.title.size + TITLE_PADDING
   frame.title:SetHeight(titleHeight)
   frame.title:EnableMouse(true)
   self:UpdateMinimizeButton()
   self:RequestUpdate()
end

function mod:UpdateMinimizeButton()
   local button = self.frame.title.minimize
   local minimized = self.db.char.minimized
   local suffix = minimized and "expand" or "collapse"
   button:SetNormalAtlas("ui-questtrackerbutton-secondary-" .. suffix)
   button:SetPushedAtlas("ui-questtrackerbutton-secondary-" .. suffix .. "-pressed")
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
      line.bg = line:CreateTexture(nil, "BACKGROUND")
      line.bg:SetAtlas("UI-QuestTracker-Secondary-Objective-Header")
      line.bg:SetPoint("TOPLEFT", -4, 4)
      line.bg:SetPoint("BOTTOMRIGHT", 0, -4)
      line.bg:SetAlpha(0.5)
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
   end
end

----------------------------------------------------------------
-- Rendering
----------------------------------------------------------------

local layout = {}  -- reused render state

local function AddLine(kind, data, text, role, indent, spacing, color, highlightColor, showHeaderBg)
   local line = AcquireLine()
   line.kind = kind
   line.data = data
   line.color = color
   line.highlightColor = highlightColor
   line:EnableMouse(highlightColor ~= nil)

   local width = layout.width - indent - (layout.rightInset or 0)
   line.text:SetFontObject(fontObjects[role])
   line.text:ClearAllPoints()
   line.text:SetPoint("TOPLEFT", indent, 0)
   line.text:SetWidth(width)
   line.text:SetText(text)
   line.text:SetTextColor(unpack(color))
   line.bg:SetShown(showHeaderBg or false)

   local height = math.ceil(line.text:GetStringHeight())
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

local function DifficultyColor(level)
   local c = GetQuestDifficultyColor and GetQuestDifficultyColor(level)
   if c then return { c.r, c.g, c.b } end
   return { Color("Header", 0.75, 0.61, 0) }
end

local function FormatQuestTitle(quest, profile)
   local title = quest.title
   if profile.showLevel then
      local tag = ""
      if quest.isElite or (quest.suggestedGroup and quest.suggestedGroup > 0) then
         tag = "+"
      end
      if Enum.QuestFrequency then
         if quest.frequency == Enum.QuestFrequency.Daily then
            tag = tag .. "D"
         elseif quest.frequency == Enum.QuestFrequency.Weekly then
            tag = tag .. "W"
         end
      end
      title = format("[%d%s] %s", quest.level, tag, title)
   end
   if profile.showQuestTags and quest.tagName and quest.tagName ~= "" then
      title = format("%s |cffff8040(%s)|r", title, quest.tagName)
   end
   return title
end

local function Brighten(color)
   return { math.min(1, color[1] + 0.2), math.min(1, color[2] + 0.2), math.min(1, color[3] + 0.2) }
end

function mod:RenderQuest(quest, profile)
   local normal = { Color("Normal", 0.8, 0.8, 0.8) }
   local complete = { Color("Complete", 0.6, 0.6, 0.6) }

   local titleColor = profile.colorByDifficulty and DifficultyColor(quest.difficultyLevel)
      or { Color("Header", 0.75, 0.61, 0) }
   local itemSize = (profile.showItemButtons and quest.hasItem) and self.ITEM_BUTTON_SIZE or 0
   layout.rightInset = itemSize

   local titleLine = AddLine("quest", quest, FormatQuestTitle(quest, profile), "quest", QUEST_INDENT, profile.questSpacing,
      titleColor, Brighten(titleColor))
   local questTop = layout.y - titleLine:GetHeight()
   if itemSize > 0 then
      tinsert(self.itemEntries, { line = titleLine, quest = quest })
   end

   if quest.isFailed then
      AddLine("objective", quest, FAILED or L["Failed"], "objective", OBJECTIVE_INDENT, profile.objectiveSpacing,
         { Color("Failed", 1, 0.1, 0.1) })
   elseif quest.isComplete then
      local text = quest.completionText
      if not text or text == "" then
         text = QUEST_WATCH_QUEST_READY or L["Ready for turn-in"]
      end
      AddLine("objective", quest, text, "objective", OBJECTIVE_INDENT, profile.objectiveSpacing, normal)
   else
      for _, objective in ipairs(quest.objectives) do
         if not objective.finished then
            AddLine("objective", quest, "- " .. objective.text, "objective", OBJECTIVE_INDENT, profile.objectiveSpacing, normal)
         elseif profile.showCompletedObjectives then
            AddLine("objective", quest, "- " .. objective.text, "objective", OBJECTIVE_INDENT, profile.objectiveSpacing, complete)
         end
      end
   end
   -- Make room for the whole item button before the next quest.
   if itemSize > 0 and layout.y - questTop < itemSize then
      layout.y = questTop + itemSize
   end
   layout.rightInset = 0
end

function mod:RenderRecipes(recipes, profile)
   if not recipes or #recipes == 0 then return end
   local collapsed = self.db.char.collapsedRecipes
   local zoneColor = { NORMAL_FONT_COLOR:GetRGB() }
   local header = format("%s %s (%d)", collapsed and "+" or "-",
      PROFESSIONS_TRACKER_HEADER_PROFESSION or L["Professions"], #recipes)
   AddLine("recipeSection", nil, header, "zone", 0, profile.zoneSpacing, zoneColor, { 1, 1, 1 }, true)
   if collapsed then return end
   layout.nextSpacing = profile.zoneHeaderSpacing

   local titleColor = { Color("Header", 0.75, 0.61, 0) }
   local normal = { Color("Normal", 0.8, 0.8, 0.8) }
   local complete = { Color("Complete", 0.6, 0.6, 0.6) }
   for _, recipe in ipairs(recipes) do
      AddLine("recipe", recipe, recipe.name, "quest", QUEST_INDENT, profile.questSpacing, titleColor, Brighten(titleColor))
      for _, reagent in ipairs(recipe.reagents) do
         AddLine("objective", recipe, "- " .. reagent.text, "objective", OBJECTIVE_INDENT, profile.objectiveSpacing,
            reagent.finished and complete or normal)
      end
   end
end

function mod:Render(sections, numQuests, numShown, recipes)
   local frame = self.frame
   local profile = self.db.profile

   if self:IsItemLayoutLocked() then
      -- Secure item buttons can't move during combat; re-render afterwards.
      self.layoutDeferred = true
      return
   end
   self.itemEntries = {}

   local titleText = format("%s (%d/%d)", TRACKER_HEADER_QUESTS or L["Quests"], numQuests,
      C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept() or numQuests)
   if numShown ~= numQuests then
      titleText = format("%d %s - %s", numShown, L["shown"], titleText)
   end
   frame.title.text:SetText(titleText)

   local hasContent = numQuests > 0 or (recipes and #recipes > 0)
   if not hasContent and profile.locked then
      frame:Hide()
      self:RequestItemButtonLayout()
      return
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
      return
   end
   frame.scroll:Show()

   local collapsedZones = self.db.char.collapsedZones
   local zoneColor = { NORMAL_FONT_COLOR:GetRGB() }
   local currentZoneColor = { 1, 1, 1 }
   for _, section in ipairs(sections) do
      local collapsed = collapsedZones[section.name]
      local text = format("%s %s (%d)", collapsed and "+" or "-", section.name, #section.quests)
      local color = section.isCurrent and currentZoneColor or zoneColor
      AddLine("zone", section, text, "zone", 0, profile.zoneSpacing, color, Brighten(color), true)
      if not collapsed then
         layout.nextSpacing = profile.zoneHeaderSpacing
         for _, quest in ipairs(section.quests) do
            self:RenderQuest(quest, profile)
         end
      end
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

local function ToggleQuestWatch(questID)
   if C_QuestLog.GetQuestWatchType(questID) ~= nil then
      C_QuestLog.RemoveQuestWatch(questID)
   else
      C_QuestLog.AddQuestWatch(questID)
   end
end

local function ShowQuestMenu(owner, questID)
   MenuUtil.CreateContextMenu(owner, function(_, root)
      root:CreateTitle(C_QuestLog.GetTitleForQuestID(questID) or "")

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
   MenuUtil.CreateContextMenu(owner, function(_, root)
      root:CreateTitle(recipe.name)
      if not recipe.isRecraft then
         root:CreateButton(PROFESSIONS_TRACKING_VIEW_RECIPE or L["View recipe"], function()
            OpenRecipe(recipe.recipeID, recipe.isRecraft)
         end)
      end
      root:CreateButton(PROFESSIONS_UNTRACK_RECIPE or L["Untrack recipe"], function()
         C_TradeSkillUI.SetRecipeTracked(recipe.recipeID, false, recipe.isRecraft)
      end)
   end)
end

mod.lineClickHandlers = {
   zone = function(self, _, section)
      local collapsed = self.db.char.collapsedZones
      collapsed[section.name] = not collapsed[section.name] or nil
      self:RequestUpdate()
   end,

   recipeSection = function(self)
      self.db.char.collapsedRecipes = not self.db.char.collapsedRecipes
      self:RequestUpdate()
   end,

   quest = function(self, line, quest, button)
      local questID = quest.questID
      if ChatFrameUtil and ChatFrameUtil.TryInsertQuestLinkForQuestID
         and ChatFrameUtil.TryInsertQuestLinkForQuestID(questID) then
         return
      end
      if button == "RightButton" then
         ShowQuestMenu(line, questID)
      elseif IsModifiedClick("QUESTWATCHTOGGLE") then
         ToggleQuestWatch(questID)
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
