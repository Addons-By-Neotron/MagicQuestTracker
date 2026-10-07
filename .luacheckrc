-- Luacheck configuration for World of Warcraft addons
std = "lua51"
max_line_length = 140
self = false

globals = {
    "MagicQuestTrackerDB",
}

read_globals = {
    -- Lua extensions
    "format", "strtrim", "tinsert", "CopyTable", "unpack",

    -- Frames / widgets
    "CreateFrame", "CreateFont", "UIParent", "GameTooltip", "ObjectiveTrackerFrame", "ProfessionsFrame",

    -- Namespaces
    "C_QuestLog", "C_SuperTrack", "C_Map", "C_TradeSkillUI", "C_Item", "C_CurrencyInfo", "Enum",
    "ChatFrameUtil", "MenuUtil", "QuestUtil", "ProfessionsUtil", "Professions", "Item",

    -- Functions
    "InCombatLockdown", "IsInGroup", "IsModifiedClick", "GetRealZoneText", "GetZoneText", "IsInInstance", "GetInstanceInfo",
    "GetQuestDifficultyColor", "GetQuestLogCompletionText", "GetQuestLogSpecialItemInfo",
    "GetQuestProgressBarPercent", "QuestMapFrame_OpenToQuestDetails", "QuestMapQuestOptions_AbandonQuest",
    "ToggleQuestLog", "GameTooltip_Hide", "ShowQuestComplete", "ProfessionsFrame_LoadUI", "ChatEdit_InsertLink",

    -- Constants / strings
    "NORMAL_FONT_COLOR", "OBJECTIVE_TRACKER_COLOR", "STANDARD_TEXT_FONT", "RETRIEVING_ITEM_INFO",
    "FAILED", "QUEST_WATCH_QUEST_READY", "TRACKER_HEADER_QUESTS", "PROFESSIONS_TRACKER_HEADER_PROFESSION",
    "PROFESSIONS_CRAFTING_FORM_RECRAFTING_HEADER", "SUPER_TRACK_QUEST", "STOP_SUPER_TRACK_QUEST",
    "OBJECTIVES_VIEW_IN_QUESTLOG", "OBJECTIVES_SHOW_QUEST_MAP", "OBJECTIVES_STOP_TRACKING", "TRACK_QUEST",
    "SHARE_QUEST", "ABANDON_QUEST_ABBREV", "PROFESSIONS_TRACKING_VIEW_RECIPE", "PROFESSIONS_UNTRACK_RECIPE",

    -- Libraries
    "LibStub", "AceGUIWidgetLSMlists",
}

exclude_files = {
    "Libs/**",
}

ignore = {
    "212", -- Unused argument
    "213", -- Unused loop variable
}
