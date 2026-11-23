local _, ns = ...

-- The chooser: what to press next, from a snapshot of the moment and a class
-- pack. Pure: it reads only its arguments, calls nothing in the client and
-- keeps no state between calls.
--
--   ns.Choose(snapshot, pack, prefs, bias) -> suggestion, trace
--
-- snapshot (every field is optional; a missing flag is unknown, and reads as
-- "not so" but for dead and inCombat):
--   inCombat, hostile, resting, dead      booleans
--     hostile not known (nil): a list rule that needs a target is not
--       suggested (R.TARGET_UNKNOWN); the list's note names the spells
--       passed by for it, and says so once without a name when only the
--       rules' own conditions turned such a rule down.
--     dead not known (nil), or true: nothing is suggested, and the trace is
--       one "dead" row.
--     inCombat not known (nil) counts as a fight (R.InFight): no dispel, no
--       starting the attack, no top-up heal, nothing a pack keeps for out
--       of a fight (R.OutOfFight is a known "no" only); an interrupt is
--       allowed.
--   role, tree, fightType                 "dps" / "heal" / "tank"; talent tree name; "aoe" or nil
--   form, stealthed                       shapeshift form name or nil; boolean
--   formKnown                             true when form was read (form nil is then no form)
--   finisherReady                         true when the reader can tell a finisher is due
--   casting, targetCasting                the spell you are casting; the spell your target is casting
--   targetNear                            true when the target is within a few yards
--   targetMelee, targetOnYou, hittingYou  target has no mana; target is on you; it hit you just now
--   attacking, canStartAttack             you are swinging; the key can start a swing
--   engageGaveUp                          starting the attack was tried and did not take
--   loc                                   the loss-of-control type holding you ("ROOT"), or nil
--   lowHealth, hurt                       the game's warning; seconds of hits (estimate)
--   buffs         { [name] = secondsLeft or true }   on you
--   targetDebuffs { [name] = true }                  yours, on the target
--   debuffTypes   { [type] = debuffName }            on you ("Poison", "Curse")
--   debuffs       { [name] = secondsLeft or true }   on you, by name (PRIEST-3); nil when not read
--   tree          the talent tree a known talent spell marks (N50, pack options.trees); nil when not known
--   current       { [spell] = true or false }        queued or toggled on (Attack, Maul)
--   conjured      { [conjure spell] = count }        what it makes, in your bags
--                                                    (Snapshot.lua R.Conjured)
--     each of the four maps is nil when not read: a rule that needs one
--       does not fire on nil (section 183). An empty map is read, nothing there.
--   pet           { exists, dead, inCombat, family, happiness, powerKind }  your pet
--     nil when not read (never "no pet"); { exists = false } when the client
--       says there is none. Each other field is nil when not known. Ask it
--       through R.PetUp, R.NoPet and R.PetDead (below), not the bare fields.
--   chosen        { [key] = name }   the seals and blessings you cast or chose
--     (Rotation/OwnCasts.lua, CF-32, N12); nil when there is none. Only a
--       class pack reads it; nothing here does.
--   ownBuffs      { [name] = secondsLeft or true }   on you, put up by you (N13);
--     nil when not read. Only a class pack reads it.
--   spells        { [name] = { known, usable, onCooldown, inRange, noPower, castMs } }
--     onCooldown not known (nil): the spell is not castable; it is not read
--       as off cooldown.
--     inRange not known (nil): a rule that needs range (a list rule that
--       needs a target, an interrupt that is not a near one) is not
--       suggested (R.RANGE_UNKNOWN); it is not read as in range, and not as
--       out of range. The step's note names the spells passed by for it,
--       after the cooldown and target reasons.
--
-- No field is a health or power amount, or made from one: this client hides
-- those from addon code. See R.FROM_AMOUNT in Snapshot.lua.
--
-- prefs: { autoAttack = false to never suggest starting the attack,
--          skip = { [spell] = true } spells never to suggest }
-- bias:  { [spell] = number } what the player has been pressing (used only
--        between neighbouring rules marked adaptive).
--
-- suggestion: { spell, kind, reason, fightType, step } or nil; farOpener's
-- also has label, and minRange = true for a pack with options.minRange.
-- trace: a list of { step, result, spell, note, passed }, one row per step
-- looked at, in order; the last row is the step that answered (result
-- "pick"). passed: the spells that step passed by only because nobody read
-- their cooldown (sorted); absent when there were none.
--
-- The steps, in the order Modules/Rotation/Engine.lua E:Choose runs them:
--   1 breakFree  2 heal  3 interrupt  4 dispel  5 engage  6 list  7 farOpener
-- and then 8 food (section 226, CF-30): Well Fed food out of a fight, last,
-- so a pull, a rotation rule or the far opener comes first. Built here.
-- N8 (lead section 238): in a fight with the low-health warning on, the heal
-- step offers your healthstone, else a healing potion, before any heal spell
-- (snapshot.healItem, Rotation/HealItems.lua).
-- Not in the chooser yet (tasks): other items (bandage, drink), and anything
-- for another player (friend heal, group buffs, group dispels), which needs
-- a party member read.
-- P-PARTY (lead section 233): group buffs and group dispels are now the last
-- step, "group" (Rotation/Group.lua), look only: the suggestion carries
-- look = true, the party unit and the member's name, and the key never
-- casts it (Rotation/Cast.lua). The friend heal is still a task.

