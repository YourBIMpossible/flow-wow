-- What the game itself told Flow: facts that correct Flow's built-in lists.
--
-- "Can you be collecting these kinds of things? How can we start to gather
-- this data so it keeps getting better?" (0.35.220) Flow's class lists and
-- the quest data are approximate on WoW: Forever: Cure Poison isn't taught
-- at 14 here, some quests have no place at all. Each time the game shows
-- the truth, Flow keeps it:
--
--   spells   what a class trainer lists: the spell, its rank, the level it
--            asks, its price                      (read at every trainer)
--   first    the level a trainer first teaches a spell, seen by a character
--            that didn't know it yet (then the list starts at its first
--            rank). It puts the class list's levels right (0.35.310: "rake
--            is lvl 24": Flow kept advising it at 20, from Classic's list,
--            although the trainer had said 24 since level 16)
--   lacks    a spell of Flow's class list that a trainer, read at a level
--            where the list says it's due, doesn't have at all
--   spots    where a quest's objective was done or the quest handed in,
--            for quests the data can't place      (Quests/LearnedSpots.lua)
--
-- Kept for the whole account (FlowDB.facts): game facts only, a class, a
-- level, a spell name, a price, a quest number, a map spot. Nothing about
-- you or your characters. Flow uses them at once: the advice follows what
-- trainers really teach, whichever of your characters saw it.
--
-- Sharing is the same opt-in as the NPC spots: /flow places share lists
-- them in your saved data, tools\share-facts.ps1 merges that list into
-- Learned\Facts.lua, and a pull request brings it to every Flow player
-- (docs/SHARE-PLACES.md). Nothing leaves your computer by itself.
--
--   /flow facts    what Flow has learned, and what came with Flow

local _, ns = ...
local F = {}
ns.facts = F

ns:OnLoad(function(saved)
    saved.facts = saved.facts or {}
    saved.facts.spells = saved.facts.spells or {}
    saved.facts.lacks = saved.facts.lacks or {}
    saved.facts.first = saved.facts.first or {}
    saved.facts.firstAt = saved.facts.firstAt or {}
end)

-- A spell's key: its name, with its rank where the game gives one.
function F.SpellKey(name, rank)
    if type(rank) == "string" and rank ~= "" then return name .. " (" .. rank .. ")" end
    return name
end

-- Pure: one trainer line into the table. The lowest level and price seen
-- win (a trainer never asks more than another for the same rank).
function F.NoteSpell(spells, class, name, rank, level, cost)
    if not (spells and class and type(name) == "string" and name ~= "") then return false end
    spells[class] = spells[class] or {}
    local key = F.SpellKey(name, rank)
    local old = spells[class][key]
    level, cost = tonumber(level) or 0, tonumber(cost) or 0
    if old and (old.level or 0) > 0 and (level == 0 or old.level <= level) then
        if cost > 0 and ((old.cost or 0) == 0 or cost < old.cost) then old.cost = cost end
        return false
    end
    spells[class][key] = { name = name, rank = (type(rank) == "string" and rank ~= "") and rank or nil, level = level, cost = cost }
    return true
end

-- Pure: the level a trainer first teaches a spell, from a character that
-- didn't know it. The lowest seen wins. (A trainer's lowest line for a spell
-- you know is a later rank, Moonfire at 16 rather than 4: so "spells" alone
-- can't say, and a known spell is never noted here.)
function F.NoteFirst(first, class, name, level)
    level = tonumber(level) or 0
    if not (first and class and type(name) == "string" and name ~= "" and level > 0) then return false end
    first[class] = first[class] or {}
    local old = first[class][name]
    if old and old <= level then return false end
    first[class][name] = level
    return true
end

