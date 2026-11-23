local _, ns = ...
-- Lead section 197. The Hunter rotation end to end, the shape of
-- PaladinRotation.lua: the whole add-on loaded on a fake client, the
-- setting -> the client's reads (the pet's among them) -> the chooser ->
-- the icon the player sees and the line the diag word gives; then the gear
-- line on an item's tooltip. Each test changes what the client answers and
-- looks at the icon and the words. Offline: the reads are the fake
-- client's, not the game's. Spell ids are plausible, not read here.
local tests = {}

local D = ns.RotationDriver
local IDS = {
    ["Aspect of the Hawk"] = 13165, ["Aspect of the Monkey"] = 13163, ["Call Pet"] = 883, ["Revive Pet"] = 982,
    ["Feed Pet"] = 6991, ["Hunter's Mark"] = 1130, ["Serpent Sting"] = 1978, ["Auto Shot"] = 75,
    ["Arcane Shot"] = 3044, ["Multi-Shot"] = 2643, ["Raptor Strike"] = 2973, ["Mongoose Bite"] = 1495,
    ["Wing Clip"] = 2974,
}
local RANGED = { "Hunter's Mark", "Serpent Sting", "Auto Shot", "Arcane Shot", "Multi-Shot" }
local MELEE = { "Raptor Strike", "Mongoose Bite", "Wing Clip" }
local HAWK = { ["Aspect of the Hawk"] = true }
local MARKED = { ["Hunter's Mark"] = true, ["Serpent Sting"] = true }
local WOLF = { exists = true, dead = false, inCombat = false, family = "Wolf", happiness = "happy" }
local ENEMY = { exists = true, hostile = true, dead = false }
local AGI = "ITEM_MOD_AGILITY_SHORT"

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    if opts.char then c.setSaved(ns.id.charDB, opts.char) end
    c.setClass("HUNTER"); c.setFaction("Alliance"); c.setLevel(opts.level or 20)
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

-- Whether each shot and each melee spell reaches the target (true, false
-- or nil for not known).
local function reach(c, ranged, melee)
    for _, name in ipairs(RANGED) do c.setInRange(IDS[name], ranged) end
    for _, name in ipairs(MELEE) do c.setInRange(IDS[name], melee) end
end

-- Out of a fight with nothing to do: the hawk up, a happy pet, no target.
local function idle(c, pet)
    c.setPlayerBuffs(HAWK); c.setTargetDebuffs({}); c.setTarget({ exists = false }); c.setCombat(false)
    c.setPet(pet)
    c.advance(1, 5)
end

-- In a fight at range: the hawk up, a happy pet, an enemy marked and stung,
-- shooting, every shot in range and no melee spell in reach.
local function fighting(c, debuffs)
    c.setPlayerBuffs(HAWK); c.setPet(WOLF); c.setTarget(ENEMY); c.setTargetDebuffs(debuffs or MARKED)
    reach(c, true, false)
    c.setCurrentSpell(IDS["Auto Shot"], true); c.setCombat(true)
    c.advance(1, 5)
end

tests["hunter: off until switched on; then the icon shows the suggestion"] = function(t)
    local c, addon, icon = start()
    t.ok(icon ~= nil, "the icon was made at login")
    c.setPlayerBuffs({}); c.setPet(WOLF); c.advance(1, 5)
    t.eq(icon.shown, false, "off by default: nothing shown")
    t.ok(said(c):find("switched off", 1, true), "the diag word says it is off: " .. said(c))
    local ok, why = on(c, addon)
    t.ok(ok, "the setting is taken: " .. tostring(why))
    t.eq(icon.shown, true)
    t.eq(icon.texture, "tex:Aspect of the Hawk", "no aspect on: the aspect first")
    addon.settings:set(D.SETTING, false); c.advance(1, 5)
    t.eq(icon.shown, false, "switched off again: hidden")
end

tests["hunter: aspect, then mark, then sting, then auto shot, then arcane shot"] = function(t)
    local c, addon, icon = start()
    c.setPlayerBuffs({}); c.setPet(WOLF); on(c, addon)
    t.eq(icon.texture, "tex:Aspect of the Hawk")
    c.setPlayerBuffs(HAWK); c.setTarget(ENEMY); c.setTargetDebuffs({}); c.setCombat(false)
    reach(c, true, false); c.setCurrentSpell(IDS["Auto Shot"], false); c.advance(1, 5)
    t.eq(icon.texture, "tex:Hunter's Mark", "an enemy, nothing on it: the mark")
    c.setTargetDebuffs({ ["Hunter's Mark"] = true }); c.advance(1, 5)
    t.eq(icon.texture, "tex:Serpent Sting", "marked: the sting")
    c.setTargetDebuffs(MARKED); c.advance(1, 5)
    t.eq(icon.texture, "tex:Auto Shot", "marked and stung, not shooting: start shooting")
    c.setCurrentSpell(IDS["Auto Shot"], true); c.setCombat(true); c.advance(1, 5)
    t.eq(icon.texture, "tex:Arcane Shot", "shooting: arcane shot")
    t.ok(said(c):find("suggesting Arcane Shot", 1, true), said(c))
