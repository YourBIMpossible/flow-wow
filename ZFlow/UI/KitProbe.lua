-- The window kit's login probe (lead DISPATCH section 297 item 3 and section
-- 303 item 5). The parts the kit would like to draw with (UI/Kit/Parts.lua:
-- Blizzard templates, atlases, texture paths and client names) have not
-- been seen on this client. This asks the client once per login whether
-- each is there (client.kitProbe, Core/Client.lua) and keeps the answer in
-- the saved diagnostics, where tools\zflow-read-diag.ps1 prints it under
-- "Kit probe":
--
--   <account saved table>.diag.kitProbe = {
--       at = uptime when it was asked,
--       interface = the client build it was asked on ("1.16.1 (7777)"),
--       rows = { [row id] = "works" | what the client said,
--                EJ_LOADED = "yes" | "no" | "not known" } }
--
-- Once per login or reload: at the first PLAYER_ENTERING_WORLD. In combat
-- then, it waits and asks once when the fight ends (PLAYER_REGEN_ENABLED),
-- not at the next login. Each answer replaces the one saved before. The
-- probe runs under pcall; one that raises is a recorded problem (kind
-- KitProbe.KIND), saves nothing and is not asked again this login.
-- LOOK ONLY: nothing is shown, no setting is changed, nothing acts, no
-- add-on is loaded. It listens on the client itself, as the diagnostics
-- do, so a paused add-on still records what its client has.
--
--   KitProbe.Start(k) -> api
--     api.done()     true once the probe was asked and answered (or raised)
--     api.result()   the record of this login, nil before it is asked
--   ns.use(KitProbe.NAME) -> { Result = api.result }
--   KitProbe.Works(record, id) -> true   the row's answer starts "works"
--                                 false  the client said anything else
--                                 nil    not asked yet: no record, or no
--                                        answer for that row in it
--     Pure. "set, not confirmed" is false: the element draws its fallback.
local _, ns = ...

local P = ns.KitProbe or {}
ns.KitProbe = P

P.NAME = "kitProbe"
P.KIND = "kitProbe"
P.WORKS = "works"
P.LOGIN = "PLAYER_ENTERING_WORLD"
P.FIGHT_OVER = "PLAYER_REGEN_ENABLED"
P.ADDON = "ADDON_LOADED"
P.JOURNAL = "Blizzard_EncounterJournal"

function P.Works(record, id)
    if type(record) ~= "table" or type(record.rows) ~= "table" then return nil end
    local text = record.rows[id]
    if type(text) ~= "string" then return nil end
    return text == P.WORKS or text:sub(1, #P.WORKS + 1) == P.WORKS .. " "
end

local function copyRows(rows)
    local out = {}
    for id, text in pairs(rows) do
        if type(id) == "string" and type(text) == "string" then out[id] = text end
    end
    return out
end

-- The saved copy is its own table: the record handed to the kit is never
-- the one the saved file holds.
local function save(k, record)
    local db = k.client.saved(k.id.accountDB)
    if type(db) ~= "table" then return end
    if type(db.diag) ~= "table" then db.diag = {} end
    db.diag.kitProbe = { at = record.at, interface = record.interface, rows = copyRows(record.rows) }
end

function P.Start(k)
    local client = k.client
    local done, last = false, nil
    local cancelLogin, cancelFight = nil, nil
    local api = {}
    function api.done() return done end
    function api.result() return last end

    local function finish()
        done = true
        if cancelFight ~= nil then
            cancelFight()
            cancelFight = nil
        end
    end

    local function try()
        if done then return end
        if type(client.kitProbe) ~= "function" then
            finish()
            return
        end
        local rows = nil
        if type(ns.KitParts) == "table" then rows = ns.KitParts.rows end
        local ok, answer, reason = pcall(client.kitProbe, rows)
        if ok and answer == nil and reason == "combat" then
            -- In a fight: asked again, once, when it ends.
            if cancelFight == nil then cancelFight = client.listen(P.FIGHT_OVER, try) end
            return
        end
        finish()
        if not ok then
            k.problems:add(P.KIND, "probe", tostring(answer))
            return
        end
        if type(answer) ~= "table" then
            k.problems:add(P.KIND, "probe", "no answer: " .. tostring(reason))
            return
        end
        local record = { rows = copyRows(answer) }
        if type(client.uptime) == "function" then record.at = client.uptime() end
        if type(ns.Diag) == "table" and type(ns.Diag.BuildKey) == "function" then
            local okBuild, build = pcall(ns.Diag.BuildKey, client)
            if okBuild and type(build) == "string" then record.interface = build end
        end
        last = record
        local okSave, err = pcall(save, k, record)
        if not okSave then k.problems:add(P.KIND, "save", tostring(err)) end
    end

    -- Lead section 307: the journal add-on is never loaded from here. When
    -- the game loads it later, whether it is loaded is asked once more
    -- (read only, no rows) and re-recorded; the other answers are kept.
    client.listen(P.ADDON, function(name)
        if name ~= P.JOURNAL or last == nil or type(client.kitProbe) ~= "function" then return end
        local ok, answer = pcall(client.kitProbe, {})
        if not ok or type(answer) ~= "table" or type(answer.EJ_LOADED) ~= "string" then return end
        last.rows.EJ_LOADED = answer.EJ_LOADED
        local okSave, err = pcall(save, k, last)
        if not okSave then k.problems:add(P.KIND, "save", tostring(err)) end
    end)

    -- The first one of this login only: a later one is a zone change.
    cancelLogin = client.listen(P.LOGIN, function()
        if cancelLogin ~= nil then
            cancelLogin()
            cancelLogin = nil
        end
        try()
    end)

    if type(k.Module) == "function" and k.phase == "declare" then
        k:Module({ name = P.NAME, needs = { "client" }, provides = { Result = api.result } })
    end
    return api
end

-- The addon's own: asked at this login.
ns.kitProbe = P.Start(ns)
