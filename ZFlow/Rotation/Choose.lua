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
--     dead not known (nil), or true: nothing is suggested, and the trace is
--       one "dead" row.
--     inCombat not known (nil) counts as a fight (R.InFight): no dispel, no
--       starting the attack, no top-up heal, nothing a pack keeps for out
--       of a fight (R.OutOfFight is a known "no" only); an interrupt is
--       allowed.
--   role, tree, fightType                 "dps" / "heal" / "tank"; talent tree name; "aoe" or nil
--   form, stealthed                       shapeshift form name or nil; boolean
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
--   current       { [spell] = true }                 queued or toggled on (Attack, Maul)
--   spells        { [name] = { known, usable, onCooldown, inRange, noPower, castMs } }
--     onCooldown not known (nil): the spell is not castable; it is not read
--       as off cooldown.
--
-- No field is a health or power amount, or made from one: this client hides
-- those from addon code. See R.FROM_AMOUNT in Snapshot.lua.
--
-- prefs: { autoAttack = false to never suggest starting the attack,
--          skip = { [spell] = true } spells never to suggest }
-- bias:  { [spell] = number } what the player has been pressing (used only
--        between neighbouring rules marked adaptive).
--
-- suggestion: { spell, kind, reason, fightType, step } or nil.
-- trace: a list of { step, result, spell, note }, one row per step looked at,
-- in order; the last row is the step that answered (result "pick").
--
-- The steps, in the order Modules/Rotation/Engine.lua E:Choose runs them:
--   1 breakFree  2 heal  3 interrupt  4 dispel  5 engage  6 list  7 farOpener
-- Left out here on purpose: items (healthstone, potion, bandage, food, drink),
-- anything for another player (friend heal, group buffs, group dispels).

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

function R.Knows(s, name)
    local r = row(s, name)
    return (r and r.known) and true or false
end

-- Castable now: known, usable, off cooldown. A cooldown nobody read
-- (onCooldown nil) is not "off cooldown": the spell is not castable, and a
-- second result gives the reason, R.COOLDOWN_UNKNOWN. That reason comes
-- only when the cooldown alone is in the way; every other no is a bare
-- false. needRange (R.Ready): and not out of range (a range the snapshot
-- does not give counts as in range).
R.COOLDOWN_UNKNOWN = "not known whether it is ready"

function R.Castable(s, name)
    local r = row(s, name)
    if not (r and r.known and r.usable ~= false) then return false end
    if r.onCooldown == nil then return false, R.COOLDOWN_UNKNOWN end
    return not r.onCooldown
end

function R.Ready(s, name, needRange)
    if not R.Castable(s, name) then return false end
    return not (needRange and row(s, name).inRange == false)
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
-- The steps. Each: (s, pack, prefs, bias) -> suggestion or nil, note
-------------------------------------------------------------------------------

local steps = {}

-- 1. Held in place: break free (not by shifting into the form you are in).
function steps.breakFree(s, pack, prefs)
    local t = s.loc
    if not t then return nil, "not held" end
    for _, b in ipairs(pack.breakers or {}) do
        if (b.any or (b.types and b.types[t])) and not (b.form and s.form == b.spell)
            and allowed(prefs, b.spell) and R.Ready(s, b.spell) then
            return { spell = b.spell, kind = "emergency",
                     reason = string.format("You are held (%s): break free", (string.gsub(string.lower(t), "_", " "))) }
        end
    end
    return nil, "nothing ready breaks " .. tostring(t)
end

-- 2. Healing yourself. Only yourself: pack.heals.self.
function steps.heal(s, pack, prefs)
    local heals = pack.heals and pack.heals.self
    if not heals or s.dead then return nil, "no heals" end
    for _, h in ipairs(heals) do
        if h == s.casting then return nil, "already casting a heal" end
    end
    local buffs = s.buffs or {}
    local function ok(sp) return allowed(prefs, sp) and R.Ready(s, sp) end
    local function ms(sp) return castMs(s, sp) end

    if s.lowHealth then
        local best = R.DirectHeal(heals, pack.heals.hots, ok, ms)
        if best then
            return { spell = best, kind = R.InFight(s) and "emergency" or "heal",
                     reason = "Low health (the game's warning is on): heal now" }
        end
        return nil, "low health, no heal ready"
    end

    local hurt = s.hurt
    if type(hurt) ~= "number" then return nil, "no estimate of being hurt" end

    -- A heal over time that is already on you is not cast again.
    local hot, ticking, isHot = nil, false, {}
    for _, sp in ipairs(pack.heals.hots or {}) do
        isHot[sp] = true
        if buffs[sp] then ticking = true
        elseif not hot and ok(sp) then hot = sp end
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
        if not spell then return nil, "hurt, no heal ready" end
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

