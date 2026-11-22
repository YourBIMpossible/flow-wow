-- Built-in advisors. Each returns a list of advice items; see Advisor.lua.

local _, ns = ...

local function classToken() return select(2, UnitClass("player")) end

local function classSpellInfo(name)
    for _, s in ipairs(ns:Get("classSpells", classToken()) or {}) do
        if s.spell == name then return s end
    end
end

-------------------------------------------------------------------------------
-- Training: spells and ranks you could have but don't.
-------------------------------------------------------------------------------

local T = {}
ns.trainerAdvice = T
-- Pure: the route step where you get a spell that another one waits for: its
-- class quest's step, else your class trainer's. nil: Flow can't say (a
-- spell with a note of its own: a talent, a book).
--   spells: your class's list ({ spell, quest, note });
--   questKeyOf(spell) -> the key of that quest's step on your route
function T.PrereqKey(spells, name, questKeyOf)
    for _, s in ipairs(spells or {}) do
        if s.spell == name then
            if s.quest then return questKeyOf and (questKeyOf(name)) or nil end
            if not s.note then return "train:class" end
            return nil
        end
    end
    return nil
end
-- What a spell at the trainer waits for, or nil when you can train it:
--   needs: the spell it needs first (class data, "Bear Form"); known: your spells;
--   category, level: as your last visit showed it; seenAt: your level then.
-- Red at the trainer although its level was within yours then: it needs
-- something Flow has no data for ("something first: it was red").
-- Pure: your class trainer, read at this level, doesn't list this spell at
-- all: then Flow's own class list is wrong about it here, and "Get X (class
-- trainer)" would send you back for nothing ("I hit the trainer in
-- Moonglade and they don't have Cure Poison", 0.35.219). services: what the
-- trainer listed ({ name } each); seenAt: your level at that visit.
function T.TrainerLacks(spell, services, seenAt, level)
    if not (spell and type(services) == "table" and #services > 0 and seenAt and level and seenAt >= level) then return false end
    for _, s in ipairs(services) do
        if s.name == spell then return false end
    end
    return true
end

-- Pure: what a trainer's line improves. info: its row in the class list (or
-- nil: Flow's list has none, as for a spell only WoW: Forever teaches);
-- isKnown: you know the spell already, so the line is a later rank. A spell
-- with no row that you don't know is new to you, not a "stronger rank".
function T.Improves(info, isKnown)
    if info and info.improves then return info.improves end
    return { isKnown and "Stronger rank" or "New spell" }
end

function T.WaitsFor(needs, known, category, level, seenAt)
    if needs and not known[needs] then return needs end
    if needs then return nil end   -- (you have what it needs now)
    if category == "unavailable" and (level or 0) > 0 and seenAt and level <= seenAt then
        return "something first (it was red at the trainer)"
    end
    return nil
end

local CATEGORY_WORDS = { available = true, unavailable = true, used = true }

ns:Register("advisor", "trainer", {
    check = function()
        local out, listed = {}, {}
        local level = UnitLevel("player")
        local known = ns.rotation:KnownSpells()

        -- 1. The real list from your last class-trainer visit.
        for _, s in ipairs(ns.db.trainer.services or {}) do
            -- Data saved by older Flow versions on newer clients had the
            -- category in the rank field; repair it.
            if CATEGORY_WORDS[s.sub] then
                s.category, s.sub, s.modern = s.sub, "", true
            end
            local learnable = s.category == "available"
                or (s.category == "unavailable" and s.level > 0 and s.level <= level)
            -- Learned since that visit (e.g. from a class quest)? Only checkable
            -- for first ranks; higher ranks clear at your next trainer visit.
            -- Newer clients give no rank text: a known spell listed again is a new rank.
            local firstRank = not s.modern and (s.sub == "" or s.sub == "Rank 1")
            if known[s.name] and firstRank then learnable = false end
            if s.category == "used" then learnable = false end
            local info = classSpellInfo(s.name)
            -- Waits for another spell first (Demoralizing Roar: Bear Form, from
            -- a class quest), or was red at the trainer for something other
            -- than your level: listed as waiting, not "go train" (0.35.142).
            local waitFor = T.WaitsFor(info and info.needs, known, s.category, s.level, ns.db.trainer.seenAt)
            if learnable and waitFor and not known[s.name] then
                out[#out + 1] = {
                    importance = 40,
                    text = string.format("%s: after %s", s.name, waitFor),
                    improves = T.Improves(info, known[s.name]),
                    waitsFor = waitFor,
                }
                listed[s.name] = true
                learnable = false
            end
            if learnable and s.level <= level then
                out[#out + 1] = {
                    importance = 80,
                    text = string.format("Train %s%s at your class trainer", s.name,
                        s.sub ~= "" and (" (" .. s.sub .. ")") or ""),
                    improves = T.Improves(info, known[s.name]),
                    goalKey = "train:class",
                    cost = s.cost,  -- copper, from your last visit (route skips it until you can pay)
                }
                listed[s.name] = true
            end
        end

        -- 2. Flow's class list (classSpells) for spells you've never seen at a trainer yet.
        for _, s in ipairs(ns:Get("classSpells", classToken()) or {}) do
            local waitFor = s.needs and not known[s.needs] and s.needs or nil
            if s.level <= level and not known[s.spell] and not listed[s.spell] and waitFor then
                out[#out + 1] = {
                    importance = 40,
                    text = string.format("%s: after %s", s.spell, waitFor),
                    improves = s.improves,
                    waitsFor = waitFor,
                    -- Its link: where you get what it waits for (Maul waits for
                    -- Bear Form: the Bear Form quest's step).
                    goalKey = T.PrereqKey(ns:Get("classSpells", classToken()), waitFor,
                        ns.quests and ns.quests.ClassQuestKey),
                }
            elseif s.level <= level and not known[s.spell] and not listed[s.spell] and not s.quest and not s.note
                -- (By the spell's own level, not yours: a trainer read at 17 that
                -- had no Cure Poison (a level 14 spell in Flow's list) still has
                -- none when you turn 18. 0.35.279: it was advised again at
                -- every level until the next visit.)
                and (T.TrainerLacks(s.spell, ns.db.trainer.services, ns.db.trainer.seenAt, s.level)
                     -- (or any trainer, on any of your characters or a player who shared: Facts.lua)
                     or (ns.facts and ns.facts.NotTaught and ns.facts.NotTaught(classToken(), s.spell, s.level))) then
                -- (Said once in the log, so the class list can be put right.)
                T.lacksLogged = T.lacksLogged or {}
                if not T.lacksLogged[s.spell] then
                    T.lacksLogged[s.spell] = true
                    ns:Log("trainer", string.format("Flow's class list has %s at level %d, but %s (read at level %s) doesn't list it: not advised",
                        s.spell, s.level, tostring(ns.db.trainer.npc), tostring(ns.db.trainer.seenAt)))
                end
            elseif s.level <= level and not known[s.spell] and not listed[s.spell] then
                -- A class quest teaches it: its link is the quest's step on your route
                -- ("Accept: Heeding the Call"), and the text says which quest.
                local questKey, questText
                if s.quest and ns.quests and ns.quests.ClassQuestKey then questKey, questText = ns.quests.ClassQuestKey(s.spell) end
                out[#out + 1] = {
                    importance = (ns.classQuests and ns.classQuests.IsForm(s.spell)) and ns.classQuests.FORM_IMPORTANCE or 75,
                    text = string.format("Get %s (level %d%s)", s.spell, s.level,
                        questText and (", class quest: " .. questText) or (s.note and (", " .. s.note) or ", class trainer")),
                    improves = s.improves,
                    goalKey = (not s.note and "train:class") or questKey,   -- (its link: the step on your route)
                }
            end
        end
        return out
    end,
})

-------------------------------------------------------------------------------
-- Action bars: rotation spells you know but can't press.
-------------------------------------------------------------------------------

local function spellsOnBars()
    local on = {}
    for slot = 1, 120 do
        if HasAction(slot) then
            local kind, id = GetActionInfo(slot)
            if kind == "spell" and id then
                local name = ns.api.SpellInfo(id)
                if name then on[name] = true end
            end
        end
    end
    -- The stance bar counts too (auras live there).
    for _, s in ipairs(ns.api.StanceSpells()) do on[s.name] = true end
    return on
end

ns:Register("advisor", "bars", {
    check = function()
        local def = ns.rotation:Definition()
        if not def then return end
        local known, on, seen, out = ns.rotation:KnownSpells(), spellsOnBars(), {}, {}
        local function consider(spell, why)
            -- (Not one you said no to, or one a key casts directly: NewSpell.lua.)
            local covered = ns.newSpell and ns.newSpell.Covered(spell)
            if known[spell] and not on[spell] and not seen[spell] and not covered then
                seen[spell] = true
                out[#out + 1] = { importance = 70,
                    text = "Put " .. spell .. " on your action bars: Flow will suggest it",
                    improves = why, spell = spell }   -- (its link: the place-or-bind card)
            end
        end
        for _, rule in ipairs(def.priority or {}) do consider(rule.spell, { "Rotation" }) end
        for _, list in pairs(def.priorities or {}) do
            for _, rule in ipairs(list) do consider(rule.spell, { "Rotation" }) end
        end
        for _, spell in ipairs(def.heals or {}) do consider(spell, { "Survival" }) end
        return out
    end,
})

-------------------------------------------------------------------------------
-- Gear: upgrades sitting in your bags.
-------------------------------------------------------------------------------

local function bagLinks()
    local links = {}
    local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local linkOf = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
    if not numSlots then return links end
    for bag = 0, 4 do
        for slot = 1, numSlots(bag) or 0 do
            local link = linkOf(bag, slot)
            if link then links[#links + 1] = link end
        end
    end
    return links
end

ns:Register("advisor", "gear", {
    check = function()
        local out = {}
        local level = UnitLevel("player")
        local role = ns:LevelingRole()
        -- Only advise about items you actually have. (An empty slot with
        -- nothing to put in it isn't actionable; an item in your bags for an
        -- empty slot shows up below as an upgrade.)
        for _, link in ipairs(bagLinks()) do
            local c = ns.gear:Compare(link)
            if c and c.canUse and c.item.minLevel <= level and c.diffs[role] >= 0.5 then
                out[#out + 1] = { importance = 90,
                    text = string.format("Equip %s from your bags (+%d %s score)", link,
                        c.diffs[role] + 0.5, ns.ROLE_LABEL[role]),
                    improves = { ns.ROLE_LABEL[role] } }
            end
        end
        return out
    end,
})

-------------------------------------------------------------------------------
-- Talents.
-------------------------------------------------------------------------------

ns:Register("advisor", "talents", {
    check = function()
        -- (Flow Talents reads the count from whichever talent system the client has.)
        local points = (ns.talents and ns.talents.Unspent and ns.talents.Unspent())
            or (UnitCharacterPoints and UnitCharacterPoints("player")) or 0
        if points and points > 0 then
            return { { importance = 85,
                text = string.format("Spend %d talent point(s): Flow Talents says which", points),
                improves = { "DPS", "Survival" },
                open = function() if ns.talents then ns.talents:Show() else ns.commands.spec("") end end,
                openLabel = "Flow Talents (/flow talents)" } }
        end
    end,
})

-------------------------------------------------------------------------------
-- Professions: keep them "on par" with your level (about 5 skill per level),
-- and raise the cap at the trainer when you hit it.
-------------------------------------------------------------------------------

-- English client header names. Riding isn't a profession to level.
local SECTIONS = { ["Professions"] = true, ["Secondary Skills"] = true }
local NOT_PROFESSIONS = { ["Riding"] = true }

-- Returns list, and whether a profession section was collapsed (unreadable).
local function professionSkills()
    local out, collapsed = {}, false
    -- Newer clients (Forever): the profession API.
    if GetProfessions and GetProfessionInfo then
        for _, p in ipairs(ns.api.Professions()) do
            if not p.other and not NOT_PROFESSIONS[p.name] then out[#out + 1] = p end
        end
        return out, false
    end
    if not GetNumSkillLines then return out, true end
    local section
    for i = 1, GetNumSkillLines() do
        local name, isHeader, isExpanded, rank, _, _, maxRank = GetSkillLineInfo(i)
        if isHeader then
            section = name
            if SECTIONS[name] and not isExpanded then collapsed = true end
        elseif SECTIONS[section] and not NOT_PROFESSIONS[name] then
            out[#out + 1] = { name = name, rank = rank or 0, max = maxRank or 0,
                              primary = section == "Professions" }
        end
    end
    return out, collapsed
end

ns:Register("advisor", "professions", {
    check = function()
        local out = {}
        local level = UnitLevel("player")
        -- Targets from the levelling guide: 75 by 10, 125 by 20, 175 by 30,
        -- 200 by 35, 225 by 40, 275 by 50, 300 by 60 (straight line in between).
        local marks = { { 1, 1 }, { 10, 75 }, { 20, 125 }, { 30, 175 }, { 35, 200 },
                        { 40, 225 }, { 50, 275 }, { 60, 300 } }
        local target = 300
        for i = 2, #marks do
            local a, b = marks[i - 1], marks[i]
            if level <= b[1] then
                target = math.floor(a[2] + (b[2] - a[2]) * (level - a[1]) / (b[1] - a[1]))
                break
            end
        end
        local primaries = 0
        local skills, collapsed = professionSkills()
        for _, p in ipairs(skills) do
            if p.primary then primaries = primaries + 1 end
            local tier = ns.skillPlan and ns.skillPlan.Tier and ns.skillPlan.Tier(p.name, p.rank, p.max, level, ns.skillPlan.TierSeen(p.name, p.max))
            if tier and tier.ready then
                out[#out + 1] = { importance = p.rank >= p.max and 60 or 45,
                    -- (Capped: every skill-up since is lost. Red. Close to it: yellow.)
                    urgency = ns.advisor.CapUrgency(p.rank, p.max),
                    text = p.rank >= p.max
                        and string.format("%s is capped at %d: learn %s %s", p.name, p.max, tier.name, p.name)
                        or string.format("%s %d of %d: you can learn %s %s now", p.name, p.rank, p.max, tier.name, p.name),
                    improves = { "Professions" }, goalKey = "train:" .. p.name }
            elseif not p.unsure and p.rank + 15 < (ns.skillPlan and ns.skillPlan.Pace(p.name, level) or target) then
                out[#out + 1] = { importance = 30,
                    text = string.format("%s is %d; aim for about %d at level %d", p.name, p.rank, ns.skillPlan and ns.skillPlan.Pace(p.name, level) or target, level),
                    improves = { "Professions" }, goalKey = "skill:" .. p.name }
            end
        end
        -- Planned professions (class data) you haven't learned yet.
        local _ = ns:ClassData()
        for _, p in ipairs(ns:ProfessionPlan()) do
            if not collapsed and not ns.api.Skill(p.name) then
                local who = ns.places and ns.places:TrainersFor(p.name) or {}
                out[#out + 1] = { importance = p.optional and 25 or 50,
                    text = string.format("Learn %s%s%s", p.name,
                        #who > 0 and (" from " .. table.concat(who, " or ")) or "",
                        p.optional and " (optional)" or ""),
                    improves = { "Professions" }, goalKey = "train:" .. p.name }
                primaries = primaries + 1  -- don't also say "no professions yet"
            end
        end
        if primaries == 0 and level >= 5 and not collapsed then
            out[#out + 1] = { importance = 40,
                text = "No professions yet: see the professions page in your leveling guide",
                improves = { "Gold", "Gear" } }
        end
        return out
    end,
})

-------------------------------------------------------------------------------
-- Rotation habits learned from your best fights.
-------------------------------------------------------------------------------

ns:Register("advisor", "fightInsights", {
    check = function()
        local out = {}
        for key in ns:Each("fightType") do
            for _, text in ipairs((ns.profiler:Insights(key))) do
                out[#out + 1] = { importance = 35, text = text, improves = { "Rotation" } }
            end
        end
        return out
    end,
})

-------------------------------------------------------------------------------
-- Missed quests (see Modules/Quests/QuestData.lua). Needs Questie + QuestieDB.
-- Only the "install Questie" hint: the quests themselves are route steps.
-------------------------------------------------------------------------------

ns:Register("advisor", "missedQuests", {
    check = function()
        if not ns.quests:Source() then
            return { { importance = 25,
                text = "Install Questie + QuestieDB so Flow can spot quests you skipped",
                improves = { "XP", "Quests" } } }
        end
        -- Quests to accept are on the route, the Flow Tracker and the map list;
        -- "Ways to improve" sticks to your character: spells, training, gear,
        -- talents, professions. (/flow missed still lists skipped quests.)
        return {}
    end,
})
