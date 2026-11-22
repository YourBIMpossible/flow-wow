-- Druid rotation. Spells you don't know yet are skipped automatically, so
-- the list grows with you: a caster at first (Moonfire, Wrath), Bear Form
-- from 10, Cat Form from 20. What's suggested follows the form you're in.
--
-- Rule fields: spell, kind (damage/buff/heal), reason, target (needs a
-- hostile target in range), when = function(ctx) -> bool,
-- adaptive = true (part of a group the profiler may reorder; see Engine).

local _, ns = ...
local A = ns.api

local BEAR = { ["Bear Form"] = true, ["Dire Bear Form"] = true }
local function inCat() return A.Form() == "Cat Form" end
local function inBear() return BEAR[A.Form() or ""] == true end
-- Caster form: no form, or Moonkin. (Travel and Aquatic Form: nothing to cast.)
local function caster()
    local f = A.Form()
    return f == nil or f == "Moonkin Form"
end
local function inAnimal() return inCat() or inBear() end
-- Prowling (stealthed). The game may hide the answer: then "no".
local function stealthed()
    if not IsStealthed then return false end
    local ok, hidden = pcall(IsStealthed)
    return ok and A.Safe(hidden) == true
end
-- What to open with from stealth, the best you know first. Ravage and Shred
-- only land from behind the mob; Pounce stuns from anywhere. Below those
-- levels it's Rake: the bleed starts ticking while you Claw.
local OPENERS = { "Ravage", "Pounce", "Shred", "Rake" }
-- Not enough mana for Wrath (the game says so: "usable, but no mana").
local function outOfMana()
    local _, noMana = A.Usable("Wrath")
    return noMana == true
end

-- Missing, or under `secs` left.
local function needBuff(name, secs)
    local up, left = A.Buff("player", name)
    return not up or left < secs
end
local function missingOnTarget(spell)
    local up = A.Debuff("target", spell)
    return not up
end

-- Pure: a tank, a fight to take (hostile target or in combat), not in Bear yet.
function ns.DruidWantsBear(role, fight, bear)
    return role == "tank" and fight and not bear
end

-- Pure: dps, a fight to take, in no form at all, and not a caster build.
-- form: A.Form() (nil = no form); tree: ns:TalentTree() (nil = unknown).
--
-- Provenance (class B, an independently authored recommendation):
--   Authored by Flow, 2026-11-21. No guide, database or other addon used.
--   Facts used, all already in Flow's code: the role Flow plays you as
--   (ns:LevelingRole(), Modules/Spec.lua); the form the game reports
--   (A.Form()); the tree with most of your talent points (ns:TalentTree());
--   that the cat list below needs Cat Form and the caster list needs no form
--   or Moonkin Form (caster(), druidForms()).
--   Method: the mirror of DruidWantsBear. Flow's own cat list is what a dps
--   druid who knows Cat Form is given, so with a fight to take it asks for
--   the form that list needs. Left alone: any form you're already in (Travel,
--   Aquatic, Moonkin, Bear: your choice), and a druid whose talents are mostly
--   Balance (the caster list is theirs). Talents unread or tied: not Balance.
--   A recommendation, not a game fact; open to correction from fight records.
function ns.DruidWantsCat(role, fight, form, tree)
    return (role == "dps" and fight and form == nil and tree ~= "Balance") and true or false
end

