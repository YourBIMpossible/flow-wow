local _, ns = ...

-- Tests for ZFlow/Gear/WeaponSkill.lua (G16, with G12's untrained
-- wording): a weapon kind your class can learn but you have not trained
-- reads "Can't use yet: not trained (a weapon master teaches it)"; a kind
-- your class can never use keeps today's line; skills not read keep
-- today's line too. Made-up items and skill lines only. Not seen in game.

local tests = {}

local STR = "ITEM_MOD_STRENGTH_SHORT"
local UNTRAINED = "Can't use yet: not trained (a weapon master teaches it)"

local function pack()
    return {
        weights = { dps = { evidence = "first guess", values = { [STR] = 1 } } },
        proficiency = { evidence = "first guess", [2] = { [0] = true, [7] = true } },
    }
end

-- A one-handed sword (2, 7) or a wand (2, 19), into an empty main hand.
local function weapon(subclass, unmet)
    return { kind = "INVTYPE_WEAPON", stats = { [STR] = 5 }, classID = 2, subclassID = subclass,
             minLevel = 1, unmet = unmet, worn = { [16] = false, [17] = false }, dualWield = false }
end

local function first(lines) return lines and lines[1] and lines[1].text or nil end

tests["weapon skill: the names agreed"] = function(t)
    local W = ns.GearWeaponSkill
    t.ok(type(W) == "table", "the module is there")
    if type(W) ~= "table" then return end
    t.eq(W.SKILL[7], "Swords")
    t.eq(W.SKILL[1], "Two-Handed Axes")
    t.eq(W.SKILL[19], "Wands")
    t.eq(W.REASON, "not trained (a weapon master teaches it)")
end

tests["weapon skill: trained, not trained, or not known"] = function(t)
    local W = ns.GearWeaponSkill
    if type(W) ~= "table" then return t.ok(false, "no module") end
    t.eq(W.Trained(7, { Axes = true, Swords = true }), true)
    t.eq(W.Trained(7, { Axes = true, Defense = true }), false)
    t.eq(W.Trained(7, nil), nil, "skills not read: not known")
    t.eq(W.Trained(7, { Defense = true, Cooking = true }), nil,
        "no weapon skill name at all: the names are not this client's words, not a no")
    t.eq(W.Trained(99, { Axes = true }), nil, "a kind with no skill name: not known")
end

tests["weapon skill: learnable but untrained reads 'not trained', never an upgrade"] = function(t)
    local lines, detail = ns.GearVerdict.Lines(weapon(7, { "Swords" }),
        { pack = pack(), role = "dps", level = 10, skills = { Axes = true } })
    t.eq(first(lines), UNTRAINED)
    t.eq(#lines, 1)
    t.eq(lines[1].tone, "bad")
    t.eq(detail.use.why, "untrained")
    t.eq(detail.use.skill, "Swords")
end

tests["weapon skill: the game's marks not read, untrained still reads 'not trained'"] = function(t)
    local lines = ns.GearVerdict.Lines(weapon(7, nil),
        { pack = pack(), role = "dps", level = 10, skills = { Axes = true } })
    t.eq(first(lines), UNTRAINED)
end

tests["weapon skill: a kind the class can never use keeps today's line"] = function(t)
    local lines = ns.GearVerdict.Lines(weapon(19, nil),
        { pack = pack(), role = "dps", level = 10, skills = { Axes = true } })
    t.eq(first(lines), "Can't use: your class cannot use this kind of item (first guess)")
end

tests["weapon skill: skills not read keep today's line, no guess"] = function(t)
    local today = ns.GearVerdict.Lines(weapon(7, { "Swords" }), { pack = pack(), role = "dps", level = 10 })
    t.eq(first(today), "Can't use: the game marks in red: Swords")
    local unread = ns.GearVerdict.Lines(weapon(7, nil), { pack = pack(), role = "dps", level = 10 })
    t.eq(first(unread), "No verdict: not confirmed by the game: what it marks on the item was not read")
end

tests["weapon skill: trained reads the verdict as before"] = function(t)
    local lines = ns.GearVerdict.Lines(weapon(7, {}),
        { pack = pack(), role = "dps", level = 10, skills = { Swords = true } })
    t.eq(first(lines), "Upgrade for your main hand (+5, dps)")
end

tests["weapon skill: wanted only for an untrained upgrade"] = function(t)
    local W = ns.GearWeaponSkill
    if type(W) ~= "table" then return t.ok(false, "no module") end
    local want = W.Wanted(weapon(7, { "Swords" }), { pack = pack(), level = 10, skills = { Axes = true } })
    t.eq(want, { subclassID = 7, skill = "Swords" })
    t.eq(W.Wanted(weapon(7, {}), { pack = pack(), level = 10, skills = { Swords = true } }), nil, "trained")
    t.eq(W.Wanted(weapon(19, nil), { pack = pack(), level = 10, skills = { Axes = true } }), nil, "never usable")
    t.eq(W.Wanted(weapon(7, nil), { pack = pack(), level = 10 }), nil, "skills not read")
end

tests["weapon skill: look only - nothing trains or buys"] = function(t)
    local W = ns.GearWeaponSkill
    if type(W) ~= "table" then return t.ok(false, "no module") end
    for name in pairs(W) do
        local n = tostring(name):lower()
        t.ok(not (n:find("^train$") or n:find("buy") or n:find("learn")), "no acting function: " .. n)
    end
end

return tests
