-- Boss kills (lead section 305): the data for the in-dungeon tracker of
-- section 303 item (d). Does the client report a boss kill? The answer is
-- measured, not assumed: the encounter events are listened to, every one
-- that comes is counted in the account's diag record, and the diag word
-- says what was seen, or that nothing has come yet, or that the client did
-- not take the event at all (client.listenFaults). The tracker reads the
-- kills of this instance visit; it shows nothing when none are reported.
--
-- LOOK ONLY. It listens and counts; it targets, casts and changes nothing.
--
--   K.Declare(k, diag) -> api
--     api.Kills()   the kills of this visit, in order: { { id, name } }
--     api.Record()  the account's counts (a copy) or nil
--   K.Lines(record, refused) -> lines     pure: what the diag word says
--
-- Saved, account "diag.bossKills": { ends = how many ENCOUNTER_END came,
--   kills = how many kills (an encounter won, or BOSS_KILL; one per
--   encounter a visit), bossKill = how many BOSS_KILL came (left out when
--   none) }. No name of a player, boss, realm or guild is saved.
-- A visit ends at PLAYER_ENTERING_WORLD outside an instance, or in an
-- instance of another kind. Two dungeons in a row without leaving through
-- the world are one visit here (no instance id is read yet). A reload
-- inside starts the visit again (kills are not saved).
-- Not tested in game: ENCOUNTER_END (encounterID, name, difficulty, group
-- size, success) and BOSS_KILL (encounterID, name) are taken from the
-- warcraft.wiki.gg event pages; neither is seen on 16001 yet, which is
-- what this module is for.
local _, ns = ...

local K = {}
ns.BossKills = K

K.NAME = "bossKills"
K.WORD = "bosskills"
K.HELP = "say whether this client has reported boss kills, and how many"
K.PATH = "diag.bossKills"
-- Said on the bus after each new kill of this visit (lead section 303 (d):
-- the in-dungeon tracker listens).
K.EVENT = "bossKills.changed"
K.EVENTS = { "ENCOUNTER_START", "ENCOUNTER_END", "BOSS_KILL", "PLAYER_ENTERING_WORLD" }
K.NOT_YET = "no ENCOUNTER_END or BOSS_KILL has come on this account yet; kill a dungeon boss and ask again"

local function plural(n, one, many) return tostring(n) .. " " .. (n == 1 and one or many) end

function K.Lines(record, refused)
    local out = {}
    for _, e in ipairs(type(refused) == "table" and refused or {}) do
        out[#out + 1] = "boss kills: the client does not have " .. tostring(e) .. "."
    end
    local r = type(record) == "table" and record or {}
    local ends, kills, bossKill = tonumber(r.ends) or 0, tonumber(r.kills) or 0, tonumber(r.bossKill) or 0
    if ends == 0 and bossKill == 0 then
        out[#out + 1] = "boss kills: " .. K.NOT_YET .. "."
        return out
    end
    out[#out + 1] = "boss kills: ENCOUNTER_END seen " .. plural(ends, "time", "times") .. ", "
        .. tostring(kills) .. " of them " .. (kills == 1 and "a kill" or "kills")
        .. "; BOSS_KILL seen " .. plural(bossKill, "time", "times") .. "."
    return out
end

-- The events of K.EVENTS this client did not take.
local function refusedOf(client)
    if type(client) ~= "table" or type(client.listenFaults) ~= "function" then return {} end
    local ok, f = pcall(client.listenFaults)
    if not ok or type(f) ~= "table" or type(f.notRegistered) ~= "table" then return {} end
    local mine, out = {}, {}
    for _, e in ipairs(K.EVENTS) do mine[e] = true end
    for _, e in ipairs(f.notRegistered) do
        if mine[e] then out[#out + 1] = e end
    end
    return out
end

function K.Declare(k, diag)
    local api = {}
    local ctx
    local kills, killed = {}, {}
    local cancels = {}

    local function record()
        if not ctx then return nil end
        local r = ctx.store:get("account", K.PATH)
        return type(r) == "table" and r or nil
    end

    local function save(change)
        if not ctx then return end
        local r = record() or {}
        local out = { ends = tonumber(r.ends) or 0, kills = tonumber(r.kills) or 0 }
        if tonumber(r.bossKill) then out.bossKill = tonumber(r.bossKill) end
        change(out)
        local ok, why = ctx.store:set("account", K.PATH, out)
        if not ok then k.problems:add(K.NAME, "save", tostring(why)) end
    end

    local function kill(id, name)
        if type(id) ~= "number" or killed[id] then return false end
        killed[id] = true
        kills[#kills + 1] = { id = id, name = type(name) == "string" and name or nil }
        return true
    end

    function api.Kills()
        local out = {}
        for i, e in ipairs(kills) do out[i] = { id = e.id, name = e.name } end
        return out
    end

    -- false only when the client took neither kill event: then no kill can
    -- ever be reported, and the tracker shows nothing (lead section 303 (d)).
    function api.Reported()
        local refused = {}
        for _, e in ipairs(refusedOf(ctx and ctx.client or k.client)) do refused[e] = true end
        return not (refused.ENCOUNTER_END and refused.BOSS_KILL)
    end

    function api.Record()
        local r = record()
        if not r then return nil end
        local out = {}
        for key, v in pairs(r) do out[key] = v end
        return out
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[K.WORD] = function()
            local id = k.id or ns.id
            local client = ctx and ctx.client or k.client
            if type(client) ~= "table" or type(client.print) ~= "function" then return end
            for _, line in ipairs(K.Lines(record(), refusedOf(client))) do client.print(id.title .. ": " .. line) end
        end
        if type(diag.help) == "table" then diag.help[K.WORD] = K.HELP end
    end

    k:Module({
        name = K.NAME,
        needs = { "client", "store", "bus" },
        provides = { Kills = api.Kills, Record = api.Record, Reported = api.Reported },
        start = function(c)
            ctx = c
            local client = c.client
            local function on(event, fn)
                cancels[#cancels + 1] = client.listen(event, function(...)
                    local ok, err = pcall(fn, ...)
                    if not ok then k.problems:add(K.NAME, event, tostring(err)) end
                end)
            end
            on("ENCOUNTER_END", function(id, name, _, _, success)
                local won = success == 1 or success == true
                local new = won and kill(id, name) or false
                save(function(r)
                    r.ends = r.ends + 1
                    if new then r.kills = r.kills + 1 end
                end)
                if new then c.bus:emit(K.EVENT, id) end
            end)
            on("BOSS_KILL", function(id, name)
                local new = kill(id, name)
                save(function(r)
                    r.bossKill = (r.bossKill or 0) + 1
                    if new then r.kills = r.kills + 1 end
                end)
                if new then c.bus:emit(K.EVENT, id) end
            end)
            on("ENCOUNTER_START", function() end)
            local where
            on("PLAYER_ENTERING_WORLD", function()
                local okI, inst = false, nil
                if type(client.instance) == "function" then okI, inst = pcall(client.instance) end
                -- Twin review 17:11, F8: an instance read that does not
                -- answer is not "outside"; the visit stays as it was.
                if not okI or type(inst) ~= "table" or type(inst.inside) ~= "boolean" then return end
                local now = inst.inside and tostring(inst.kind) or "outside"
                if now ~= where then
                    kills, killed = {}, {}
                end
                where = now
            end)
        end,
        stop = function()
            for _, cancel in ipairs(cancels) do pcall(cancel) end
            cancels = {}
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.bossKills = K.Declare(ns, ns.diag)
