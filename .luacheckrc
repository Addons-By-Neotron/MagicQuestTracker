-- Luacheck configuration for World of Warcraft addons
std = "lua51"
max_line_length = 140
self = false

globals = {
    "MagicQuestTrackerDB", "BINDING_HEADER_MAGICQUESTTRACKER",
}

read_globals = {
    -- Lua extensions
    "format", "strtrim", "tinsert", "CopyTable", "unpack",

    -- Frames / widgets
    "CreateFrame", "CreateFont", "UIParent", "GameTooltip", "GENERAL", "COMPLETE_QUEST", "ObjectiveTrackerFrame", "ProfessionsFrame",

    -- Namespaces
    "C_QuestLog", "C_SuperTrack", "C_Map", "C_TradeSkillUI", "C_Item", "C_CurrencyInfo", "Enum",
    "ChatFrameUtil", "MenuUtil", "QuestUtil", "ProfessionsUtil", "Professions", "Item",

    -- Functions
    "InCombatLockdown", "IsInGroup", "IsModifiedClick", "GetRealZoneText", "GetZoneText", "IsInInstance", "GetInstanceInfo",
    "GetQuestDifficultyColor", "GetQuestLogCompletionText", "GetQuestLogSpecialItemInfo",
    "GetQuestProgressBarPercent", "QuestMapFrame_OpenToQuestDetails", "QuestMapQuestOptions_AbandonQuest",
    "ToggleQuestLog", "GameTooltip_Hide", "C_Timer", "CooldownFrame_Set", "GetQuestLogSpecialItemCooldown",
    "IsQuestLogSpecialItemInRange", "GetPlayerFacing", "GetBuildInfo", "IsControlKeyDown", "IsShiftKeyDown", "POIButtonUtil", "POIButtonMixin", "GetCursorPosition", "hooksecurefunc", "C_Scenario", "C_ScenarioInfo", "DefaultWidgetLayout", "C_Texture", "GameFontHighlightMedium", "C_ContentTracking", "Enum", "GetAchievementInfo", "GetAchievementNumCriteria", "GetAchievementCriteriaInfo", "GetAchievementLink", "IsAchievementEligible", "EVALUATION_TREE_FLAG_PROGRESS_BAR", "CRITERIA_TYPE_ACHIEVEMENT", "bit", "TRACKER_HEADER_ACHIEVEMENTS", "OBJECTIVES_VIEW_ACHIEVEMENT", "AchievementFrame", "AchievementFrame_LoadUI", "AchievementFrame_ToggleAchievementFrame", "AchievementFrame_SelectAchievement", "AchievementFrameAchievements", "AchievementFrameAchievements_ForceUpdate", "ShowAchievementFrameForAchievement", "LE_SCENARIO_TYPE_CHALLENGE_MODE", "LE_SCENARIO_TYPE_PROVING_GROUNDS", "issecretvalue", "C_EventUtils", "ScenarioObjectiveTracker", "GetCVar", "C_LFGList", "GetTasksTable", "GetTaskInfo", "C_TaskQuest", "QuestUtils_IsQuestWorldQuest",
    "QuestUtils_IsQuestWatched", "QuestUtils_ShouldDisplayExpirationWarning", "BONUS_OBJECTIVE_TIME_LEFT",
    "SecondsToTime", "OpenQuestLog", "EventRegistry", "TRACKER_HEADER_WORLD_QUESTS", "TRACKER_HEADER_BONUS_OBJECTIVES", "TomTom", "CreateVector2D", "wipe", "UnitLevel", "RANGE_INDICATOR", "tonumber", "ShowQuestComplete", "ProfessionsFrame_LoadUI", "ChatEdit_InsertLink",

    -- Other game API used (found by luacheck)
     "ACCEPT", "BreakUpLargeNumbers", "CANCEL", "C_CVar", "C_EncodingUtil", "C_EncounterJournal", "C_Housing",
     "CombatLogGetCurrentEventInfo", "COMBATLOG_XPGAIN_EXHAUSTION1", "COMBATLOG_XPGAIN_EXHAUSTION2",
     "COMBATLOG_XPGAIN_FIRSTPERSON", "Constants", "C_PlayerInfo", "EditModeMagnetismManager",
     "EditModeManagerFrame", "EJ_GetEncounterInfoByIndex", "EJ_SelectInstance", "GetBindingKey",
     "GetBindingText", "GetCoinTextureString", "GetCVarBool", "GetDifficultyColor", "geterrorhandler",
     "GetInstanceLockTimeRemaining", "GetInstanceLockTimeRemainingEncounter", "GetItemInfo",
     "GetMinimapZoneText", "GetMoney", "GetNumGroupMembers", "GetNumSubgroupMembers", "GetQuestUiMapID",
     "GetSubZoneText", "GetTime", "HideUIPanel", "HOUSING_CORNERSTONE_NEIGHBORHOOD", "INSTANCE_RESET_SUCCESS",
     "InterfaceOptionsFrame", "IsInRaid", "KeybindFrames_InQuickKeybindMode",
     "LE_SCENARIO_TYPE_USE_DUNGEON_DISPLAY", "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE", "MerchantFrame",
     "MinimalSliderWithSteppersMixin", "QuestDifficultyColors", "QuestTimerFrame",
     "QuickKeybindButtonTemplateMixin", "QuickKeybindFrame", "QuickKeybindTooltip", "RegisterStateDriver",
     "SecondsToClock", "SELFKILLOTHER", "SetCVar", "SettingsPanel", "strsplit", "time",
     "TRACKER_HEADER_DUNGEON", "TRACKER_HEADER_PROVINGGROUNDS", "UIErrorsFrame", "UNITDIESOTHER", "UnitExists",
     "UnitGUID", "UnitIsDead", "UnitIsGroupLeader", "UnitName", "UnitXP", "UnitXPMax", "UNKNOWN",
     "UnregisterStateDriver",

    -- Taint-safe replacements (click overlay, quest details, abandon / share, watch edits)
    "ATTRIBUTE_NOOP", "GetModifiedClick", "SecureButton_GetModifiedAttribute", "WorldMapFrame",
    "C_InstanceEncounter", "IsEncounterInProgress", "C_QuestInfoSystem", "QuestLogPushQuest",
    "PlaySound", "SOUNDKIT", "GetQuestLogQuestText", "GetQuestLogRewardXP", "GetQuestLogRewardMoney",
    "GetNumQuestLogRewards", "GetQuestLogRewardInfo", "GetNumQuestLogChoices", "GetQuestLogChoiceInfo",
    "GetMoneyString", "GameFontHighlight", "GameFontNormalLarge", "ITEM_QUALITY_COLORS",
    "ABANDON_QUEST_CONFIRM", "ABANDON_QUEST_CONFIRM_WITH_ITEMS", "YES", "NO", "LEVEL", "COMPLETE",
    "QUEST_OBJECTIVES", "QUEST_DESCRIPTION", "QUEST_REWARDS", "BONUS_OBJECTIVE_EXPERIENCE_FORMAT",
    "REWARD_CHOICES",

    -- Constants / strings
    "NORMAL_FONT_COLOR", "OBJECTIVE_TRACKER_COLOR", "STANDARD_TEXT_FONT", "RETRIEVING_ITEM_INFO",
    "FAILED", "DAILY", "WEEKLY", "QUEST_WATCH_QUEST_READY", "TRACKER_HEADER_QUESTS", "PROFESSIONS_TRACKER_HEADER_PROFESSION",
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
