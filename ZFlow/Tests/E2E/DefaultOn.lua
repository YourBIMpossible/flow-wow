local _, ns = ...
-- Lead section 293 item 1, zflow-default-on: what a fresh character sees at
-- a default profile, on the whole add-on loaded on a fake client. Legacy
-- Flow showed the next-spell icon (Modules/Rotation/Engine.lua:1532) and
-- its world-map buttons (Modules/Nav/MapOverlay.lua:1176) without being
-- asked; Z-Flow does too. A choice the player saved is never overwritten:
-- only the default of an unset key changed. Made-up spells. Not tested in game.
local tests = {}

local D = ns.RotationDriver
-- The druid spells and reads of Tests/E2E/DruidRotation.lua: a caster
-- with no buff on is offered Mark of the Wild there.
local IDS = {
    ["Mark of the Wild"] = 1126, ["Thorns"] = 467, ["Cat Form"] = 768, ["Prowl"] = 5215,
    ["Claw"] = 1082, ["Rake"] = 1822, ["Wrath"] = 5176, ["Moonfire"] = 8921, ["Attack"] = 6603,
}

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

-- Out of a fight, in caster form, no buff on: the druid's first suggestion.
local function caster(c)
    c.setFormName(nil, true); c.setPlayerBuffs({}); c.setCombat(false)
    c.advance(1, 5)
end

tests["default on: the next-spell icon shows at a default profile, nothing switched on"] = function(t)
    local c, addon = boot()
    t.eq(addon.settings:get(D.SETTING), true, "the setting's default")
    caster(c)
    local h = icon(c)
    t.ok(h ~= nil, "the icon is made")
    t.eq(h and h.shown, true, "and shown")
    t.eq(h and h.texture, "tex:Mark of the Wild", "with the suggested spell's picture")
end

tests["default on: a character that switched the next spell off keeps it off"] = function(t)
    local c, addon = boot({ char = { settings = { rotation = { enabled = false } } } })
    t.eq(addon.settings:get(D.SETTING), false, "the saved choice")
    caster(c)
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

-- Lead section 294: the dev panel is not shown to a player who did not
-- ask for it (`/zflow panel`).
tests["default on: no dev panel at a default profile; the panel word shows it"] = function(t)
    local c = boot()
    local panel
    for _, h in ipairs(c.panels) do
        if h.spec and h.spec.name == ns.id.framePrefix .. "DevPanel" then panel = h end
    end
    t.ok(panel ~= nil, "made, for when it is asked for")
    t.eq(panel and panel.shown, false, "not shown")
    c.slashes[ns.id.slash]("panel")
    t.eq(panel and panel.shown, true, "asked for: shown")
end

return tests