ns.Rotation = ns.Rotation or {}
local R = ns.Rotation

-- Seconds of being hit (Flow's estimate) at which a heal is suggested.
R.HURT = { outStart = 6, outBig = 15, inHot = 8, inHeal = 20 }
-- How much more a neighbouring adaptive rule must have been pressed to win.
R.BIAS_EDGE = 0.05

local function row(s, name)
    local spells = s.spells
    return spells and spells[name] or nil
end

-- Is a fight on? Not known (inCombat nil) counts as a fight. Use InFight
-- where a fight forbids or changes something, OutOfFight for what is only
-- for out of a fight; never the bare flag.
function R.InFight(s) return s.inCombat ~= false end
function R.OutOfFight(s) return s.inCombat == false end

-- The pet (lead section 197). Each answers true, false, or nil when it
-- cannot be told; a rule fires only on true, so a pet nobody read is never
-- "no pet" and never "dead".
--   R.PetUp(s)    a pet is out and alive: nil when whether there is one, or
--                 (with one) whether it is dead, was not read
--   R.NoPet(s)    the client said there is no pet: nil when not read
--   R.PetDead(s)  there is a pet and it is dead: false with no pet; nil when
--                 not read, or dead not read
local function petOf(s)
    local p = s.pet
    if type(p) ~= "table" or type(p.exists) ~= "boolean" then return nil end
    return p
end
function R.NoPet(s)
    local p = petOf(s)
    if p == nil then return nil end
    return not p.exists
end
function R.PetDead(s)
    local p = petOf(s)
    if p == nil then return nil end
    if not p.exists then return false end
    if type(p.dead) ~= "boolean" then return nil end
    return p.dead
end
function R.PetUp(s)
    local dead = R.PetDead(s)
    if dead == nil then return nil end
    if R.NoPet(s) then return false end
    return not dead
end

function R.Knows(s, name)
    local r = row(s, name)
    return (r and r.known) and true or false
end

-- Castable now: known, usable, off cooldown. A cooldown nobody read
-- (onCooldown nil) is not "off cooldown": the spell is not castable, and a
-- second result gives the reason, R.COOLDOWN_UNKNOWN. That reason comes
-- only when the cooldown alone is in the way; every other no is a bare
-- false. needRange (R.Ready): and read as in range. A range nobody read
-- (inRange nil) is not "in range": not ready, with the reason
-- R.RANGE_UNKNOWN; read as out of range is a bare false. The cooldown is
-- asked first. R.Ready hands either reason on, and a step that passed a
-- spell by for one says so in its trace note.
R.COOLDOWN_UNKNOWN = "not known whether it is ready"
R.RANGE_UNKNOWN = "not known whether it is in range"

function R.Castable(s, name)
    local r = row(s, name)
    if not (r and r.known and r.usable ~= false) then return false end
    if r.onCooldown == nil then return false, R.COOLDOWN_UNKNOWN end
    return not r.onCooldown
end

function R.Ready(s, name, needRange)
    local ok, why = R.Castable(s, name)
    if not ok then return false, why end
    if not needRange then return true end
    local near = row(s, name).inRange
    if near == nil then return false, R.RANGE_UNKNOWN end
    return near and true or false
end

-- Adds a name to a list of names, once.
local function remember(names, name)
    if not names[name] then
        names[name] = true
        names[#names + 1] = name
    end
end

-- R.Ready for a step. A spell stopped only by a cooldown nobody read is
-- remembered in `unread` (each name once) for the step's note; one stopped
-- only by a range nobody read, in `noRange` when the step gives one.
local function ready(s, name, needRange, unread, noRange)
    local ok, why = R.Ready(s, name, needRange)
    if why == R.COOLDOWN_UNKNOWN then
        remember(unread, name)
    elseif why == R.RANGE_UNKNOWN and noRange then
        remember(noRange, name)
    end
    return ok
end

-- A spell that needs a target is not suggested while nobody read whether
-- there is one (hostile nil). Not read is not "no target".
R.TARGET_UNKNOWN = "not known whether you have a target"

-- The names in a list filled by ready (or the list step), sorted.
local function sorted(names)
    local out = {}
    for i, name in ipairs(names) do out[i] = name end
    table.sort(out)
    return out
end

-- What a step could not tell, beside cooldowns: `target`, the spells passed
-- by for a target not read; `range`, those passed by for a range not read;
-- `declined`, true when the target was not read and a rule that needs one
-- was turned down by its own condition.
local function newGaps()
    return { target = {}, range = {}, declined = false }
end

-- The step's note, with the spells it passed by for a cooldown not read,
-- then (gaps) the target not read, then the range not read. The target
-- reason is said once: with its spells, or alone when no spell is named.
local function noteWith(note, unread, gaps)
    if #unread > 0 then
        note = note .. "; " .. R.COOLDOWN_UNKNOWN .. ": " .. table.concat(sorted(unread), ", ")
    end
    if not gaps then return note end
    if #gaps.target > 0 then
        note = note .. "; " .. R.TARGET_UNKNOWN .. ": " .. table.concat(sorted(gaps.target), ", ")
    elseif gaps.declined then
        note = note .. "; " .. R.TARGET_UNKNOWN
    end
    if #gaps.range > 0 then
        note = note .. "; " .. R.RANGE_UNKNOWN .. ": " .. table.concat(sorted(gaps.range), ", ")
    end
    return note
end

local function allowed(prefs, name)
    return not (prefs and prefs.skip and prefs.skip[name])
end

local function castMs(s, name)
    local r = row(s, name)
    return (r and r.castMs) or 0
end

-- The quickest heal that lands at once (not a heal over time); else the
-- quickest of any.
function R.DirectHeal(heals, hots, ok, ms)
    local isHot = {}
    for _, sp in ipairs(hots or {}) do isHot[sp] = true end
    local function fastest(direct)
        local best, bestMs
        for _, sp in ipairs(heals or {}) do
            if not (direct and isHot[sp]) and ok(sp) then
                local t = ms(sp) or 0
                if not best or t < bestMs then best, bestMs = sp, t end
            end
        end
        return best
    end
    return fastest(true) or fastest(false)
end

-------------------------------------------------------------------------------
-- The steps. Each: (s, pack, prefs, bias, unread) -> suggestion or nil, note
-- unread: a table the step fills with the spells it passed by only because
-- nobody read their cooldown (see ready); a fresh one when left out.
-------------------------------------------------------------------------------

local steps = {}

-- 1. Held in place: break free (not by shifting into the form you are in).
function steps.breakFree(s, pack, prefs, _, unread)
    local t = s.loc
    if not t then return nil, "not held" end
    unread = unread or {}
    for _, b in ipairs(pack.breakers or {}) do
        if (b.any or (b.types and b.types[t])) and not (b.form and s.form == b.spell)
            and allowed(prefs, b.spell) and ready(s, b.spell, nil, unread) then
            return { spell = b.spell, kind = "emergency",
                     reason = string.format("You are held (%s): break free", (string.gsub(string.lower(t), "_", " "))) }
        end
    end
    return nil, noteWith("nothing ready breaks " .. tostring(t), unread)
end

-- N8 (lead section 238, Flow Modules/Rotation/BuffItems.lua PickEmergency):
-- in a fight (inCombat true; not known is no item) with the game's
-- low-health warning on, your healthstone when it is ready, else a healing
-- potion when it is ready. A cooldown not read is not ready. snapshot.
-- healItem = { stone, stoneName, stoneWait, potion, potionName, potionWait,
-- alt }; alt is the item on Alt + your rotation key (set out of a fight).
local function healItem(s)
    local h = s.healItem
    if type(h) ~= "table" or s.inCombat ~= true or s.lowHealth ~= true then return nil end
    local id, name
    if h.stone and h.stoneWait == 0 then
        id, name = h.stone, h.stoneName
    elseif h.potion and h.potionWait == 0 then
        id, name = h.potion, h.potionName
    end
    if type(id) ~= "number" then return nil end
    name = type(name) == "string" and name or ("item " .. id)
    local how = h.alt == id and "press Alt + your rotation key"
        or "press it on your bar or in your bag: the key is locked in a fight"
    return { item = name, itemId = id, kind = "emergency",
             reason = string.format("Low health: use your %s now (%s)", name, how) }
end
R._healItem = healItem   -- (tests)

-- 2. Healing yourself. Only yourself: pack.heals.self. First the healing
-- items (N8), which need no pack.
function steps.heal(s, pack, prefs, _, unread)
    if not s.dead then
        local item = healItem(s)
        if item then return item end
    end
    local heals = pack.heals and pack.heals.self
    if not heals or s.dead then return nil, "no heals" end
    for _, h in ipairs(heals) do
        if h == s.casting then return nil, "already casting a heal" end
    end
    -- Buffs not read: a heal over time may already be on, so none is
    -- suggested; the direct heals below still run (section 183).
    local buffsKnown = type(s.buffs) == "table"
    local buffs = s.buffs or {}
    unread = unread or {}
    local function ok(sp) return allowed(prefs, sp) and ready(s, sp, nil, unread) end
    local function ms(sp) return castMs(s, sp) end

    if s.lowHealth then
        local best = R.DirectHeal(heals, pack.heals.hots, ok, ms)
        if best then
            return { spell = best, kind = R.InFight(s) and "emergency" or "heal",
                     reason = "Low health (the game's warning is on): heal now" }
        end
        return nil, noteWith("low health, no heal ready", unread)
    end

    local hurt = s.hurt
    if type(hurt) ~= "number" then return nil, "no estimate of being hurt" end

    -- A heal over time that is already on you is not cast again.
    local hot, ticking, isHot = nil, false, {}
    for _, sp in ipairs(pack.heals.hots or {}) do
        isHot[sp] = true
        if buffs[sp] then ticking = true
        elseif buffsKnown and not hot and ok(sp) then hot = sp end
    end
    local lingering, again = {}, nil
    for sp in pairs(pack.heals.lingers or {}) do
        if buffs[sp] then
            lingering[sp] = true
            ticking = true
            if ok(sp) then again = again or sp end
        end
    end
    local fast, fastMs, big, bigMs
    for _, sp in ipairs(heals) do
        if ok(sp) and not (isHot[sp] and sp ~= hot) and not lingering[sp] then
            local t = ms(sp)
            if not fastMs or t < fastMs then fast, fastMs = sp, t end
            if not bigMs or t > bigMs then big, bigMs = sp, t end
        end
    end
    local function heal(spell, why)
        if not spell then return nil, noteWith("hurt, no heal ready", unread) end
        return { spell = spell, kind = "heal", early = true,
                 reason = string.format("%s (Flow's estimate: about %d s of hits since you last healed)", why, hurt) }
    end

    local H = R.HURT
    if R.InFight(s) then   -- in a fight, or not known: no top-up
        if hurt >= H.inHeal then
            local direct = R.DirectHeal(heals, pack.heals.hots, function(sp) return not lingering[sp] and ok(sp) end, ms)
            return heal(direct or fast or again, "You have been hit a lot: heal now")
        end
        if hurt >= H.inHot and hot then return heal(hot, "Hit for a while: " .. hot .. " now, before it is a problem") end
        return nil, "not hurt enough in a fight"
    end
    if hurt < H.outStart then return nil, "not hurt enough" end
    if hurt < H.outBig then
        local why = s.hostile and "Top up before you pull" or "A little hurt: top up"
        if hot then return heal(hot, why) end
        if ticking then return nil, "a heal over time is on you" end
        return heal(fast, why)
    end
    return heal(big or fast, s.hostile and "Hurt: heal up before you pull" or "Hurt from your fights: heal up before the next pull")
end

-- An interrupt row's forms (lead 197): none named, any form; named, only
-- in one of them, and only when the form was read (not read is not a yes).
local function inForms(s, forms)
    if type(forms) ~= "table" then return true end
    if s.formKnown ~= true then return false end
    return forms[s.form or "none"] == true
end

-- 3. Your target is casting: stop it. Your own target only.
function steps.interrupt(s, pack, prefs, _, unread)
    if not (R.InFight(s) and s.hostile == true and s.targetCasting) then return nil, "target is not casting" end
    unread = unread or {}
    local gaps = newGaps()
    for _, r in ipairs(pack.interrupts or {}) do
        local reach = true
        if r.near then reach = s.targetNear == true end
        reach = reach and inForms(s, r.forms)
        if reach and allowed(prefs, r.spell) and ready(s, r.spell, not r.near, unread, gaps.range) then
            return { spell = r.spell, kind = "damage",
                     reason = string.format("Stop its %s: %s", tostring(s.targetCasting), r.spell) }
        end
    end
    return nil, noteWith("no interrupt ready", unread, gaps)
end

-- 4. Something on you that you can remove: out of a fight, yourself only.
function steps.dispel(s, pack, prefs, _, unread)
    local list = pack.dispels
    if not list or #list == 0 then return nil, "no dispels" end
    if not R.OutOfFight(s) then
        return nil, s.inCombat and "in a fight" or "not known whether you are in a fight"
    end
    local types = s.debuffTypes
    if not types then return nil, "nothing to remove" end
    unread = unread or {}
    for _, rule in ipairs(list) do
        if R.Knows(s, rule.spell) and allowed(prefs, rule.spell) and (not rule.when or rule.when(s)) then
            for kind in pairs(rule.types or {}) do
                if types[kind] and ready(s, rule.spell, nil, unread) then
                    return { spell = rule.spell, kind = "buff", unit = "player",
                             reason = string.format("%s on you: %s (%s)", rule.spell, string.lower(kind), tostring(types[kind])) }
                end
            end
        end
    end
    return nil, noteWith("nothing ready removes it", unread)
end

-- 5. An enemy targeted, not fighting yet: start the attack first.
function steps.engage(s, pack, prefs)
    if s.hostile ~= true or not R.OutOfFight(s) then return nil, "not a pull" end
    if prefs and prefs.autoAttack == false then return nil, "switched off" end
    if s.engageGaveUp then return nil, "gave up starting the attack" end
    if s.attacking or not s.canStartAttack then return nil, "already swinging, or the key cannot start it" end
    -- Starting the swing breaks stealth, so it is started only when stealth
    -- was read and the answer was no. Not read is not "not stealthed".
    if s.stealthed == nil then return nil, "not known whether you are stealthed" end
    if s.stealthed ~= false then return nil, "stealthed" end
    local spell = (R.Knows(s, "Auto Attack") and "Auto Attack") or (R.Knows(s, "Attack") and "Attack") or nil
    if not spell then return nil, "no attack known" end
    return { spell = spell, kind = "damage", engage = true,
             reason = "Start attacking: auto attack on now, your opener with the next press" }
end

local function listFor(s, pack)
    local lists = pack.lists or {}
    return (s.fightType and lists[s.fightType]) or lists.default or {}
end

-- Is the rule wanted? A second result, true, when the no came from the
-- rule's own condition (when) and nothing before it.
local function ruleWants(s, rule, prefs)
    if rule.kind == "buff" and R.OutOfFight(s) and s.resting == true then return false end
    if not allowed(prefs, rule.spell) or not R.Knows(s, rule.spell) then return false end
    if not rule.when or rule.when(s) then return true end
    return false, true
end

-- Wanted and ready. Asked in this order, so a spell is named for the first
-- thing nobody read and for nothing after it: the cooldown; then, for a
-- rule that needs a target, the target (hostile nil: remembered in
-- gaps.target); then its range (inRange nil: remembered in gaps.range).
-- With the target not read, a rule that needs one and was turned down by
-- its own condition sets gaps.declined: the condition may have read "not
-- known" as "no".
local function ruleReady(s, rule, prefs, unread, gaps)
    local wants, declined = ruleWants(s, rule, prefs)
    if not wants then
        if declined and rule.target and s.hostile == nil then gaps.declined = true end
        return false
    end
    if not ready(s, rule.spell, nil, unread) then return false end
    if not rule.target then return true end
    if s.hostile == nil then
        remember(gaps.target, rule.spell)
        return false
    end
    return ready(s, rule.spell, true, unread, gaps.range)
end

local function suggest(rule, learned)
    return { spell = rule.spell, kind = rule.kind or "damage",
             reason = (rule.reason or rule.spell) .. (learned and " (learned)" or "") }
end

-- 6. The priority list for this kind of fight: the first ready rule wins.
-- Neighbouring rules marked adaptive are one group: the first ready one
-- wins unless a later ready one has been pressed clearly more (bias).
function steps.list(s, pack, prefs, bias, unread)
    local list = listFor(s, pack)
    bias = bias or {}
    unread = unread or {}
    local gaps = newGaps()
    local i, n = 1, #list
    while i <= n do
        local rule = list[i]
        if rule.adaptive then
            local best, bestBias
            while i <= n and list[i].adaptive do
                local r = list[i]
                if ruleReady(s, r, prefs, unread, gaps) then
                    local b = bias[r.spell] or 0
                    if not best or b > bestBias + R.BIAS_EDGE then best, bestBias = r, b end
                end
                i = i + 1
            end
            if best then return suggest(best, bestBias > R.BIAS_EDGE) end
        else
            if ruleReady(s, rule, prefs, unread, gaps) then return suggest(rule) end
            i = i + 1
        end
    end
    return nil, noteWith("no rule ready", unread, gaps)
end

-- 7. An enemy targeted and the first rule that wants it is only out of range.
-- A pack whose spells have a minimum range (options.minRange = true, lead
-- section 197: the hunter's dead zone) gets minRange = true on the
-- suggestion and "too far or too close" in its reason: the client's range
-- read answers false inside the dead zone as well as too far away, so
-- "move closer" alone would be wrong.
function steps.farOpener(s, pack, prefs, _, unread)
    if s.hostile == nil then return nil, R.TARGET_UNKNOWN end
    if not s.hostile then return nil, "no enemy targeted" end
    unread = unread or {}
    local minRange = type(pack.options) == "table" and pack.options.minRange == true
    for _, rule in ipairs(listFor(s, pack)) do
        if rule.target and ruleWants(s, rule, prefs) and row(s, rule.spell).inRange == false
            and ready(s, rule.spell, nil, unread) then
            local out = { spell = rule.spell, kind = rule.kind or "damage", label = "Out of range",
                          reason = (rule.reason or rule.spell) .. " (out of range)" }
            if minRange then
                out.minRange = true
                out.reason = (rule.reason or rule.spell) .. " (out of range: too far or too close)"
            end
            return out
        end
    end
    return nil, noteWith("nothing out of range", unread)
end

-- Section 226 (CF-30): eat Well Fed food. Out of a fight only, with your
-- buffs read and no Well Fed among them, and a Well Fed food in your bags
-- (snapshot.buffFood, the driver's pick for your role). Buffs not read is
-- not "no Well Fed": nothing is suggested.
-- Section 230: not with the setting off (BF-3, foodOn false); not while
-- eating or drinking, mounted, or on a flight path, and not when mounted or
-- the flight path is not known (BF-2).
function steps.food(s)
    if s.foodOn == false then return nil, "Well Fed food is switched off" end
    if not R.OutOfFight(s) then return nil, "not out of a fight" end
    if type(s.buffs) ~= "table" then return nil, "your buffs not read" end
    if ns.BuffFood.Eating(s.buffs) then return nil, "eating or drinking" end
    if s.onTaxi == true then return nil, "on a flight path" end
    if s.onTaxi ~= false then return nil, "not known whether you are on a flight path" end
    if s.mounted == true then return nil, "mounted" end
    if s.mounted ~= false then return nil, "not known whether you are mounted" end
    if s.buffs[ns.BuffFood.WELL_FED] then return nil, "Well Fed is on you" end
    local f = s.buffFood
    if type(f) ~= "table" then return nil, "your food not read" end
    if type(f.name) ~= "string" or f.name == "" or type(f.item) ~= "number" then
        return nil, "no Well Fed food in your bags"
    end
    return { item = f.name, itemId = f.item, kind = "food",
             reason = "Eat " .. f.name .. ": Well Fed is not on you" }
end

R.STEPS = { "breakFree", "heal", "interrupt", "dispel", "engage", "list", "farOpener", "food" }
-- 9. P-GATHER: out of a fight, a gathering tracking that is off and can be
-- turned on (Rotation/Gather.lua G.Step). Last: anything above comes first,
-- food included (lead, merge of P-FOOD and P-GATHER).
steps.track = function(s)
    if type(ns.Gather) ~= "table" then return nil, "no gathering tracking" end
    return ns.Gather.Step(s)
end
R.STEPS[#R.STEPS + 1] = "track"
-- 10. P-PARTY: out of a fight, a buff a member of your party is missing, or
-- a curse or poison on one you could remove (Rotation/Group.lua G.Step).
-- Last: it is only shown, so it never pushes off anything the key can do.
steps.group = function(s, pack, prefs)
    if type(ns.PartyGroup) ~= "table" then return nil, "no group suggestions" end
    return ns.PartyGroup.Step(s, pack, prefs)
end
R.STEPS[#R.STEPS + 1] = "group"
R._steps = steps   -- (tests)

function ns.Choose(snapshot, pack, prefs, bias)
    local trace = {}
    if type(snapshot) ~= "table" or type(pack) ~= "table" then
        trace[1] = { step = "input", result = "skip", note = "no snapshot or no pack" }
        return nil, trace
    end
    if snapshot.dead ~= false then
        trace[1] = { step = "dead", result = "skip",
                     note = snapshot.dead and "dead" or "not known whether you are dead" }
        return nil, trace
    end
    for _, name in ipairs(R.STEPS) do
        local unread = {}
        local s, note = steps[name](snapshot, pack, prefs, bias, unread)
        local passed = #unread > 0 and sorted(unread) or nil
        if s then
            s.fightType = snapshot.fightType
            s.step = name
            trace[#trace + 1] = { step = name, result = "pick", spell = s.spell, item = s.item, note = s.reason,
                                  passed = passed }
            return s, trace
        end
        trace[#trace + 1] = { step = name, result = "skip", note = note, passed = passed }
    end
    return nil, trace
end
