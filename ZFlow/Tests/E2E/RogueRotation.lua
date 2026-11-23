local _, ns = ...
-- Lead section 197. The Rogue rotation end to end, on the whole add-on
-- loaded on a fake client: the setting -> the client's reads (stealth as
-- its own yes or no) -> the chooser -> the icon the player sees and the
-- line the diag word gives. Plus gear: what a rogue cannot use is not
-- offered, what it can use is scored. Each test changes what the client
-- answers and looks at the icon and the words. Offline: the reads are the
-- fake client's, not the game's. The spell ids are made up for the test.
local tests = {}

local D = ns.RotationDriver
local IDS = {
    ["Stealth"] = 91001, ["Ambush"] = 91002, ["Garrote"] = 91003, ["Cheap Shot"] = 91004,
    ["Attack"] = 91005, ["Sinister Strike"] = 91006, ["Eviscerate"] = 91007,
    ["Slice and Dice"] = 91008, ["Kick"] = 91009,
}
-- The spells cast on the target: their range is read.
local AIMED = { "Ambush", "Garrote", "Cheap Shot", "Attack", "Sinister Strike", "Eviscerate", "Kick" }
local ENEMY = { exists = true, hostile = true, dead = false }

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    -- These tests read the suggestion without the key frame (on by default
    -- since lead section 294 item 1), so it is switched off unless a test
    -- gives its own char settings.
    c.setSaved(ns.id.charDB, opts.char or { settings = { rotation = { keyFrame = false } } })
    c.setClass("ROGUE"); c.setFaction("Alliance"); c.setLevel(20)
    if not opts.deadUnknown then c.setDead(false) end
    for name, id in pairs(IDS) do
        if not (opts.unlearned and opts.unlearned[name]) then
            c.setSpellId(name, id)
            c.setSpell(id, { known = true, usable = true })
            c.setSpellCooldown(id, false)
        end
        if not (opts.noTexture and opts.noTexture[name]) then c.setSpellTexture(id, "tex:" .. name) end
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    local icon
    for _, h in ipairs(c.icons) do
        if tostring(h.spec.name):find("RotationIcon", 1, true) then icon = h end
    end
    return c, addon, icon
end

local function on(c, addon)
    local ok, why = addon.settings:set(D.SETTING, true)
    c.advance(1, 5)
    return ok, why
end

