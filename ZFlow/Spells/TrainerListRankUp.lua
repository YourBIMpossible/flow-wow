local _, ns = ...

-- Rank-up reminder (A-E): when A-D's trainer lists show a higher rank of a
-- spell the player knows, at the player's level, one advisor prompt naming
-- the spell, the rank and the trainer. The prompt goes once the rank is
-- learned. Look-only: it trains nothing.
--
-- Pure. lists are as Spells/TrainerList.lua stores them; knownRanks is
-- { [spell name] = highest known rank number } from the spellbook when the
-- caller has it ({} otherwise); level is the player's level. A spell is
-- "known" at the highest rank found in knownRanks or in a trainer row whose
-- state is "known". Only ranks written "Rank N" are compared, a row without
-- a level is skipped and no level means no prompts: nothing is guessed.
--
-- The advisor (U-A) is handed in: Add(id, text, priority), Remove(id).
-- Sync only removes "aps.rankup.*" ids it added itself.

ns.TrainerListRankUp = {}
local R = ns.TrainerListRankUp

R.PREFIX = "aps.rankup."
R.PRIORITY = 1

local function rankNumber(rank)
    if type(rank) ~= "string" then return nil end
    local n = rank:match("^Rank (%d+)$")
    return n and tonumber(n) or nil
end

local function level(v)
    return type(v) == "number" and v == v and v >= 0 and v ~= math.huge
end

local function eachRow(lists, fn)
    for _, e in pairs(lists) do
        if type(e) == "table" and type(e.rows) == "table" and type(e.npc) == "string" then
            for _, r in ipairs(e.rows) do
                if type(r) == "table" and type(r.name) == "string" then fn(e.npc, r) end
            end
        end
    end
end

-- { { id =, text =, priority = }, ... } sorted by id.
function R.Prompts(lists, knownRanks, playerLevel)
    local out = {}
    if type(lists) ~= "table" or not level(playerLevel) then return out end
    local known = {}
    if type(knownRanks) == "table" then
        for name, n in pairs(knownRanks) do
            if type(name) == "string" and type(n) == "number" then known[name] = n end
        end
    end
    eachRow(lists, function(_, r)
        local n = rankNumber(r.rank)
        if r.state == "known" and n and (not known[r.name] or n > known[r.name]) then known[r.name] = n end
    end)
    local best = {} -- name -> { rank = n, trainers = { [npc] = true } }
    eachRow(lists, function(npc, r)
        local n = rankNumber(r.rank)
        if r.state ~= "known" and n and known[r.name] and n > known[r.name]
            and level(r.level) and r.level <= playerLevel then
            local b = best[r.name]
            if not b or n > b.rank then
                best[r.name] = { rank = n, trainers = { [npc] = true } }
            elseif n == b.rank then
                b.trainers[npc] = true
            end
        end
    end)
    for name, b in pairs(best) do
        local who = {}
        for npc in pairs(b.trainers) do who[#who + 1] = npc end
        table.sort(who)
        out[#out + 1] = {
            id = R.PREFIX .. name,
            text = string.format("%s Rank %d can be learned at %s.", name, b.rank, table.concat(who, " or ")),
            priority = R.PRIORITY,
        }
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

-- Sync with the player's level read through the one shared client.level()
-- (CLIENT NEED, shared with Plexy; A-F). No client, no level function, a
-- failed read or no answer means no level: no prompt is claimed, and this
-- module's earlier prompts are removed.
function R.Refresh(client, advisor, lists, knownRanks, shown)
    local level
    if type(client) == "table" and type(client.level) == "function" then
        local ok, v = pcall(client.level)
        if ok then level = v end
    end
    return R.Sync(advisor, lists, knownRanks, level, shown)
end

-- Puts the current prompts in the advisor and removes the ones this module
-- added before that no longer apply. Returns the new shown set.
function R.Sync(advisor, lists, knownRanks, playerLevel, shown)
    local now = {}
    if type(advisor) ~= "table" or type(advisor.Add) ~= "function" or type(advisor.Remove) ~= "function" then
        return now
    end
    for _, p in ipairs(R.Prompts(lists, knownRanks, playerLevel)) do
        if advisor.Add(p.id, p.text, p.priority) then now[p.id] = true end
    end
    if type(shown) == "table" then
        for id in pairs(shown) do
            if type(id) == "string" and id:sub(1, #R.PREFIX) == R.PREFIX and not now[id] then
                advisor.Remove(id)
            end
        end
    end
    return now
end