end

tests["hunter: no pet out asks to call it, a dead one to revive it, out of a fight only"] = function(t)
    local c, addon, icon = start()
    on(c, addon); idle(c, { exists = false })
    t.eq(icon.shown, true)
    t.eq(icon.texture, "tex:Call Pet", "no pet: call it")
    c.setPet({ exists = true, dead = true }); c.advance(1, 5)
    t.eq(icon.texture, "tex:Revive Pet", "a dead pet: revive it")
    c.setPet({ exists = false }); c.setCombat(true); c.advance(1, 5)
    t.ok(not (icon.shown and icon.texture == "tex:Call Pet"), "in a fight: no call")
end

tests["hunter: the pet not read: nothing about it, and the diag names the read"] = function(t)
    local c, addon, icon = start()
    on(c, addon); idle(c, nil)
    t.eq(icon.shown, false, "pet not read: nothing asked for")
    local line = said(c)
    t.ok(line:find("not read: your pet", 1, true), line)
    c.setPet({ exists = false }); c.advance(1, 5)
    t.eq(icon.texture, "tex:Call Pet", "read now, and none out")
    t.ok(not said(c):find("your pet", 1, true), "read: not named: " .. said(c))
end

tests["hunter: an unhappy pet is fed; its happiness not read asks for nothing"] = function(t)
    local c, addon, icon = start()
    on(c, addon); idle(c, { exists = true, dead = false, happiness = "unhappy" })
    t.eq(icon.texture, "tex:Feed Pet", "unhappy: feed it")
    c.setPet({ exists = true, dead = false, happiness = "content" }); c.advance(1, 5)
    t.eq(icon.shown, false, "content: nothing")
    c.setPet({ exists = true, dead = false }); c.advance(1, 5)
    t.eq(icon.shown, false, "happiness not read: nothing")
end

tests["hunter: reads not given yet say what is missing"] = function(t)
    local c, addon, icon = start({ deadUnknown = true })
    c.setPlayerBuffs({}); c.setPet(WOLF); on(c, addon)
    t.eq(icon.shown, false, "dead not read: nothing shown")
    t.ok(said(c):find("not known whether you are dead", 1, true), said(c))
    c.setDead(false); c.advance(1, 5)
    t.eq(icon.texture, "tex:Aspect of the Hawk", "the read arrived")
    idle(c, WOLF); c.setPlayerBuffs(nil); c.advance(1, 5)
    t.eq(icon.shown, false, "buffs not read: no aspect asked for")
    t.ok(said(c):find("not read: your buffs", 1, true), said(c))
    fighting(c); c.setTargetDebuffs(nil); c.advance(1, 5)
    t.eq(icon.texture, "tex:Arcane Shot", "debuffs not read: mark and sting passed by")
    t.ok(said(c):find("rotation: not read: your debuffs on the target; spells that need them are passed by.",
        1, true), said(c))
end

tests["hunter: range not read is named; melee in reach takes over from the shots"] = function(t)
    local c, addon, icon = start()
    on(c, addon); fighting(c)
    t.eq(icon.texture, "tex:Arcane Shot")
    reach(c, nil, nil); c.advance(1, 5)
    t.eq(icon.shown, false, "range not known: nothing suggested")
    local line = said(c)
    t.ok(line:find("not known whether it is in range", 1, true), line)
    t.ok(line:find("Arcane Shot", 1, true), "names the spell: " .. line)
    c.setCurrentSpell(IDS["Raptor Strike"], false)
    reach(c, false, true); c.advance(1, 5)
    t.eq(icon.texture, "tex:Raptor Strike", "too close for the shots, in melee reach: raptor strike")
    -- HU3: whether Raptor Strike is queued not read: it is not asked for.
    c.setCurrentSpell(IDS["Raptor Strike"], nil); c.advance(1, 5)
    t.eq(icon.texture, "tex:Mongoose Bite", "raptor strike's queued read not given: passed by")
    reach(c, true, false); c.advance(1, 5)
    t.eq(icon.texture, "tex:Arcane Shot", "back at range")
end

-- Shared gap (section 197): the range read is false inside a shot's dead
-- zone too, so "move closer" was wrong there.
tests["hunter: out of range says too far or too close, not only move closer"] = function(t)
    local c, addon, icon = start()
    on(c, addon); fighting(c)
    reach(c, false, false); c.advance(1, 5)
    t.eq(icon.shown, true)
    t.eq(icon.texture, "tex:Arcane Shot", "the shot to get to")
    t.eq(icon.marked, "far", "marked out of range")
    local line = said(c)
    t.ok(line:find("out of range: too far away or too close", 1, true), line)
    t.ok(not line:find("move closer", 1, true), line)
end

tests["hunter: arcane shot on cooldown is passed by, and comes back when ready"] = function(t)
    local c, addon, icon = start()
    on(c, addon); fighting(c)
    t.eq(icon.texture, "tex:Arcane Shot")
    c.setSpellCooldown(IDS["Arcane Shot"], true); c.advance(1, 5)
    t.ok(not (icon.shown and icon.texture == "tex:Arcane Shot"), "on cooldown: not shown")
    t.ok(not (icon.shown and icon.texture == "tex:Raptor Strike"), "and not sent into melee")
    c.setSpellCooldown(IDS["Arcane Shot"], false); c.advance(1, 5)
    t.eq(icon.shown, true, "ready again")
    t.eq(icon.texture, "tex:Arcane Shot")
