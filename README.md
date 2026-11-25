# Magic Quest Tracker

A replacement for the built-in objective tracker for WoW Retail and Classic Forever.

- Laid out like the built-in tracker: an "All Objectives" (or "Zone Objectives" when filtered) title, collapsible sections for Quests, World Quests, Bonus Objectives and Professions, and zones within Quests.
- Quests are grouped by zone (quest log header), using only the built-in quest log API (no quest database).
- Optionally shows the current zone first; remaining zones are sorted by their lowest quest level, name or quest distance.
- Quests within a zone are sorted by level, name, or straight-line distance to the quest's next map location.
- Optional distance (yards) and direction arrow on each quest, with the arrow before or after the distance.
- Option to hide quests that aren't in the current zone.
- Option to auto-fold every zone except the current one when you change zones.
- Three views: all quests, current zone only, or only the quests on the built-in watch list (like the built-in tracker). Middle-click the title to switch.
- Quests on the built-in watch list get a check mark when all quests are shown.
- Optionally hides quests that are too difficult (red) or too easy (gray) for your level.
- Zone headers can be hidden, always or only while a single zone is shown; quests are then sorted as one list. The Tracked and Completed section headers always stay.
- Section headers can show the count and maximum, like Quests (12/25), only the count, or nothing; zone header counts can be turned off separately.
- Fold icons for collapsible headers: triangle, chevron, plus / minus or Blizzard's button, on the left, right or after the title.
- Completed quests can be sorted normally, listed first (default) or last in their zone, and zone headers show how many are complete. Optionally, completed quests (all, or only those in the current zone) get their own section instead, sorted by the quest sort order.
- Optional section on top of the zones with the focused quest (Focused), or the focused quest plus the quests on the built-in watch list (Tracked). The focused quest is always shown there, even when filtered out; when only watched quests are shown, only the focused quest moves up.
- The level is suffixed by quest type: `+` elite/group, `D` dungeon, `R` raid, `H` heroic (e.g. `[33D]`, `[60R]`), and the quest type (Elite, Dungeon, Raid, Daily, ...) is appended to the title.
- Quest item buttons for quests with a usable item, plus an optional separate quest item bar (see below).
- Optional Timed section on top for quests with a time limit, least time left first, shown whatever the filters. Time left can show as a bar that empties as it runs out.
- Quest markers, find group and voiceover buttons can be hidden until the mouse is over the tracker.
- On WoW Forever, the play button of the Spoken Quests addon on quests with a voiceover.
- On WoW Forever, quests that were not in original Classic are marked with an infinity sign.
- Retail: world quests (in the current area and tracked) and bonus objectives in their own sections.
- Retail: scenarios (delves, open world scenarios, ...) in their own section on top, with your quests below. In Mythic+ and Proving Grounds the tracker steps aside for Blizzard's scenario block, which still shows when the Blizzard tracker is hidden.
- Tracked achievements and profession recipes are shown in separate sections.
- Scrollable, with a configurable max height, width and scale (via Edit Mode).
- Tracker background (texture, color, border) as part of custom themes, with separate opacity for normal and mouseover.
- Configurable spacing between zones, zone header and quests, quests and objectives.
- Themes: "Blizzard" (the built-in tracker's header art) or your own named themes (colored title, section and zone bars, each with its own SharedMedia texture or Blizzard header art, color and optional border). Built-in themes: Blizzard, plus dark themes Solarized Dark, Nord, Dracula, Gruvbox Dark, Catppuccin Mocha, Tokyo Night, One Dark, Monokai, Everforest Dark, Rose Pine, Kanagawa Dragon, Tomorrow Night and Zenburn. Themes are shared by all profiles; a new theme starts as a copy of the selected one, built-in or not.
- Configurable fonts (face, size, outline) for the title, section and zone headers, quest titles and objectives, as part of custom themes.
- Optionally hides in combat (inside instances only or everywhere), and inside instances (always, or when none of your quests are for the instance).
- Configurable text colors in custom themes: headers, current zone, quest titles (single color or per difficulty), quest type, objectives, completed/failed objectives, time left, distance, direction arrow and scrollbar.
- Left-click a quest to open its details window (see below), shift-click to link it, right-click for a menu. Right-click the Quests header for the views, filters and the quest log.
- Ctrl-click a quest to navigate to its next location (objective area, or turn-in when complete) with a TomTom waypoint, Blizzard's navigation (focusing the quest), or both. Without TomTom, Blizzard's navigation is used.
- Blizzard quest focus (ctrl-click, the right-click menu and the quest POI buttons) can be turned off; with it off, ctrl-click only sets a TomTom waypoint. Changing the focus in combat takes effect when combat ends.
- A setup wizard (on first install, from the settings or `/mqt wizard`) to pick a look and the features, and a What's New window after updates that lists new features with a switch to turn each on.

## Position and size

The tracker is moved in Blizzard's Edit Mode, with its position saved per Edit Mode layout. Width, maximum height and scale are set in the Edit Mode dialog and, like the position, saved per Edit Mode layout. The Layout settings page shows them. Open Edit Mode from the game menu or with /editmode. The Edit Mode dialog's "Match Blizzard tracker" button moves it to where the built-in objective tracker sits in the current layout and copies its height. Outside Edit Mode the tracker hides when there is nothing to track.

## Tracker title

- Middle-click switches the view: all quests, current zone, tracked quests
- Right-click opens a menu with the views, filters and settings

## Commands

- `/mqt toggle` - show/hide the tracker contents
- `/mqt config` - open settings
- `/mqt wizard` - run the setup wizard
- `/mqt new` - show what's new
- `/mqt newrun` - (Forever) start a new dungeon run: stats and kills from now

## Quest details window

Left-clicking a quest opens a window with its objectives, description and rewards (XP, money and items),
with a note when the XP is reduced because the quest is far below your level. Its buttons show the quest
on the map (or complete an auto-complete quest), focus, track or untrack, share and abandon it.

The map button works by clicking the quest's block in Blizzard's own (hidden) tracker, which keeps the map
usable in combat (see "Fewer errors in combat" below). So it only works out of combat, and only for quests
Blizzard's tracker has a block for. When it doesn't (the quest isn't tracked, or too many quests are tracked
for its height), the button opens the quest log instead.

## Dungeons (Forever)

Optional Dungeon section listing the bosses of the dungeon you're in, checked off as they die, like Retail.

- Scarlet Monastery, Dire Maul, Stratholme and Blackrock Spire list only the bosses of the wing you entered,
  detected from the door you used. In Dire Maul and Stratholme, a run that crosses into another wing (a kill
  there, or going out and in by another door) keeps going and lists the bosses of every wing visited.
- Optional run stats: kill XP, quest XP (as soon as the dungeon's quests are complete), coins, the vendor value
  of the loot, deaths and time. Hover them for XP and money per hour, split into kills and quests, coins and items.
- The run starts over when the dungeon is reset, when you enter with a different group leader, when you walk
  into a finished run, or with `/mqt newrun` or the Dungeon header's right-click menu.
- After you leave, the section stays for a minute (with a close button). Its chat button posts the run summary
  (kills, XP, money, time, deaths and rates) to your group, or prints it when you're solo. The summary can also
  be printed to your chat window on leaving.

## Quest item bar

A separate bar with up to five quest item buttons you can bind keys to. The first holds the focused or nearest
quest's item; the others the items of nearby quests (within a set distance). Move and size it in Edit Mode.

## Quest item buttons

Quests with a usable item get a button (like the built-in tracker) at the right edge of the quest title.
Using a quest item is protected, so these are secure action buttons. They can't be moved, shown or hidden
in combat, so:

- The buttons live in their own holder frame on UIParent and are positioned from the quest title lines.
- Buttons are only shown when their quest title is fully inside the visible scroll area.
- While any item button is shown in combat, the tracker doesn't update, scroll, collapse or move. It
  catches up as soon as combat ends.
- Item buttons can be turned off in the options.

## Fewer errors in combat

Blizzard blocks some actions in combat once an addon has touched parts of its UI (called "taint"), which
showed up as "action blocked" errors and a map that wouldn't open in combat. To avoid that, a few things work
a little differently from the built-in tracker:

- Clicking a quest opens the details window instead of the map; its map button only works out of combat.
- `/mqt config` opens the settings in their own window instead of Blizzard's Settings panel. The settings
  are still listed under AddOns in Blizzard's panel.
- The right-click menus are the addon's own, not Blizzard's.
- Changing the focused quest in combat takes effect when combat ends.

## License

Copyright (C) 2026 NeoTron

MagicQuestTracker is free software: you can redistribute it and/or modify it under the terms of the
GNU General Public License as published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version. See [LICENSE](LICENSE) for the full text.

## Credits

The infinity sign texture (`Textures/Infinity.tga`) and the idea of marking quests new to WoW Forever
come from Forever Quest Tint by xanastar (GPLv3).
