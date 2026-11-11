-- Rotation engine: each tick, work out the single best thing to press.
--
-- 1. Self-preservation: should I heal myself right now?
--    - "efficient" heal: by the time the cast lands, I'll be missing at least
--      as much health as the heal restores (crits ignored), so nothing is wasted.
--    - "emergency" heal: at the current incoming damage I die before I could
--      safely act later, and the mob won't die first.
-- 2. Otherwise the class priority list (buffs, then damage).
--
-- This only SUGGESTS. WoW doesn't allow addons to cast for you; you press the key.

local _, ns = ...
local A, T = ns.api, ns.tracker
local E = {}
ns.rotation = E

-- In an inn or city (resting)? One place to ask, so tests can stand in for
-- it on E: never on the game's own IsResting (that taints it).
function E.Resting() return IsResting and IsResting() and true or false end

local known = {}
local GCD = 1.5
local REACTION = 1.0  -- seconds we allow you to notice and press the key

-- The rotation definition for your class, registered with
-- ns:Register("rotation", CLASS_TOKEN, def). See docs/ARCHITECTURE.md.
function E:Definition()
    local _, class = UnitClass("player")
    return ns:Get("rotation", class)
end

function E:KnownSpells() return known end

function E:RefreshSpells()
    known = A.KnownSpells()
    T:ResetTooltipCache()
end

function E:Knows(spell) return known[spell] == true end

-- Ready = known, usable (mana/resources/conditions), off cooldown, in range.
function E:Ready(spell, unit)
    if not known[spell] then return false end
    local usable = A.Usable(spell)
    if not usable then return false end
    if A.Cooldown(spell) > A.Latency() then return false end
    if unit and not A.InRange(spell, unit) then return false end
    return true
end

local function hostileTarget()
    return UnitExists("target") and UnitCanAttack("player", "target")
        and not UnitIsDead("target")
end

-- Snapshot of the situation that class rules can read.
function E:Context()
    -- Health can be hidden from addons in combat; then heal advice is skipped
    -- (maxHp = 0) but damage and buff suggestions still work.
    -- If either value is hidden, health is UNKNOWN: report maxHp = 0 so no
    -- heal is suggested. (Treating hidden health as 0 made Flow think you
    -- were dying at full health.)
    local hp = A.Safe(UnitHealth("player"))
    local maxHp = A.Safe(UnitHealthMax("player"))
    if not hp or not maxHp or maxHp <= 0 then hp, maxHp = 0, 0 end
    local ok, dtps = pcall(T.DTPS, T)
    if not ok then dtps = 0 end
    local okT, ttd = pcall(T.TargetTTD, T)
    return {
        hp = hp,
        maxHp = maxHp,
        hpPct = maxHp > 0 and hp / maxHp or 1,
        dtps = dtps,
        selfTTD = dtps > 0 and hp / dtps or math.huge,
        targetTTD = okT and ttd or math.huge,
        latency = A.Latency(),
        inCombat = UnitAffectingCombat("player"),
        hostile = hostileTarget(),
        casting = A.Casting(),
        fightType = ns.fight and ns.fight:Classify() or "normal",
        role = ns.LevelingRole and ns:LevelingRole() or "dps",
        lowHealth = A.LowHealthWarning(),   -- the game's red low-health warning is on
        loc = A.LossOfControl(),            -- "STUN", "FEAR"... when something holds you
        engine = self,
    }
end

-------------------------------------------------------------------------------
-- Heal decision
-------------------------------------------------------------------------------

-- Returns suggestion table or nil.
function E:HealDecision(ctx, heals)
    local cfg = ns.db.rotation
    if ctx.maxHp <= 0 or UnitIsDeadOrGhost("player") then return nil end

    -- Already casting a heal: let it land before suggesting another.
    if ctx.casting then
        for _, h in ipairs(heals) do
            if h == ctx.casting then return nil end
        end
    end

    local bestEfficient, bestEfficientAmt, fastest, fastestLand
    for _, spell in ipairs(heals) do
        if self:Ready(spell) then
            local amount = T:HealAmount(spell)
            local _, _, castMs = A.SpellInfo(spell)
            -- Time until the heal actually lands: cast + network round trip.
            local land = (castMs or 0) / 1000 + ctx.latency
            if amount and amount > 0 then
                local deficitAtLand = ctx.maxHp - (ctx.hp - ctx.dtps * land)
                if deficitAtLand >= amount * (1 - cfg.overheal) then
                    -- Prefer the biggest heal that still fits fully.
                    if not bestEfficientAmt or amount > bestEfficientAmt then
                        bestEfficient, bestEfficientAmt = spell, amount
                    end
                end
            end
            if not fastestLand or land < fastestLand then
                fastest, fastestLand = spell, land
            end
        end
    end
    if not fastest then return nil end

    -- Emergency: we'd die before we could finish this heal plus one more
    -- global cooldown of reaction time, unless the mob dies first.
    if ctx.inCombat then
        local danger = ctx.dtps > 0 and ctx.selfTTD < fastestLand + GCD + REACTION
        local mobDiesFirst = ctx.hostile and ctx.targetTTD + 0.5 < ctx.selfTTD
        -- Below the panic line always heal, even if incoming damage reads as 0.
        if (danger and not mobDiesFirst) or ctx.hpPct < cfg.panicPct then
            return { spell = fastest, kind = "emergency",
                     reason = ctx.selfTTD < math.huge
                         and string.format("Emergency: %.1fs to live", ctx.selfTTD)
                         or "Emergency: health very low" }
        end
    end

    if bestEfficient then
        -- In combat, don't stop to top up if the mob is about to die anyway
        -- and we're not under pressure: heal after (or let regen do it).
        if ctx.inCombat and ctx.hostile and ctx.targetTTD < ctx.selfTTD
            and ctx.targetTTD < 3 then
            return nil
        end
        return { spell = bestEfficient, kind = "heal",
                 reason = string.format("Heal: no overheal (%d)", bestEfficientAmt) }
    end
    return nil
end

