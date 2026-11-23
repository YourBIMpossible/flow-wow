local _, ns = ...
-- The dungeon entry and exit alert (lead section 303, item 8c), through the
-- alerts (UI/Alerts.lua), on the whole add-on loaded on a fake client. With
-- alerts on and "Alerts: entering and leaving a dungeon" on, one chat line
-- says when the player goes into a dungeon or a raid and one when they come
-- out. Off by default: nothing saved, nothing is said. Nothing at login
-- (logging in inside is the state the player logged in to, not a change),
-- nothing when the client does not say where the player is, and nothing
-- for a battleground. It says only: nothing acts in the game.
-- Offline test: the fake client's instance read, not the game's. Not tested
-- in game. Made-up values only.
-- Fails before the code: Alerts has no DUNGEON row and says no such line,
-- so each test fails at its first check.
local tests = {}

local function A() return ns.Alerts or {} end

local OUT = { inside = false, kind = "none" }
local PARTY = { inside = true, kind = "party" }
local RAID = { inside = true, kind = "raid" }
local PVP = { inside = true, kind = "pvp" }

-- opts.at: the instance read at login (false: the client does not say).
-- opts.on, opts.dungeon: the two settings, set after login. opts.account:
-- saved tables (a reload).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, {})
    if opts.at ~= false then c.setInstance(opts.at or OUT) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    if opts.on then addon.settings:set(A().SETTING, true) end
    if opts.dungeon and A().DUNGEON then addon.settings:set(A().DUNGEON, true) end
    c.advance((A().SETTLE or 10) + 5, 20)
    return c, addon
end

-- The player crosses a loading screen and is now at `where`.
local function go(c, where)
    c.setInstance(where)
    c.fire("PLAYER_ENTERING_WORLD")
    c.fire("ZONE_CHANGED_NEW_AREA")
end

local function said(c, from, text)
    local want = ns.id.title .. ": " .. tostring(text)
    local n = 0
    for i = from, #c.printed do
        if tostring(c.printed[i]) == want then n = n + 1 end
    end
    return n
end

local function has(t)
    local a = A()
    local ok = type(a.DUNGEON) == "string" and type(a.ENTERED) == "string" and type(a.LEFT) == "string"
    t.ok(ok, "Alerts.DUNGEON, ENTERED and LEFT are declared")
    return ok
end

tests["dungeon alert: its own row, off by default, filed with the alerts"] = function(t)
    if not has(t) then return end
    local _, addon = start()
    local row = addon.settings:row(A().DUNGEON)
    t.ok(type(row) == "table", "the row " .. A().DUNGEON)
    if type(row) ~= "table" then return end
    t.eq({ row.type, row.default, row.scope, row.group }, { "bool", false, "account", "general" })
    t.ok(type(row.synonyms) == "table" and #row.synonyms > 0, "synonyms")
    t.eq(addon.settings:get(A().DUNGEON), false, "off with nothing saved")
end

tests["dungeon alert: nothing saved, going in and out says nothing"] = function(t)
    if not has(t) then return end
    local c = start()
    local from = #c.printed + 1
    go(c, PARTY); go(c, OUT)
    t.eq(said(c, from, A().ENTERED), 0)
    t.eq(said(c, from, A().LEFT), 0)
end

tests["dungeon alert: alerts on but this row off says nothing; this row on but alerts off says nothing"] = function(t)
    if not has(t) then return end
    local c = start({ on = true })
    local from = #c.printed + 1
    go(c, PARTY)
    t.eq(said(c, from, A().ENTERED), 0, "the row is off")
    c = start({ dungeon = true })
    from = #c.printed + 1
    go(c, PARTY)
    t.eq(said(c, from, A().ENTERED), 0, "alerts are off")
end

tests["dungeon alert: both on: one line going in, one line coming out"] = function(t)
    if not has(t) then return end
    local c = start({ on = true, dungeon = true })
    local from = #c.printed + 1
    go(c, PARTY)
    t.eq(said(c, from, A().ENTERED), 1, "both events of one loading screen say it once")
    t.eq(said(c, from, A().LEFT), 0)
    go(c, OUT)
    t.eq(said(c, from, A().LEFT), 1)
    t.eq(said(c, from, A().ENTERED), 1)
end

tests["dungeon alert: a raid counts; a battleground does not"] = function(t)
    if not has(t) then return end
    local c = start({ on = true, dungeon = true })
    local from = #c.printed + 1
    go(c, PVP)
    t.eq(said(c, from, A().ENTERED), 0, "a battleground is not a dungeon")
    go(c, OUT)
    t.eq(said(c, from, A().LEFT), 0, "nothing was entered")
    go(c, RAID)
    t.eq(said(c, from, A().ENTERED), 1)
end

tests["dungeon alert: logging in inside a dungeon says nothing; leaving it then does"] = function(t)
    if not has(t) then return end
    local c = start({ on = true, dungeon = true, at = PARTY,
        account = { settings = { alerts = { on = true, dungeon = true } } } })
    t.eq(said(c, 1, A().ENTERED), 0, "the state logged in to is not a change")
    local from = #c.printed + 1
    go(c, OUT)
    t.eq(said(c, from, A().LEFT), 1)
end

tests["dungeon alert: a client that does not say where you are says nothing, and no fault"] = function(t)
    if not has(t) then return end
    local c, addon = start({ on = true, dungeon = true, at = false })
    local from = #c.printed + 1
    c.fire("PLAYER_ENTERING_WORLD"); c.fire("ZONE_CHANGED_NEW_AREA")
    t.eq(said(c, from, A().ENTERED), 0)
    t.eq(said(c, from, A().LEFT), 0)
    go(c, PARTY)
    t.eq(said(c, from, A().ENTERED), 0, "not known to be outside before: not a change seen")
    go(c, OUT)
    t.eq(said(c, from, A().LEFT), 1, "now seen inside, then out")
    t.eq((addon:ModuleState(A().NAME)), "started")
end

tests["dungeon alert: the read not answered in between keeps what was known"] = function(t)
    if not has(t) then return end
    local c = start({ on = true, dungeon = true })
    local from = #c.printed + 1
    go(c, PARTY)
    c.setInstance(nil); c.fire("ZONE_CHANGED_NEW_AREA")
    t.eq(said(c, from, A().LEFT), 0, "no answer is not leaving")
    go(c, PARTY)
    t.eq(said(c, from, A().ENTERED), 1, "still inside: not said again")
end

tests["dungeon alert: with the sound on, one sound with the line"] = function(t)
    if not has(t) then return end
    local c, addon = start({ on = true, dungeon = true })
    addon.settings:set(A().SOUND, true)
    local before = type(c.alertsPlayed) == "function" and #c.alertsPlayed() or 0
    go(c, PARTY)
    t.eq(type(c.alertsPlayed) == "function" and #c.alertsPlayed() or -1, before + 1)
end

tests["dungeon alert: the saved choice is kept over a reload"] = function(t)
    if not has(t) then return end
    local c = start({ on = true, dungeon = true })
    local c2, addon2 = start({ account = c.saved(ns.id.accountDB) })
    t.eq(addon2.settings:get(A().DUNGEON), true)
    local from = #c2.printed + 1
    go(c2, PARTY)
    t.eq(said(c2, from, A().ENTERED), 1)
end

return tests
