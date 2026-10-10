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
      get = function(info) return mod:GetDisplayTheme().fonts[role][info[#info]] end,
      set = function(info, val)
         mod:GetDisplayTheme().fonts[role][info[#info]] = val
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

local function IsNotCustom()
   return not mod:GetCustomTheme()
end

-- Color with opacity in the selected custom theme.
local function ColorOption(name, order)
   return {
      type = "color",
      name = name,
      hasAlpha = true,
      order = order,
      get = function(info)
         local c = mod:GetDisplayTheme()[info[#info - 1]][info[#info]]
         return c.r, c.g, c.b, c.a
      end,
      set = function(info, r, g, b, a)
         local c = mod:GetDisplayTheme()[info[#info - 1]][info[#info]]
         c.r, c.g, c.b, c.a = r, g, b, a
         mod:ApplyLayout()
      end,
   }
end

-- Bar texture, color and border for one header kind of the selected custom theme.
local function CustomGroup(kind, name, order, desc)
   return {
      type = "group",
      name = name,
      inline = true,
      order = order,
      get = function(info) return mod:GetDisplayTheme()[kind][info[#info]] end,
      set = function(info, val)
         mod:GetDisplayTheme()[kind][info[#info]] = val
         mod:ApplyLayout()
      end,
      args = {
         desc = desc and { type = "description", name = desc, order = 0 } or nil,
         borderedButton = kind == "title" and {
            type = "toggle",
            name = L["Bordered minimize button"],
            order = 6,
         } or nil,
         texture = {
            type = "select",
            dialogControl = "LSM30_Statusbar",
            name = L["Bar texture"],
            values = function() return mod:GetBarTextureList() end,
            order = 1,
         },
         color = ColorOption(L["Bar color"], 2),
         border = {
            type = "select",
            dialogControl = "LSM30_Border",
            name = L["Border"],
            values = AceGUIWidgetLSMlists.border,
            order = 3,
         },
         borderSize = {
            type = "range",
            name = L["Border size"],
            min = 1, max = 32, step = 1,
            order = 4,
         },
         borderColor = ColorOption(L["Border color"], 5),
      },
   }
end

-- Tracker background tab of the selected custom theme.
local function BackgroundGroup(order)
   local function Settings() return mod:GetDisplayTheme().background end
   local function RGBOption(name, order, desc)
      return {
         type = "color",
         name = name,
         desc = desc,
         order = order,
         get = function(info)
            local c = Settings()[info[#info]]
            return c.r, c.g, c.b
         end,
         set = function(info, r, g, b)
            local c = Settings()[info[#info]]
            c.r, c.g, c.b = r, g, b
            mod:ApplyLayout()
         end,
      }
   end
   return {
      type = "group",
      name = L["Background"],
      order = order,
      get = function(info) return Settings()[info[#info]] end,
      set = function(info, val)
         Settings()[info[#info]] = val
         mod:ApplyLayout()
      end,
      args = {
         texture = {
            type = "select",
            dialogControl = "LSM30_Background",
            name = L["Background texture"],
            values = AceGUIWidgetLSMlists.background,
            order = 1,
         },
         color = RGBOption(L["Background color"], 2),
         alpha = {
            type = "range",
            name = L["Background opacity"],
            desc = L["Background opacity when the mouse is not over the tracker."],
            min = 0, max = 1, step = 0.01, bigStep = 0.05, isPercent = true,
            order = 3,
         },
         hoverAlpha = {
            type = "range",
            name = L["Mouseover opacity"],
            desc = L["Background opacity when the mouse is over the tracker."],
            min = 0, max = 1, step = 0.01, bigStep = 0.05, isPercent = true,
            order = 4,
         },
         border = {
            type = "select",
            dialogControl = "LSM30_Border",
            name = L["Border"],
            values = AceGUIWidgetLSMlists.border,
            order = 5,
         },
         borderSize = {
            type = "range",
            name = L["Border size"],
            min = 1, max = 32, step = 1,
            order = 6,
         },
         borderColor = RGBOption(L["Border color"], 7, L["The border fades in and out with the background opacity."]),
      },
   }
end

-- Text color of the selected custom theme (theme.colors[key]).
local function TextColor(name, order, desc)
   return {
      type = "color",
      name = name,
      desc = desc,
      order = order,
      get = function(info)
         local c = mod:GetDisplayTheme().colors[info[#info]]
         return c.r, c.g, c.b
      end,
      set = function(info, r, g, b)
         local c = mod:GetDisplayTheme().colors[info[#info]]
         c.r, c.g, c.b = r, g, b
         mod:ApplyLayout()
      end,
   }
end

local function ColorGroup(name, order, args)
   return { type = "group", name = name, inline = true, order = order, args = args }
end

local METERS_PER_YARD = 0.9144

local function UsesMeters()
   local units = mod.db.profile.distanceUnits
   return units == "meters" or units == "metric"
end

local function DisableForBuiltIn(group)
   for _, option in pairs(group.args) do
      if option.type == "group" then
         DisableForBuiltIn(option)
      elseif option.type ~= "description" and option.type ~= "header" then
         option.disabled = IsNotCustom
      end
   end
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
            titleHeader = { type = "header", name = L["Quest titles"], order = 20 },
            distanceHeader = { type = "header", name = L["Distance and navigation"], order = 30 },
            sectionHeader = { type = "header", name = L["Sections"], order = 40 },
            buttonHeader = { type = "header", name = L["Buttons"], order = 50 },
            otherHeader = { type = "header", name = L["Other"], order = 60 },
            showAllQuests = {
               type = "toggle",
               name = L["Show all quests"],
               desc = L["Show every quest in the quest log. When disabled, only quests on the built-in watch list are shown."],
               order = 11,
               width = COLUMN_WIDTH,
            },
            currentZoneFirst = {
               type = "toggle",
               name = L["Show current zone first"],
               desc = L["Place the zone you are currently in at the top. Remaining zones are sorted using the zone sort order."],
               order = 13,
               width = COLUMN_WIDTH,
            },
            onlyCurrentZone = {
               type = "toggle",
               name = L["Only show quests in current zone"],
               desc = L["Hide quests that are not in your current zone or on the current map."],
               order = 12,
               width = COLUMN_WIDTH,
            },
            autoFoldZones = {
               type = "toggle",
               name = L["Auto-fold other zones"],
               desc = L["When showing all quests, fold every zone except the current one whenever you enter a new zone. Zones you unfold stay open until the next zone change."],
               order = 14,
               width = COLUMN_WIDTH,
               disabled = function() return mod.db.profile.onlyCurrentZone end,
               set = function(_, val)
                  mod.db.profile.autoFoldZones = val
                  mod.db.char.autoFoldZone = nil  -- apply right away
                  mod:RequestUpdate()
               end,
            },
            focusedSection = {
               type = "select",
               name = L["Section on top"],
               desc = L["Show a section above the zones: Focused holds the focused quest, Tracked also holds the quests on the built-in watch list. Those quests move out of their zones, and the focused quest is shown even when other settings would hide it. When only watched quests are shown, Tracked holds just the focused quest."],
               values = {
                  none = L["None"],
                  focused = L["Focused"],
                  tracked = L["Tracked"],
               },
               sorting = { "none", "focused", "tracked" },
               order = 17,
               width = COLUMN_WIDTH,
            },
            zoneSort = {
               type = "select",
               name = L["Zone sort order"],
               desc = L["How zones are ordered. Level sorts zones by their lowest level quest, distance by their nearest quest."],
               values = SORT_VALUES,
               order = 15,
               width = COLUMN_WIDTH,
               set = SetAndUpdateDistance,
            },
            questSort = {
               type = "select",
               name = L["Quest sort order"],
               desc = L["How quests are ordered within each zone. Distance sorts by straight-line distance to the quest's next location on the map; quests without one are listed last."],
               values = SORT_VALUES,
               order = 16,
               width = COLUMN_WIDTH,
               set = SetAndUpdateDistance,
            },
            showDistance = {
               type = "toggle",
               name = L["Show distance"],
               desc = L["Show the straight-line distance to each quest's next location on the map."],
               order = 31,
               width = COLUMN_WIDTH,
               set = SetAndUpdateDistance,
            },
            distanceUnits = {
               type = "select",
               name = L["Distance units"],
               desc = L["Show distances in yards or meters, optionally switching to miles or kilometers for long distances."],
               values = {
                  yards = L["Yards"],
                  meters = L["Meters"],
                  imperial = L["Yards / miles"],
                  metric = L["Meters / kilometers"],
               },
               sorting = { "yards", "imperial", "meters", "metric" },
               order = 31.5,
               width = COLUMN_WIDTH,
               disabled = function()
                  local profile = mod.db.profile
                  return not (profile.showDistance or profile.showDirection)
               end,
            },
            showDirection = {
               type = "toggle",
               name = L["Show direction"],
               desc = L["Show an arrow pointing toward each quest's next location on the map. Not available in instances."],
               order = 32,
               width = COLUMN_WIDTH,
               set = SetAndUpdateDistance,
            },
            arrowSize = {
               type = "range",
               name = L["Arrow size"],
               min = 8, max = 32, step = 1,
               order = 33,
               width = COLUMN_WIDTH,
               disabled = function() return not mod.db.profile.showDirection end,
            },
            arrowMaxDistance = {
               type = "range",
               -- Saved in yards, shown in the selected distance units.
               name = function()
                  return format(L["Arrow max distance (%s)"], UsesMeters() and L["m"] or L["yd"])
               end,
               desc = L["Only show arrows for quests in other zones within this distance. Quests in the current zone always get an arrow. 0 shows arrows at any distance."],
               min = 0, max = 5000, step = 50, bigStep = 250,
               order = 34,
               width = COLUMN_WIDTH,
               disabled = function() return not mod.db.profile.showDirection end,
               get = function()
                  local yards = mod.db.profile.arrowMaxDistance
                  return UsesMeters() and math.floor(yards * METERS_PER_YARD / 50 + 0.5) * 50 or yards
               end,
               set = function(_, val)
                  mod.db.profile.arrowMaxDistance = UsesMeters() and val / METERS_PER_YARD or val
                  mod:RequestUpdate()
               end,
            },
            showLevel = {
               type = "toggle",
               name = L["Show quest level"],
               desc = L["Prefix quest titles with their level. + marks elite and group quests, D dungeon, R raid and H heroic quests."],
               order = 21,
               width = COLUMN_WIDTH,
            },
            waypointMode = {
               type = "select",
               name = L["Ctrl-click navigation"],
               desc = L["What ctrl-clicking a quest does: set a TomTom waypoint, focus the quest for Blizzard's navigation, or both."],
               values = {
                  tomtom = L["TomTom"],
                  blizzard = L["Blizzard"],
                  both = L["Both"],
               },
               order = 35,
               -- Without TomTom, ctrl-click always uses Blizzard's navigation.
               hidden = function() return not mod:HasTomTom() end,
               disabled = function() return not mod.db.profile.blizzardFocus end,
               width = COLUMN_WIDTH,
            },
            blizzardFocus = {
               type = "toggle",
               name = L["Use Blizzard quest focus"],
               desc = L["Let the tracker focus (super track) quests for Blizzard's navigation, and show the quest POI buttons. Focusing quests from an addon can cause harmless errors about blocked or tainted actions in Blizzard's UI; turn this off to avoid them."],
               order = 36,
               width = COLUMN_WIDTH,
            },
            markForeverQuests = {
               type = "toggle",
               name = L["Mark new Forever quests"],
               desc = L["Show an infinity sign after quests that were not in original Classic."],
               order = 25,
               width = COLUMN_WIDTH,
               hidden = function() return not mod.IS_FOREVER end,
            },
            markWatchedQuests = {
               type = "toggle",
               name = L["Mark tracked quests"],
               desc = L["Show a check mark after quests on the built-in watch list. Not shown in the section on top, or when only watched quests are shown."],
               order = 26,
               width = COLUMN_WIDTH,
               disabled = function() return not mod.db.profile.showAllQuests end,
            },
            showQuestTags = {
               type = "toggle",
               name = L["Show quest type"],
               desc = L["Append the quest type, such as Elite, Dungeon, Raid or Daily, to quest titles."],
               order = 22,
               width = COLUMN_WIDTH,
            },
            colorByDifficulty = {
               type = "toggle",
               name = L["Color by difficulty"],
               desc = L["Color quest titles by their difficulty relative to your level."],
               order = 23,
               width = COLUMN_WIDTH,
            },
            showCompletedObjectives = {
               type = "toggle",
               name = L["Show completed objectives"],
               desc = L["Show finished objectives of incomplete quests, dimmed."],
               order = 24,
               width = COLUMN_WIDTH,
            },
            showRecipes = {
               type = "toggle",
               name = L["Show tracked recipes"],
               desc = L["Show recipes tracked from the professions window in a separate section."],
               order = 41,
               width = COLUMN_WIDTH,
            },
            showWorldQuests = {
               type = "toggle",
               name = L["Show world quests"],
               desc = L["Show world quests in the current area and tracked world quests in a separate section."],
               order = 42,
               width = COLUMN_WIDTH,
               hidden = function() return mod.IS_FOREVER or not GetTasksTable end,
            },
            showBonusObjectives = {
               type = "toggle",
               name = L["Show bonus objectives"],
               desc = L["Show bonus objectives in the current area in a separate section."],
               order = 43,
               width = COLUMN_WIDTH,
               hidden = function() return not GetTasksTable end,
            },
            showItemButtons = {
               type = "toggle",
               name = L["Show quest item buttons"],
               desc = L["Show a button to use the quest item next to quests that have one. While a button is shown, the tracker does not update or scroll during combat."],
               order = 51,
               width = COLUMN_WIDTH,
            },
            showPOIButtons = {
               type = "toggle",
               name = L["Show quest POI buttons"],
               desc = L["Show the quest map icon next to each quest, like the built-in tracker. Click it to focus the quest. Follows the game's quest POI setting."],
               order = 52,
               width = COLUMN_WIDTH,
               disabled = function() return not mod.db.profile.blizzardFocus end,
            },
            showFindGroupButton = {
               type = "toggle",
               name = L["Show find group buttons"],
               desc = L["Show the group finder button on quests that support it, like the built-in tracker."],
               order = 53,
               width = COLUMN_WIDTH,
            },
            hideBlizzardTracker = {
               type = "toggle",
               name = L["Hide Blizzard tracker"],
               desc = L["Hide the built-in objective tracker. Note that this hides all of its sections, including scenarios and bonus objectives."],
               order = 61,
               width = COLUMN_WIDTH,
               set = function(_, val)
                  mod.db.profile.hideBlizzardTracker = val
                  mod:SetBlizzardTrackerHidden(val)
               end,
            },
            hideInCombat = {
               type = "select",
               name = L["Hide in combat"],
               desc = L["Hide the tracker while in combat: never, only inside instances (dungeons, raids, battlegrounds, ...), or always."],
               values = {
                  never = L["Never"],
                  instances = L["In instances"],
                  always = L["Always"],
               },
               order = 62,
               width = COLUMN_WIDTH,
               set = function(_, val)
                  mod.db.profile.hideInCombat = val
                  mod:UpdateCombatVisibility()
               end,
            },
            hideInInstances = {
               type = "select",
               name = L["Hide in instances"],
               desc = L["Hide the tracker inside instances (dungeons, raids, battlegrounds, ...): never, when none of your quests are for the instance, or always."],
               values = {
                  never = L["Never"],
                  noQuests = L["Without quests there"],
                  always = L["Always"],
               },
               order = 63,
               width = COLUMN_WIDTH,
            },
            cmdHeader = { type = "header", name = L["Commands"], order = 90 },
            cmdDesc = {
               type = "description",
               name = L["/mqt toggle  - show/hide the tracker"] .. "\n"
                  .. L["/mqt config  - open settings"],
               order = 91,
               fontSize = "medium",
            },
         },
      },
      -- Size and position are set in Edit Mode, per layout; shown here read-only.
      layout = {
         type = "group",
         name = L["Layout"],
         args = {
            current = {
               type = "description",
               name = function()
                  local size = mod:GetLayoutSettings()
                  return format(L["LAYOUT_SUMMARY"], mod:GetEditModeLayoutName() or UNKNOWN or "?",
                     size.width, size.scale * 100 + 0.5, size.maxHeight)
               end,
               fontSize = "medium",
               width = "full",
               order = 3,
            },
         },
      },
      theme = {
         type = "group",
         name = L["Theme"],
         childGroups = "tab",
         args = {
            desc = {
               type = "description",
               name = L["Themes are shared by all profiles. Built-in themes can't be changed; use Edit theme to make an editable copy."],
               order = 0,
            },
            theme = {
               type = "select",
               name = L["Theme"],
               values = function() return mod:GetThemeList() end,
               order = 1,
               get = function()
                  return mod:GetThemeSettings() and mod.db.profile.theme or "blizzard"
               end,
               set = function(_, val) mod:SelectTheme(val) end,
            },
            copyTheme = {
               type = "execute",
               name = function() return IsNotCustom() and L["Edit theme"] or L["Copy theme"] end,
               desc = function()
                  return IsNotCustom() and L["Built-in themes can't be changed. Make an editable copy under a new name."]
                     or L["Make a copy of the selected theme under a new name."]
               end,
               order = 2,
               func = function() mod:ShowNewThemePopup() end,
            },
            renameTheme = {
               type = "input",
               name = L["Rename theme"],
               desc = L["Enter a new name for the selected theme. Profiles using it keep using it."],
               order = 2.5,
               hidden = IsNotCustom,
               get = function() return mod.db.profile.theme end,
               validate = function(_, val)
                  if strtrim(val or "") == mod.db.profile.theme then return true end
                  return mod:ValidateThemeName(val) or true
               end,
               set = function(_, val)
                  if strtrim(val) ~= mod.db.profile.theme then mod:RenameTheme(val) end
               end,
            },
            resetTheme = {
               type = "execute",
               name = L["Reset to Blizzard"],
               desc = L["Change the selected theme to look like the Blizzard theme."],
               confirm = true,
               confirmText = L["Reset the selected theme to look like the Blizzard theme?"],
               order = 3,
               hidden = IsNotCustom,
               func = function() mod:ResetThemeToBlizzard() end,
            },
            deleteTheme = {
               type = "execute",
               name = L["Delete theme"],
               confirm = true,
               confirmText = L["Delete the selected theme? Profiles using it switch to the Blizzard theme."],
               order = 4,
               hidden = IsNotCustom,
               func = function() mod:DeleteTheme() end,
            },
            importTheme = {
               type = "execute",
               name = L["Import theme"],
               desc = L["Paste a theme export string. The theme is added under its own name and selected."],
               order = 5,
               hidden = function() return not mod:CanImportExportThemes() end,
               func = function() mod:ShowThemeImport() end,
            },
            exportTheme = {
               type = "execute",
               name = L["Export theme"],
               desc = L["Show the selected theme as a string to copy and share."],
               order = 6,
               hidden = function() return IsNotCustom() or not mod:CanImportExportThemes() end,
               func = function() mod:ShowThemeExport() end,
            },
            headers = {
               type = "group",
               name = L["Headers"],
               order = 10,
               args = {
                  title = CustomGroup("title", L["Tracker title"], 1),
                  section = CustomGroup("section", L["Section headers"], 2),
                  zone = CustomGroup("zone", L["Zone headers"], 3,
                     L["With zero opacity and no border, zone headers are shown as plain text."]),
               },
            },
            background = BackgroundGroup(11),
            fonts = {
               type = "group",
               name = L["Fonts"],
               order = 13,
               args = {
                  title = FontGroup("title", L["Tracker title"], 1),
                  module = FontGroup("module", L["Section headers"], 1.5),
                  zone = FontGroup("zone", L["Zone headers"], 2),
                  quest = FontGroup("quest", L["Quest titles"], 3),
                  objective = FontGroup("objective", L["Objectives"], 4),
               },
            },
            colors = {
               type = "group",
               name = L["Colors"],
               order = 14,
               args = {
                  headers = ColorGroup(L["Headers"], 1, {
                     title = TextColor(L["Tracker title"], 1),
                     section = TextColor(L["Section headers"], 2),
                     zone = TextColor(L["Zone headers"], 3),
                     currentZone = TextColor(L["Current zone"], 4),
                  }),
                  quests = ColorGroup(L["Quest titles"], 2, {
                     quest = TextColor(L["Quest title"], 1,
                        L["Quest titles when not colored by difficulty, and tracked recipes."]),
                     questTag = TextColor(L["Quest type"], 2),
                     trivial = TextColor(L["Trivial"], 3),
                     standard = TextColor(L["Standard"], 4),
                     difficult = TextColor(L["Difficult"], 5),
                     verydifficult = TextColor(L["Very difficult"], 6),
                     impossible = TextColor(L["Impossible"], 7),
                  }),
                  objectives = ColorGroup(L["Objectives"], 3, {
                     objective = TextColor(L["Objective"], 1),
                     complete = TextColor(L["Completed objective"], 2),
                     failed = TextColor(L["Failed"], 3),
                     timeLeft = TextColor(L["Time left"], 4),
                  }),
                  other = ColorGroup(L["Other"], 4, {
                     distance = TextColor(L["Distance"], 1),
                     arrow = TextColor(L["Direction arrow"], 2),
                     scrollbar = TextColor(L["Scrollbar"], 3),
                  }),
               },
            },
            contentLayout = {
               type = "group",
               name = L["Layout"],
               desc = L["Spacing of the tracker contents."],
               order = 12,
               get = function(info) return mod:GetDisplayTheme().layout[info[#info]] end,
               set = function(info, val)
                  mod:GetDisplayTheme().layout[info[#info]] = val
                  mod:ApplyLayout()
               end,
               args = {
               padding = {
                  type = "range",
                  name = L["Padding"],
                  desc = L["Space between the tracker's edges and its content, for example to keep it clear of the border."],
                  min = 0, max = 30, step = 1,
                  order = 1,
               },
               sectionSpacing = {
                  type = "range",
                  name = L["Section spacing"],
                  desc = L["Space above each section header (Quests, World Quests, Professions)."],
                  min = 0, max = 40, step = 1,
                  order = 20.5,
               },
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
         },
      },
   }
   -- Built-in themes show their settings greyed out. (Disabling a tab group
   -- would disable the tab itself, so disable the settings inside.)
   for _, key in ipairs({ "headers", "background", "contentLayout", "fonts", "colors" }) do
      DisableForBuiltIn(options.theme.args[key])
   end
   options.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(mod.db)
end

----------------------------------------------------------------
-- New theme name popup (copy of the selected theme)
----------------------------------------------------------------

local NEW_THEME_POPUP = "MAGICQUESTTRACKER_NEW_THEME"

local function PopupEditBox(dialog)
   return dialog.GetEditBox and dialog:GetEditBox() or dialog.editBox
end

local function PopupButton1(dialog)
   return dialog.GetButton1 and dialog:GetButton1() or dialog.button1
end

StaticPopupDialogs[NEW_THEME_POPUP] = {
   text = L["Name for the copy of %s:"],
   button1 = ACCEPT,
   button2 = CANCEL,
   hasEditBox = 1,
   OnShow = function(dialog, data)
      local editBox = PopupEditBox(dialog)
      editBox:SetText(mod:GetFreeThemeName(format(L["%s (copy)"], data.sourceName)))
      editBox:HighlightText()
      editBox:SetFocus()
   end,
   OnAccept = function(dialog)
      mod:CreateTheme(PopupEditBox(dialog):GetText())
   end,
   EditBoxOnTextChanged = function(editBox)
      PopupButton1(editBox:GetParent()):SetEnabled(not mod:ValidateThemeName(editBox:GetText()))
   end,
   EditBoxOnEnterPressed = function(editBox)
      local dialog = editBox:GetParent()
      if PopupButton1(dialog):IsEnabled() then
         mod:CreateTheme(editBox:GetText())
         dialog:Hide()
      end
   end,
   EditBoxOnEscapePressed = function(editBox)
      editBox:GetParent():Hide()
   end,
   hideOnEscape = 1,
   timeout = 0,
   whileDead = 1,
}

--- Asks for a name and creates an editable copy of the selected theme.
function mod:ShowNewThemePopup()
   local sourceName = self:GetThemeList()[self:GetThemeSettings() and self.db.profile.theme or "blizzard"]
   StaticPopup_Show(NEW_THEME_POPUP, sourceName, nil, { sourceName = sourceName })
end

----------------------------------------------------------------
-- Theme import / export windows
----------------------------------------------------------------

local AceGUI = LibStub("AceGUI-3.0")
local ioFrame

-- One window, reused for import and export; returns its edit box.
local function ShowThemeWindow(title, status)
   if ioFrame then ioFrame:Hide() end  -- OnClose releases it
   local frame = AceGUI:Create("Frame")
   frame:SetTitle(title)
   frame:SetStatusText(status)
   frame:SetLayout("Fill")
   frame:SetWidth(500)
   frame:SetHeight(300)
   local box = AceGUI:Create("MultiLineEditBox")
   frame:SetCallback("OnClose", function(widget)
      if ioFrame == widget then ioFrame = nil end
      -- Widgets are pooled; restore the default button label.
      box.button:SetText(ACCEPT)
      if box.themeName then box.themeName:Hide() end
      widget:Release()
   end)
   box:SetLabel("")
   frame:AddChild(box)
   ioFrame = frame
   return frame, box
end

function mod:ShowThemeExport()
   local _, box = ShowThemeWindow(L["Export theme"], L["Press Ctrl-C to copy."])
   box:DisableButton(true)
   box:SetText(self:ExportTheme())
   box:SetFocus()
   box:HighlightText()
end

function mod:ShowThemeImport()
   local frame, box = ShowThemeWindow(L["Import theme"], L["Paste a theme export string and click Import."])
   box.button:SetText(L["Import"])

   -- Name of the pasted theme, right of the button.
   local label = box.themeName
   if not label then
      label = box.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      box.themeName = label
   end
   label:ClearAllPoints()
   label:SetPoint("LEFT", box.button, "RIGHT", 8, 0)
   label:SetPoint("RIGHT", box.frame, "RIGHT")
   label:SetJustifyH("LEFT")
   label:SetText("")
   label:Show()
   box:SetCallback("OnTextChanged", function(_, _, text)
      if strtrim(text) == "" then
         label:SetText("")
         return
      end
      local name, err = self:ParseThemeImport(text)
      if not name then
         label:SetText("|cffff4040" .. err .. "|r")
         return
      end
      local freeName = self:GetFreeThemeName(name)
      if freeName == name then
         label:SetFormattedText(L["Theme: %s"], name)
      else
         label:SetFormattedText(L["Theme: %s (imported as %s)"], name, freeName)
      end
   end)
   box:SetCallback("OnEnterPressed", function(_, _, text)
      local name, err = self:ParseThemeImport(text)
      if not name then
         frame:SetStatusText("|cffff4040" .. err .. "|r")
         return
      end
      self:ImportTheme(text)
      frame:Hide()
   end)
   box:SetFocus()
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
   self:OptReg(": Theme", options.theme, L["Theme"])
   self.optionsEnd = self:OptReg(": Profiles", options.profiles, L["Profiles"])
end

function mod:NotifyOptionsChanged()
   AceConfigRegistry:NotifyChange(APP_NAME)
   AceConfigRegistry:NotifyChange(APP_NAME .. ": Layout")
   AceConfigRegistry:NotifyChange(APP_NAME .. ": Theme")
end