local buffs = {
    { spell = "Mark of the Wild", kind = "buff", reason = "Mark of the Wild missing or running out",
      when = function(c) return not c.inCombat and caster() and needBuff("Mark of the Wild", 60) end },
    { spell = "Thorns", kind = "buff", reason = "Thorns missing or running out",
      when = function(c) return not c.inCombat and caster() and needBuff("Thorns", 30) end },
    -- Prowl before a pull (0.35.335: "in Cat Form it would be nice if the easy
    -- buttons were suggesting to use stealth"). Only with an enemy targeted:
    -- prowling slows you, so it isn't asked for while you travel. Once you
    -- prowl, the target key holds your opener (the cat list below).
    -- Tanking (your role: "Your role" Tank, /flow spec tank, or Auto with
    -- tank talents; ns:LevelingRole()): into Bear Form
    -- when there's a fight to take, the druid's Righteous Fury. Dire Bear
    -- Form first once you know it. Not while you travel with nothing targeted.
    { spell = "Dire Bear Form", kind = "buff", reason = "Tanking: Bear Form",
      when = function(c) return ns.DruidWantsBear(c.role, c.hostile or c.inCombat, inBear()) end },
    { spell = "Bear Form", kind = "buff", reason = "Tanking: Bear Form",
      when = function(c)
          return ns.DruidWantsBear(c.role, c.hostile or c.inCombat, inBear()) and not c.engine:Knows("Dire Bear Form")
      end },
    -- DPS (not a Balance build): into Cat Form when there's a fight to take,
    -- under the same conditions as Bear Form for a tank (ns.DruidWantsCat,
    -- with its provenance note). Before Prowl: that needs the form first.
    { spell = "Cat Form", kind = "buff", reason = "Suggested for DPS: Cat Form",
      when = function(c)
          return ns.DruidWantsCat(c.role, c.hostile or c.inCombat, A.Form(), ns.TalentTree and ns:TalentTree() or nil)
      end },
    { spell = "Prowl", kind = "buff", reason = "Prowl before you pull: your key then holds your opener from stealth",
      when = function(c) return not c.inCombat and c.hostile and inCat() and not stealthed() end },
}

-- Auto attack in Cat or Bear Form ("Attack" on older clients).
-- Not while prowling (0.35.327): with an enemy targeted the key said "Attack",
-- and auto attack on means you swing the moment you're in reach, which
-- throws the opener away. The opener starts your swings by itself.
local melee = {
    { spell = "Attack", target = true, reason = "Start attacking",
      when = function(c) return c.hostile and inAnimal() and not stealthed() and not A.IsCurrent("Attack") end },
    { spell = "Auto Attack", target = true, reason = "Start attacking",
      when = function(c) return c.hostile and inAnimal() and not stealthed() and not A.IsCurrent("Auto Attack") end },
}

local cat = {
    -- Prowling: the opener (0.35.326). After it lands you're out of stealth and
    -- the list below takes over; in a fight the key itself is moved on by the
    -- game (Cast.lua C.STEALTH_STATE).
    { spell = "Ravage", target = true, reason = "Open from stealth (from behind the mob)",
      when = function(c) return c.hostile and inCat() and stealthed() end },
    { spell = "Pounce", target = true, reason = "Open from stealth (it stuns)",
      when = function(c) return c.hostile and inCat() and stealthed() end },
    { spell = "Shred", target = true, reason = "Open from stealth (from behind the mob)",
      when = function(c) return c.hostile and inCat() and stealthed() end },
    { spell = "Ferocious Bite", target = true, reason = "Spend 4+ combo points",
      when = function(c) return c.hostile and inCat() and A.ComboPoints() >= 4 end },
    { spell = "Rip", target = true, reason = "Spend combo points (bleed)",
      when = function(c)
          return c.hostile and inCat() and A.ComboPoints() >= 4 and not c.engine:Knows("Ferocious Bite")
              and missingOnTarget("Rip")
      end },
    { spell = "Rake", target = true, reason = "Rake bleed missing",
      when = function(c) return c.hostile and inCat() and missingOnTarget("Rake") end },
    { spell = "Claw", target = true, reason = "Build combo points",
      when = function(c) return c.hostile and inCat() end },
}

local bear = {
    { spell = "Demoralizing Roar", reason = "Weaken what's hitting you",
      when = function(c) return c.inCombat and c.hostile and inBear() and missingOnTarget("Demoralizing Roar") end },
    { spell = "Maul", target = true, reason = "Maul on your next swing",
      when = function(c) return c.hostile and inBear() and not A.IsCurrent("Maul") end },
}

local bearAoe = {
    { spell = "Swipe", target = true, reason = "Several enemies",
      when = function(c) return c.hostile and inBear() end },
}

-- Entangling Roots holds a melee mob back while you cast (outdoors only: the
-- game says when it can't). Before the pull it's the opener the key casts
-- (the fight starts when it lands, then the key stays on Wrath); in a fight
-- it shows on the icon when the mob is on you again: press it on your bar.
-- Not on a caster mob (it has a mana pool: it casts from where it stands
-- anyway). Beasts and fighters report mana as their power with none of it.
function ns.MeleeMob(manaMax) return not (manaMax and manaMax > 0) end
local function meleeMob() return ns.MeleeMob(A.Safe(UnitPowerMax and UnitPowerMax("target", 0))) end
local function targetOnYou()
    return A.Safe(UnitIsUnit("targettarget", "player")) == true
end
-- It has hit you (or swung at you) in the last few seconds: it's in melee.
-- (The game won't measure the distance to an enemy in a fight.)
local function hittingYou()
    local T = ns.tracker
    if not (T and T.HitBy) then return false end
    return T:HitBy(A.Safe(UnitGUID("target")), A.Safe(UnitName("target")), 3)
end
local roots = {
    -- A melee mob on you and hitting you: Nature's Grasp (instant: its next
    -- hits may root it), then step back and cast. Entangling Roots below is
    -- for one still on its way: under its blows the cast is pushed back.
    -- Mana sense: only with enough left to cast after it.
    { spell = "Nature's Grasp", kind = "buff", reason = "It's hitting you: Nature's Grasp may root it on its next hit",
      when = function(c)
          local E = c.engine
          return c.inCombat and c.hostile and caster() and meleeMob() and targetOnYou() and hittingYou()
              and missingOnTarget("Entangling Roots") and needBuff("Nature's Grasp", 0)
              and E.CanSpare(E.ManaShare(), E.CantAfford(E:Definition()), 0.2)
      end },
    { spell = "Entangling Roots", target = true, reason = "Root it before it reaches you, then cast",
      when = function(c)
          return c.hostile and caster() and meleeMob() and missingOnTarget("Entangling Roots")
              and (not c.inCombat or targetOnYou())
      end },
}

local casterDamage = {
    { spell = "Moonfire", target = true, reason = "Moonfire missing on the target",
      when = function(c) return c.hostile and caster() and missingOnTarget("Moonfire") end },
    { spell = "Wrath", target = true, reason = "Wrath",
      when = function(c) return c.hostile and caster() end },
    -- Out of mana in caster form: hit it with your staff (in one 66 s fight
    -- Flow had nothing to suggest for 52 of 131 checks once the mana ran out).
    { spell = "Attack", target = true, reason = "Out of mana: hit it with your weapon",
      when = function(c) return c.hostile and caster() and outOfMana() and not A.IsCurrent("Attack") end },
    { spell = "Auto Attack", target = true, reason = "Out of mana: hit it with your weapon",
      when = function(c) return c.hostile and caster() and outOfMana() and not A.IsCurrent("Auto Attack") end },
}

local function join(...)
    local out = {}
    for _, list in ipairs({ ... }) do
        for _, rule in ipairs(list) do out[#out + 1] = rule end
    end
    return out
end

-- Plain-language rotation for /flow rot guide, using only spells you know.
local function guide(e)
    local k = function(s) return e:Knows(s) end
    local out = {}
    local function add(s) out[#out + 1] = s end
    add("Before a pull:")
    if k("Mark of the Wild") then add("  - Mark of the Wild on yourself (30 minutes).") end
    if k("Thorns") then add("  - Thorns on yourself (10 minutes): melee mobs hurt themselves.") end
    add("As a caster:")
    if k("Entangling Roots") then add("  1. Entangling Roots on a melee mob to open (the key casts it): it can't reach you.") end
    if k("Moonfire") then add("  2. Moonfire (instant, damage over time).") end
    if k("Wrath") then add("  3. Wrath until it dies; the cast key stays on Wrath for the fight.") end
    if k("Entangling Roots") then add("  - It comes for you again: Entangling Roots on your bar, step back, keep casting.") end
    if k("War Stomp") then add("  - It starts casting close to you: War Stomp on your bar stops it.") end
    if k("Bear Form") then
        add("Bear Form (tough pulls, several mobs):")
        if k("Demoralizing Roar") then add("  1. Demoralizing Roar.") end
        if k("Maul") then add("  2. Maul on every swing (the cast key stays on Maul).") end
        if k("Swipe") then add("  - Several enemies: Swipe.") end
    end
    if k("Cat Form") then
        add("Cat Form (fastest kills, no mana):")
        if k("Rake") then add("  1. Rake.") end
        if k("Claw") then add("  2. Claw to build combo points (the cast key stays on Claw).") end
        if k("Ferocious Bite") then add("  3. Ferocious Bite at 4-5 combo points.")
        elseif k("Rip") then add("  3. Rip at 4-5 combo points.") end
    end
    add("Healing (caster form):")
    if k("Rejuvenation") then add("  - Rejuvenation after a fight (instant, heals over time).") end
    if k("Healing Touch") then add("  - Healing Touch when hurt; mid-fight only when Flow flashes gold.") end
    if k("Regrowth") then add("  - Regrowth: quick heal plus a heal over time.") end
    return out
end

-- Your party or raid (Engine GroupBuff): Mark of the Wild for everyone,
-- Thorns for whoever takes the hits (a tank, or a warrior). Caster form only.
local groupBuffs = {
    canCast = caster,
    { spell = "Mark of the Wild", aura = { "Mark of the Wild", "Gift of the Wild" }, minutes = 30, rebuff = 60,
      who = function() return true end },
    { spell = "Thorns", minutes = 10, rebuff = 30,
      who = function(u) return u.kind == "tank" or u.class == "WARRIOR" end },
}

-- Curses and poisons on you or your group (Engine Dispel). Caster form only.
local dispels = {
    canCast = caster,
    { spell = "Remove Curse", types = { Curse = true } },
    { spell = "Abolish Poison", types = { Poison = true } },
    { spell = "Cure Poison", types = { Poison = true } },
}

-- What the key and each modifier cast, form by form (the first spell of a
-- list you know; no spell twice in a form). Read at the pull (fightKeys) and
-- handed to the game for a change of form in a fight (formKeys).
local FORMS   -- (built once: the key asks ten times a second)
local function druidForms()
    if FORMS then return FORMS end
    local caster = { key = "Wrath", ctrl = { "Moonfire", "Entangling Roots" }, shift = { "Entangling Roots", "Nature's Grasp" },
                     alt = { "Nature's Grasp", "War Stomp" }, more = { "Entangling Roots", "Nature's Grasp", "War Stomp" } }
    local bear = { key = "Maul", ctrl = { "Swipe", "Demoralizing Roar" }, shift = { "Bash", "Growl", "Demoralizing Roar" },
                   alt = { "Enrage", "Growl" }, more = { "Demoralizing Roar", "Growl", "Enrage" } }
    local cat = { key = "Claw", ctrl = { "Ferocious Bite", "Rip", "Rake" }, shift = { "Rake", "Rip" },
                  alt = { "Tiger's Fury", "Dash" }, more = { "Rip", "Prowl" } }
    -- Prowling in Cat Form: the opener on the key, the rest as in Cat Form.
    local prowl = { form = "Cat Form", key = { "Ravage", "Pounce", "Shred", "Rake", "Claw" },
                    ctrl = cat.ctrl, shift = cat.shift, alt = cat.alt, more = cat.more }
    FORMS = { none = caster, ["Moonkin Form"] = caster, ["Bear Form"] = bear, ["Dire Bear Form"] = bear, ["Cat Form"] = cat,
              stealth = prowl }
    return FORMS
end

ns:Register("rotation", "DRUID", {
    guide = guide,
    groupBuffs = groupBuffs,
    dispels = dispels,

    -- Self-heals, considered before anything else (see Engine HealDecision).
    -- In Cat or Bear Form they're not usable, so they're skipped there.
    heals = { "Regrowth", "Healing Touch", "Rejuvenation" },
    -- Spells that wait for your next swing instead of going off at once: the
    -- target button blinks red while one waits (Display.lua, E.UpdateQueued).
    nextSwing = { "Maul" },
    -- Shifts form: Flow learns which spells take you out of a form and says
    -- so in their tooltips (Modules/Rotation/FormSpells.lua).
    shapeshifts = true,
    -- Heals over time: put on early (Engine EarlyHeal), counted as on you for
    -- their duration after you cast them.
    hots = { "Rejuvenation" },
    hotDuration = { Rejuvenation = 12 },
    -- Regrowth heals at once and then for 21 s more: while that's on you it
    -- isn't suggested again (Engine EarlyHeal).
    lingers = { Regrowth = 21 },

    -- What the cast key stays on for a fight (it can't change in combat):
    -- the form's main attack, so pressing it all fight keeps hitting.
    -- Moonfire, Rake and Roar show on the Flow icon to press yourself.
    pullLock = function(s, engine)
        if s and (s.kind == "heal" or s.kind == "emergency") then s = nil end
        if inCat() then
            -- Prowling: the opener, when the game is set to move the key on
            -- once stealth breaks (else it would sit on the key all fight).
            if stealthed() and ns.cast and ns.cast.StealthReady and ns.cast.StealthReady() then
                for _, spell in ipairs(OPENERS) do
                    if engine:Knows(spell) then return spell end
                end
            end
            if engine:Knows("Claw") then return "Claw" end
        elseif inBear() then
            if engine:Knows("Maul") then return "Maul" end
        elseif engine:Knows("Wrath") then
            return "Wrath"
        end
        return s and s.spell
    end,

    -- The target button's queue (Queue.lua): what Ctrl + key and Alt + key cast
    -- in a fight, for the form you're in at the pull (the first you know).
    -- Caster: Moonfire beside Wrath on Ctrl; Entangling Roots on Ctrl + Shift
    -- (to hold a mob off you while you cast); on Alt, when no healthstone or
    -- potion holds it, Nature's Grasp, else War Stomp.
    -- Cat: your finisher beside Claw (Rake until you have one). Bear: Swipe
    -- beside Maul, Bash to stop a cast.
    -- Shift + key is your heal; Alt is your healthstone or potion if you carry one.
    -- (0.35.227: one list for both: what a form's presses are at the pull and
    -- after a change of form mid-fight. Two lists disagreed: Bash could be on
    -- two presses.)
    fightKeys = function()
        local all = druidForms()
        local k = all[A.Form() or "none"] or all.none
        return { ctrl = k.ctrl, shift = k.shift, alt = k.alt, more = k.more }
    end,

    -- What the key and Ctrl + key cast in each form, for a change of form
    -- in the middle of a fight (Cast.lua: the key follows your form).
    formKeys = function() return druidForms() end,

    -- Default priority (first match wins).
    priority = join(buffs, melee, cat, bear, roots, casterDamage),

    -- Per fight type (see Modules/Fight/FightTypes.lua). Missing types use `priority`.
    priorities = {
        aoe = join(buffs, melee, cat, bearAoe, bear, casterDamage),   -- (several mobs: no roots, they keep coming)
    },
})
