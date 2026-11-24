local _, ns = ...
-- The modifier queue (S13, UI/RotationQueue.lua) on the whole add-on loaded
-- on a fake client, a warrior, through its real entry: the driver's view on
-- the bus at each tick and the game's MODIFIER_STATE_CHANGED. The player
-- sees four small icons beside the rotation icon: what Shift, Ctrl, Alt and
-- Ctrl + Shift with the key cast, the held one edged green. Show only:
-- nothing is cast, bound or set on a secure button by the queue. Unknown
-- data: no modifier read, a half-known one, and a view that is not a table.
-- The expected icons are worked out from the view the driver gave, by the
-- same pure rules (Rotation/Queue.lua). Spell ids are made up; not tested
-- in game.
local tests = {}

local U = ns.RotationQueue
local Q = ns.Queue
local D = ns.RotationDriver
local I = ns.RotationIcon
local IDS = {
    ["Battle Stance"] = 2457, ["Defensive Stance"] = 71, ["Berserker Stance"] = 2458,
    ["Battle Shout"] = 6673, ["Attack"] = 6603, ["Charge"] = 100, ["Rend"] = 772,
    ["Heroic Strike"] = 78, ["Execute"] = 5308, ["Overpower"] = 7384, ["Revenge"] = 6572,
    ["Sunder Armor"] = 7386, ["Hamstring"] = 1715, ["Thunder Clap"] = 6343,
}
local SHOUT = { ["Battle Shout"] = 100 }
local ENEMY = { exists = true, hostile = true, dead = false }

local function start()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setFaction("Horde"); c.setLevel(10)
    c.setDead(false); c.setCombat(false)
    c.setScreen(1000, 768)
    for name, id in pairs(IDS) do
        c.setSpellId(name, id)
        c.setSpell(id, { known = true, usable = true })
        c.setSpellCooldown(id, false)
        c.setSpellTexture(id, "tex:" .. name)
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    local seen = {}
    addon.bus:on("e2eRotationQueue", D.EVENT, function(view) seen.view = view end)
    -- In Battle Stance, the shout up, an enemy targeted, out of a fight.
    c.setFormName("Battle Stance", true); c.setPlayerBuffs(SHOUT)
    c.setTarget(ENEMY); c.setStealthed(false)
    for _, id in pairs(IDS) do c.setInRange(id, true) end
    c.advance(1, 5)
    return c, addon, seen
end

local function queueIcons(c)
    local out = {}
    local prefix = ns.id.framePrefix .. "RotationQueue"
    for _, h in ipairs(c.slotIcons or {}) do
        local name = tostring(h.spec and h.spec.name)
        if name:sub(1, #prefix) == prefix then out[#out + 1] = h end
    end
    return out
end

-- What the queue must draw for this view and held modifier, or nil.
local function expected(c, view, held)
    if type(view) ~= "table" or type(view.keys) ~= "table" then return nil end
    local snap = type(view.snapshot) == "table" and view.snapshot or {}
    local form = snap.form
    if type(form) ~= "number" then form = c.form() end
    local row = Q.Row(view.keys.plan, form, snap.stealthed, view.keys.stealthForm)
    if not row then return nil end
    return Q.Slots(row, I.Spell(view), held)
end

local function secureCount(c)
    local binds = type(c.bindingCalls) == "function" and #c.bindingCalls() or 0
    return #c.secureGiven + binds + #(c.clickRows or {})
end

local function isHeld(marked)
    local g = U.COLOR.held
    return type(marked) == "table" and marked[1] == g[1] and marked[2] == g[2] and marked[3] == g[3]
end

tests["rotation queue: an enemy targeted, the icons show what each modifier casts, the held one edged green"] = function(t)
    local c, addon, seen = start()
    t.eq(addon.settings:get(U.SETTING), true, "on by default")
    local icons = queueIcons(c)
    t.eq(#icons, #Q.ORDER, "one icon for each modifier")
    local view = seen.view
    t.ok(type(view) == "table" and type(view.keys) == "table" and type(view.keys.plan) == "table",
        "the driver gave a view with a key plan")
    local want = expected(c, view, nil)
    t.ok(want ~= nil, "a key plan row for the stance")
    if not want or #icons ~= #Q.ORDER then return end
    local shown = 0
    for i, e in ipairs(want) do
        local h = icons[i]
        t.eq(h.shown, e.spell ~= nil, e.slot .. " shown only with a spell: " .. tostring(e.spell))
        if e.spell then
            shown = shown + 1
            t.eq(h.texture, "tex:" .. e.spell, e.slot .. " shows its spell")
            t.ok(h.point ~= nil, e.slot .. " placed beside the icon")
        end
    end
    t.ok(shown > 0, "at least one modifier casts something in Battle Stance")

    local before = secureCount(c)
    c.setModifiers(false, true, false)
    c.fire(U.MOD_EVENT)
    local held = expected(c, view, "shift")
    for i, e in ipairs(held) do
        local colour = e.state and U.COLOR[e.state] or nil
        t.eq(icons[i].marked, colour, e.slot .. " edge: " .. tostring(e.state))
    end
    if held[1].spell then t.ok(isHeld(icons[1].marked), "Shift held: its icon edged green") end
    c.setModifiers(false, false, false)
    c.fire(U.MOD_EVENT)
    for i, h in ipairs(icons) do t.ok(not isHeld(h.marked), "let go: slot " .. i .. " not edged green") end
    t.eq(secureCount(c), before, "the queue cast, bound and set nothing")
    for _, h in ipairs(c.clickRows or {}) do
        t.ok(not tostring(h.spec.name):find("RotationQueue", 1, true), "no secure button for the queue")
    end
end

tests["rotation queue: unknown modifiers and a broken view show nothing held; switched off, the icons go"] = function(t)
    local c, addon, seen = start()
    local icons = queueIcons(c)
    if #icons ~= #Q.ORDER then t.ok(false, "the icons were made") return end
    -- No modifier read given: not known, so nothing is edged green.
    c.fire(U.MOD_EVENT)
    for i, h in ipairs(icons) do t.ok(not isHeld(h.marked), "modifiers not known: slot " .. i .. " not edged green") end
    local before = secureCount(c)
    addon.bus:emit(D.EVENT, "not a view")
    for i, h in ipairs(icons) do t.eq(h.shown, false, "a broken view: slot " .. i .. " hidden") end
    c.setModifiers(true, nil, false)
    c.fire(U.MOD_EVENT)
    for i, h in ipairs(icons) do t.eq(h.shown, false, "a half-known modifier read: slot " .. i .. " still hidden") end
    t.eq(secureCount(c), before, "nothing cast or bound")

    seen.view = nil
    addon.settings:set(U.SETTING, false)
    c.advance(1, 5)
    t.ok(seen.view ~= nil, "the driver ticked again")
    for i, h in ipairs(icons) do t.eq(h.shown, false, "switched off: slot " .. i .. " hidden") end
end

return tests
