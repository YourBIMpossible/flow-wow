local _, ns = ...

-- Facts learned from the game (S26): what class trainers really teach on
-- this client, kept for the whole account so every character's advice can
-- follow it. Ported from legacy Flow's Modules/Facts.lua (0.35.220 and
-- 0.35.310), which ran on this client; research:
-- WoW/from-plexy/RESEARCH-facts.md.
--
-- Stored exactly as legacy Flow stored them, at the places the importer
-- (Import/FromFlow.lua) already fills, so imported and new facts merge:
--   account learned.facts.spells[class][key] = { name, rank, level, cost }
--     key: the name, with " (rank)" where the game gives a rank. The lowest
--     level and price seen win.
--   account learned.facts.first[class][name] = level
--     the level a trainer first teaches a spell, seen by a character that
--     did not know it yet. The lowest seen wins.
--   account learned.facts.firstAt[class][name] = when (client.clock())
--   account learned.facts.lacks[class][name] = level   (imported only: the
--     class list legacy Flow compared with is not ported; see the note)
-- Game facts only: a class, a spell, a rank, a level, a price. Nothing about
-- the player. Nothing leaves the computer.
--
--   Facts.SpellKey(name, rank)
--   Facts.NoteSpell(spells, class, name, rank, level, cost) -> changed
--   Facts.NoteFirst(first, class, name, level) -> changed
--   Facts.TrainerRead(facts, class, rows, when) -> how many new facts
--     rows: client.trainer().services ({ name, rank, state, cost, level });
--     a row whose state is "known" is a spell this character knows.
--   Facts.Lines(facts) -> lines for /zflow facts
--   Facts.ResetFirst(facts) -> how many first levels were dropped
--     ("facts reset", F-new-4: first and firstAt only)
--   Facts.Declare(k, diag) -> api   (api.read() -> the last TrainerRead count)
--
-- Only a class trainer is read: a trainer window whose profession the
-- client does not name. Whether this client names none for a class trainer
-- needs a game test (the note says how to check).
local F = {}
ns.Facts = F

F.NAME = "facts"
F.WORD = "facts"
F.PATH = "learned.facts"
F.HELP = "what " .. ns.id.title .. " has learned from class trainers on this game"

local function whole(v)
    return type(v) == "number" and v == v and v >= 0 and v ~= math.huge and v == math.floor(v)
end

function F.SpellKey(name, rank)
    if type(rank) == "string" and rank ~= "" then return name .. " (" .. rank .. ")" end
    return name
end

function F.NoteSpell(spells, class, name, rank, level, cost)
    if type(spells) ~= "table" or type(class) ~= "string" or type(name) ~= "string" or name == "" then return false end
    spells[class] = spells[class] or {}
    local key = F.SpellKey(name, rank)
    local old = spells[class][key]
    level = whole(level) and level or 0
    cost = whole(cost) and cost or 0
    if type(old) == "table" and whole(old.level) and old.level > 0 and (level == 0 or old.level <= level) then
        if cost > 0 and (not whole(old.cost) or old.cost == 0 or cost < old.cost) then
            old.cost = cost
            return true
        end
        return false
    end
    spells[class][key] = { name = name, rank = (type(rank) == "string" and rank ~= "") and rank or nil,
                           level = level, cost = cost }
    return true
end

function F.NoteFirst(first, class, name, level)
    if type(first) ~= "table" or type(class) ~= "string" or type(name) ~= "string" or name == "" then return false end
    if not whole(level) or level <= 0 then return false end
    first[class] = first[class] or {}
    local old = first[class][name]
    if whole(old) and old <= level then return false end
    first[class][name] = level
    return true
end

function F.TrainerRead(facts, class, rows, when)
    if type(facts) ~= "table" or type(class) ~= "string" or type(rows) ~= "table" then return 0 end
    facts.spells = type(facts.spells) == "table" and facts.spells or {}
    facts.first = type(facts.first) == "table" and facts.first or {}
    facts.firstAt = type(facts.firstAt) == "table" and facts.firstAt or {}
    local known = {}
    for _, r in ipairs(rows) do
        if type(r) == "table" and r.state == "known" and type(r.name) == "string" then known[r.name] = true end
    end
    local n = 0
    for _, r in ipairs(rows) do
        if type(r) == "table" and type(r.name) == "string" then
            if F.NoteSpell(facts.spells, class, r.name, r.rank, r.level, r.cost) then n = n + 1 end
            -- The first rank of a spell this character does not know: its
            -- lowest line is where the trainer starts teaching it.
            if not known[r.name] and (r.rank == nil or r.rank == "" or r.rank == "Rank 1")
                and F.NoteFirst(facts.first, class, r.name, r.level) then
                n = n + 1
                facts.firstAt[class] = type(facts.firstAt[class]) == "table" and facts.firstAt[class] or {}
                facts.firstAt[class][r.name] = whole(when) and when or nil
            end
        end
    end
    return n