-------------------------------------------------------------------------------
-- Main evaluation
-------------------------------------------------------------------------------

-- A rotation can give a different priority list per fight type
-- (def.priorities.boss, .elite, .aoe, ...), falling back to def.priority.
local function priorityFor(def, ctx)
    return (def.priorities and def.priorities[ctx.fightType]) or def.priority or {}
end

local function ruleReady(self, rule, ctx)
    -- No buff nagging in inns and cities (resting): you rebuff on the way out.
    if rule.kind == "buff" and not ctx.inCombat and E.Resting() then return false end
    if not self:Knows(rule.spell) then return false end
    if rule.when then
        -- One failing check (e.g. a buff the game hides in combat) skips that
        -- rule only, instead of stopping every suggestion.
        local ok, w = pcall(rule.when, ctx)
        if not ok then self.lastError, self.lastErrorAt = tostring(w), GetTime() return false end
        if not w then return false end
    end
    return self:Ready(rule.spell, rule.target and "target" or nil)
end

local function suggest(rule, ctx, note)
    return { spell = rule.spell, kind = rule.kind or "damage",
             reason = (rule.reason or rule.spell) .. (note or ""),
             fightType = ctx.fightType }
end

-------------------------------------------------------------------------------
-- Healing early, without seeing your health
-------------------------------------------------------------------------------
-- Forever hides your health from add-ons, in fights and out (Flow reads
-- "0/0"), and its combat log is off, so Flow can't see damage either. Waiting
-- for the game's red low-health warning (about a third left) was far too
-- late. So Flow keeps an estimate, E.hurt, in "seconds of being hit":
--   + 1 a second while an enemy is on you (you have its attention, or your
--     target targets you); in a fight where the game won't say: half that
--   - your heals (HEAL_VALUE), natural regen out of combat (1 every 3 s;
--     eating or drinking: 3 a second); all of it when you level up
--   = at least 40 while the game's low-health warning is on
-- and heals on it, early (E.HURT):
--   out of combat, hurt 6+: heal before the next pull, even with an enemy
--     targeted (healing first is the point). The small one (your HoT, or the
--     fastest heal) when a little hurt or about to pull; the big one at 15+.
--   in a fight, hurt 8+: your HoT if it isn't on you; 20+: your fastest heal.
--     The key can't change mid-fight, so they show on the icon with a green
--     "Shift+key": Shift + your key casts your fastest heal on you.
-- Each fight's estimate goes in the log ("[heal]" lines, diagnostics).

E.HURT = { outStart = 6, outBig = 15, inHot = 8, inHeal = 20, low = 40, regen = 1 / 3, eat = 3, max = 60 }
-- How much a heal takes off the estimate (seconds of being hit it makes up
-- for). Lowered in 0.35.95: after a 2-minute fight (low-health warning on)
-- one Rejuvenation and one Healing Touch took the estimate to nearly 0, yet
-- the player went on casting Rejuvenation four more times: still hurt.
E.HEAL_VALUE = { Rejuvenation = 8, Regrowth = 12, ["Healing Touch"] = 15,
                 ["Flash of Light"] = 10, ["Holy Light"] = 15, ["Word of Glory"] = 12, ["Lay on Hands"] = 60,
                 ["First Aid"] = 15 }   -- (a bandage)
E.hurt = 0

-- How much an enemy is on you right now: 1 yes, 0 no, 0.5 the game won't say.
function E.BeingHit()
    local threat = A.Safe(UnitThreatSituation and UnitThreatSituation("player"))
    if threat ~= nil then return threat >= 2 and 1 or 0 end
    if UnitExists("targettarget") then
        local me = A.Safe(UnitIsUnit("targettarget", "player"))
        if me ~= nil then return me and 1 or 0 end
    end
    return 0.5
end

local EATING = { Food = true, Drink = true, ["Food & Drink"] = true, Refreshment = true }
local function eating() return (A.Buff("player", function(n) return EATING[n] end)) end

-- One step of the estimate. inCombat, hit (0..1), eat, low: what the game says now.
function E.StepHurt(hurt, dt, inCombat, hit, eat, low)
    local H = E.HURT
    if inCombat then hurt = hurt + dt * hit
    else hurt = hurt - dt * (eat and H.eat or H.regen) end
    if low then hurt = math.max(hurt, H.low) end
    return math.max(0, math.min(H.max, hurt))
end

-- Your HoT counts as on you for its duration after you cast it (its buff
-- may be hidden in a fight).
local hotCastAt = {}
local function hotUp(spell, def, now)
    if A.Buff("player", spell) then return true end
    local dur = def.hotDuration and def.hotDuration[spell] or 12
    return hotCastAt[spell] ~= nil and now - hotCastAt[spell] < dur
end

