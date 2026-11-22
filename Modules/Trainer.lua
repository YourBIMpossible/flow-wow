-- Training nudges. The rotation helper ignores spells you haven't learned and
-- picks each one up as soon as you learn it. This module tells you when
-- there's something new to learn.

local _, ns = ...
local TR = {}
ns.trainer = TR

-- Is this your class trainer? Not a profession trainer, and not a riding (or
-- other) trainer: one of your class's trainers by name, or what it teaches
-- includes your class's spells. (Kar Stormsinger, the tauren riding trainer,
-- was taken for a druid's class trainer: every trainer that wasn't a
-- profession trainer counted, and his riding lessons replaced the spell list.)
--   services: names it teaches; classSet: { [spell] = true }; classTrainers: names
function TR.IsClassTrainer(name, services, classSet, classTrainers, isTrade)
    if isTrade then return false end
    for _, n in ipairs(classTrainers or {}) do if n == name then return true end end
    for _, s in ipairs(services or {}) do if classSet[s] then return true end end
    return false
end

local function classTrainerCheck(name, services, isTrade)
    local _, class = UnitClass("player")
    return TR.IsClassTrainer(name, services, ns:ClassSpellSet(class),
        ns.places and ns.places:TrainersFor("class:" .. class) or {}, isTrade)
end

local CATEGORIES = { available = true, unavailable = true, used = true, header = true }

-- Classic clients return (name, rankText, category); newer ones, Forever
-- included, return (name, category, icon). Returns name, category, rankText, modern.
local function serviceInfo(i)
    local name, a, b = GetTrainerServiceInfo(i)
    if CATEGORIES[a] then return name, a, nil, true end
    return name, b, a, false
end

local function listAvailable()
    if not GetNumTrainerServices then return end
    local money = GetMoney()
    local any = false
    for i = 1, GetNumTrainerServices() do
        local name, category, sub = serviceInfo(i)
        if category == "available" then
            local cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or 0
            local afford = cost <= money
            if not any then ns:Print("you can learn here:") end
            any = true
            print(string.format("  %s%s%s - %s%s|r",
                afford and "|cff66ff66" or "|cffff6666", name,
                (sub and sub ~= "") and (" (" .. sub .. ")") or "",
                ns.Money(cost),
                afford and "" or " (can't afford)"))
        end
    end
    if not any then ns:Print("nothing new to learn here right now.") end
end

