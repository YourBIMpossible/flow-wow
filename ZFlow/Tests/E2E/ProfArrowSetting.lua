local _, ns = ...
-- The profession arrow setting end to end (lead section 279 item 2, N25),
-- on the whole add-on loaded on a fake client, through the real entry
-- point: Flow's nav.profArrow, brought in by the import, lands in a setting
-- the profession step reads. Off, the arrow gives no profession step; the
-- quest arrow is untouched. On (the default), the step is as before.
-- Look only: nothing trains, buys or moves the player. Made-up rows; not
-- tested in game.
local tests = {}

local SETTING = "nav.profArrow"

-- A character with Mining at its cap and one saved trainer on this map.
-- account: the account saved table to start from (an import result, or a
-- plain one).
local function start(account)
    local c = ns.make.fakeClient()
    account = account or {}
    account.layout = account.layout or {}
    if account.layout.arrowIntroSeen == nil then account.layout.arrowIntroSeen = true end
    account.learned = account.learned or {}
    account.learned.places = account.learned.places or {}
    account.learned.places.npcs = {
        ["Test Trainer"] = { map = 1411, x = 0.8, y = 0.5, trains = { Mining = true },
                             factions = { Horde = true }, seen = 10 },
    }
    c.setSaved(ns.id.accountDB, account)
    c.setSaved(ns.id.charDB, { learned = { facts = { profSkill = {
        Mining = { skill = 75, max = 75 },
    } } } })
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFacing(0)
    c.setFaction("Horde")
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    c.setWaypoint(1411, 0.5, 0.3)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

-- What the arrows show: is a profession needle up, and is any line about
-- the trainer said on any arrow.
local function seen(c)
    local needle, said = false, false
    for i, h in ipairs(c.arrows or {}) do
        if i > 1 and h.shown then needle = true end
        for _, line in ipairs(type(h.lines) == "table" and h.lines or {}) do
            if type(line) == "string" and line:find("Mining trainer", 1, true) then said = true end
        end
    end
    return needle, said
end

local function imported(nav)
    local result = ns.Import.FromFlow({ nav = nav }, {})
    return result.account
end

tests["prof arrow: imported nav.profArrow off gives no profession step"] = function(t)
    local account = imported({ profArrow = false })
    t.eq(account.settings.nav.profArrow, false, "the import lands the choice in the account settings")
    local c, addon = start(account)
    t.eq(addon.settings:get(SETTING), false, "the add-on reads the imported choice")
    local needle, said = seen(c)
    t.eq(needle, false, "no profession needle")
    t.eq(said, false, "no trainer line on any arrow")
    t.eq(c.arrows[1] and c.arrows[1].shown, true, "the quest arrow is still shown")
end

-- Passes before: a guard that the step still comes with the setting on.
tests["prof arrow: imported nav.profArrow on, or no import, keeps the profession step"] = function(t)
    for name, account in pairs({ ["imported on"] = imported({ profArrow = true }), ["no import"] = {} }) do
        local c = start(account)
        local needle, said = seen(c)
        t.eq(needle, true, name .. ": the profession needle is shown")
        t.eq(said, true, name .. ": the trainer is said")
    end
end

tests["prof arrow: the setting is declared once, per account, on by default, filed and findable"] = function(t)
    local _, addon = start({})
    local row = addon.settings:row(SETTING)
    t.ok(type(row) == "table", "nav.profArrow is a declared row")
    if type(row) ~= "table" then return end
    t.eq(row.scope, "account")
    t.eq(row.type, "bool")
    t.eq(row.default, true)
    t.ok(addon.Settings.Topics.Find(row.group) ~= nil, "it names a topic of the one list: " .. tostring(row.group))
    t.ok(type(row.synonyms) == "table" and #row.synonyms > 0, "it lists synonyms")
    local n = 0
    for r in addon.settings:each() do
        if r.key == SETTING then n = n + 1 end
    end
    t.eq(n, 1, "declared once")
end

tests["prof arrow: turned off during play, the profession step goes; back on, it returns"] = function(t)
    local c, addon = start({})
    t.eq(select(1, seen(c)), true, "on: the needle is shown")
    addon.settings:set(SETTING, false)
    c.advance(2, 4)
    local needle, said = seen(c)
    t.eq(needle, false, "off: no needle")
    t.eq(said, false, "off: no trainer line")
    addon.settings:set(SETTING, true)
    c.advance(2, 4)
    t.eq(select(1, seen(c)), true, "on again: the needle is back")
end

return tests
