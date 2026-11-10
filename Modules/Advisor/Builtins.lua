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
            if learnable and s.level <= level then
                local info = classSpellInfo(s.name)
                out[#out + 1] = {
                    importance = 80,
                    text = string.format("Train %s%s at your class trainer", s.name,
                        s.sub ~= "" and (" (" .. s.sub .. ")") or ""),
                    improves = info and info.improves or { "Stronger rank" },
                    goalKey = "train:class",
                    cost = s.cost,  -- copper, from your last visit (route skips it until you can pay)
                }
                listed[s.name] = true
            end
        end

        -- 2. Guide data for spells you've never seen at a trainer yet.
        for _, s in ipairs(ns:Get("classSpells", classToken()) or {}) do
            if s.level <= level and not known[s.spell] and not listed[s.spell] then
                out[#out + 1] = {
                    importance = 75,
                    text = string.format("Get %s (level %d%s)", s.spell, s.level,
                        s.note and (", " .. s.note) or ", class trainer"),
                    improves = s.improves,
                    goalKey = not s.note and "train:class" or nil,   -- (its link: your class trainer's stop)
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
        local points = UnitCharacterPoints and UnitCharacterPoints("player") or 0
        if points and points > 0 then
            return { { importance = 85,
                text = string.format("Spend %d talent point(s): /flow spec for the plan", points),
                improves = { "DPS", "Survival" },
                open = function() ns.commands.spec("") end, openLabel = "the talent plan (/flow spec)" } }
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
            if p.max > 0 and p.rank >= p.max and p.max < 300 then
                out[#out + 1] = { importance = 60,
                    text = string.format("%s is capped at %d (max %d): train the next tier", p.name, p.rank, p.max),
                    improves = { "Professions" }, goalKey = "train:" .. p.name }
            elseif p.rank + 15 < (ns.skillPlan and ns.skillPlan.Pace(p.name, level) or target) then
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
-- Only the "install Questie" hint: the quests themselves are route stops.
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
