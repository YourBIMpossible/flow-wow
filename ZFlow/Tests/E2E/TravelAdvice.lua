local _, ns = ...
-- Travel advice end to end (S33, lead dispatch section 395 item 4), on the
-- whole add-on loaded on a fake client: a trip stop far from the player, a
-- shaman with Astral Recall and a saved home near the stop. The advisor
-- prompt names the recall and the minutes; it goes on cooldown, the spell
-- not known, a stop too near, a position not known: no prompt. Advice
-- only: nothing is cast. Made-up places; not tested in game.
local tests = {}

local MAP = 1436
local CORNERS = { cont = 0, ox = 0, oy = 0, ex = 3000, ey = 0, sx = 0, sy = 3000 }
local RECALL = 556

local function T() return ns.TravelAdvice or {} end

local function slash(c, text)
    c.slashes[ns.id.slash](text)
    c.advance(1, 5)
end

-- opts.known (default true), opts.cooldown (default false).
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("SHAMAN"); c.setFaction("Horde"); c.setLevel(30)
    c.setZone(1, MAP); c.setPosition(MAP, 0.1, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 3000, 3000); c.setMapCont(MAP, 0); c.setMapCorners(MAP, CORNERS)
    c.setQuestLog({})
    c.setSpellId("Astral Recall", RECALL)
    local known = opts.known
    if known == nil then known = true end
    c.setSpell(RECALL, { known = known })
    local cd = opts.cooldown
    if cd == nil then cd = false end
    c.setSpellCooldown(RECALL, cd)
    c.setBindLocation("Test Inn")
    c.setMounted(false)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    addon.store:set("char", "learned.places.bind", { name = "Test Inn", map = MAP, x = 0.15, y = 0.5, seen = 1 })
    -- The stop is made where the player stands, then the player walks away.
    slash(c, "trip add here camp")
    c.setPosition(MAP, 0.9, 0.5)
    c.advance(1, 5)
    slash(c, "trip go")
    c.advance(3, 10)
    return c, addon
end

local function prompt(addon)
    for _, p in ipairs(addon.advisor.List()) do
        if T().PROMPT ~= nil and p.id == T().PROMPT then return p.text end
    end
    return nil
end

tests["travel advice e2e: a ready recall that saves the walk is one advisor line"] = function(t)
    local c, addon = boot()
    t.eq(prompt(addon), "Your Astral Recall is ready: it saves about 5 minutes.")
    -- Nothing is cast: the fake client records no cast or use.
    t.eq(#(c.casts or {}), 0, "nothing cast")
end

tests["travel advice e2e: on cooldown, no line; ready again, the line comes back"] = function(t)
    local c, addon = boot({ cooldown = true })
    t.eq(prompt(addon), nil)
    c.setSpellCooldown(RECALL, false)
    c.advance(3, 10)
    t.eq(prompt(addon), "Your Astral Recall is ready: it saves about 5 minutes.")
end

tests["travel advice e2e: a spell not known gives no line"] = function(t)
    local _, addon = boot({ known = false })
    t.eq(prompt(addon), nil)
end

tests["travel advice e2e: a stop too near gives no line"] = function(t)
    local c, addon = boot()
    c.setPosition(MAP, 0.3, 0.5)  -- 600 yards: under two minutes on foot
    c.advance(3, 10)
    t.eq(prompt(addon), nil)
end

tests["travel advice e2e: a position not known gives no line"] = function(t)
    local c, addon = boot()
    c.setPosition(nil)
    c.advance(3, 10)
    t.eq(prompt(addon), nil)
end

tests["travel advice e2e: the setting turns the line off"] = function(t)
    local c, addon = boot()
    t.ok(type(T().SETTING) == "string", "the setting has a key")
    if type(T().SETTING) ~= "string" then return end
    addon.settings:set(T().SETTING, false)
    c.advance(3, 10)
    t.eq(prompt(addon), nil)
end

return tests
