-- Druid trainer spells: the level each first becomes trainable, and what it
-- improves. Used by the advisor to say "go train X, it improves A, B".
--
-- Levels are meant as the Classic Era (1.12) trainer levels. The commit that
-- added them (6ee995a) names no source, and they were not checked against a
-- WoW: Forever trainer: every level here is a first guess, and some are
-- known to differ there (CHANGELOG.md records a Forever trainer teaching
-- Rake at 24, not 20). The truth is read from the trainer: each visit records the level
-- a spell is first taught at, and that level is laid over this one while it
-- is within F.MAX_SHIFT levels of it (Modules/Facts.lua, F.FixLevels). A
-- spell the trainer doesn't list at all is no longer advised (F.NotTaught).
-- needs = "Bear Form": the trainer won't teach it until you know that spell
-- (it shows red there). Flow then doesn't count it as "to train" and says
-- what it waits for. quest / questName: the class quest that teaches a spell.

local _, ns = ...

ns:Register("classSpells", "DRUID", {
    { level = 1,  spell = "Wrath",                 improves = { "DPS" } },
    { level = 1,  spell = "Healing Touch",         improves = { "Healing", "Survival" } },
    { level = 1,  spell = "Mark of the Wild",      improves = { "Stats" } },
    { level = 4,  spell = "Moonfire",              improves = { "DPS" } },
    { level = 4,  spell = "Rejuvenation",          improves = { "Healing", "Survival" } },
    { level = 6,  spell = "Thorns",                improves = { "DPS", "Survival" } },
    { level = 8,  spell = "Entangling Roots",      improves = { "Control" } },
    -- Bear Form comes from a class quest chain, not the trainer; its last
    -- turn-in ("Body and Heart": 6001 Alliance, 6002 Horde in Classic) teaches
    -- it (Needs.lua: the training step goes after it on the route).
    { level = 10, spell = "Bear Form",             improves = { "Survival", "Threat" }, note = "class quest",
      quest = { 6001, 6002 }, questName = "Body and Heart" },
    { level = 10, spell = "Demoralizing Roar",     improves = { "Survival" }, needs = "Bear Form" },
    { level = 10, spell = "Growl",                 improves = { "Threat" }, needs = "Bear Form" },
    { level = 10, spell = "Maul",                  improves = { "DPS", "Threat" }, needs = "Bear Form" },
    { level = 10, spell = "Nature's Grasp",        improves = { "Control" } },
    { level = 12, spell = "Regrowth",              improves = { "Healing" } },
    { level = 12, spell = "Enrage",                improves = { "Threat" }, needs = "Bear Form" },
    { level = 14, spell = "Bash",                  improves = { "Control" }, needs = "Bear Form" },
    { level = 14, spell = "Cure Poison",           improves = { "Survival" } },
    { level = 16, spell = "Swipe",                 improves = { "DPS", "Threat" }, needs = "Bear Form" },
    -- Aquatic Form: a class quest chain too ("A Lesson to Learn", "Trial of the
    -- Lake", "Trial of the Sea Lion"); its last quest, "Aquatic Form" (5061
    -- Alliance, 31 Horde in Classic), teaches it. With the quest named, Flow
    -- finds where you are in the chain and links the step (0.35.279: "it's
    -- been telling me to get Aquatic Form since level 16 and not showing where").
    { level = 16, spell = "Aquatic Form",          improves = { "Travel" }, note = "class quest",
      quest = { 5061, 31 }, questName = "Aquatic Form" },
    { level = 18, spell = "Faerie Fire",           improves = { "DPS" } },
    { level = 18, spell = "Hibernate",             improves = { "Control" } },
    { level = 20, spell = "Cat Form",              improves = { "DPS" } },
    { level = 20, spell = "Claw",                  improves = { "DPS" }, needs = "Cat Form" },
    { level = 20, spell = "Rake",                  improves = { "DPS" }, needs = "Cat Form" },
    { level = 20, spell = "Prowl",                 improves = { "Control" }, needs = "Cat Form" },
    { level = 20, spell = "Starfire",              improves = { "DPS" } },
    { level = 20, spell = "Rebirth",               improves = { "Group" } },
    { level = 22, spell = "Shred",                 improves = { "DPS" }, needs = "Cat Form" },
    { level = 24, spell = "Rip",                   improves = { "DPS" }, needs = "Cat Form" },
    { level = 24, spell = "Tiger's Fury",          improves = { "DPS" }, needs = "Cat Form" },
    { level = 24, spell = "Remove Curse",          improves = { "Survival" } },
    { level = 26, spell = "Dash",                  improves = { "Travel" }, needs = "Cat Form" },
    { level = 30, spell = "Travel Form",           improves = { "Travel" } },
    { level = 30, spell = "Tranquility",           improves = { "Healing", "Group" } },
    { level = 32, spell = "Ferocious Bite",        improves = { "DPS" }, needs = "Cat Form" },
    { level = 36, spell = "Pounce",                improves = { "DPS", "Control" }, needs = "Cat Form" },
    { level = 36, spell = "Frenzied Regeneration", improves = { "Survival" }, needs = "Bear Form" },
    { level = 40, spell = "Dire Bear Form",        improves = { "Survival", "Threat" }, needs = "Bear Form" },
    { level = 40, spell = "Innervate",             improves = { "Mana" } },
    { level = 40, spell = "Hurricane",             improves = { "DPS" } },
})
