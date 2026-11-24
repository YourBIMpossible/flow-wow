local _, ns = ...

-- The profession reminder card (G18): for a profession at its cap with a
-- trainer this character has seen, one short prompt in the advisor (U-A).
--
-- Pure. Readings and trainers come in exactly as Nav/ProfSeen.lua saves
-- them: char "learned.facts.profSkill"[name] = { skill, max, ... } and
-- account "learned.places.npcs"[npc].trains[profession] = true. Nothing is
-- guessed: a reading without numeric skill and max, or a max not above 0,
-- gives no prompt.
--
-- The advisor is handed in (ctx.use("advisor") once wired, or a fake in
-- tests) and needs only Add(id, text, priority) and Remove(id). Sync adds
-- and removes only ids it added itself ("aps.prof.<profession>").
--
-- Faction (review zflow-aps-a-b-0c77057): the same rule as
-- Nav/ProfStep.lua: a trainer is named only when the player's faction is
-- a known string and the npc's saved factions mark it true. Another
-- faction's trainer, an npc with no factions and an unknown player faction
-- name nobody.
--
-- The module (F5, was U-F): P.Declare(k) needs the advisor and ProfSeen,
-- so it starts after both and hears each event after ProfSeen has saved
-- what the event brought. It calls Sync when the character enters the
-- world, when the recipe list changes and when a trainer window opens: a
-- prompt appears when its cause does and is removed when its cause goes
-- (the cap was raised, or the faction is no longer known). Stopped, it
-- removes what it added. Look-only: it trains, buys and changes nothing.
-- Not tested in game.

ns.ProfCard = {}
local P = ns.ProfCard

P.NAME = "profCard"
P.ADVISOR = "advisor"
P.SEEN = "profSeen"
P.ENTER_EVENT = "PLAYER_ENTERING_WORLD"
P.PREFIX = "aps.prof."
P.PRIORITY = 1
P.LISTS = "learned.trainerLists" -- Spells/TrainerModule.lua M.PATH

local function num(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

-- Sorted names of the trainers seen for one profession.
local function trainersFor(npcs, profession, faction)
    local names = {}
    for npc, e in pairs(npcs) do
        if type(npc) == "string" and npc ~= "" and type(e) == "table" and type(e.trains) == "table" and e.trains[profession] == true
            and type(e.factions) == "table" and e.factions[faction] == true then
            names[#names + 1] = npc
        end
    end
    table.sort(names)
    return names
end

-- P-PROF slice 3 (Lazy): the next rank of a profession from the saved
-- trainer lists (Spells/TrainerModule.lua, char "learned.trainerLists"), as
-- Flow's SkillPlan TierPriceLine: a row not known, of this profession, whose
-- rank is one of P.RANKS (in rank, or "<rank> <profession>" as its name;
-- first guess, needs a game test) and whose cost was read. The cheapest
-- such row. Returns rank, copper, or nil.
P.RANKS = { Apprentice = true, Journeyman = true, Expert = true, Artisan = true, Master = true }
local function nextRank(lists, profession)
    if type(lists) ~= "table" then return nil end
    local bestRank, bestCost = nil, nil
    for _, l in pairs(lists) do
        if type(l) == "table" and l.profession == profession and type(l.rows) == "table" then
            for _, r in ipairs(l.rows) do
                if type(r) == "table" and r.state ~= "known" and num(r.cost) and type(r.name) == "string" then
                    local rank = nil
                    if r.name == profession and type(r.rank) == "string" and P.RANKS[r.rank] then rank = r.rank end
                    local head = r.name:match("^(%S+) " .. profession:gsub("(%p)", "%%%1") .. "$")
                    if head and P.RANKS[head] then rank = head end
                    if rank and (bestCost == nil or r.cost < bestCost) then bestRank, bestCost = rank, r.cost end
                end
            end
        end
    end
    return bestRank, bestCost
end

-- { { id =, text =, priority = }, ... } sorted by id. lists (slice 3,
-- optional): the saved trainer lists, for the next rank's price.
function P.Prompts(readings, npcs, faction, lists)
    local out = {}
    if type(readings) ~= "table" or type(npcs) ~= "table" then return out end
    if type(faction) ~= "string" or faction == "" then return out end
    for name, r in pairs(readings) do
        if type(name) == "string" and name ~= "" and type(r) == "table"
            and num(r.skill) and num(r.max) and r.max > 0 and r.skill >= r.max then
            local seen = trainersFor(npcs, name, faction)
            if #seen > 0 then
                local who = seen[1]
                if #seen > 1 then who = who .. ", and " .. (#seen - 1) .. " more" end
                local text = string.format("%s is at its cap (%d/%d). Trainer seen: %s.", name, r.skill, r.max, who)
                local rank, cost = nextRank(lists, name)
                if rank then text = text .. " " .. rank .. " costs " .. ns.Prices.Coin(cost) .. "." end
                out[#out + 1] = {
                    id = P.PREFIX .. name,
                    text = text,
                    priority = P.PRIORITY,
                }
            end
        end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

-- Puts the current prompts in the advisor and removes the ones this card
-- added before that no longer apply. faction: the player's faction.
-- shown: { [id] = true } from the last call (nil the first time). Returns
-- the new shown set.
function P.Sync(advisor, readings, npcs, faction, shown, lists)
    local now = {}
    if type(advisor) ~= "table" or type(advisor.Add) ~= "function" or type(advisor.Remove) ~= "function" then
        return now
    end
    for _, p in ipairs(P.Prompts(readings, npcs, faction, lists)) do
        if advisor.Add(p.id, p.text, p.priority) then now[p.id] = true end
    end
    if type(shown) == "table" then
        for id in pairs(shown) do
            if type(id) == "string" and id:sub(1, #P.PREFIX) == P.PREFIX and not now[id] then
                advisor.Remove(id)
            end
        end
    end
    return now
end

-- The module. api.shown(): a copy of the ids now in the advisor.
function P.Declare(k)
    local api = {}
    local shown, advisor = {}, nil
    function api.shown()
        local out = {}
        for id in pairs(shown) do out[id] = true end
        return out
    end

    local function clear()
        if type(advisor) == "table" and type(advisor.Remove) == "function" then
            for id in pairs(shown) do pcall(advisor.Remove, id) end
        end
        shown = {}
    end

    k:Module({
        name = P.NAME,
        needs = { "client", "store", "bus", P.ADVISOR, P.SEEN },
        provides = { Shown = api.shown },
        start = function(ctx)
            local Seen = ns.ProfSeen
            local function sync()
                local okA, found = pcall(ctx.use, P.ADVISOR)
                if not okA or type(found) ~= "table" then return end
                advisor = found
                local faction = nil
                if type(ctx.client.faction) == "function" then
                    local okF, f = pcall(ctx.client.faction)
                    if okF then faction = f end
                end
                -- An advisor that raises costs this module nothing; what it
                -- held before is kept as it was.
                local okS, now = pcall(P.Sync, advisor, ctx.store:get("char", Seen.READINGS),
                    ctx.store:get("account", Seen.NPCS), faction, shown, ctx.store:get("char", P.LISTS))
                if okS and type(now) == "table" then shown = now end
            end
            ctx.bus:on(P.NAME, P.ENTER_EVENT, sync)
            ctx.bus:on(P.NAME, Seen.RECIPES_EVENT, sync)
            ctx.bus:on(P.NAME, Seen.TRAINER_EVENT, sync)
        end,
        stop = clear,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.profCard = P.Declare(ns)
