# Magic Quest Tracker

A replacement for the built-in objective tracker for WoW Retail and Classic Forever.

- Laid out like the built-in tracker: an "All Objectives" (or "Zone Objectives" when filtered) title, collapsible sections for Quests, World Quests, Bonus Objectives and Professions, and zones within Quests.
- Quests are grouped by zone (quest log header), using only the built-in quest log API (no quest database).
- Optionally shows the current zone first; remaining zones are sorted by their lowest quest level, name or quest distance.
- Quests within a zone are sorted by level, name, or straight-line distance to the quest's next map location.
- Optional distance (yards) and direction arrow on each quest.
- Option to hide quests that aren't in the current zone.
- Option to auto-fold every zone except the current one when you change zones.
- Shows all quests by default, or only those on the built-in watch list.
- The level is suffixed by quest type: `+` elite/group, `D` dungeon, `R` raid, `H` heroic (e.g. `[33D]`, `[60R]`), and the quest type (Elite, Dungeon, Raid, Daily, ...) is appended to the title.
- Quest item buttons for quests with a usable item.
- On WoW Forever, quests that were not in original Classic are marked with an infinity sign.
- Retail: world quests (in the current area and tracked) and bonus objectives in their own sections.
- Tracked profession recipes are shown in a separate section.
- Scrollable, with a configurable max height, width and scale.
- Tracker background (texture, color, border) as part of custom themes, with separate opacity for normal and mouseover.
- Configurable spacing between zones, zone header and quests, quests and objectives.
- Themes: "Blizzard" (the built-in tracker's header art) or your own named themes (colored title, section and zone bars, each with its own SharedMedia texture or Blizzard header art, color and optional border). Themes are shared by all profiles; a new theme starts as a copy of the selected one.
- Configurable fonts (face, size, outline) for the title, section and zone headers, quest titles and objectives, as part of custom themes.
- Clicks behave like the built-in tracker: left-click opens the quest on the map, shift-click links, right-click opens a menu.
- Ctrl-click a quest to navigate to its next location (objective area, or turn-in when complete) with a TomTom waypoint, Blizzard's navigation (focusing the quest), or both. Without TomTom, Blizzard's navigation is used.

## Position and size

The tracker is moved in Blizzard's Edit Mode, with its position saved per Edit Mode layout. Width, maximum height and scale are set in the Edit Mode dialog and, like the position, saved per Edit Mode layout. The Layout settings page shows them and has a button to open Edit Mode. The Edit Mode dialog's "Match Blizzard tracker" button moves it to where the built-in objective tracker sits in the current layout and copies its height. Outside Edit Mode the tracker hides when there is nothing to track.

## Tracker title

- Middle-click toggles "only show quests in current zone"
- Right-click opens settings

## Commands

- `/mqt toggle` - show/hide the tracker contents
- `/mqt config` - open settings

## Quest item buttons

Quests with a usable item get a button (like the built-in tracker) at the right edge of the quest title.
Using a quest item is protected, so these are secure action buttons. They can't be moved, shown or hidden
in combat, so:

- The buttons live in their own holder frame on UIParent and are positioned from the quest title lines.
- Buttons are only shown when their quest title is fully inside the visible scroll area.
- While any item button is shown in combat, the tracker doesn't update, scroll, collapse or move. It
  catches up as soon as combat ends.
- Item buttons can be turned off in the options.

## License

Copyright (C) 2026 NeoTron

MagicQuestTracker is free software: you can redistribute it and/or modify it under the terms of the
GNU General Public License as published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version. See [LICENSE](LICENSE) for the full text.

## Credits

The infinity sign texture (`Textures/Infinity.tga`) and the idea of marking quests new to WoW Forever
come from Forever Quest Tint by xanastar (GPLv3).