end

local function count(t)
    local n = 0
    for _, list in pairs(type(t) == "table" and t or {}) do
        if type(list) == "table" then for _ in pairs(list) do n = n + 1 end end
    end
    return n
end

function F.Lines(facts)
    facts = type(facts) == "table" and facts or {}
    local out = { string.format("learned from the game: %d trainer line(s), %d first level(s), %d spell(s) trainers did not have",
        count(facts.spells), count(facts.first), count(facts.lacks)) }
    local classes = {}
    for class in pairs(type(facts.first) == "table" and facts.first or {}) do classes[#classes + 1] = class end
    table.sort(classes)
    for _, class in ipairs(classes) do
        local names = {}
        for name, lv in pairs(facts.first[class]) do
            if whole(lv) then names[#names + 1] = name .. " " .. lv end
        end
        table.sort(names)
        if #names > 0 then out[#out + 1] = "  " .. class .. ", first taught at: " .. table.concat(names, ", ") end
    end
    return out
end

-- Drops every first level (and when each was seen), the part of the facts
-- a wrong trainer read can spoil. -> how many first levels there were.
function F.ResetFirst(facts)
    local n = 0
    if type(facts) ~= "table" then return n end
    for _, list in pairs(type(facts.first) == "table" and facts.first or {}) do
        if type(list) == "table" then
            for _ in pairs(list) do n = n + 1 end
        end
    end
    facts.first, facts.firstAt = {}, {}
    return n
end

function F.Declare(k, diag)
    local api = {}
    local ctx, last = nil, nil
    function api.read() return last end

    local function facts()
        local saved = ctx and ctx.store:get("account", F.PATH)
        return type(saved) == "table" and saved or {}
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[F.WORD] = function(rest)
            if rest == "reset" then
                -- A wrong first level (a trainer read on an odd character)
                -- can be dropped; what trainers teach and the imported
                -- facts stay. A refused save leaves everything as it was.
                local copy = {}
                for key, v in pairs(facts()) do copy[key] = v end
                local n = F.ResetFirst(copy)
                local said = "could not save; nothing was reset."
                if not ctx then
                    said = "not started yet; nothing was reset."
                elseif ctx.store:set("account", F.PATH, copy) == true then
                    said = ("dropped %d first level(s) learned from class trainers; the next trainer visit learns them again."):format(n)
                end
                k.client.print(k.id.title .. ": " .. said)
                return
            end
            for _, line in ipairs(F.Lines(facts())) do k.client.print(k.id.title .. ": " .. line) end
            k.client.print(k.id.title .. ": " .. ("  a first level wrong? %s %s reset drops them all."):format(k.id.slash, F.WORD))
        end
        if type(diag.help) == "table" then diag.help[F.WORD] = F.HELP end
    end

    k:Module({
        name = F.NAME,
        needs = { "client", "store", "bus" },
        provides = { Read = api.read },
        start = function(c)
            ctx = c
            if type(c.client.watchTrainer) == "function" then c.client.watchTrainer() end
            c.bus:on(F.NAME, "TRAINER_SHOW", function()
                local client = c.client
                local reading = type(client.trainer) == "function" and client.trainer() or nil
                if type(reading) ~= "table" or reading.profession ~= nil or type(reading.services) ~= "table" then return end
                local class = type(client.class) == "function" and client.class() or nil
                if type(class) ~= "string" or class == "" then return end
                -- A copy is changed and saved whole: a refused save leaves
                -- the saved facts as they were.
                local copy = {}
                for key, v in pairs(facts()) do copy[key] = v end
                for _, part in ipairs({ "spells", "first", "firstAt" }) do
                    local src, dst = copy[part], {}
                    for cl, list in pairs(type(src) == "table" and src or {}) do
                        dst[cl] = {}
                        for name, v in pairs(type(list) == "table" and list or {}) do
                            if type(v) == "table" then
                                local row = {}
                                for f2, x in pairs(v) do row[f2] = x end
                                dst[cl][name] = row
                            else
                                dst[cl][name] = v
                            end
                        end
                    end
                    copy[part] = dst
                end
                local when = type(client.clock) == "function" and client.clock() or nil
                local n = F.TrainerRead(copy, class, reading.services, when)
                last = n
                if n > 0 then c.store:set("account", F.PATH, copy) end
            end)
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.facts = F.Declare(ns, ns.diag)