-- Remember what the trainer offers, so the advisor can say "you can train X
-- now" later, using the real list for this game version.
local function record()
    if not GetNumTrainerServices then return end
    local list, names = {}, {}
    for i = 1, GetNumTrainerServices() do
        local name, category, sub, modern = serviceInfo(i)
        if name and category ~= "header" then
            names[#names + 1] = name
            list[#list + 1] = {
                name = name, sub = sub or "", category = category, modern = modern,
                level = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i) or 0,
                cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or 0,
            }
        end
    end
    -- Class trainers only (where "go train" errands send you).
    local npc = ns.api.Safe(UnitName("npc"))
    if #list == 0 or not classTrainerCheck(npc, names, IsTradeskillTrainer and IsTradeskillTrainer()) then return end
    ns.db.trainer.npc = npc
    ns.db.trainer.services = list
    ns.db.trainer.seenAt = UnitLevel("player")
    -- What this trainer really teaches (and doesn't), kept for good: Facts.lua.
    if ns.facts and ns.facts.TrainerRead then
        local _, class = UnitClass("player")
        pcall(ns.facts.TrainerRead, class, list, UnitLevel("player"), ns.rotation and ns.rotation:KnownSpells() or nil)
    end
end

-- A riding (or other) trainer saved as your class trainer before 0.35.90:
-- forgotten, so the errands use your class's trainers again.
ns:On("PLAYER_LOGIN", function()
    local t = ns.db.trainer
    if not (t and t.npc) then return end
    local names = {}
    for _, s in ipairs(t.services or {}) do names[#names + 1] = s.name end
    if not classTrainerCheck(t.npc, names, false) then
        ns:Log("trainer", "forgot " .. tostring(t.npc) .. " as your class trainer (not a trainer for your class)")
        t.npc, t.services = nil, nil
    end
end)

ns:OnLoad(function(saved) saved.trainer = saved.trainer or {} end)
-- What your class trainer offers is your character's. The old shared copy
-- goes to the class it lists spells of.
ns:PerCharacter("trainer", { adopt = function(old, ctx)
    local mine = ns:ClassSpellSet(ctx.class)
    for _, s in ipairs(old.services or {}) do
        if mine[s.name] then return old end
    end
    return nil
end })

-------------------------------------------------------------------------------
-- What a profession trainer asks for the next tier (Journeyman, Expert,
-- Artisan). Flow's own numbers are classic's (skill 50 and level 10 for
-- Journeyman); WoW: Forever's differ, and the only place that says what they
-- are is the trainer's own list. So each time you open a profession trainer
-- the next tier's line is read: the level and skill it asks for, its price,
-- and whether you can learn it now. The route goes by that from then on
-- (SkillPlan SP.Tier): no more trips to a trainer who'll only say "not yet".
-------------------------------------------------------------------------------

-- Pure: the tier's line among a trainer's services ({ name, sub, category }).
function TR.TierService(services, tierName)
    if not tierName then return nil end
    for _, s in ipairs(services or {}) do
        if s.category ~= "used" and s.category ~= "header"
            and ((s.name or ""):find(tierName, 1, true) or (s.sub or ""):find(tierName, 1, true)) then
            return s
        end
    end
end

-- Pure: "level 50 and Skinning 125" from what a tier asks for.
function TR.TierAsks(prof, level, skill)
    local bits = {}
    if (level or 0) > 0 then bits[#bits + 1] = "level " .. level end
    if (skill or 0) > 0 then bits[#bits + 1] = prof .. " " .. skill end
    return #bits > 0 and table.concat(bits, " and ") or nil
end

-- Pure: keep the skill a trainer asked for each thing it teaches, as read
-- from its window. into: { [service name] = skill }. Only what the game gave
-- as a number is kept; headers and unreadable rows change nothing.
function TR.RecordLearn(into, name, category, need)
    if type(into) ~= "table" or type(name) ~= "string" or name == "" or category == "header" then return false end
    if type(need) ~= "number" or need < 0 then return false end
    into[name] = need
    return true
end

function TR.ReadTier()
    if not GetNumTrainerServices then return end
    local prof = ns.places and ns.places.TrainerProfession and ns.places.TrainerProfession()
    if not prof then return end
    local rank, max = ns.api.Skill(prof)
    local SP = ns.skillPlan
    local tierName = SP and SP.TierName and SP.TierName(max)
    -- What each recipe asks, as this trainer shows it (the skill plan's only
    -- source for it: SP.LearnSkill). Read before the tier check below, so a
    -- profession at its last tier still records.
    local learn
    if ns.db and type(ns.db.prof) == "table" then
        ns.db.prof.recipeLearn = ns.db.prof.recipeLearn or {}
        ns.db.prof.recipeLearn[prof] = ns.db.prof.recipeLearn[prof] or {}
        learn = ns.db.prof.recipeLearn[prof]
    end
    local list = {}
    for i = 1, GetNumTrainerServices() do
        local name, category, sub = serviceInfo(i)
        local skill = 0
        if GetTrainerServiceSkillReq then
            local ok, _, need = pcall(GetTrainerServiceSkillReq, i)
            if ok and type(need) == "number" then
                skill = need
                TR.RecordLearn(learn, name, category, need)
            end
        end
        list[#list + 1] = { name = name, sub = sub, category = category, skill = skill,
                            level = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i) or 0,
                            cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or 0 }
    end
    if not (rank and tierName) then return end
    local s = TR.TierService(list, tierName)
    if not s then return end
    ns.db.prof.tierSeen = ns.db.prof.tierSeen or {}
    local was = ns.db.prof.tierSeen[prof]
    ns.db.prof.tierSeen[prof] = { cap = max, name = s.name, category = s.category, level = s.level or 0, skill = s.skill or 0,
                                  cost = s.cost or 0, atLevel = UnitLevel("player"), atRank = rank }
    if was and was.cap == max and was.category == s.category and was.level == (s.level or 0) and was.skill == (s.skill or 0) then return end
    local asks = TR.TierAsks(prof, s.level, s.skill)
    ns:Log("trainer", string.format("%s %s: %s at the trainer; asks for %s; costs %s", tierName, prof, tostring(s.category),
        asks or "nothing Flow can read", tostring(s.cost)))
    if s.category == "unavailable" then
        ns:Print(string.format("%s %s isn't yours to learn yet%s. Flow takes it off your route until it is.", tierName, prof,
            asks and (": the trainer asks for " .. asks) or ""))
    end
    if ns.nav and ns.nav.RequestCollect then ns.nav.RequestCollect("a profession trainer read") end
end

ns:On("TRAINER_SHOW", function()
    -- Trainer list fills in a moment after the window opens.
    C_Timer.After(0.2, function() pcall(listAvailable); pcall(record); pcall(TR.ReadTier) end)
end)

ns:On("TRAINER_UPDATE", function() pcall(record); pcall(TR.ReadTier) end)

ns:On("PLAYER_LEVEL_UP", function(level)
    ns:Print(string.format("level %d! Visit your class trainer: you may have new spells or ranks to learn.", level))
end)