-- The heal to suggest for the estimate, or nil. hurt defaults to E.hurt.
function E:EarlyHeal(ctx, def, hurt, now)
    hurt, now = hurt or E.hurt, now or GetTime()
    local heals = def and def.heals
    if not heals or UnitIsDeadOrGhost("player") then return nil end
    if ctx.casting then
        for _, h in ipairs(heals) do if h == ctx.casting then return nil end end
    end
    local H = E.HURT
    local hot, ticking, isHot = nil, false, {}
    for _, sp in ipairs(def.hots or {}) do
        isHot[sp] = true
        if hotUp(sp, def, now) then ticking = true
        elseif not hot and self:Ready(sp) then hot = sp end
    end
    -- (A HoT already on you isn't cast again.)
    local fast, fastMs, big, bigMs
    for _, sp in ipairs(heals) do
        if self:Ready(sp) and not (isHot[sp] and sp ~= hot) then
            local _, _, ms = A.SpellInfo(sp)
            ms = ms or 0
            if not fastMs or ms < fastMs then fast, fastMs = sp, ms end
            if not bigMs or ms > bigMs then big, bigMs = sp, ms end
        end
    end
    local function heal(spell, why)
        if not spell then return nil end
        return { spell = spell, kind = "heal", fightType = ctx.fightType, early = true,
                 reason = string.format("%s (Flow's estimate: about %d s of hits since you last healed; it can't see your health)", why, hurt) }
    end
    if ctx.inCombat then
        if hurt >= H.inHeal then return heal(fast, "You've been hit a lot: heal now (Shift + key)") end
        if hurt >= H.inHot and hot then return heal(hot, "Hit for a while: " .. hot .. " now, before it's a problem (Shift + key)") end
        return nil
    end
    if hurt < H.outStart then return nil end
    if hurt < H.outBig then
        local why = ctx.hostile and "Top up before you pull" or "A little hurt: top up"
        if hot then return heal(hot, why) end
        if ticking then return nil end          -- your HoT is on: it's healing you
        return heal(fast, why)                  -- (no HoT: the quick heal)
    end
    return heal(big or fast, ctx.hostile and "Hurt: heal up before you pull" or "Hurt from your fights: heal up before the next pull")
end


-------------------------------------------------------------------------------
-- When your health is hidden: the game's low-health warning
-------------------------------------------------------------------------------

-- Heal when the game's low-health warning is on (your health itself is
-- hidden from add-ons on Forever). The fastest heal you can cast: at a third
-- of your health there's no time for a slow one. In combat it shows on the
-- Flow icon and glows on your bar (the key is locked for the fight).
function E:LowHealthHeal(ctx, heals)
    if ctx.maxHp > 0 or not ctx.lowHealth or UnitIsDeadOrGhost("player") then return nil end
    if ctx.casting then
        for _, h in ipairs(heals) do if h == ctx.casting then return nil end end
    end
    local best, bestCast
    for _, spell in ipairs(heals) do
        if self:Ready(spell) then
            local _, _, castMs = A.SpellInfo(spell)
            if not bestCast or (castMs or 0) < bestCast then best, bestCast = spell, castMs or 0 end
        end
    end
    if not best then return nil end
    return { spell = best, kind = ctx.inCombat and "emergency" or "heal",
             reason = "Low health (the game's warning is on): heal now" }
end

-------------------------------------------------------------------------------
-- Healing items: a healthstone or potion in a fight, bandages and food after
-- (BuffItems.lua finds them in your bags)
-------------------------------------------------------------------------------

