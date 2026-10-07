# Magic Quest Tracker

A replacement for the built-in objective tracker for WoW Retail and Classic Forever.

- Quests are grouped by zone (quest log header), using only the built-in quest log API (no quest database).
- Optionally shows the current zone first; remaining zones are sorted by their lowest quest level (or name).
- Quests within a zone are sorted by level.
- Option to hide quests that aren't in the current zone.
- Shows all quests by default, or only those on the built-in watch list.
- Elite quests are marked with `+` after the level, and the quest type (Elite, Dungeon, Raid, ...) is appended to the title.
- Tracked profession recipes are shown in a separate section.
- Scrollable, with a configurable max height, width, scale and background opacity.
- Configurable fonts (face, size, outline) for the title, zone headers, quest titles and objectives.
- Clicks behave like the built-in tracker: left-click opens the quest on the map, shift-click links, right-click opens a menu.

## Tracker title

- Drag to move (when unlocked)
- Middle-click toggles "only show quests in current zone"
- Right-click opens settings

## Commands

- `/mqt toggle` - show/hide the tracker contents
- `/mqt lock` - lock/unlock the tracker position
- `/mqt reset` - reset the tracker position
- `/mqt config` - open settings

## Planned: quest item buttons

Quest item buttons require secure action buttons, which can't be created or moved during combat and
can't sit inside the scroll child without making it combat-restricted. The planned design:

- Item buttons live in an overlay frame on the tracker (not in the scroll child).
- Buttons are positioned from the quest title lines' offsets minus the scroll offset; space is reserved at
  the right edge of those lines (`ITEM_BUTTON_SIZE` in `Tracker.lua`).
- While in combat with item buttons visible, rendering and scrolling are deferred (`mod.layoutDeferred`)
  and re-run on `PLAYER_REGEN_ENABLED`.
