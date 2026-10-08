--[[
**********************************************************************
MagicQuestTracker - Configuration options.
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
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local AceConfig = LibStub("AceConfig-3.0")

local APP_NAME = "Magic Quest Tracker"

local options

local function Get(info)
   return mod.db.profile[info[#info]]
end

-- Option setters: refresh data (filters/sorting) or just layout.
local function SetAndUpdate(info, val)
   mod.db.profile[info[#info]] = val
   mod:RequestUpdate()
end

local function SetAndLayout(info, val)
   mod.db.profile[info[#info]] = val
   mod:ApplyLayout()
end

local SORT_VALUES = {
   level = L["Level"],
   name = L["Name"],
   distance = L["Distance"],
}

local function SetAndUpdateDistance(info, val)
   mod.db.profile[info[#info]] = val
   mod:UpdateDistanceTimer()
   mod:RequestUpdate()
end

local OUTLINE_VALUES = {
   [""] = L["None"],
   OUTLINE = L["Outline"],
   THICKOUTLINE = L["Thick outline"],
}

local function FontGroup(role, name, order)
   return {
      type = "group",
      name = name,
      inline = true,
      order = order,
      get = function(info) return mod.db.profile.fonts[role][info[#info]] end,
      set = function(info, val)
         mod.db.profile.fonts[role][info[#info]] = val
         mod:ApplyLayout()
      end,
      args = {
         face = {
            type = "select",
            dialogControl = "LSM30_Font",
            name = L["Font"],
            values = AceGUIWidgetLSMlists.font,
            order = 1,
         },
         size = {
            type = "range",
            name = L["Font size"],
            min = 6, max = 30, step = 1,
            order = 2,
         },
         outline = {
            type = "select",
            name = L["Outline"],
            values = OUTLINE_VALUES,
            order = 3,
         },
      },
   }
end

local function BuildOptions()
   options = {
      general = {
         type = "group",
         name = APP_NAME,
         get = Get,
         set = SetAndUpdate,
         args = {
            desc = {
               type = "description",
               name = L["A quest tracker that groups quests by zone, sorts them by level and shows tracked recipes in a separate section."],
               order = 0,
               fontSize = "medium",
            },
            displayHeader = { type = "header", name = L["Quests"], order = 10 },
            showAllQuests = {
               type = "toggle",
               name = L["Show all quests"],
               desc = L["Show every quest in the quest log. When disabled, only quests on the built-in watch list are shown."],
               width = "full",
               order = 11,
            },
            currentZoneFirst = {
               type = "toggle",
               name = L["Show current zone first"],
               desc = L["Place the zone you are currently in at the top. Remaining zones are sorted using the zone sort order."],
               width = "full",
               order = 12,
            },
            onlyCurrentZone = {
               type = "toggle",
               name = L["Only show quests in current zone"],
               desc = L["Hide quests that are not in your current zone or on the current map."],
               width = "full",
               order = 13,
            },
            zoneSort = {
               type = "select",
               name = L["Zone sort order"],
               desc = L["How zones are ordered. Level sorts zones by their lowest level quest, distance by their nearest quest."],
               values = SORT_VALUES,
               order = 14,
               set = SetAndUpdateDistance,
            },
            questSort = {
               type = "select",
               name = L["Quest sort order"],
               desc = L["How quests are ordered within each zone. Distance sorts by straight-line distance to the quest's next location on the map; quests without one are listed last."],
               values = SORT_VALUES,
               order = 15,
               set = SetAndUpdateDistance,
            },
            showDistance = {
               type = "toggle",
               name = L["Show distance"],
               desc = L["Show the straight-line distance to each quest's next location on the map."],
               width = "full",
               order = 15.5,
               set = SetAndUpdateDistance,
            },
            showDirection = {
               type = "toggle",
               name = L["Show direction"],
               desc = L["Show an arrow pointing toward each quest's next location on the map. Not available in instances."],
               width = "full",
               order = 15.6,
               set = SetAndUpdateDistance,
            },
            arrowSize = {
               type = "range",
               name = L["Arrow size"],
               min = 8, max = 32, step = 1,
               order = 15.7,
               disabled = function() return not mod.db.profile.showDirection end,
            },
            showLevel = {
               type = "toggle",
               name = L["Show quest level"],
               desc = L["Prefix quest titles with their level. + marks elite and group quests, D dungeon, R raid and H heroic quests."],
               width = "full",
               order = 16,
            },
            markForeverQuests = {
               type = "toggle",
               name = L["Mark new Forever quests"],
               desc = L["Show an infinity sign after quests that were not in original Classic."],
               width = "full",
               order = 16.6,
               hidden = function() return not mod.IS_FOREVER end,
            },
            showQuestTags = {
               type = "toggle",
               name = L["Show quest type"],
               desc = L["Append the quest type, such as Elite, Dungeon, Raid or Daily, to quest titles."],
               width = "full",
               order = 16.5,
            },
            colorByDifficulty = {
               type = "toggle",
               name = L["Color by difficulty"],
               desc = L["Color quest titles by their difficulty relative to your level."],
               width = "full",
               order = 17,
            },
            showCompletedObjectives = {
               type = "toggle",
               name = L["Show completed objectives"],
               desc = L["Show finished objectives of incomplete quests, dimmed."],
               width = "full",
               order = 18,
            },
            showRecipes = {
               type = "toggle",
               name = L["Show tracked recipes"],
               desc = L["Show recipes tracked from the professions window in a separate section."],
               width = "full",
               order = 19,
            },
            showItemButtons = {
               type = "toggle",
               name = L["Show quest item buttons"],
               desc = L["Show a button to use the quest item next to quests that have one. While a button is shown, the tracker does not update or scroll during combat."],
               width = "full",
               order = 20,
            },
            hideBlizzardTracker = {
               type = "toggle",
               name = L["Hide Blizzard tracker"],
               desc = L["Hide the built-in objective tracker. Note that this hides all of its sections, including scenarios and bonus objectives."],
               width = "full",
               order = 21,
               set = function(_, val)
                  mod.db.profile.hideBlizzardTracker = val
                  mod:SetBlizzardTrackerHidden(val)
               end,
            },
            cmdHeader = { type = "header", name = L["Commands"], order = 90 },
            cmdDesc = {
               type = "description",
               name = L["/mqt toggle  - show/hide the tracker"] .. "\n"
                  .. L["/mqt lock  - lock/unlock the tracker position"] .. "\n"
                  .. L["/mqt reset  - reset the tracker position"] .. "\n"
                  .. L["/mqt config  - open settings"],
               order = 91,
               fontSize = "medium",
            },
         },
      },
      layout = {
         type = "group",
         name = L["Layout"],
         get = Get,
         set = SetAndLayout,
         args = {
            locked = {
               type = "toggle",
               name = L["Lock tracker"],
               desc = L["Prevent the tracker from being moved. An unlocked tracker stays visible even when empty."],
               width = "full",
               order = 1,
            },
            width = {
               type = "range",
               name = L["Width"],
               min = 150, max = 600, step = 1, bigStep = 10,
               order = 2,
            },
            maxHeight = {
               type = "range",
               name = L["Maximum height"],
               desc = L["The tracker grows with its contents up to this height, then becomes scrollable."],
               min = 100, max = 1200, step = 1, bigStep = 10,
               order = 3,
            },
            scale = {
               type = "range",
               name = L["Scale"],
               min = 0.5, max = 2.0, step = 0.01, bigStep = 0.05, isPercent = true,
               order = 4,
            },
            backgroundHeader = { type = "header", name = L["Background"], order = 10 },
            backgroundColor = {
               type = "color",
               name = L["Background color"],
               order = 11,
               get = function()
                  local c = mod.db.profile.backgroundColor
                  return c.r, c.g, c.b
               end,
               set = function(_, r, g, b)
                  local c = mod.db.profile.backgroundColor
                  c.r, c.g, c.b = r, g, b
                  mod:ApplyLayout()
               end,
            },
            backgroundAlpha = {
               type = "range",
               name = L["Background opacity"],
               desc = L["Background opacity when the mouse is not over the tracker."],
               min = 0, max = 1, step = 0.01, bigStep = 0.05, isPercent = true,
               order = 12,
            },
            backgroundHoverAlpha = {
               type = "range",
               name = L["Mouseover opacity"],
               desc = L["Background opacity when the mouse is over the tracker."],
               min = 0, max = 1, step = 0.01, bigStep = 0.05, isPercent = true,
               order = 13,
            },
            spacingHeader = { type = "header", name = L["Spacing"], order = 20 },
            zoneSpacing = {
               type = "range",
               name = L["Zone spacing"],
               desc = L["Space above each zone header."],
               min = 0, max = 40, step = 1,
               order = 21,
            },
            zoneHeaderSpacing = {
               type = "range",
               name = L["Zone header spacing"],
               desc = L["Space between a zone header and its first quest."],
               min = 0, max = 30, step = 1,
               order = 22,
            },
            questSpacing = {
               type = "range",
               name = L["Quest spacing"],
               desc = L["Space above each quest title."],
               min = 0, max = 30, step = 1,
               order = 23,
            },
            objectiveSpacing = {
               type = "range",
               name = L["Objective spacing"],
               desc = L["Space between objective lines."],
               min = 0, max = 20, step = 1,
               order = 24,
            },
         },
      },
      fonts = {
         type = "group",
         name = L["Fonts"],
         args = {
            title = FontGroup("title", L["Tracker title"], 1),
            zone = FontGroup("zone", L["Zone headers"], 2),
            quest = FontGroup("quest", L["Quest titles"], 3),
            objective = FontGroup("objective", L["Objectives"], 4),
         },
      },
   }
   options.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(mod.db)
end

function mod:OptReg(optname, tbl, dispname)
   if dispname then
      optname = APP_NAME .. optname
      AceConfig:RegisterOptionsTable(optname, tbl)
      return AceConfigDialog:AddToBlizOptions(optname, dispname, APP_NAME)
   else
      AceConfig:RegisterOptionsTable(optname, tbl)
      return AceConfigDialog:AddToBlizOptions(optname, APP_NAME)
   end
end

function mod:SetupOptions()
   BuildOptions()
   self.optionsMain = self:OptReg(APP_NAME, options.general)
   self:OptReg(": Layout", options.layout, L["Layout"])
   self:OptReg(": Fonts", options.fonts, L["Fonts"])
   self.optionsEnd = self:OptReg(": Profiles", options.profiles, L["Profiles"])
end

function mod:NotifyOptionsChanged()
   AceConfigRegistry:NotifyChange(APP_NAME)
   AceConfigRegistry:NotifyChange(APP_NAME .. ": Layout")
end
