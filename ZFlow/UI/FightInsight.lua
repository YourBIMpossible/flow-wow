local _, ns = ...

-- FightInsight (parity row C-51; lead section 664): an advice prompt from
-- the fight log. One insight so far: you died to the same enemy more than
-- once this session.
--
-- LOOK ONLY. It reads what UI/FightLog.lua already holds and adds or takes
-- back one advisor prompt. No new read of the combat log, nothing saved,
-- nothing done in the game.
--
-- From Flow (Modules/Advisor/Builtins.lua:365-374, "fightInsights"): an
-- advisor source fed by the fight records. Flow's own insights compare the
-- casts of your best and worst fights (Modules/Fight/Profiler.lua:380);
-- Z-Flow's fight log keeps no such ranking, so those are not here. What it
-- does keep is the hits before your last death and who landed each
-- (Rotation/Fights.lua, rec:died), and this insight is made from that.
--
-- Where the facts are from (lead section 611): the game's combat log, as
-- the fight log read it. The enemy's name is the name the log gave for
-- whoever landed the last hit on you that named anyone. A death with no
-- such hit counts for nobody: who killed you is then not known, and no
-- enemy is guessed. Not here: "ran out of mana". The fight log reads no
-- mana, and this client hides power amounts.
--
-- Kept in memory only, as the fights are: gone at a reload or logout.
--
-- Pure:
--   FI.Killer(death) -> name or nil   death as rec:died gives it
--   FI.Text(name, count) -> the prompt
-- Module "fightInsight" (FI.Declare(k[, log]) -> api):
--   log: function() -> the fight log ({ death = fn }) or nil; left out, the
--     add-on's own (ns.fightLog).
--   api.Deaths() -> { [name] = count } (a copy)   ns.use: { Deaths }
-- The prompt (FI.PROMPT) is for your last death: shown when that enemy has
-- killed you FI.AT times or more this session, taken back when your last
-- death was to another enemy or to nobody known. Not tested in game.

local FI = {}
ns.FightInsight = FI

FI.NAME = "fightInsight"
FI.PROMPT = "fight.diedTo"
FI.PRIORITY = 2
FI.AT = 2
FI.EVERY = 1
FI.DEAD = "PLAYER_DEAD"
FI.TEXT = "You have died to %s %d times this session."

function FI.Killer(death)
    if type(death) ~= "table" or type(death.hits) ~= "table" then return nil end
    for i = #death.hits, 1, -1 do
        local h = death.hits[i]
        if type(h) == "table" and type(h.from) == "string" and h.from ~= "" then return h.from end
    end
    return nil
end

function FI.Text(name, count)
    if type(name) ~= "string" or name == "" or type(count) ~= "number" then return nil end
    return FI.TEXT:format(name, count)
end

function FI.Declare(k, log)
    local api = {}
    local deaths = {}
    -- pending: you died, and the fight log's record of it is read at the
    -- next look (the fight log hears of the death on its own listener, in
    -- no order this module can rely on).
    local pending = false
    local advisor

    local function fightLog()
        if type(log) == "function" then
            local ok, v = pcall(log)
            if ok then return v end
            return nil
        end
        return ns.fightLog
    end

    function api.Deaths()
        local out = {}
        for name, n in pairs(deaths) do out[name] = n end
        return out
    end

    local function look()
        if not pending then return end
        pending = false
        if type(advisor) ~= "table" then return end
        local L = fightLog()
        local death
        if type(L) == "table" and type(L.death) == "function" then
            local ok, d = pcall(L.death)
            if ok then death = d end
        end
        local name = FI.Killer(death)
        local text
        if name then
            deaths[name] = (deaths[name] or 0) + 1
            if deaths[name] >= FI.AT then text = FI.Text(name, deaths[name]) end
        end
        if text then advisor.Add(FI.PROMPT, text, FI.PRIORITY) else advisor.Remove(FI.PROMPT) end
    end

    k:Module({
        name = FI.NAME,
        needs = { "client", "bus", "advisor" },
        provides = { Deaths = api.Deaths },
        ticks = { { every = FI.EVERY, when = "always", run = function() look() end } },
        start = function(ctx)
            advisor = ctx.use("advisor")
            ctx.bus:on(FI.NAME, FI.DEAD, function() pending = true end)
        end,
        stop = function()
            advisor, pending, deaths = nil, false, {}
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.fightInsight = FI.Declare(ns)
