--[[
**********************************************************************
MagicQuestTracker - Localization.
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
local isSilent = true
--@debug@
isSilent = false
--@end-debug@

local L = LibStub("AceLocale-3.0"):NewLocale("MagicQuestTracker", "enUS", true, isSilent)

L["Miscellaneous"] = true
L["Failed"] = true
L["Ready for turn-in"] = true
L["Professions"] = true
L["Quests"] = true
L["Focus quest"] = true
L["Stop focusing quest"] = true
L["Open quest details"] = true
L["Show on map"] = true
L["Stop tracking"] = true
L["Track quest"] = true
L["Share quest"] = true
L["Abandon quest"] = true
L["View recipe"] = true
L["Untrack recipe"] = true
L["Level"] = true
L["Name"] = true
L["None"] = true
L["Outline"] = true
L["Thick outline"] = true
L["Font"] = true
L["Font size"] = true
L["A quest tracker that groups quests by zone, sorts them by level and shows tracked recipes in a separate section."] = true
L["Show all quests"] = true
L["Show every quest in the quest log. When disabled, only quests on the built-in watch list are shown."] = true
L["Show current zone first"] = true
L["Place the zone you are currently in at the top. Remaining zones are sorted using the zone sort order."] = true
L["Only show quests in current zone"] = true
L["Hide quests that are not in your current zone or on the current map."] = true
L["Zone sort order"] = true
L["Quest sort order"] = true
L["Show quest level"] = true
L["Prefix quest titles with their level. + marks elite and group quests, D dungeon, R raid and H heroic quests."] = true
L["Show quest type"] = true
L["Append the quest type, such as Elite, Dungeon, Raid or Daily, to quest titles."] = true
L["Daily"] = true
L["Weekly"] = true
L["Color by difficulty"] = true
L["Color quest titles by their difficulty relative to your level."] = true
L["Show completed objectives"] = true
L["Show finished objectives of incomplete quests, dimmed."] = true
L["Show tracked recipes"] = true
L["Show recipes tracked from the professions window in a separate section."] = true
L["Show quest item buttons"] = true
L["Hide Blizzard tracker"] = true
L["Hide the built-in objective tracker. Note that this hides all of its sections, including scenarios and bonus objectives."] = true
L["Commands"] = true
L["/mqt toggle  - show/hide the tracker"] = true
L["/mqt config  - open settings"] = true
L["Layout"] = true
L["Move the tracker in Edit Mode. Width, height and scale can also be changed there."] = true
L["Width"] = true
L["Match Blizzard tracker"] = true
L["Maximum height"] = true
L["The tracker grows with its contents up to this height, then becomes scrollable."] = true
L["Scale"] = true
L["Background opacity"] = true
L["Fonts"] = true
L["Tracker title"] = true
L["Zone headers"] = true
L["Quest titles"] = true
L["Objectives"] = true
L["Profiles"] = true
L["Available commands:"] = true
L["Middle-click: Toggle current zone only"] = true
L["Right-click: Options"] = true
L["Background"] = true
L["Background color"] = true
L["Background opacity when the mouse is not over the tracker."] = true
L["Mouseover opacity"] = true
L["Background opacity when the mouse is over the tracker."] = true
L["Spacing"] = true
L["Zone spacing"] = true
L["Space above each zone header."] = true
L["Zone header spacing"] = true
L["Space between a zone header and its first quest."] = true
L["Quest spacing"] = true
L["Space above each quest title."] = true
L["Objective spacing"] = true
L["Space between objective lines."] = true
L["Show a button to use the quest item next to quests that have one. While a button is shown, the tracker does not update or scroll during combat."] = true
L["%d yd"] = true
L["Distance"] = true
L["How quests are ordered within each zone. Distance sorts by straight-line distance to the quest's next location on the map; quests without one are listed last."] = true
L["Show distance"] = true
L["Show the straight-line distance to each quest's next location on the map."] = true
L["How zones are ordered. Level sorts zones by their lowest level quest, distance by their nearest quest."] = true
L["Show direction"] = true
L["Show an arrow pointing toward each quest's next location on the map. Not available in instances."] = true
L["Arrow size"] = true
L["Mark new Forever quests"] = true
L["Show an infinity sign after quests that were not in original Classic."] = true
L["Arrow max distance"] = true
L["Only show arrows for quests in other zones within this many yards. Quests in the current zone always get an arrow. 0 shows arrows at any distance."] = true
L["No location known for %s."] = true
L["Set TomTom waypoint"] = true
L["Ctrl-click navigation"] = true
L["What ctrl-clicking a quest does: set a TomTom waypoint, focus the quest for Blizzard's navigation, or both. Without TomTom, Blizzard's navigation is always used."] = true
L["TomTom"] = true
L["Blizzard"] = true
L["Both"] = true
L["Show quest POI buttons"] = true
L["Show the quest map icon next to each quest, like the built-in tracker. Click it to focus the quest. Follows the game's quest POI setting."] = true
L["Show find group buttons"] = true
L["Show the group finder button on quests that support it, like the built-in tracker."] = true
L["World Quests"] = true
L["Bonus Objectives"] = true
L["Show world quests"] = true
L["Show world quests in the current area and tracked world quests in a separate section."] = true
L["Show bonus objectives"] = true
L["Show bonus objectives in the current area in a separate section."] = true
L["All Objectives"] = true
L["Zone Objectives"] = true
L["%s (%d of %d/%d)"] = true
L["Section headers"] = true
L["Section spacing"] = true
L["Space above each section header (Quests, World Quests, Professions)."] = true
L["Auto-fold other zones"] = true
L["When showing all quests, fold every zone except the current one whenever you enter a new zone. Zones you unfold stay open until the next zone change."] = true
L["Theme"] = true
L["Bar texture"] = true
L["Border"] = true
L["Border size"] = true
L["Border color"] = true
L["Background texture"] = true
L["The border fades in and out with the background opacity."] = true
L["Distance and navigation"] = true
L["Sections"] = true
L["Buttons"] = true
L["Other"] = true
L["Padding"] = true
L["Space between the tracker's edges and its content, for example to keep it clear of the border."] = true
L["Open settings"] = true
L["Custom"] = true
L["Bar color"] = true
L["With zero opacity and no border, zone headers are shown as plain text."] = true
L["Bordered minimize button"] = true
L["Reset to Blizzard"] = true
L["Themes are shared by all profiles. A new theme starts as a copy of the selected one."] = true
L["New theme"] = true
L["Enter a name to create a new theme from the selected one."] = true
L["Change the selected theme to look like the Blizzard theme."] = true
L["Reset the selected theme to look like the Blizzard theme?"] = true
L["Delete theme"] = true
L["Delete the selected theme? Profiles using it switch to the Blizzard theme."] = true
L["Enter a theme name."] = true
L["A theme with that name already exists."] = true
L["Headers"] = true
L["Spacing of the tracker contents."] = true
L["Rename theme"] = true
L["Enter a new name for the selected theme. Profiles using it keep using it."] = true
L["Import theme"] = true
L["Export theme"] = true
L["This is not a theme export string."] = true
L["This theme export string is damaged."] = true
L["Imported"] = true
L["Paste a theme export string. The theme is added under its own name and selected."] = true
L["Show the selected theme as a string to copy and share."] = true
L["Press Ctrl-C to copy."] = true
L["Paste a theme export string and click Import."] = true
L["Import"] = true
L["Theme: %s"] = true
L["Theme: %s (imported as %s)"] = true
