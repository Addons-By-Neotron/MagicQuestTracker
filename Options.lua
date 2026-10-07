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
}

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
               desc = L["How zones are ordered. Level sorts zones by their lowest level quest."],
               values = SORT_VALUES,
               order = 14,
            },
            questSort = {
               type = "select",
               name = L["Quest sort order"],
               desc = L["How quests are ordered within each zone."],
               values = SORT_VALUES,
               order = 15,
            },
            showLevel = {
               type = "toggle",
               name = L["Show quest level"],
               desc = L["Prefix quest titles with their level. + marks group quests, D daily and W weekly."],
               width = "full",
               order = 16,
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
               width = "full",
               order = 20,
               hidden = function() return not mod.itemButtonsImplemented end,
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
            backgroundAlpha = {
               type = "range",
               name = L["Background opacity"],
               min = 0, max = 1, step = 0.01, bigStep = 0.05, isPercent = true,
               order = 5,
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