end

tests["hunter: a spell not learned is never shown"] = function(t)
    local c, addon, icon = start({ unlearned = { ["Hunter's Mark"] = true, ["Serpent Sting"] = true } })
    on(c, addon); fighting(c, {})
    t.eq(icon.texture, "tex:Arcane Shot", "nothing on the target, mark and sting not learned")
    c.setCurrentSpell(IDS["Auto Shot"], false); c.advance(1, 5)
    t.eq(icon.texture, "tex:Auto Shot")
end

tests["hunter: the enemy dying, no target, and your own death take the attack away"] = function(t)
    local c, addon, icon = start()
    on(c, addon); fighting(c)
    t.eq(icon.texture, "tex:Arcane Shot")
    local function shooting()
        return icon.shown and (icon.texture == "tex:Arcane Shot" or icon.texture == "tex:Auto Shot"
            or icon.texture == "tex:Hunter's Mark" or icon.texture == "tex:Serpent Sting")
    end
    c.setTarget({ exists = true, hostile = true, dead = true }); c.setCombat(false); c.advance(1, 5)
    t.ok(not shooting(), "dead target: no shot, got " .. tostring(icon.texture))
    c.setTarget({ exists = false }); c.advance(1, 5)
    t.ok(not shooting(), "no target")
    c.setDead(true); c.advance(1, 5)
    t.eq(icon.shown, false, "you are dead: nothing")
    t.ok(said(c):find("dead; nothing suggested", 1, true), said(c))
end

tests["hunter: no picture for the spell hides the icon, never a blank one"] = function(t)
    local c, addon, icon = start({ noTexture = { ["Aspect of the Hawk"] = true } })
    c.setPlayerBuffs({}); c.setPet(WOLF); on(c, addon)
    t.eq(icon.shown, false)
    t.ok(said(c):find("suggesting Aspect of the Hawk", 1, true), "still explained: " .. said(c))
end

tests["hunter: the switch is kept over a reload"] = function(t)
    local c, addon = start()
    on(c, addon)
    local account, char = c.saved(ns.id.accountDB), c.saved(ns.id.charDB)
    local c2, addon2, icon2 = start({ account = account, char = char })
    t.eq(addon2.settings:get(D.SETTING), true, "still on after the reload")
    c2.setPlayerBuffs({}); c2.setPet(WOLF); c2.advance(1, 5)
    t.eq(icon2.shown, true, "and suggesting with no word typed")
    t.eq(icon2.texture, "tex:Aspect of the Hawk")
end

-- The gear verdict's lines among what the tooltip was given (other
-- modules may add lines of their own to the same tooltip).
local VERDICT = { "Can't use: ", "No verdict: ", "Upgrade for ", "Same as ", "Not an upgrade for " }
local function texts(added)
    local out = {}
    for i = 1, #added do
        local text = tostring(added[i].text)
        for _, head in ipairs(VERDICT) do
            if text:sub(1, #head) == head then
                out[#out + 1] = text
                break
            end
        end
    end
    return out
end

tests["hunter gear: plate refused, mail from level 40, a bow scored"] = function(t)
    local c = start({ level = 30 })
    c.setWorn(5, false); c.setWorn(18, false)
    c.setItem("item:plate", { kind = "INVTYPE_CHEST", stats = { [AGI] = 10 }, classID = 4, subclassID = 4, minLevel = 30 })
    c.setItem("item:mail", { kind = "INVTYPE_CHEST", stats = { [AGI] = 10 }, classID = 4, subclassID = 3, minLevel = 30 })
    c.setItem("item:bow", { kind = "INVTYPE_RANGED", stats = { [AGI] = 5 }, classID = 2, subclassID = 2,
        minLevel = 20, unmet = {} })
    t.eq(texts(c.showItemTooltip("item:plate")),
        { "Can't use: your class cannot use this kind of item (first guess)" }, "plate: never")
    t.eq(texts(c.showItemTooltip("item:mail")),
        { "Can't use: your class can use this kind from level 40 (first guess)" }, "mail at 30: not yet")
    c.setLevel(40)
    t.eq(texts(c.showItemTooltip("item:mail")), { "No verdict: " .. ns.GearUsable.REASON.unconfirmed },
        "mail at 40: the class table allows it; the game's own marks not read")
    c.setItem("item:mail", { kind = "INVTYPE_CHEST", stats = { [AGI] = 10 }, classID = 4, subclassID = 3,
        minLevel = 30, unmet = {} })
    t.eq(texts(c.showItemTooltip("item:mail")), { "Upgrade for your chest (+10, dps)" }, "mail at 40: scored")
    t.eq(texts(c.showItemTooltip("item:bow")), { "Upgrade for your ranged slot (+5, dps)" }, "a bow: scored")
end

return tests
