local _, ns = ...

-- End to end (S26): the whole add-on on a fake client. A class trainer's
-- window teaches facts that the facts word reports; a profession trainer's
-- window is not read. Made-up spells and prices; not tested in game.

local tests = {}

local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setFaction("Alliance"); c.setLevel(6)
    c.setClock(1700000000)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon)
    if opts.login ~= false then
        c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
        c.advance(10, 40)
    end
    return c, addon
end

local function said(c, text)
    for _, line in ipairs(c.printed or {}) do
        if tostring(line):find(text, 1, true) then return line end
    end
    return nil
end

local CLASS_ROWS = {
    { name = "Charge", rank = "Rank 1", state = "available", cost = 100, level = 4 },
    { name = "Battle Shout", rank = "Rank 1", state = "known", cost = 10, level = 1 },
}

local function facts(c)
    c.printed = {}
    c.slashes[ns.id.slash]("facts")
end

tests["facts: a class trainer window teaches facts and the facts word reports them"] = function(t)
    local c = boot()
    c.setTrainer({ services = CLASS_ROWS })
    c.fire("TRAINER_SHOW")
    c.advance(1, 5)
    facts(c)
    t.ok(said(c, ns.id.title .. ": learned from the game: 2 trainer line(s), 1 first level(s), 0 spell(s) trainers did not have") ~= nil,
        "counts after the class trainer")
    t.ok(said(c, "WARRIOR, first taught at: Charge 4") ~= nil, "the first level of the spell not known yet")
    t.ok(said(c, "Battle Shout 1") == nil, "a known spell has no first level")
end

tests["facts: a profession trainer window is not read"] = function(t)
    local c = boot()
    c.setTrainer({ profession = "Mining", services = {
        { name = "Smelt Copper", state = "available", cost = 50, level = 1 },
    } })
    c.fire("TRAINER_SHOW")
    c.advance(1, 5)
    facts(c)
    t.ok(said(c, "learned from the game: 0 trainer line(s), 0 first level(s), 0 spell(s)") ~= nil, "nothing learned")
    t.ok(said(c, "Smelt Copper") == nil, "the profession spell is not listed")
end

tests["facts: nothing learned yet says counts of 0"] = function(t)
    local c = boot()
    facts(c)
    t.ok(said(c, ns.id.title .. ": learned from the game: 0 trainer line(s), 0 first level(s), 0 spell(s) trainers did not have") ~= nil,
        "empty counts")
    t.eq(#c.printed, 1, "one line only")
end

return tests
