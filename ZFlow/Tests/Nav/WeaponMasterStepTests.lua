-- Weapon master step (G16): an upgrade weapon of a kind your class can
-- learn but you have not trained, once shown (tooltip, roll), offers a
-- "visit a weapon master" step: at a weapon master this player has saved,
-- else words only, with no needle. Made-up places, items and skill lines,
-- test only. Nothing here trains, buys or clicks. Not seen in game.
local _, ns = ...

local T = {}

local STR = "ITEM_MOD_STRENGTH_SHORT"
local SWORD, WAND = "item:2001", "item:2002"

local function WM() return ns.WeaponMasterStep end

local function packs()
    return { WARRIOR = {
        weights = { dps = { evidence = "first guess", values = { [STR] = 1 } } },
        proficiency = { evidence = "first guess", [2] = { [0] = true, [7] = true } },
    } }
end

local WANT = { subclassID = 7, skill = "Swords" }
local HERE = { map = 1454, x = 0.5, y = 0.5 }

-- ------------------------------------------------------------------ pure

T["weapon master step: the names agreed"] = function(t)
    local S = WM()
    t.ok(type(S) == "table", "the module is there")
    if type(S) ~= "table" then return end
    t.eq(S.NAME, "weaponMasterStep")
    t.eq(S.SETTING, "nav.weaponMasterStep")
    t.eq(S.KIND, "weaponMaster")
end

T["weapon master step: none saved, words only and no needle"] = function(t)
    local S = WM()
    if type(S) ~= "table" then return t.ok(false, "no module") end
    local step = S.Of(WANT, HERE, nil)
    t.eq(step.kind, "weaponMaster")
    t.eq(step.place, nil, "no place: the arrow has nothing to point at")
    t.eq(step.skill, "Swords")
    t.eq(S.Lines(step), { "A weapon master in a capital city teaches Swords." })
    t.eq(S.Of(nil, HERE, nil), nil, "nothing wanted, no step")
end

T["weapon master step: a weapon master this player saved on this map is pointed at"] = function(t)
    local S = WM()
    if type(S) ~= "table" then return t.ok(false, "no module") end
    local npcs = {
        ["Far Master"] = { map = 1454, x = 0.9, y = 0.9, roles = { weaponMaster = true } },
        ["Near Master"] = { map = 1454, x = 0.4, y = 0.5, roles = { weaponMaster = true } },
        ["A Trainer"] = { map = 1454, x = 0.5, y = 0.5, roles = { trainer = true } },
        ["Elsewhere"] = { map = 1453, x = 0.5, y = 0.5, roles = { weaponMaster = true } },
    }
    local step = S.Of(WANT, HERE, npcs)
    t.eq(step.place, { map = 1454, x = 0.4, y = 0.5 })
    t.eq(step.label, "Weapon master: Near Master")
    t.eq(S.Lines(step), { "Train Swords at a weapon master you have seen: Near Master." })
end

-- ---------------------------------------------------------------- module

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR")
    c.setLevel(10)
    c.setPosition(1454, 0.5, 0.5)
    c.setItem(SWORD, { kind = "INVTYPE_WEAPON", stats = { [STR] = 5 }, classID = 2, subclassID = 7,
                       minLevel = 1, unmet = { "Swords" } })
    c.setItem(WAND, { kind = "INVTYPE_WEAPON", stats = { [STR] = 5 }, classID = 2, subclassID = 19,
                      minLevel = 1, unmet = { "Wands" } })
    c.setWorn(16, false); c.setWorn(17, false)
    c.setDualWield(false)
    if opts.skills ~= false then c.setWeaponSkills(opts.skills or { "Axes", "Defense" }) end
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    local api = WM().Declare(k, packs())
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api
end

T["weapon master step module: an untrained upgrade shown gives the step"] = function(t)
    if type(WM()) ~= "table" then return t.ok(false, "no module") end
    local k, c, api = start()
    t.eq(api.step(), nil, "nothing shown yet")
    c.showItemTooltip(SWORD)
    local step = api.step()
    t.ok(step ~= nil, "shown: offered")
    t.eq(step and step.skill, "Swords")
    t.eq(api.lines(), { "A weapon master in a capital city teaches Swords." })
    t.eq(k.use(WM().NAME).Step().skill, "Swords", "others ask for it by name")
end

T["weapon master step module: a kind the class can never use gives none"] = function(t)
    if type(WM()) ~= "table" then return t.ok(false, "no module") end
    local _, c, api = start()
    c.showItemTooltip(WAND)
    t.eq(api.step(), nil)
end

T["weapon master step module: training the skill takes the step away"] = function(t)
    if type(WM()) ~= "table" then return t.ok(false, "no module") end
    local _, c, api = start()
    c.showItemTooltip(SWORD)
    t.ok(api.step() ~= nil)
    c.setWeaponSkills({ "Axes", "Swords", "Defense" })
    c.fire("SKILL_LINES_CHANGED")
    t.eq(api.step(), nil)
    t.eq(api.lines(), {})
end

T["weapon master step module: the setting row, on by default, turns the step off"] = function(t)
    if type(WM()) ~= "table" then return t.ok(false, "no module") end
    local k, c, api = start()
    local row = k.settings:row(WM().SETTING)
    t.eq(row and row.type, "bool")
    t.eq(row and row.group, "travel.route")
    t.eq(k.settings:get(WM().SETTING), true, "on by default")
    c.showItemTooltip(SWORD)
    k.settings:set(WM().SETTING, false)
    t.eq(api.step(), nil)
    k.settings:set(WM().SETTING, true)
    t.ok(api.step() ~= nil)
end

T["weapon master step module: skills not read, or the read raising: no step, no fault"] = function(t)
    if type(WM()) ~= "table" then return t.ok(false, "no module") end
    local _, c, api = start({ skills = false })
    c.showItemTooltip(SWORD)
    t.eq(api.step(), nil)
    c.setWeaponSkills({ "Axes" })
    c.setWeaponSkillsFails(true)
    c.showItemTooltip(SWORD)
    t.eq(api.step(), nil)
end

T["weapon master step: look only - nothing trains, buys or clicks"] = function(t)
    local S = WM()
    if type(S) ~= "table" then return t.ok(false, "no module") end
    for name in pairs(S) do
        local n = tostring(name):lower()
        t.ok(not (n:find("^train") or n:find("buy") or n:find("click") or n:find("auto")),
            "no acting function: " .. n)
    end
end

return T