-- Pure: trainer lines read before "first" existed (0.35.310). A spell this
-- character still doesn't know was listed from its first rank whenever it
-- was read, so its lowest level is where it starts. (Lines with a later rank
-- named are left out. On an account with two characters of a class, a line
-- may be the other's; the next trainer visit corrects it.) known: { [name] = true }.
function F.FirstFromSeen(spells, first, class, known)
    local n = 0
    for _, s in pairs(spells and spells[class] or {}) do
        if s.name and not known[s.name] and (s.rank == nil or s.rank == "" or s.rank == "Rank 1")
            and F.NoteFirst(first, class, s.name, s.level) then
            n = n + 1
        end
    end
    return n
end

-- The level a trainer first teaches a spell: the lowest of yours and what
-- came with Flow, and where it came from ("yours" or "shared"). nil: no
-- trainer was seen with it.
function F.FirstLevel(class, name, own, sharedFacts)
    own = own or (ns.db and ns.db.facts) or {}
    sharedFacts = sharedFacts or F.Shared()
    local best, from
    for i, src in ipairs({ own, sharedFacts }) do
        local lv = src.first and src.first[class] and src.first[class][name]
        if lv and (not best or lv < best) then best, from = lv, (i == 1 and "yours" or "shared") end
    end
    return best, from
end

-- Pure: is a learned level believable for a spell the list puts at listLevel?
-- A trainer moves a spell a few levels on WoW: Forever (Rake 20 -> 24), not
-- across the game: a wrong or old line farther than this is not used.
F.MAX_SHIFT = 10
function F.Plausible(level, listLevel)
    level, listLevel = tonumber(level), tonumber(listLevel)
    if not level or level < 1 or level > 60 then return false end
    return not listLevel or math.abs(level - listLevel) <= F.MAX_SHIFT
end

-- Pure: the class list's levels put right by what trainers teach (the list
-- is Flow's guess from Classic; the trainer is the truth). The list's own
-- level is kept as listLevel and is always the base: a learned level is laid
-- over it only while it is believable (F.Plausible), and when the learned
-- level is gone (/flow facts reset) the list's own comes back. Spells from a
-- quest or with a note of their own aren't a trainer's.
-- firstOf(name) -> level, from or nil.
-- -> what changed: { { spell, from, to, source } } (source nil: back to the list).
function F.FixLevels(list, firstOf)
    local changed = {}
    for _, s in ipairs(list or {}) do
        if s.spell and not s.quest and not s.note then
            local base = s.listLevel or s.level
            local lv, from = firstOf(s.spell)
            if not (lv and F.Plausible(lv, base)) then lv, from = base, nil end
            if lv ~= s.level then
                s.listLevel = base
                changed[#changed + 1] = { spell = s.spell, from = s.level, to = lv, source = from }
                s.level = lv
            end
        end
    end
    return changed
end

-- Your class's list, put right now. Said once a spell in the log.
F.fixed = {}
function F.Apply(class)
    local list = class and ns:Get("classSpells", class)
    if not list then return 0 end
    local changed = F.FixLevels(list, function(name) return F.FirstLevel(class, name) end)
    for _, c in ipairs(changed) do
        if c.source then
            local at = c.source == "yours" and ns.db.facts.firstAt and ns.db.facts.firstAt[class]
            c.at = at and at[c.spell] or nil
            F.fixed[c.spell] = c
            ns:Log("facts", string.format("%s: trainers teach it at level %d (Flow's list said %d; %s)", c.spell, c.to, c.from,
                c.source == "yours" and "seen by you" or "came with Flow"))
        else
            F.fixed[c.spell] = nil
            ns:Log("facts", string.format("%s: back to Flow's list, level %d", c.spell, c.to))
        end
    end
    return #changed
end

-- Pure: a class-list spell a trainer doesn't have, read at `level`. Kept at
-- the highest level it was seen missing: "not taught up to level N".
function F.NoteLack(lacks, class, name, level)
    if not (lacks and class and name and level) then return false end
    lacks[class] = lacks[class] or {}
    if (lacks[class][name] or 0) >= level then return false end
    lacks[class][name] = level
    return true
end

-- Pure: which of a class list's spells a trainer's list lacks. list: the
-- class's spells ({ spell, level, quest, note }); names: { [name] = true }
-- the trainer listed; known: your spells; level: yours. Only spells the
-- list says a trainer teaches (no quest, no note) and that are due.
function F.Lacking(list, names, known, level)
    local out = {}
    for _, s in ipairs(list or {}) do
        if s.spell and (s.level or 0) <= level and not s.quest and not s.note
            and not (known and known[s.spell]) and not names[s.spell] then
            out[#out + 1] = s.spell
        end
    end
    return out
end

-- What came with Flow (Learned\Facts.lua, from players who shared).
local shared
function F.Shared()
    if shared then return shared end
    shared = { spells = {}, lacks = {}, spots = {}, first = {} }
    for _, data in ns:Each("sharedFacts") do
        for class, list in pairs(data.first or {}) do
            shared.first[class] = shared.first[class] or {}
            for name, lv in pairs(list) do
                if not shared.first[class][name] or lv < shared.first[class][name] then shared.first[class][name] = lv end
            end
        end
        for class, list in pairs(data.spells or {}) do
            shared.spells[class] = shared.spells[class] or {}
            for key, s in pairs(list) do shared.spells[class][key] = s end
        end
        for class, list in pairs(data.lacks or {}) do
            shared.lacks[class] = shared.lacks[class] or {}
            for name, lv in pairs(list) do shared.lacks[class][name] = math.max(shared.lacks[class][name] or 0, lv) end
        end
        for quest, by in pairs(data.spots or {}) do
            shared.spots[quest] = shared.spots[quest] or {}
            for index, pts in pairs(by) do shared.spots[quest][index] = pts end
        end
    end
    return shared
end
function F.ResetShared() shared = nil end   -- (tests)

-- Is this class-list spell known not to be taught up to `level`? Yours
-- first, then what came with Flow. (A spell seen at a trainer since beats
-- an older "lacks".)
function F.NotTaught(class, name, level, own, sharedFacts)
    own = own or (ns.db and ns.db.facts) or {}
    sharedFacts = sharedFacts or F.Shared()
    for _, src in ipairs({ own, sharedFacts }) do
        for _, s in pairs(src.spells and src.spells[class] or {}) do
            if s.name == name then return false end   -- a trainer does list it
        end
    end
    for _, src in ipairs({ own, sharedFacts }) do
        local lv = src.lacks and src.lacks[class] and src.lacks[class][name]
        if lv and lv >= level then return true end
    end
    return false
end

-- A learned spot for a quest that came with Flow (yours are in LearnedSpots).
function F.SharedSpots(questID, index)
    local by = F.Shared().spots[questID]
    local pts = by and by[index]
    if type(pts) ~= "table" or #pts == 0 then return nil end
    local out = {}
    for _, p in ipairs(pts) do out[#out + 1] = { map = p[1] or p.map, x = p[2] or p.x, y = p[3] or p.y } end
    return out
end

-- A class trainer was read (Trainer.lua): its lines, and what it lacks.
--   services: { { name, sub, level, cost } }
function F.TrainerRead(class, services, level, known)
    if not (ns.db and ns.db.facts and class) then return 0 end
    local n, names = 0, {}
    ns.db.facts.first = ns.db.facts.first or {}
    local firsts = 0
    for _, s in ipairs(services or {}) do
        names[s.name] = true
        if F.NoteSpell(ns.db.facts.spells, class, s.name, s.sub, s.level, s.cost) then n = n + 1 end
        if known and not known[s.name] and (s.sub == nil or s.sub == "" or s.sub == "Rank 1")
            and F.NoteFirst(ns.db.facts.first, class, s.name, s.level) then
            n, firsts = n + 1, firsts + 1
            ns.db.facts.firstAt = ns.db.facts.firstAt or {}
            ns.db.facts.firstAt[class] = ns.db.facts.firstAt[class] or {}
            ns.db.facts.firstAt[class][s.name] = time()
        end
    end
    if firsts > 0 and class == select(2, UnitClass("player")) then F.Apply(class) end
    for _, name in ipairs(F.Lacking(ns:Get("classSpells", class), names, known, level)) do
        if F.NoteLack(ns.db.facts.lacks, class, name, level) then
            n = n + 1
            ns:Log("facts", string.format("%s: a level %d trainer has no %s (Flow's list said it would)", class, level, name))
        end
    end
    if n > 0 then ns:Log("facts", string.format("%s trainer read at level %d: %d new fact(s)", class, level, n)) end
    return n
end

-------------------------------------------------------------------------------
-- Sharing (with /flow places share; tools\share-facts.ps1)
-------------------------------------------------------------------------------
--   "S|CLASS|spell|rank|level|cost"   a trainer's line (rank may be empty)
--   "L|CLASS|spell|level"             a class-list spell no trainer had up to that level
--   "F|CLASS|spell|level"             the level a trainer first teaches a spell
--   "Q|questID|index|map|x|y"         where an objective was done (index: a number, or "done")
function F.ShareLines(facts, spots)
    local lines = {}
    local function clean(s) return type(s) == "string" and not s:find("[|\n\"\\]") and #s <= 64 end
    for class, list in pairs(facts and facts.spells or {}) do
        for _, s in pairs(list) do
            if clean(class) and clean(s.name) and (s.rank == nil or clean(s.rank)) then
                lines[#lines + 1] = string.format("S|%s|%s|%s|%d|%d", class, s.name, s.rank or "", s.level or 0, s.cost or 0)
            end
        end
    end
    for class, list in pairs(facts and facts.lacks or {}) do
        for name, lv in pairs(list) do
            if clean(class) and clean(name) then lines[#lines + 1] = string.format("L|%s|%s|%d", class, name, lv) end
        end
    end
    for class, list in pairs(facts and facts.first or {}) do
        for name, lv in pairs(list) do
            if clean(class) and clean(name) then lines[#lines + 1] = string.format("F|%s|%s|%d", class, name, lv) end
        end
    end
    for quest, by in pairs(spots or {}) do
        for index, pts in pairs(by) do
            for _, p in ipairs(pts) do
                if type(quest) == "number" and p.map and p.x and p.y then
                    lines[#lines + 1] = string.format("Q|%d|%s|%d|%.4f|%.4f", quest, tostring(index), p.map, p.x, p.y)
                end
            end
        end
    end
    table.sort(lines)
    return lines
end

-------------------------------------------------------------------------------
-- /flow facts
-------------------------------------------------------------------------------
local function count(t)
    local n = 0
    for _, list in pairs(t or {}) do for _ in pairs(list) do n = n + 1 end end
    return n
end
function F.Lines()
    local own, sh = ns.db.facts or {}, F.Shared()
    local spots = 0
    for _, by in pairs(ns.db.learnedSpots or {}) do for _, pts in pairs(by) do spots = spots + #pts end end
    local out = { string.format("Flow has learned from the game: %d trainer line(s), %d spell(s) trainers don't have, %d quest spot(s)",
        count(own.spells), count(own.lacks), spots) }
    out[#out + 1] = string.format("  came with Flow (shared by players): %d trainer line(s), %d missing spell(s), %d quest(s) with spots",
        count(sh.spells), count(sh.lacks), (function() local n = 0; for _ in pairs(sh.spots) do n = n + 1 end; return n end)())
    out[#out + 1] = string.format("  first levels: %d of yours, %d came with Flow", count(own.first), count(sh.first))
    for class, list in pairs(own.lacks or {}) do
        for name, lv in pairs(list) do
            out[#out + 1] = string.format("  %s: no trainer had %s up to level %d", class, name, lv)
        end
    end
    local fixed = {}
    for _, c in pairs(F.fixed) do
        local age = c.at and math.floor((time() - c.at) / 86400)
        fixed[#fixed + 1] = string.format("%s %d -> %d (%s%s)", c.spell, c.from, c.to,
            c.source == "yours" and "seen by you" or "came with Flow", age and string.format(", %d day(s) ago", age) or "")
    end
    table.sort(fixed)
    if #fixed > 0 then out[#out + 1] = "  your class list put right by trainers: " .. table.concat(fixed, ", ") end
    out[#out + 1] = "  share them with every Flow player: /flow places share (game facts only, nothing about you)"
    out[#out + 1] = "  a level wrong? /flow facts reset forgets the first levels you learned; the list's own come back"
    return out
end
-- At login: "first" filled from trainer lines read before it existed (once
-- the spellbook is in, to know which spells you have), then your class's
-- list put right. (Again after each trainer visit: TrainerRead.)
ns:On("PLAYER_LOGIN", function()
    C_Timer.After(3, function()
        local _, class = UnitClass("player")
        local ok, known = pcall(function() return ns.rotation and ns.rotation:KnownSpells() end)
        if ok and type(known) == "table" and next(known) and ns.db.facts then
            ns.db.facts.first = ns.db.facts.first or {}
            local n = F.FirstFromSeen(ns.db.facts.spells, ns.db.facts.first, class, known)
            if n > 0 then ns:Log("facts", string.format("%d first level(s) taken from trainer lines read before", n)) end
        end
        F.Apply(class)
    end)
end)

-- Pure: forget the first levels this account learned (what came with Flow
-- stays: it is in the addon). -> how many were forgotten.
function F.ResetFirst(facts)
    local n = 0
    if not facts then return n end
    for _, list in pairs(facts.first or {}) do for _ in pairs(list) do n = n + 1 end end
    facts.first, facts.firstAt = {}, {}
    return n
end

ns.commands.facts = function(arg)
    if arg == "reset" then
        local n = F.ResetFirst(ns.db.facts)
        F.Apply(select(2, UnitClass("player")))
        ns:Print(string.format("forgot %d first level(s) you learned; your class list uses its own levels again (what came with Flow still applies)", n))
        return
    end
    for i, l in ipairs(F.Lines()) do if i == 1 then ns:Print(l) else print(l) end end
end
ns:Register("help", "facts", { order = 61, title = "What Flow learns from the game", lines = {
    "What trainers really teach, which listed spells they don't have, and where unplaced quests were done: kept and used at once.",
    "/flow facts: the count. /flow facts reset: forget the first levels you learned. /flow places share lists them for sharing (docs/SHARE-PLACES.md).",
} })