-- The rotation lines the diag word prints now.
local function said(c)
    local from = #c.printed + 1
    c.slashes[ns.id.slash]("diag")
    local out = {}
    for i = from, #c.printed do
        local line = tostring(c.printed[i])
        if line:find("rotation:", 1, true) then out[#out + 1] = line end
    end
    return table.concat(out, " / ")
end

local function inRange(c, yes)
    for _, name in ipairs(AIMED) do c.setInRange(IDS[name], yes) end
end

-- An enemy targeted, out of a fight, not stealthed, not swinging, in range.
local function pull(c)
    c.setPlayerBuffs({}); c.setTarget(ENEMY); c.setStealthed(false); c.setCombat(false)
    c.setTargetDebuffs({}); c.setCurrentSpell(IDS["Attack"], false); inRange(c, true)
    c.advance(1, 5)
end

-- In the fight, out of stealth, already swinging, everything in range.
local function fighting(c)
    c.setPlayerBuffs({}); c.setTarget(ENEMY); c.setStealthed(false); c.setCombat(true)
    c.setTargetDebuffs({}); c.setCurrentSpell(IDS["Attack"], true); inRange(c, true)
    c.advance(1, 5)
end

tests["rogue: off until switched on; then the icon shows the suggestion"] = function(t)
    local c, addon, icon = start()
    t.ok(icon ~= nil, "the icon was made at login")
    pull(c)
    t.eq(icon.shown, false, "off by default: nothing shown")
    t.ok(said(c):find("switched off", 1, true), "the diag word says it is off: " .. said(c))
    local ok, why = on(c, addon)
    t.ok(ok, "the setting is taken: " .. tostring(why))
    t.eq(icon.shown, true)
    t.eq(icon.texture, "tex:Stealth", "an enemy, out of a fight: stealth first")
    addon.settings:set(D.SETTING, false); c.advance(1, 5)
    t.eq(icon.shown, false, "switched off again: hidden")
end

tests["rogue: stealth, the opener from stealth, then the strike"] = function(t)
    local c, addon, icon = start()
    on(c, addon); pull(c)
    t.eq(icon.texture, "tex:Stealth")
    c.setStealthed(true); c.advance(1, 5)
    t.eq(icon.texture, "tex:Ambush", "stealthed: the opener")
    t.ok(said(c):find("suggesting Ambush", 1, true), said(c))
    c.setSpell(IDS["Ambush"], { known = true, usable = false }); c.advance(1, 5)
    t.eq(icon.texture, "tex:Garrote", "the game refuses Ambush: Garrote")
    c.setStealthed(false); c.setCombat(true); c.setCurrentSpell(IDS["Attack"], true); c.advance(1, 5)
    t.eq(icon.texture, "tex:Sinister Strike", "out of stealth, swinging: the strike")
end

tests["rogue: no finisher is shown while the combo read is not built"] = function(t)
    local c, addon, icon = start()
    on(c, addon); fighting(c)
    t.eq(icon.texture, "tex:Sinister Strike")
    c.advance(5, 20)
    t.ok(icon.texture ~= "tex:Eviscerate" and icon.texture ~= "tex:Slice and Dice",
        "no finisher without the read: " .. tostring(icon.texture))
end

tests["rogue: Stealth not learned: the swing on the pull"] = function(t)
    local c, addon, icon = start({ unlearned = { ["Stealth"] = true } })
    on(c, addon); pull(c)
    t.ok(not (icon.shown and icon.texture == "tex:Stealth"), "Stealth not learned: never shown")
    t.eq(icon.texture, "tex:Attack", "the swing instead")
end

tests["rogue: reads not given yet say what is missing, and show nothing"] = function(t)
    local c, addon, icon = start({ deadUnknown = true })
    pull(c); on(c, addon)
    t.eq(icon.shown, false, "dead not read: nothing shown")
    t.ok(said(c):find("not known whether you are dead", 1, true), said(c))
    c.setDead(false); c.advance(1, 5)
    t.eq(icon.shown, true, "the read arrived: shown")
    t.eq(icon.texture, "tex:Stealth")
    -- Stealth not read: no Stealth, no swing, no strike.
    c.setStealthed(nil); c.advance(1, 5)
    local strike = { ["tex:Stealth"] = true, ["tex:Attack"] = true, ["tex:Sinister Strike"] = true }
    t.ok(not (icon.shown and strike[icon.texture]), "stealth not read: got " .. tostring(icon.texture))
end

tests["rogue: range not read is the reason given, not that nothing is out of range"] = function(t)
    local c, addon, icon = start()
    c.setPlayerBuffs({}); c.setTarget(ENEMY); c.setStealthed(false); c.setCombat(true)
    c.setCurrentSpell(IDS["Attack"], true); on(c, addon)
    t.eq(icon.shown, false, "range not known: nothing suggested")
    local line = said(c)
    t.ok(line:find("not known whether it is in range", 1, true), line)
    t.ok(line:find("Sinister Strike", 1, true), "names the spell: " .. line)
    t.ok(not line:find("(nothing out of range)", 1, true), line)
    c.setInRange(IDS["Sinister Strike"], true); c.advance(1, 5)
    t.eq(icon.shown, true, "the range arrived")
    t.eq(icon.texture, "tex:Sinister Strike")
end

tests["rogue: Stealth on cooldown is passed by, and comes back when ready"] = function(t)
    local c, addon, icon = start()
    on(c, addon); pull(c)
    t.eq(icon.texture, "tex:Stealth")
    c.setSpellCooldown(IDS["Stealth"], true); c.advance(1, 5)
    t.ok(not (icon.shown and icon.texture == "tex:Stealth"), "on cooldown: not shown")
    c.setSpellCooldown(IDS["Stealth"], false); c.advance(1, 5)
    t.eq(icon.texture, "tex:Stealth", "ready again")
    -- Out of range in the fight: the words say so.
    fighting(c); inRange(c, false); c.advance(1, 5)
    t.ok(said(c):find("out of range", 1, true), "told it is out of range: " .. said(c))
end

tests["rogue: a spell not learned is never shown"] = function(t)
    local c, addon, icon = start({ unlearned = { ["Ambush"] = true, ["Garrote"] = true } })
    on(c, addon); pull(c); c.setStealthed(true); c.advance(1, 5)
    t.ok(not (icon.shown and (icon.texture == "tex:Ambush" or icon.texture == "tex:Garrote")), tostring(icon.texture))
    t.eq(icon.texture, "tex:Cheap Shot", "the opener that is learned")
end

tests["rogue: the enemy dying, no target, and your own death take the attack away"] = function(t)
    local c, addon, icon = start()
    on(c, addon); fighting(c)
    t.eq(icon.texture, "tex:Sinister Strike")
    local attack = { ["tex:Sinister Strike"] = true, ["tex:Attack"] = true, ["tex:Ambush"] = true,
                     ["tex:Garrote"] = true, ["tex:Cheap Shot"] = true, ["tex:Stealth"] = true }
    local function attacking() return icon.shown and attack[icon.texture] == true end
    c.setTarget({ exists = true, hostile = true, dead = true }); c.setCombat(false); c.advance(1, 5)
    t.ok(not attacking(), "dead target: no attack, got " .. tostring(icon.texture))
    c.setTarget({ exists = false }); c.advance(1, 5)
    t.ok(not attacking(), "no target")
    c.setDead(true); c.advance(1, 5)
    t.eq(icon.shown, false, "you are dead: nothing")
    t.ok(said(c):find("dead; nothing suggested", 1, true), said(c))
end

tests["rogue: no picture for the spell hides the icon, never a blank one"] = function(t)
    local c, addon, icon = start({ noTexture = { ["Stealth"] = true } })
    on(c, addon); pull(c)
    t.eq(icon.shown, false)
    t.ok(said(c):find("suggesting Stealth", 1, true), "still explained: " .. said(c))
end

tests["rogue: the switch is kept over a reload"] = function(t)
    local c, addon = start()
    on(c, addon)
    local account, char = c.saved(ns.id.accountDB), c.saved(ns.id.charDB)
    local c2, addon2, icon2 = start({ account = account, char = char })
    t.eq(addon2.settings:get(D.SETTING), true, "still on after the reload")
    pull(c2)
    t.eq(icon2.shown, true, "and suggesting with no word typed")
    t.eq(icon2.texture, "tex:Stealth")
end

-- Gear: the add-on's own client, with the item's class, subclass, needed
-- level and what the game marks on it added to the gear read.
local LEATHER, PLATE = "item:2", "item:7"

local function gearClient()
    local c = start()
    c.setItem(LEATHER, { kind = "INVTYPE_HEAD", stats = { ITEM_MOD_AGILITY_SHORT = 10, ITEM_MOD_STAMINA_SHORT = 10 } })
    c.setItem(PLATE, { kind = "INVTYPE_HEAD", stats = { ITEM_MOD_STRENGTH_SHORT = 10, ITEM_MOD_STAMINA_SHORT = 10 } })
    c.setWorn(1, false)
    -- Leather helm: the game marks nothing. Plate helm: the marks not read.
    local types = { [LEATHER] = { 4, 2, 1, {} }, [PLATE] = { 4, 4, 1, nil } }
    local gear = c.gear
    c.gear = function(link)
        local g = gear(link)
        local ty = types[link]
        if ty and type(g) == "table" then
            g.classID, g.subclassID, g.minLevel, g.unmet = ty[1], ty[2], ty[3], ty[4]
        end
        return g
    end
    return c
end

tests["rogue gear: a leather helm is scored, a plate helm is not offered"] = function(t)
    local c = gearClient()
    local lines = ns.GearTooltipModule.Lines(c, ns.Packs, LEATHER)
    t.ok(type(lines) == "table" and #lines >= 1, "the helm has lines")
    for _, line in ipairs(lines or {}) do
        t.eq(line.tone, "good", line.text)
        t.ok(line.text:find("^Upgrade for your head piece %(%+") ~= nil, line.text)
    end
    t.eq(ns.GearTooltipModule.Lines(c, ns.Packs, PLATE),
        { { text = "Can't use: your class cannot use this kind of item (first guess)", tone = "bad" } })
end


-- The Flow button (the key frame) is on by default, so the engage step can
-- start the swing. Starting it breaks stealth: at the default profile the
-- rogue at the pull is still told Stealth, not Attack. Stealth not ready
-- (on a cooldown): the swing.
tests["rogue: default profile, the Flow button on: Stealth at the pull, not Attack"] = function(t)
    local c, addon, icon = start({ char = {} })
    on(c, addon); pull(c)
    t.eq(icon.shown, true)
    t.eq(icon.texture, "tex:Stealth", "an enemy, out of a fight, the Flow button on: stealth first")
end

tests["rogue: default profile, Stealth on a cooldown: the swing at the pull"] = function(t)
    local c, addon, icon = start({ char = {} })
    on(c, addon)
    c.setSpellCooldown(IDS["Stealth"], true)
    pull(c)
    t.eq(icon.shown, true)
    t.eq(icon.texture, "tex:Attack", "Stealth not ready: start attacking")
end

return tests