-- 3. Your target is casting: stop it. Your own target only.
function steps.interrupt(s, pack, prefs)
    if not (R.InFight(s) and s.hostile == true and s.targetCasting) then return nil, "target is not casting" end
    for _, r in ipairs(pack.interrupts or {}) do
        local reach = true
        if r.near then reach = s.targetNear == true end
        if reach and allowed(prefs, r.spell) and R.Ready(s, r.spell, not r.near) then
            return { spell = r.spell, kind = "damage",
                     reason = string.format("Stop its %s: %s", tostring(s.targetCasting), r.spell) }
        end
    end
    return nil, "no interrupt ready"
end

-- 4. Something on you that you can remove: out of a fight, yourself only.
function steps.dispel(s, pack, prefs)
    local list = pack.dispels
    if not list or #list == 0 then return nil, "no dispels" end
    if not R.OutOfFight(s) then
        return nil, s.inCombat and "in a fight" or "not known whether you are in a fight"
    end
    local types = s.debuffTypes
    if not types then return nil, "nothing to remove" end
    for _, rule in ipairs(list) do
        if R.Knows(s, rule.spell) and allowed(prefs, rule.spell) and (not rule.when or rule.when(s)) then
            for kind in pairs(rule.types or {}) do
                if types[kind] and R.Ready(s, rule.spell) then
                    return { spell = rule.spell, kind = "buff", unit = "player",
                             reason = string.format("%s on you: %s (%s)", rule.spell, string.lower(kind), tostring(types[kind])) }
                end
            end
        end
    end
    return nil, "nothing ready removes it"
end

-- 5. An enemy targeted, not fighting yet: start the attack first.
function steps.engage(s, pack, prefs)
    if s.hostile ~= true or not R.OutOfFight(s) then return nil, "not a pull" end
    if prefs and prefs.autoAttack == false then return nil, "switched off" end
    if s.engageGaveUp then return nil, "gave up starting the attack" end
    if s.attacking or not s.canStartAttack then return nil, "already swinging, or the key cannot start it" end
    local spell = (R.Knows(s, "Auto Attack") and "Auto Attack") or (R.Knows(s, "Attack") and "Attack") or nil
    if not spell then return nil, "no attack known" end
    return { spell = spell, kind = "damage", engage = true,
             reason = "Start attacking: auto attack on now, your opener with the next press" }
end

local function listFor(s, pack)
    local lists = pack.lists or {}
    return (s.fightType and lists[s.fightType]) or lists.default or {}
end

local function ruleWants(s, rule, prefs)
    if rule.kind == "buff" and R.OutOfFight(s) and s.resting == true then return false end
    if not allowed(prefs, rule.spell) or not R.Knows(s, rule.spell) then return false end
    return not rule.when or (rule.when(s) and true or false)
end

local function ruleReady(s, rule, prefs)
    return ruleWants(s, rule, prefs) and R.Ready(s, rule.spell, rule.target)
end

local function suggest(rule, learned)
    return { spell = rule.spell, kind = rule.kind or "damage",
             reason = (rule.reason or rule.spell) .. (learned and " (learned)" or "") }
end

-- 6. The priority list for this kind of fight: the first ready rule wins.
-- Neighbouring rules marked adaptive are one group: the first ready one
-- wins unless a later ready one has been pressed clearly more (bias).
function steps.list(s, pack, prefs, bias)
    local list = listFor(s, pack)
    bias = bias or {}
    local i, n = 1, #list
    while i <= n do
        local rule = list[i]
        if rule.adaptive then
            local best, bestBias
            while i <= n and list[i].adaptive do
                local r = list[i]
                if ruleReady(s, r, prefs) then
                    local b = bias[r.spell] or 0
                    if not best or b > bestBias + R.BIAS_EDGE then best, bestBias = r, b end
                end
                i = i + 1
            end
            if best then return suggest(best, bestBias > R.BIAS_EDGE) end
        else
            if ruleReady(s, rule, prefs) then return suggest(rule) end
            i = i + 1
        end
    end
    return nil, "no rule ready"
end

-- 7. An enemy targeted and the first rule that wants it is only out of range.
function steps.farOpener(s, pack, prefs)
    if not s.hostile then return nil, "no enemy targeted" end
    for _, rule in ipairs(listFor(s, pack)) do
        if rule.target and ruleWants(s, rule, prefs) and R.Castable(s, rule.spell)
            and row(s, rule.spell).inRange == false then
            return { spell = rule.spell, kind = rule.kind or "damage", label = "Out of range",
                     reason = (rule.reason or rule.spell) .. " (out of range)" }
        end
    end
    return nil, "nothing out of range"
end

R.STEPS = { "breakFree", "heal", "interrupt", "dispel", "engage", "list", "farOpener" }
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
        local s, note = steps[name](snapshot, pack, prefs, bias)
        if s then
            s.fightType = snapshot.fightType
            s.step = name
            trace[#trace + 1] = { step = name, result = "pick", spell = s.spell, note = s.reason }
            return s, trace
        end
        trace[#trace + 1] = { step = name, result = "skip", note = note }
    end
    return nil, trace
end
