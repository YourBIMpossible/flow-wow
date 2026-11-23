local _, ns = ...
-- Lead section 293 item 1, zflow-default-on: what a fresh character sees at
-- a default profile, on the whole add-on loaded on a fake client. Legacy
-- Flow showed the next-spell icon (Modules/Rotation/Engine.lua:1532) and
-- its world-map buttons (Modules/Nav/MapOverlay.lua:1176) without being
-- asked; Z-Flow does too. A choice the player saved is never overwritten:
-- only the default of an unset key changed. Made-up spells. Not tested in game.
local tests = {}

local D = ns.RotationDriver
local IDS = { ["Wrath"] = 5176, ["Moonfire"] = 8921, ["Attack"] = 6603 }
local ENEMY = { exists = true, hostile = true, dead = false }

-- opts: account (the saved account table), char (the saved character table).
-- The account table is there before login: not a new install, so the staged
-- reveal holds nothing back and what is seen is the defaults alone.
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setClass("DRUID"); c.setFaction("Alliance"); c.setLevel(20); c.setDead(false)
    for name, id in pairs(IDS) do
        c.setSpellId(name, id)
        c.setSpell(id, { known = true, usable = true })
        c.setSpellCooldown(id, false)
        c.setSpellTexture(id, "tex:" .. name)
    end
    c.setWindow("WorldMapFrame", {})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function icon(c)
    for _, h in ipairs(c.icons) do
        if tostring(h.spec.name):find("RotationIcon", 1, true) then return h end
    end
    return nil
end

local function mapButton(c)
    for _, h in ipairs(c.windowButtons) do
        if h.frame == "WorldMapFrame" then return h end
    end
    return nil
end

local function fight(c)
    c.setTarget(ENEMY); c.setCombat(true)
    c.advance(1, 5)
end

tests["default on: the next-spell icon shows at a default profile, nothing switched on"] = function(t)
    local c, addon = boot()
    t.eq(addon.settings:get(D.SETTING), true, "the setting's default")
    fight(c)
    local h = icon(c)
    t.ok(h ~= nil, "the icon is made")
    t.eq(h and h.shown, true, "and shown in a fight")
    t.ok(h and type(h.texture) == "string" and h.texture:find("^tex:") ~= nil, "with a spell's picture")
end

tests["default on: a character that switched the next spell off keeps it off"] = function(t)
    local c, addon = boot({ char = { settings = { rotation = { enabled = false } } } })
    t.eq(addon.settings:get(D.SETTING), false, "the saved choice")
    fight(c)
    local h = icon(c)
    t.eq(h and h.shown or false, false, "no icon")
end

tests["default on: the world map has the Z-Flow button at a default profile"] = function(t)
    local c, addon = boot()
    t.eq(addon.settings:get("buttons.worldMap"), true, "the setting's default")
    local h = mapButton(c)
    t.ok(h ~= nil, "a button on the world map")
    t.eq(h and h.shown, true, "shown")
end

tests["default on: an account that switched the world map button off keeps it off"] = function(t)
    local c, addon = boot({ account = { settings = { buttons = { worldMap = false } } } })
    t.eq(addon.settings:get("buttons.worldMap"), false, "the saved choice")
    t.eq(mapButton(c), nil, "no button")
end

return tests