-- Low health in a fight (the game's warning, or a third of your health where
-- it's shown): your healthstone, else your best healing potion, before any
-- heal spell. Every class. The key is locked in a fight, so it shows on the
-- Flow icon and glows on your bar: press it there.
E.EMERGENCY_PCT = 0.35
function E:Emergency(ctx)
    local BI = ns.buffItems
    if not (BI and ctx.inCombat) or ns.db.rotation.emergencyItems == false then return nil end
    if UnitIsDeadOrGhost("player") then return nil end
    local low = ctx.lowHealth or (ctx.maxHp > 0 and ctx.hpPct <= E.EMERGENCY_PCT)
    if not low then return nil end
    local s = BI.EmergencyStep()
    if s then s.fightType = ctx.fightType end
    return s
end

-- Out of a fight and hurt (Flow's estimate): your recovery steps in the
-- order you chose (right-click the Flow key), by default bandage, then food,
-- then a heal spell. A step you have nothing for is skipped. Not while you
-- eat, cast or channel (a bandage is a channel); food only when you're quite
-- hurt and no enemy is targeted (you'd sit down at the pull).
E.FOOD_PCT = 0.6   -- eat at or below this share of your health (where it's shown)
-- (Two small looks at the game, on their own so the tests can stand in.)
function E.RecoverBusy(ctx)
    return UnitIsDeadOrGhost("player") or eating() or ctx.casting or (UnitChannelInfo and UnitChannelInfo("player")) or false
end
function E.Mounted() return (IsMounted and IsMounted()) and true or false end

function E:Recover(ctx, def)
    if ctx.inCombat or E.RecoverBusy(ctx) then return nil end
    -- Hurt: Flow's estimate, your real health where the game shows it, or
    -- the game's low-health warning. All three go through the same order,
    -- so a heal spell never jumps ahead of the bandage you put first, and
    -- "Cast heals" off means no heal spell at all out of a fight.
    local direct = def.heals and (self:HealDecision(ctx, def.heals) or self:LowHealthHeal(ctx, def.heals)) or nil
    local quite = E.hurt >= E.HURT.outBig or ctx.lowHealth or (ctx.maxHp > 0 and ctx.hpPct <= E.FOOD_PCT)
    if not (E.hurt >= E.HURT.outStart or direct or quite) then return nil end
    local BI, r = ns.buffItems, ns.db.rotation
    local mounted = E.Mounted()
    for _, step in ipairs(BI and BI.Order(r.recoverOrder) or { "heal" }) do
        local s
        if step == "bandage" and BI and r.recoverBandage ~= false and not mounted then
            s = BI.BandageStep(r.bandageRank == "low")
        elseif step == "food" and BI and r.recoverFood ~= false and not mounted and not ctx.hostile and quite then
            s = BI.FoodStep(r.recoverBuffFood ~= false)
        elseif step == "heal" and r.recoverHeal ~= false then
            s = direct or self:EarlyHeal(ctx, def)
        end
        if s then s.fightType = ctx.fightType; return s end
    end
    return nil
end

-------------------------------------------------------------------------------
-- Breaking free (stuns, fears...)
-------------------------------------------------------------------------------

-- Spells that get you out, and what they break. "any" = every kind of loss of
-- control. Racials first; extend with ns.rotation.BREAKERS.
E.BREAKERS = {
    { spell = "Will to Survive", any = true },             -- human (newer clients)
    { spell = "Every Man for Himself", any = true },       -- human
    { spell = "Will of the Forsaken", types = { FEAR = true, FEAR_MECHANIC = true, CHARM = true, SLEEP = true } },
    { spell = "Escape Artist", types = { ROOT = true } },  -- gnome
    { spell = "Blessing of Freedom", types = { ROOT = true } },
    -- Druid: changing form frees you from roots (not into the form you're in:
    -- that would only take you out of it).
    { spell = "Travel Form", types = { ROOT = true }, form = true },
    { spell = "Cat Form", types = { ROOT = true }, form = true },
    { spell = "Bear Form", types = { ROOT = true }, form = true },
    { spell = "Dire Bear Form", types = { ROOT = true }, form = true },
}

function E:BreakFree(ctx)
    local t = ctx.loc
    if not t then return nil end
    local form = A.Form()
    for _, b in ipairs(E.BREAKERS) do
        if (b.any or (b.types and b.types[t])) and not (b.form and form == b.spell) and self:Ready(b.spell) then
            return { spell = b.spell, kind = "emergency", fightType = ctx.fightType,
                     reason = string.format("You're held (%s): break free", t:lower():gsub("_", " ")) }
        end
    end
end
-- The heal to suggest now, or nil. In a fight: a healthstone or potion at
-- low health, then heal spells (real health, the game's low-health warning,
-- then Flow's estimate). Out of one: only your recovery order.
function E:HealStep(ctx, def)
    if not ctx.inCombat then return self:Recover(ctx, def) end
    local h = self:Emergency(ctx)
    if not h and def.heals then
        -- Your health is hidden (Forever): the game's own low-health warning
        -- says when you're at about a third or less: heal now, fastest first.
        h = self:HealDecision(ctx, def.heals) or self:LowHealthHeal(ctx, def.heals)
    end
    h = h or self:EarlyHeal(ctx, def)
    if h then h.fightType = ctx.fightType end
    return h
end

function E:Choose()
    local def = self:Definition()
    if not def then return nil end

    pcall(T.SampleTarget, T)
    local ctx = self:Context()
    self.lastCtx = ctx   -- (OnDeck reads it: same moment, no second look)

    -- Stunned, feared, charmed...: break free first, if you can.
    local brk = self:BreakFree(ctx)
    if brk then return brk end

    -- Healing: items and spells in a fight, your recovery order out of one.
    local h = self:HealStep(ctx, def)
    if h then
        local key = (h.spell or h.label or "item") .. (ctx.inCombat and " (in a fight)" or "")
        if key ~= E.lastEarlyLog then
            E.lastEarlyLog = key
            ns:Log("heal", string.format("suggest %s: hurt %.0f%s", key, E.hurt, ctx.hostile and ", enemy targeted" or ""))
        end
        return h
    end
    E.lastEarlyLog = nil

    -- A curse, poison, disease or magic you can remove, on you or your group.
    local d = self:Dispel(ctx, def)
    if d then return d end

    local list = priorityFor(def, ctx)
    local i = 1
    while i <= #list do
        local rule = list[i]
        if rule.adaptive then
            -- A run of adaptive rules is a group of roughly equal options. Pick
            -- the ready one the profiler found most linked to your best fights of
            -- this type. Ties keep the written order.
            local best, bestBias
            local j = i
            while list[j] and list[j].adaptive do
                local r = list[j]
                if ruleReady(self, r, ctx) then
                    local b = ns.profiler and ns.profiler:Bias(ctx.fightType, r.spell) or 0
                    if not best or b > bestBias + 0.05 then best, bestBias = r, b end
                end
                j = j + 1
            end
            if best then
                local note = (bestBias or 0) > 0.05 and " (learned)" or nil
                return suggest(best, ctx, note)
            end
            i = j
        else
            if ruleReady(self, rule, ctx) then return suggest(rule, ctx) end
            i = i + 1
        end
    end
    -- Nothing for you to press: buff your party or raid.
    return self:GroupBuff(ctx, def)
end

-------------------------------------------------------------------------------
-- Buffing your group: the right buff on the right person
-------------------------------------------------------------------------------
-- A rotation lists who gets what (def.groupBuffs):
--   { spell, aura = { names that count } (default the spell), minutes (how
--     long it lasts), rebuff (seconds left to re-cast at), who = fn(u) -> bool,
--     group = "blessing" (one of the group per person: the first that fits) }
--   groupBuffs.canCast = fn() -> bool (e.g. a druid in caster form)
-- u = { unit, name, guid, class, kind = "tank" | "healer" | "melee" | "caster" | "ranged" }.
-- Out of combat, with no enemy targeted, not resting, and nothing else to
-- press: each buff in order, for everyone it fits who's missing it (or it's
-- running out), alive and in range. Yourself: your own priority list.
-- Setting: "Easy button buffs your group" (/flow settings).

-- What someone in your group does, for picking their buff: the role they
-- chose in the group finder first, then their class (a druid by its form).
--   assigned: UnitGroupRolesAssigned ("TANK", "HEALER", "DAMAGER", "NONE")
--   power: UnitPowerType (1 = rage, 3 = energy)
local MELEE = { WARRIOR = true, ROGUE = true, PALADIN = true, DEATHKNIGHT = true }
local CASTER = { MAGE = true, WARLOCK = true, PRIEST = true, SHAMAN = true }
function E.UnitKind(class, assigned, power)
    if assigned == "TANK" then return "tank" end
    if assigned == "HEALER" then return "healer" end
    if class == "HUNTER" then return "ranged" end
    if class == "DRUID" then
        if power == 1 then return "tank" end          -- Bear Form
        if power == 3 then return "melee" end         -- Cat Form
        return "caster"
    end
    if MELEE[class] then return "melee" end
    if CASTER[class] then return "caster" end
    return "melee"
end

-- Your party or raid, without you: only people you can buff now (online,
-- alive, near enough to see, friendly).
function E.GroupUnits()
    local out = {}
    local raid = IsInRaid and IsInRaid()
    local n = raid and GetNumGroupMembers() or (GetNumSubgroupMembers and GetNumSubgroupMembers() or 0)
    for i = 1, n do
        local unit = (raid and "raid" or "party") .. i
        if UnitExists(unit) and not UnitIsUnit(unit, "player") and UnitIsConnected(unit)
            and not UnitIsDeadOrGhost(unit) and UnitIsVisible(unit) and UnitIsFriend("player", unit) then
            -- In combat both can be secret (any test on them errors, every
            -- rotation tick): unknown counts as in range.
            local inRange, checked = UnitInRange(unit)
            inRange, checked = A.Safe(inRange), A.Safe(checked)
            if not (checked and inRange == false) then
                local _, class = UnitClass(unit)
                local assigned = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or "NONE"
                out[#out + 1] = { unit = unit, name = A.Safe(UnitName(unit)) or unit, guid = UnitGUID(unit),
                                  class = class, kind = E.UnitKind(class, assigned, UnitPowerType(unit)) }
            end
        end
    end
    return out
end

-- Is one of these buffs on the unit? true/false and seconds left, or nil
-- when the game won't say (then Flow goes by what it cast: E.buffMemory).
local function auraOn(unit, names)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
        for i = 1, 40 do
            local n, _, _, _, _, e = UnitBuff(unit, i)
            if not n then return false, 0 end
            if names[n] then return true, (e and e > 0) and (e - GetTime()) or math.huge end
        end
        return false, 0
    end
    for i = 1, 40 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
        if not ok then return nil end
        if not a then return false, 0 end
        local n = A.Safe(a.name)
        if n == nil then return nil end
        if names[n] then
            local e = A.Safe(a.expirationTime)
            return true, (e and e > 0) and (e - GetTime()) or math.huge
        end
    end
    return false, 0
end

-- guid -> { [spell] = when you cast it on them } (from the easy button).
E.buffMemory = {}

-- Has this person got it, with more than `rebuff` seconds left?
--   read(unit, names) -> up, left (or nil: unknown); defaults to the game.
function E.GroupCovered(u, rule, now, read)
    local names = {}
    for _, n in ipairs(rule.aura or { rule.spell }) do names[n] = true end
    local up, left = (read or auraOn)(u.unit, names)
    local rebuff = rule.rebuff or 30
    if up ~= nil then return up and left > rebuff end
    local m = u.guid and E.buffMemory[u.guid] and E.buffMemory[u.guid][rule.spell]
    return m ~= nil and (now - m) < ((rule.minutes or 5) * 60 - rebuff)
end

local groupCache   -- { at, s }: reading 40 people's buffs 10 times a second is too much
function E:GroupBuff(ctx, def, now)
    local list = def and def.groupBuffs
    if not list or ns.db.rotation.groupBuffs == false then return nil end
    if ctx.inCombat or ctx.hostile or E.Resting() then return nil end
    if list.canCast and not list.canCast() then return nil end
    now = now or GetTime()
    if groupCache and now - groupCache.at < 1 then return groupCache.s end
    local units = E.GroupUnits()
    -- Who wants what (a "group" gives each person only its first fit).
    local wants = {}
    for i, u in ipairs(units) do
        local done, w = {}, {}
        for _, rule in ipairs(list) do
            if not (rule.group and done[rule.group]) and self:Knows(rule.spell) and rule.who(u) then
                if rule.group then done[rule.group] = true end
                w[rule] = true
            end
        end
        wants[i] = w
    end
    local s
    for _, rule in ipairs(list) do
        for i, u in ipairs(units) do
            if wants[i][rule] and not E.GroupCovered(u, rule, now) and self:Ready(rule.spell, u.unit) then
                s = { spell = rule.spell, kind = "buff", unit = u.unit, target = u.name, guid = u.guid,
                      fightType = ctx.fightType,
                      reason = string.format("%s for %s (%s): missing or running out", rule.spell, u.name, u.kind) }
                break
            end
        end
        if s then break end
    end
    groupCache = { at = now, s = s }
    return s
end
function E.ClearGroupCache() groupCache = nil end

-------------------------------------------------------------------------------
-- Removing curses, poisons, diseases and magic
-------------------------------------------------------------------------------
-- A rotation lists what it can remove (def.dispels, in order of preference):
--   { spell, types = { Curse = true, Poison = true, ... } }
--   dispels.canCast = fn() -> bool (a druid in caster form)
-- You first, then your group's tank, healers and everyone else, alive and in
-- range. Out of combat always (the key casts it). In a fight only for a
-- healer, and only for someone else: the icon shows it (the key can't change
-- mid-fight), so it never pushes your attacks off the icon for a poison on you.

-- Debuff types on a unit, from the game: { Curse = "Curse of Weakness", ... },
-- or nil if the game won't say (hidden in a fight on some clients).
local function debuffTypes(unit)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    local out = {}
    for i = 1, 40 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HARMFUL")
        if not ok then return nil end
        if not a then break end
        local kind = A.Safe(a.dispelName)
        if kind and kind ~= "" and not out[kind] then out[kind] = A.Safe(a.name) or kind end
    end
    return out
end
E._debuffTypes = debuffTypes

-- The first spell you know that removes one of these types: spell, type, debuff name.
function E.DispelFor(dispels, types, knows)
    for _, rule in ipairs(dispels or {}) do
        if knows(rule.spell) then
            for kind in pairs(rule.types) do
                if types[kind] then return rule.spell, kind, types[kind] end
            end
        end
    end
end

local ORDER = { tank = 1, healer = 2 }
local dispelCache
function E:Dispel(ctx, def, now, read)
    local list = def and def.dispels
    if not list or (list.canCast and not list.canCast()) then return nil end
    if ctx.inCombat and ctx.role ~= "heal" then return nil end
    now = now or GetTime()
    if not read and dispelCache and now - dispelCache.at < 0.5 then return dispelCache.s end
    local units = {}
    if not ctx.inCombat then units[1] = { unit = "player", name = "you", kind = "self" } end
    local group = E.GroupUnits()
    table.sort(group, function(a, b) return (ORDER[a.kind] or 3) < (ORDER[b.kind] or 3) end)
    for _, u in ipairs(group) do units[#units + 1] = u end
    local s
    for _, u in ipairs(units) do
        local types = (read or debuffTypes)(u.unit)
        local spell, kind, what = nil, nil, nil
        if types then spell, kind, what = E.DispelFor(list, types, function(sp) return self:Knows(sp) end) end
        if spell and self:Ready(spell, u.unit) then
            s = { spell = spell, kind = "buff", unit = u.unit, target = u.unit ~= "player" and u.name or nil,
                  fightType = ctx.fightType,
                  reason = string.format("%s on %s: %s (%s)", spell, u.name, kind:lower(), tostring(what)) }
            break
        end
    end
    if not read then dispelCache = { at = now, s = s } end
    return s
end
function E.ClearDispelCache() dispelCache = nil end

-- Remember who got what (some clients hide other people's buffs), and look
-- again at once after any cast of yours.
ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellId)
    if unit ~= "player" then return end
    groupCache, dispelCache = nil, nil
    local s = E.current
    if not (s and s.guid and s.unit) then return end
    local name = A.SpellInfo(A.Safe(spellId) or 0)
    if name == s.spell then
        E.buffMemory[s.guid] = E.buffMemory[s.guid] or {}
        E.buffMemory[s.guid][s.spell] = GetTime()
    end
end)
ns:On("GROUP_ROSTER_UPDATE", function() groupCache = nil end)

-- Diagnostics for /flow rot why: why each rule is or isn't suggested.
function E:Explain()
    local out = {}
    local def = self:Definition()
    if not def then return { "No rotation registered for your class." } end
    local n = 0
    for _ in pairs(known) do n = n + 1 end
    out[#out + 1] = string.format("Known spells: %d. Last error: %s", n, tostring(self.lastError or "none"))
    local ok, ctx = pcall(self.Context, self)
    if not ok then
        out[#out + 1] = "Context failed: " .. tostring(ctx)
        return out
    end
    out[#out + 1] = string.format("Fight type %s, hostile target %s, in combat %s, health %s/%s",
        ctx.fightType, tostring(ctx.hostile), tostring(ctx.inCombat), tostring(ctx.hp), tostring(ctx.maxHp))
    local H = E.HURT
    out[#out + 1] = string.format("Hurt estimate: %.0f s of hits (heals out of a fight at %d+, big heal at %d+; in a fight HoT at %d+, heal at %d+); an enemy on you now: %s",
        E.hurt, H.outStart, H.outBig, H.inHot, H.inHeal, tostring(E.BeingHit()))
    local s = self.current
    out[#out + 1] = "Suggesting now: " .. (s and ((s.spell or s.label or "?") .. " (" .. tostring(s.reason) .. ")") or "nothing")
    for _, rule in ipairs(priorityFor(def, ctx)) do
        local state
        if not known[rule.spell] then
            state = "not known (skipped)"
        else
            local okW, w = pcall(function() return not rule.when or rule.when(ctx) end)
            local usable = A.Usable(rule.spell)
            if not okW then state = "condition error: " .. tostring(w)
            elseif not w then state = "condition not met"
            elseif not usable then state = "not usable now (mana/requirements)"
            elseif A.Cooldown(rule.spell) > A.Latency() then state = "on cooldown"
            elseif rule.target and not A.InRange(rule.spell, "target") then state = "out of range"
            else state = "READY" end
            local buttons = self.ButtonsFor and #self:ButtonsFor(rule.spell) or 0
            if buttons == 0 then state = state .. ", NOT on your action bars (can't glow)" end
        end
        out[#out + 1] = "  " .. rule.spell .. ": " .. state
    end
    return out
end


-- What's on deck: the next spells after the current one, in your priority
-- order, among those whose condition holds right now (their cooldowns may
-- still be running: that's the "future"). As things change (a seal running
-- out, a target getting low) they move up and down. { {spell, cd} ... }
function E:OnDeck(n, current)
    local def, ctx = self:Definition(), self.lastCtx
    if not (def and ctx) then return {} end
    local out, seen = {}, { [current or ""] = true }
    for _, rule in ipairs(priorityFor(def, ctx)) do
        local s = rule.spell
        if not seen[s] and self:Knows(s) and s ~= "Attack" and s ~= "Auto Attack" then
            local okW, w = true, true
            if rule.when then okW, w = pcall(rule.when, ctx) end
            if okW and w then
                seen[s] = true
                out[#out + 1] = { spell = s, cd = A.Cooldown(s), kind = rule.kind or "damage", reason = rule.reason }
                if #out >= n then break end
            end
        end
    end
    return out
end
-- What to press now. Also remembered as E.current so the profiler can tell
-- whether you followed the suggestion.
function E:Evaluate()
    local s = self:Choose()
    self.current = s
    return s
end

-------------------------------------------------------------------------------
-- Setup and slash commands
-------------------------------------------------------------------------------

ns:OnLoad(function(saved)
    local r = saved.rotation
    if r.enabled == nil then r.enabled = true end
    if r.locked == nil then r.locked = true end
    r.overheal = r.overheal or 0.05   -- tolerate up to 5% overheal
    r.panicPct = r.panicPct or 0.15   -- always heal below 15% in combat
end)

ns:On("SPELLS_CHANGED", function() E:RefreshSpells() end)
ns:On("PLAYER_LOGIN", function() E:RefreshSpells() end)

ns.commands.rot = function(arg)
    local r = ns.db.rotation
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        r.enabled = (arg == "on")
        ns:Print("rotation helper " .. (r.enabled and "on" or "off"))
    elseif arg == "unlock" or arg == "lock" then
        r.locked = (arg == "lock")
        ns:Print(r.locked and "icon hidden when there is nothing to press" or "icon always shown: hold Shift and drag it where you want")
    elseif arg == "debug" then
        r.debug = not r.debug
        ns:Print("debug " .. (r.debug and "on" or "off"))
    elseif arg == "reset" then
        wipe(r.heals); wipe(r.mobs)
        ns:Print("forgot learned heals and mob damage")
    elseif arg == "why" then
        ns:Print("rotation check:")
        for _, line in ipairs(E:Explain()) do print(line) end
    elseif arg == "guide" then
        local def = E:Definition()
        if not (def and def.guide) then ns:Print("no rotation guide for your class yet") return end
        ns:Print("your rotation (with the spells you have now):")
        for _, line in ipairs(def.guide(E)) do print("  " .. line) end
    elseif arg == "known" then
        -- Check that the helper only sees spells you really have.
        local names = {}
        for name in pairs(known) do names[#names + 1] = name end
        table.sort(names)
        ns:Print("spells Flow thinks you know: " .. table.concat(names, ", "))
    elseif arg == "stats" then
        local ctx = E:Context()
        ns:Print(string.format("latency %dms, incoming %.1f dps, you die in %s, target dies in %s, combat log %s",
            ctx.latency * 1000, ctx.dtps,
            ctx.selfTTD == math.huge and "never" or string.format("%.1fs", ctx.selfTTD),
            ctx.targetTTD == math.huge and "?" or string.format("%.1fs", ctx.targetTTD),
            T:Stats().combatLog and "yes" or "no"))
        print("  fight type now: " .. ctx.fightType)
        local def = E:Definition()
        for _, spell in ipairs(def and def.heals or {}) do
            if E:Knows(spell) then
                local amt, src = T:HealAmount(spell)
                print(string.format("  %s: %s (%s)", spell, amt and tostring(math.floor(amt)) or "?", src or "unknown"))
            end
        end
        for name, m in pairs(r.mobs) do
            print(string.format("  %s hits for %.1f dps (%d fights)", name, m.dps, m.n))
        end
    else
        ns:Print("/flow rot guide|why|on|off|lock|unlock|stats|known|debug|reset")
    end
end

-- The hurt estimate (see EarlyHeal), stepped twice a second, and a line per
-- fight in the log: how long you were hit, the estimate before and after.
local fightLog
local probes = { wounds = 0, readable = 0 }
C_Timer.NewTicker(0.5, function()
    if UnitIsDeadOrGhost("player") then E.hurt = 0 return end
    local inCombat = UnitAffectingCombat("player") and true or false
    local hit = inCombat and E.BeingHit() or 0
    if fightLog then
        fightLog.hit = fightLog.hit + 0.5 * hit
        if hit == 0.5 then fightLog.unknown = fightLog.unknown + 0.5 end
    end
    local low = A.LowHealthWarning() == true
    if low and fightLog then fightLog.low = true end
    E.hurt = E.StepHurt(E.hurt, 0.5, inCombat, hit, not inCombat and eating(), low)
end)

ns:On("PLAYER_REGEN_DISABLED", function()
    fightLog = { start = GetTime(), hurt = E.hurt, hit = 0, unknown = 0 }
end)
ns:On("PLAYER_REGEN_ENABLED", function()
    local f = fightLog
    fightLog = nil
    if not f then return end
    local H = E.HURT
    ns:Log("heal", string.format("fight %d s: an enemy on you ~%d s%s; hurt %.0f -> %.0f (Flow heals at %d out of a fight, HoT at %d / heal at %d in one)%s",
        GetTime() - f.start, f.hit, f.unknown > 0 and string.format(" (%d s the game wouldn't say)", f.unknown) or "",
        f.hurt, E.hurt, H.outStart, H.inHot, H.inHeal, f.low and "; the game's low-health warning came on" or ""))
    -- Once a session: can Flow read any real numbers here? (If so, the
    -- estimate could use them.)
    if not probes.done then
        probes.done = true
        ns:Log("heal", string.format("probe: your health %s, max health %s, hits seen %d (numbers readable in %d)",
            A.Safe(UnitHealth("player")) ~= nil and "readable" or "hidden",
            A.Safe(UnitHealthMax("player")) ~= nil and "readable" or "hidden", probes.wounds, probes.readable))
    end
end)
-- Damage numbers the game shows over your character (combat text): logged
-- only, to learn whether they're readable on this client.
ns:On("UNIT_COMBAT", function(unit, action, _, amount)
    if unit ~= "player" or A.Safe(action) ~= "WOUND" then return end
    probes.wounds = probes.wounds + 1
    if A.Safe(amount) ~= nil then probes.readable = probes.readable + 1 end
end)
ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit ~= "player" then return end
    local name = A.SpellInfo(A.Safe(spellID) or 0)
    local value = name and E.HEAL_VALUE[name]
    if not value then return end
    local def = E:Definition()
    for _, sp in ipairs(def and def.hots or {}) do if sp == name then hotCastAt[sp] = GetTime() end end
    local before = E.hurt
    E.hurt = math.max(0, E.hurt - value)
    ns:Log("heal", string.format("cast %s: hurt %.0f -> %.0f", name, before, E.hurt))
end)
ns:On("PLAYER_LEVEL_UP", function() E.hurt = 0 end)                -- a new level fills your health
ns:On("PLAYER_UNGHOST", function() E.hurt = E.HURT.outBig + 5 end)  -- back from the dead: about half

-------------------------------------------------------------------------------
-- Death reports: what happened in the fight you died in, so the easy button
-- can learn from it. When you die, Flow says in chat what went wrong (1-3
-- findings), saves the report (FlowDB.deathReports, the last 30, read by
-- tools\claude-bridge.ps1 as a DEATH line for a Claude post-mortem) and logs
-- it in full ("[death]" lines: what Flow suggested, what you cast).
-------------------------------------------------------------------------------

local track     -- the fight you're in (or were last in)
local function newTrack()
    return { start = GetTime(), casts = {}, seen = {}, heals = 0, healSeen = 0, shift = 0, hurtMax = E.hurt }
end
ns:On("PLAYER_REGEN_DISABLED", function() track = newTrack() end)
C_Timer.NewTicker(0.5, function()
    local t = track
    if not t or UnitIsDeadOrGhost("player") or not UnitAffectingCombat("player") then return end
    local now = GetTime() - t.start
    local s = E.current
    if s and s.spell then
        t.seen[s.spell] = (t.seen[s.spell] or 0) + 1
        if s.kind == "heal" or s.kind == "emergency" then
            t.healSeen = t.healSeen + 1
            t.healAt = t.healAt or now
        end
    end
    if A.LowHealthWarning() == true then t.lowAt = t.lowAt or now end
    t.hurtMax = math.max(t.hurtMax, E.hurt)
    if UnitExists("target") and UnitCanAttack("player", "target") then
        t.enemy = { name = A.Safe(UnitName("target")), level = A.Safe(UnitLevel("target")),
                    class = A.Safe(UnitClassification("target")) }
    end
end)
ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit ~= "player" or not track then return end
    local name = A.SpellInfo(A.Safe(spellID) or 0)
    if not name then return end
    if #track.casts < 40 then track.casts[#track.casts + 1] = string.format("%s@%ds", name, GetTime() - track.start) end
    if E.HEAL_VALUE[name] then track.heals = track.heals + 1 end
end)
-- Cast.lua: Shift + key (your heal) was pressed.
function E.NoteShiftPress() if track then track.shift = track.shift + 1 end end

-- One line on what happened. r: { fight, level, lowAt, healAt, healSeen,
-- heals, shift, oom, enemy = { name, level, class }, hurtMax, healKnown }.
function E.DeathSummary(r)
    local parts = { string.format("died after %d s", r.fight or 0) }
    local e = r.enemy
    if e and e.name then
        local tags = {}
        if e.level then tags[#tags + 1] = "level " .. tostring(e.level == -1 and "??" or e.level) end
        if e.class and e.class ~= "normal" and e.class ~= "minus" then tags[#tags + 1] = e.class end
        tags[#tags + 1] = "you " .. tostring(r.level)
        parts[1] = parts[1] .. string.format(" fighting %s (%s)", e.name, table.concat(tags, ", "))
    end
    if r.lowAt then parts[#parts + 1] = string.format("low-health warning %d s before", (r.fight or 0) - r.lowAt) end
    parts[#parts + 1] = string.format("heals: suggested %d times, cast %d", r.healSeen or 0, r.heals or 0)
    parts[#parts + 1] = string.format("Shift + key %d", r.shift or 0)
    if r.oom then parts[#parts + 1] = "out of mana" end
    return table.concat(parts, "; ")
end

-- What could have saved you: 1-3 findings, most useful first.
function E.DeathFindings(r)
    local out = {}
    local fight = r.fight or 0
    if r.oom then
        out[#out + 1] = "You were out of mana, so heals and spells couldn't be cast. Drink to full between fights."
    end
    if r.lowAt and r.healKnown and (r.heals or 0) == 0 then
        out[#out + 1] = string.format("The low-health warning came on %d s before you died, but no heal was cast: Shift + your easy key casts %s on you, even in a fight.",
            fight - r.lowAt, r.healKnown)
    end
    if r.healKnown and not r.healAt and fight >= 12 then
        out[#out + 1] = string.format("Flow didn't suggest a heal this fight (its estimate of how hurt you were only reached %d): it should have warned you sooner.", r.hurtMax or 0)
    elseif r.healAt and r.lowAt and r.healAt >= r.lowAt then
        out[#out + 1] = "Flow's first heal suggestion came only with the low-health warning: too late."
    end
    local e = r.enemy
    if e and e.name then
        if e.class == "elite" or e.class == "rareelite" or e.class == "worldboss" then
            out[#out + 1] = e.name .. " is elite: bring a friend, or leave it for later."
        elseif type(e.level) == "number" and r.level and (e.level == -1 or e.level - r.level >= 3) then
            out[#out + 1] = string.format("%s was level %s, %s above you: hard to win alone.", e.name,
                e.level == -1 and "??" or tostring(e.level), e.level == -1 and "far" or tostring(e.level - r.level))
        end
    end
    if #out == 0 then out[1] = "Nothing stands out in what Flow can see; the fight is saved for a closer look." end
    while #out > 3 do table.remove(out) end
    return out
end

ns:OnLoad(function(saved)
    saved.deathReports = saved.deathReports or {}
    saved.deathNext = saved.deathNext or 1
end)

ns:On("PLAYER_DEAD", function()
    local t = track or newTrack()
    track = nil
    local def = E:Definition()
    local healKnown, oom
    for _, sp in ipairs(def and def.heals or {}) do
        if E:Knows(sp) then
            healKnown = healKnown or sp
            local _, noMana = A.Usable(sp)
            if noMana == true then oom = true end
        end
    end
    local level = UnitLevel("player")
    local r = { fight = GetTime() - t.start, level = level, lowAt = t.lowAt, healAt = t.healAt, healSeen = t.healSeen,
                heals = t.heals, shift = t.shift, oom = oom, enemy = t.enemy, hurtMax = t.hurtMax, healKnown = healKnown }
    local summary, findings = E.DeathSummary(r), E.DeathFindings(r)
    -- Saved for the post-mortem (tools\claude-bridge.ps1 passes it on as a DEATH line).
    local id = ns.db.deathNext or 1
    ns.db.deathNext = id + 1
    local _, class = UnitClass("player")
    local who = (A.Safe(UnitName("player")) or "?"):gsub("|", "")
    local zone = ((GetZoneText and GetZoneText()) or "?"):gsub("|", "")
    local reports = ns.db.deathReports
    reports[#reports + 1] = string.format("%d|%s|%s|%d|%s|%s || %s", id, who, tostring(class), level, zone,
        summary, table.concat(findings, " / "))
    while #reports > 30 do table.remove(reports, 1) end
    ns:Log("death", string.format("#%d %s", id, summary))
    for _, f in ipairs(findings) do ns:Log("death", "  - " .. f) end
    local seen = {}
    for sp, n in pairs(t.seen) do seen[#seen + 1] = sp .. " x" .. n end
    ns:Log("death", "  Flow suggested: " .. (#seen > 0 and table.concat(seen, ", ") or "nothing"))
    ns:Log("death", "  you cast: " .. (#t.casts > 0 and table.concat(t.casts, ", ") or "nothing"))
    -- In chat: what went wrong.
    ns:Print("|cffff6060You died.|r " .. summary)
    for _, f in ipairs(findings) do print("  - " .. f) end
    if ns.claudeInbox and #ns.claudeInbox > 0 then
        print("  |cff888888(Claude looks at each death to improve the easy button: this one goes at your next /reload.)|r")
    end
end)
