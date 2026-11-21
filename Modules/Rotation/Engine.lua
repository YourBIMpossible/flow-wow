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

-- A class with no rotation yet still gets the help that needs no class
-- spells: breaking free, healthstones and potions, your recovery order
-- (bandage, food, drink), interrupts with a racial. No class rules.
E.NO_CLASS = "NOCLASS"
ns:Register("rotation", E.NO_CLASS, { noClass = true, priority = {} })

-- What the engine chooses from: your class's rotation, or the class-agnostic one.
function E:Rules()
    return self:Definition() or ns:Get("rotation", E.NO_CLASS)
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
local function isEating(n) return EATING[n] end   -- (one function, not a new one ten times a second)
local function eating() return (A.Buff("player", isEating)) end
function E.EatingNow() return eating() and true or false end

-- Well Fed food: the buff comes after 10 seconds of eating. When the key's
-- last suggestion was such a food and you start eating, the button counts
-- down to Well Fed. Display only: the key never eats a second one.
E.WELL_FED_SECS = 10
local wellFed = { at = nil, lastShown = nil, item = nil, icon = nil }
-- Each tick: what the key would do now (s: its suggestion, or nil).
function E.NoteKeyShown(s, now)
    if s and s.wellFed then wellFed.lastShown, wellFed.item, wellFed.icon = now, s.item, s.icon end
end
-- Seconds until Well Fed, or nil. isEating / isFed: what the game says now.
-- Starts when eating begins within 3 s of the key showing Well Fed food.
function E.WellFedIn(now, isEating, isFed)
    if isFed or not isEating then wellFed.at = nil return nil end
    if not wellFed.at and wellFed.lastShown and now - wellFed.lastShown < 3 then
        wellFed.at = now + E.WELL_FED_SECS
    end
    if not wellFed.at then return nil end
    return math.max(0, wellFed.at - now)
end
E._wellFed = wellFed   -- (tests)
-- Is a countdown running, or could one start (the key showed Well Fed food
-- within the last 3 s)? Asked every tick before reading your buffs: reading
-- them for nothing ten times a second cost 0.9 ms a second (0.35.156).
function E.WellFedWatch(now)
    return wellFed.at ~= nil or (wellFed.lastShown ~= nil and now - wellFed.lastShown < 3)
end
-- The button's view while it counts down, or nil.
function E.WellFedView(now)
    local left = E.WellFedIn(now, eating() and true or false, (A.Buff("player", "Well Fed")) and true or false)
    if not left then return nil end
    return { item = wellFed.item, icon = wellFed.icon, kind = "buff", label = "Well Fed in", countdown = left,
             reason = "Eating Well Fed food: keep eating until the buff lands" }
end

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

-- Your heal for when you're really hurt: the fastest to cast that heals at
-- once. A heal over time (def.hots) only when it's all you have: by the
-- time you stop to heal, twelve seconds of ticks don't answer it.
-- (0.35.163, from the player's own casts: 6 heals in fights, every one a
-- Healing Touch where Flow advised Rejuvenation, and 48 Rejuvenation
-- prompts left alone; in one death Rejuvenation was advised 65 times.)
-- ok(spell): usable (or known); castMs(spell): its cast time.
function E.DirectHeal(heals, hots, ok, castMs)
    local isHot = {}
    for _, sp in ipairs(hots or {}) do isHot[sp] = true end
    local function fastest(direct)
        local best, bestMs
        for _, sp in ipairs(heals or {}) do
            if not (direct and isHot[sp]) and ok(sp) then
                local ms = castMs(sp) or 0
                if not best or ms < bestMs then best, bestMs = sp, ms end
            end
        end
        return best
    end
    return fastest(true) or fastest(false)
end

-- How you press your heal in a fight, in words: Shift + Flow's key, or the
-- second key when your heals live there (CareKeys.lua).
function E.HealPress()
    local K = ns.careKeys
    if K and K.Moved and K.Moved() then return "your second key" end
    return "Shift + key"
end

-- Pure: is a lingering heal still on you? up: its buff shows; castAt: when
-- you last cast it (nil: never); lasts: its seconds.
function E.Lingers(up, castAt, lasts, now)
    if up then return true end
    return castAt ~= nil and (now - castAt) < (lasts or 0)
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
    -- A heal that goes on healing after it lands (def.lingers: Regrowth, 21 s)
    -- and is still on you: not that one again ("the target button tells me to
    -- cast Regrowth again even though it is active on me", 0.35.205). Another
    -- heal if you're hit a lot; out of a fight it counts as healing you.
    local lingering, again = {}, nil
    for sp, dur in pairs(def.lingers or {}) do
        if E.Lingers(A.Buff("player", sp) and true or false, hotCastAt[sp], dur, now) then
            lingering[sp] = true
            ticking = true
            if self:Ready(sp) then again = again or sp end
        end
    end
    -- (A HoT already on you isn't cast again.)
    local fast, fastMs, big, bigMs
    for _, sp in ipairs(heals) do
        if self:Ready(sp) and not (isHot[sp] and sp ~= hot) and not lingering[sp] then
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
        -- Hit a lot: a heal that lands at once (E.DirectHeal), not twelve
        -- seconds of ticks. The same heal Shift + key casts (Cast.lua HealFor).
        if hurt >= H.inHeal then
            local direct = E.DirectHeal(heals, def.hots, function(sp) return not lingering[sp] and self:Ready(sp) end,
                function(sp) return select(3, A.SpellInfo(sp)) end)
            -- (Only the lingering heal to cast: again, then. Its first part lands at once.)
            return heal(direct or fast or again, "You've been hit a lot: heal now (" .. E.HealPress() .. ")")
        end
        if hurt >= H.inHot and hot then return heal(hot, "Hit for a while: " .. hot .. " now, before it's a problem (" .. E.HealPress() .. ")") end
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
-- hidden from add-ons on Forever). The fastest heal that lands at once
-- (E.DirectHeal; hots: the class's heals over time, which don't answer a
-- third of your health). In combat it shows on the Flow icon; Shift + key
-- casts it (the key is locked for the fight).
function E:LowHealthHeal(ctx, heals, hots)
    if ctx.maxHp > 0 or not ctx.lowHealth or UnitIsDeadOrGhost("player") then return nil end
    if ctx.casting then
        for _, h in ipairs(heals) do if h == ctx.casting then return nil end end
    end
    local best = E.DirectHeal(heals, hots, function(sp) return self:Ready(sp) end,
        function(sp) return select(3, A.SpellInfo(sp)) end)
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
-------------------------------------------------------------------------------
-- After a fight: eat and drink together, or bandage (0.35.197)
-------------------------------------------------------------------------------
-- "Can't the items after combat swap, so it could say to eat, and then drink
-- one right after the other? Else bandage, if only health and the bandage
-- covers it?"
--   * You'll sit to drink (low on mana, or you've cast a few spells and
--     carry a drink): food comes before the bandage, lightly hurt or not, and
--     the drink is offered the moment you're eating. One sit does both.
--   * No drink needed and a bandage covers what you're missing: the bandage
--     comes before food (eight seconds on your feet, not thirty sitting).
--   * Otherwise: your own order (right-click the Flow key).
-- The game hides your mana here, so "a few spells" is counted in casts:
-- each cast that costs mana adds one; out of a fight one comes back every
-- 12 seconds, drinking one every 3.
E.SPENT = { drink = 3, back = 12, drinking = 3, max = 30 }
E.spent = 0
-- Pure: the count after `dt` seconds.
function E.StepSpent(spent, dt, inCombat, drinking)
    if drinking then return math.max(0, spent - dt / E.SPENT.drinking) end
    if inCombat then return spent end
    return math.max(0, spent - dt / E.SPENT.back)
end
-- Pure: worth a drink with your food? (You're sitting anyway.)
function E.DrinkWithFood(spent, min) return (spent or 0) >= (min or E.SPENT.drink) end
-- Pure: the recovery order for right now.
--   order: yours, { "bandage", "food", "heal" } in some order
--   sitting: you'll drink; covers: a bandage of yours fills what you're missing
function E.SmartRecover(order, sitting, covers)
    local out = {}
    for _, s in ipairs(order or {}) do out[#out + 1] = s end
    local function before(a, b)
        local ia, ib
        for i, s in ipairs(out) do
            if s == a then ia = i elseif s == b then ib = i end
        end
        if ia and ib and ia > ib then
            table.remove(out, ia)
            table.insert(out, ib, a)
        end
    end
    if sitting then before("food", "bandage")
    elseif covers then before("bandage", "food") end
    return out
end
-- Pure: does a bandage cover it? missing: health you lack (nil: hidden);
-- best: the most one of your bandages heals (nil: none); hurt: Flow's
-- estimate, used where your health is hidden (a bandage is worth
-- E.HEAL_VALUE["First Aid"] of it).
function E.BandageCovers(missing, best, hurt, worth)
    if not best then return false end
    if missing then return best >= missing end
    return (hurt or 0) > 0 and (hurt or 0) <= (worth or 0)
end

-- Above this share of your health (where the game shows it) Flow suggests
-- no heal of any kind: no spell, bandage, food or Cannibalize. Its own
-- estimate (E.hurt) only counts while your health is hidden.
E.HEAL_ABOVE_NONE = 0.8
function E.HealthFine(ctx)
    return ctx ~= nil and (ctx.maxHp or 0) > 0 and (ctx.hpPct or 0) > E.HEAL_ABOVE_NONE
end
E.FOOD_PCT = 0.6   -- eat at or below this share of your health (where it's shown)
-- (Two small looks at the game, on their own so the tests can stand in.)
function E.RecoverBusy(ctx)
    return UnitIsDeadOrGhost("player") or eating() or ctx.casting or (UnitChannelInfo and UnitChannelInfo("player")) or false
end
function E.Mounted() return (IsMounted and IsMounted()) and true or false end

-- Fights ahead (a kill step, or just after a fight) and not Well Fed: food
-- that makes you Well Fed comes first when you eat (one meal does both).
function E.WantWellFed()
    local BI, X = ns.buffItems, ns.actions
    if not (BI and BI.Killing) or A.Buff("player", "Well Fed") then return false end
    local ok, ctx = pcall(function() return X and X:Context() end)
    return BI.Killing(ok and ctx or nil) == true
end

-- Drinking: out of a fight at or below this share of your mana, with no
-- enemy targeted (you'd sit down at the pull). You can drink while you eat.
E.DRINK_PCT = 0.5
function E.ManaShare()
    local max = A.Safe(UnitPowerMax and UnitPowerMax("player", 0))
    if not (max and max > 0) then return nil end
    local mana = A.Safe(UnitPower and UnitPower("player", 0))
    return mana and mana / max or nil
end
local DRINKING = { Drink = true, ["Food & Drink"] = true, Refreshment = true }
local function isDrinking(n) return DRINKING[n] == true end
function E.Drinking()
    return (A.Buff("player", isDrinking)) and true or false
end
-- The game may hide your mana as it hides your health (then ManaShare is
-- nil, and the drink step used to give up: "the target button never suggests
-- to drink water"). What it still says is whether you can afford a spell:
-- when one of your heals is "usable, but no mana", you're low.
--   def: your rotation (def.heals). -> true / false
function E.CantAfford(def)
    for _, spell in ipairs(def and def.heals or {}) do
        if known[spell] then
            local _, noMana = A.Usable(spell)
            if noMana == true then return true end
        end
    end
    return false
end
-- Pure: low on mana? share: your mana's share where the game shows it
-- (nil: hidden); cantAfford: a heal of yours is out of reach.
function E.ManaLow(share, cantAfford, pct)
    if share ~= nil then return share <= (pct or E.DRINK_PCT) end
    return cantAfford == true
end
-- Why the drink step would or wouldn't fire now, in words (/flow rot why).
function E:DrinkWhy(ctx)
    local r = ns.db.rotation
    local share = E.ManaShare()
    local BI = ns.buffItems
    local drink = BI and BI.DrinkItem and BI.DrinkItem()
    local cant = E.CantAfford(self:Definition())
    return string.format("Drink: %s; your mana %s; a heal out of reach %s; in your bags %s; %s",
        r.recoverDrink == false and "turned off (right-click the Flow key)" or "on",
        share and string.format("%d%% (drinks at %d%% or less)", share * 100 + 0.5, E.DRINK_PCT * 100) or "hidden by the game",
        cant and "yes" or "no", drink or "nothing Flow takes for a drink",
        (ctx and ctx.hostile) and "an enemy is targeted (no drinking then)" or "no enemy targeted")
end
function E:DrinkStep(ctx)
    local r = ns.db.rotation
    if ctx.inCombat or ctx.hostile or ctx.casting or r.recoverDrink == false then return nil end
    if UnitIsDeadOrGhost("player") or E.Mounted() or E.Drinking() then return nil end
    local share = E.ManaShare()
    -- Low on mana; or you're eating and have cast a few spells: one sit does both.
    local low = E.ManaLow(share, share == nil and E.CantAfford(self:Definition()))
    local withFood = r.recoverSmart ~= false and E.EatingNow() and E.DrinkWithFood(E.spent)
    if not (low or withFood) then return nil end
    local BI = ns.buffItems
    local s = BI and BI.DrinkStep and BI.DrinkStep()
    if s and withFood and not low then s.reason = "You're eating: drink with it (you've cast a few spells)" end
    if s then s.fightType = ctx.fightType end
    return s
end

-- Cannibalize (Undead racial): heals 7% of your health every 2 s for 10 s
-- from a humanoid or undead corpse within 5 yards; 2 min cooldown. It costs
-- nothing, so when it's ready and the corpse you just killed fits, it comes
-- before your recovery order. The game can't tell an add-on where corpses
-- are, so Flow goes by your target: dead, humanoid or undead. Close (about
-- 10 yards, the nearest the game will say): eat it; farther: walk to it.
E.CANNIBALIZE = "Cannibalize"
E.CORPSE_TYPES = { [6] = "Undead", [7] = "Humanoid" }   -- creature type IDs, English names as a fallback
function E.CorpseFits(typeName, localName)
    if not typeName then return false end
    for id, en in pairs(E.CORPSE_TYPES) do
        if typeName == en or (localName and typeName == localName(id)) then return true end
    end
    return false
end
local function creatureTypeName(id)
    local CI = C_CreatureInfo
    if not (CI and CI.GetCreatureTypeInfo) then return nil end
    local ok, info = pcall(CI.GetCreatureTypeInfo, id)
    return ok and info and info.name or nil
end
-- A usable corpse targeted: true, close (within about 10 yards).
function E.CannibalCorpse()
    if not (UnitExists("target") and A.Safe(UnitIsDead("target"))) then return false end
    if A.Safe(UnitIsPlayer and UnitIsPlayer("target")) and not A.Safe(UnitCanAttack("player", "target")) then return false end
    local kind = A.Safe(UnitCreatureType and UnitCreatureType("target"))
    if not E.CorpseFits(kind, creatureTypeName) then return false end
    -- (E.Near: in a fight the game forbids asking how far a corpse is; it asks only when it may.)
    local close = E.Near("target")
    return true, close and true or false
end
function E:CannibalizeStep(ctx)
    if ns.db.rotation.recoverCannibalize == false or E.Mounted() then return nil end
    if not self:Ready(E.CANNIBALIZE) then return nil end
    local fits, close = E.CannibalCorpse()
    if not fits then return nil end
    return { spell = E.CANNIBALIZE, kind = "heal", fightType = ctx.fightType,
             reason = close and "Hurt after your fight: Cannibalize the corpse (free, heals over 10 s; stay within 5 yards)"
                 or "Hurt after your fight: walk onto the corpse and Cannibalize it (free; within 5 yards)" }
end

-- part: with the self button on (BuffButton.lua) the bandage and food are
-- on it and only the heal spell is on the Flow key. nil = this is the Flow
-- key ("heal" when the self button is on, else "all"); "items" = the buff
-- button asking. Your order still holds across the two: the heal spell waits
-- while a bandage or food you put first is there to use, and the other way.
-- all: a list to fill with EVERY step you could take now, in your order,
-- instead of returning the first (E:RecoverOptions).
function E:Recover(ctx, def, part, all)
    if ctx.inCombat or E.RecoverBusy(ctx) or E.HealthFine(ctx) then return nil end
    if part == nil then part = (ns.buffButton and ns.buffButton.On()) and "heal" or "all" end
    -- Hurt: Flow's estimate, your real health where the game shows it, or
    -- the game's low-health warning. All three go through the same order,
    -- so a heal spell never jumps ahead of the bandage you put first, and
    -- "Cast heals" off means no heal spell at all out of a fight.
    local direct = def.heals and (self:HealDecision(ctx, def.heals) or self:LowHealthHeal(ctx, def.heals, def.hots)) or nil
    local quite = E.hurt >= E.HURT.outBig or ctx.lowHealth or (ctx.maxHp > 0 and ctx.hpPct <= E.FOOD_PCT)
    if not (E.hurt >= E.HURT.outStart or direct or quite) then return nil end
    local BI, r = ns.buffItems, ns.db.rotation
    local mounted = E.Mounted()
    -- Cannibalize first (free, on the self button with your bandages).
    local can = self:CannibalizeStep(ctx)
    if can then
        -- (Listing every option for the queue: it's the first of them, and
        -- the others still follow; returning here left the queue with none.)
        if all then
            all[#all + 1] = can
        else
            if part == "heal" then return nil end
            return can
        end
    end
    local order = BI and BI.Order(r.recoverOrder) or { "heal" }
    -- Eat and drink together, or bandage when it covers it (above).
    local sitting = false
    if BI and r.recoverSmart ~= false then
        local okS, sit, covers = pcall(E.RecoverNow, self, ctx, def)
        if okS then
            sitting = sit and true or false
            order = E.SmartRecover(order, sitting, covers)
        end
    end
    for _, step in ipairs(order) do
        local s
        if step == "bandage" and BI and r.recoverBandage ~= false and not mounted then
            s = BI.BandageStep(r.bandageRank == "low")
        elseif step == "food" and BI and r.recoverFood ~= false and not mounted and not ctx.hostile and (quite or sitting) then
            s = BI.FoodStep(r.recoverBuffFood ~= false, E.WantWellFed())
        elseif step == "heal" and r.recoverHeal ~= false then
            s = direct or self:EarlyHeal(ctx, def)
        end
        if s then
            s.fightType = ctx.fightType
            if all then
                all[#all + 1] = s
            else
                if part ~= "all" and part ~= (step == "heal" and "heal" or "items") then return nil end
                return s
            end
        end
    end
    return nil
end

-- Right now: will you sit to drink (and so eat with it), and does a bandage
-- cover what you're missing? -> sitting, covers
function E:RecoverNow(ctx, def)
    local BI, r = ns.buffItems, ns.db.rotation
    local share = E.ManaShare()
    local canDrink = r.recoverDrink ~= false and not ctx.hostile and BI.DrinkItem and BI.DrinkItem() ~= nil
    local sitting = canDrink and (E.ManaLow(share, share == nil and E.CantAfford(def)) or E.DrinkWithFood(E.spent)) or false
    local missing = BI.MissingHealth(UnitHealth("player"), UnitHealthMax("player"), nil, nil)
    local best = BI.BestBandage and BI.BestBandage() or nil
    return sitting, E.BandageCovers(missing, best, E.hurt, E.HEAL_VALUE["First Aid"])
end

-- Every way to heal up right now, in your recovery order (bandage, food,
-- heal spell: the ones you carry or know). The first is what the key does;
-- the target button's queue puts the others on Ctrl and Alt (Queue.lua), so
-- you choose with a modifier. Empty when you aren't hurt, or in a fight.
function E:RecoverOptions(ctx, def)
    local out = {}
    if ctx and def then self:Recover(ctx, def, "all", out) end
    return out
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

-------------------------------------------------------------------------------
-- Stopping a cast
-------------------------------------------------------------------------------

-- Spells that step your target's cast. near = it hits everything around you
-- (War Stomp: 8 yards), so it needs the target close, not in spell range.
-- Classes add theirs: table.insert(ns.rotation.INTERRUPTS, { spell = ... }).
E.INTERRUPTS = {
    { spell = "Bash" },                     -- druid, Bear Form: a stun in melee reach (0.35.212)
    { spell = "Hammer of Justice" },        -- paladin: a stun at 10 yd
    { spell = "War Stomp", near = true },   -- tauren: stuns everything within 8 yd for 2 s
}
-- What the target is casting or channelling (nil: nothing, or the game hides it).
function E.TargetCasting()
    local name = A.Safe(UnitCastingInfo and UnitCastingInfo("target"))
    if name then return name end
    return A.Safe(UnitChannelInfo and UnitChannelInfo("target"))
end
-- May Flow ask the game how far a unit is? Out of a fight: about anyone
-- there. In a fight the game only allows the question about an enemy you
-- can attack: about a friend, a corpse or nobody it's forbidden, and asking
-- got Flow "blocked from an action only available to the Blizzard UI"
-- (0.35.159: the cast recorder asked it on every cast, also with yourself
-- or nothing targeted). Pure: the game's answers in.
function E.MayAskDistance(inCombat, exists, canAttack, dead)
    if not exists then return false end
    if not inCombat then return true end
    return canAttack == true and not dead
end
-- Is the unit within about 10 yards? (the game's duel range; nil: can't
-- tell, or may not ask)
function E.Near(unit)
    if not CheckInteractDistance then return nil end
    if not E.MayAskDistance(InCombatLockdown() and true or false, E.Yes(UnitExists(unit), false),
            E.Yes(UnitCanAttack("player", unit), false), E.Yes(UnitIsDead(unit), true)) then
        return nil
    end
    local ok, near = pcall(CheckInteractDistance, unit, 3)
    if not ok then return nil end
    return A.Safe(near)
end
-- The interrupt to press now: your target is casting, and one you know is
-- ready and reaches it. (In a fight the key is locked, so it shows on the
-- icon; press it on your bar: it glows there.)
function E:Interrupt(ctx, casting, near)
    if not (ctx.inCombat and ctx.hostile) then return nil end
    casting = casting or E.TargetCasting()
    if not casting then return nil end
    for _, r in ipairs(E.INTERRUPTS) do
        local reach = true
        if r.near then
            local n = near
            if n == nil then n = E.Near("target") end
            reach = n == true   -- (can't tell: no, it would stomp at nothing)
        end
        if reach and self:Ready(r.spell, not r.near and "target" or nil) then
            return { spell = r.spell, kind = "damage", fightType = ctx.fightType,
                     reason = string.format("Stop its %s: %s", casting, r.spell) }
        end
    end
end

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
    -- Above 80% health (where the game shows it): no heal, food or bandage.
    if E.HealthFine(ctx) then return (not ctx.inCombat) and self:DrinkStep(ctx) or nil end
    -- Out of a fight: your recovery order, then a drink if you're low on mana
    -- (also while you eat: Recover waits while you eat, drinking doesn't).
    if not ctx.inCombat then return self:Recover(ctx, def) or self:DrinkStep(ctx) end
    local h = self:Emergency(ctx)
    if not h and def.heals then
        -- Your health is hidden (Forever): the game's own low-health warning
        -- says when you're at about a third or less: heal now, fastest first.
        h = self:HealDecision(ctx, def.heals) or self:LowHealthHeal(ctx, def.heals, def.hots)
    end
    h = h or self:EarlyHeal(ctx, def)
    if h then h.fightType = ctx.fightType end
    return h
end

-------------------------------------------------------------------------------
-- Auto attack at the pull
-------------------------------------------------------------------------------
-- WoW: Forever doesn't turn your auto attack on when you cast at an enemy,
-- and the key can't change once the fight is on, so a caster's key (Wrath all
-- fight) never started it: "it still doesn't enable auto-attack after I
-- engage an enemy". So the first press at a new enemy, before the fight,
-- turns auto attack on: the key is the game's own Start Attack then (on,
-- never off; Cast.lua), it's instant, and your opener comes with the next
-- press. Only where the game has Start Attack: the Attack spell toggles, and
-- a second press would turn it off again.
--   Off: "Start auto attack at the pull" (Flow Settings, Easy keys).
--   Not for one enemy (a boss whose shield hurts whoever hits it):
--     ns:Register("noAutoAttack", "<its name>", { why = "..." })
-- If two presses don't start it (the game refused), Flow lets it go for that
-- enemy and shows your opener, so the key is never stuck.
function E.AutoAttackOn() return ns.db.rotation.autoAttack ~= false end

-- Pure: should the pull start with auto attack? s = { on (the setting),
-- hostile, inCombat, attacking, canStart (the game has Start Attack),
-- barred (this enemy is on the noAutoAttack list) }.
function E.EngageFirst(s)
    return (s.on and s.hostile and not s.inCombat and not s.attacking and s.canStart and not s.barred) and true or false
end

local engage = { unit = nil, presses = 0, gaveUp = false }
E._engage = engage   -- (tests)
E.ENGAGE_TRIES = 2

-- A press of the Flow key (Cast.lua tells): counted while it's Start Attack.
function E.NoteKeyPress()
    if E.current and E.current.engage then engage.presses = engage.presses + 1 end
end

function E:EngageStep(ctx)
    if not ctx.hostile or ctx.inCombat then return nil end
    local name = A.Safe(UnitName("target"))
    local id = A.Safe(UnitGUID and UnitGUID("target")) or name
    if id ~= engage.unit then engage.unit, engage.presses, engage.gaveUp = id, 0, false end
    if engage.gaveUp then return nil end
    local spell = (known["Auto Attack"] and "Auto Attack") or (known["Attack"] and "Attack") or nil
    if not spell then return nil end
    local want = E.EngageFirst({
        on = E.AutoAttackOn(), hostile = true, inCombat = false, attacking = A.Swinging(),
        canStart = (ns.cast and ns.cast.HasStartAttack and ns.cast.HasStartAttack()) and true or false,
        barred = name ~= nil and ns:Get("noAutoAttack", name) ~= nil,
    })
    if not want then return nil end
    if engage.presses >= E.ENGAGE_TRIES then
        engage.gaveUp = true
        ns:Log("cast", string.format("auto attack didn't start after %d presses: on with your opener", engage.presses))
        return nil
    end
    return { spell = spell, kind = "damage", engage = true, fightType = ctx.fightType,
             reason = "Start attacking: auto attack on now, your opener with the next press" }
end

function E:Choose()
    local def = self:Rules()

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

    -- Your target is casting: stop it (War Stomp when it's close).
    local int = self:Interrupt(ctx)
    if int then return int end

    -- A curse, poison, disease or magic you can remove, on you or your group.
    local d = self:Dispel(ctx, def)
    if d then return d end

    -- A new enemy, no fight yet: auto attack on first (one instant press).
    local atk = self:EngageStep(ctx)
    if atk then return atk end

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
    -- An enemy targeted but too far for anything: show what you'd open with,
    -- red (out of range), so the button is up as soon as you pick a target.
    if ctx.hostile then
        local far = self:FarOpener(list, ctx)
        if far then return far end
    end
    -- Nothing for you to press. A friendly player targeted: your buffs for
    -- them, then a heal.
    local okF, friend = pcall(self.FriendTarget, self, ctx, def)
    if okF and friend then return friend end
    if not okF then self.lastError, self.lastErrorAt = tostring(friend), GetTime() end
    -- Else: buff your party or raid.
    return self:GroupBuff(ctx, def)
end

-- The first spell on your target that's ready but for range: your opener
-- once you're close enough. nil when one is in range, or none would do.
-- (The button tints it red while you're too far: Display.lua tintOf.)
function E:FarOpener(list, ctx)
    for _, rule in ipairs(list or {}) do
        if rule.target and rule.kind ~= "buff" and self:Knows(rule.spell) then
            local okW, w = true, true
            if rule.when then okW, w = pcall(rule.when, ctx) end
            if okW and w and self:Ready(rule.spell) and A.InRange(rule.spell, "target") == false then
                local s = suggest(rule, ctx, " (out of range)")
                s.outOfRange, s.label = true, "Out of range"
                return s
            end
        end
    end
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
-- Setting: "Target button buffs your group" (/flow settings).

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

-- A yes/no from the game, or `unknown` when it hides the answer. Forever can
-- hand back a "secret" true/false, and even testing one (`if checked then`)
-- errors. That stopped the target button choosing anything out of a fight
-- whenever you were in a group (0.35.123).
function E.Yes(v, unknown)
    v = A.Safe(v)
    if v == nil then return unknown end
    return v and true or false
end
-- Too far to buff? Only when the game plainly says it checked and you're out
-- of range; when it won't say, they count as near (the cast checks range).
function E.TooFar(inRange, checked)
    return E.Yes(checked, false) and E.Yes(inRange, true) == false
end

-- Your party or raid, without you: only people you can buff now (online,
-- alive, near enough to see, friendly). Anything the game hides counts in
-- their favour; the cast itself is checked before Flow suggests it.
function E.GroupUnits()
    local out = {}
    local raid = IsInRaid and IsInRaid()
    local n = raid and GetNumGroupMembers() or (GetNumSubgroupMembers and GetNumSubgroupMembers() or 0)
    local Yes = E.Yes
    for i = 1, n do
        local unit = (raid and "raid" or "party") .. i
        if Yes(UnitExists(unit), true) and not Yes(UnitIsUnit(unit, "player"), false)
            and Yes(UnitIsConnected(unit), true) and not Yes(UnitIsDeadOrGhost(unit), false)
            and Yes(UnitIsVisible(unit), true) and Yes(UnitIsFriend("player", unit), true)
            and not E.TooFar(UnitInRange(unit)) then
            local _, class = UnitClass(unit)
            class = A.Safe(class)
            local assigned = A.Safe(UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)) or "NONE"
            out[#out + 1] = { unit = unit, name = A.Safe(UnitName(unit)) or unit, guid = A.Safe(UnitGUID(unit)),
                              class = class, kind = E.UnitKind(class, assigned, A.Safe(UnitPowerType(unit))) }
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
            if names[n] then return true, (e and e > 0) and (e - GetTime()) or math.huge, n end
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
            return true, (e and e > 0) and (e - GetTime()) or math.huge, n
        end
    end
    return false, 0
end
E.AuraOn = auraOn   -- (up, seconds left, the name that matched; nil when the game hides it)

-- guid -> { [spell] = when you cast it on them } (from the target button).
E.buffMemory = {}

-- "A more powerful spell is already active" (0.35.246): someone has a
-- stronger buff than yours, of a kind Flow can't tell from their buffs (a
-- higher rank, another class's, or their buffs are hidden). Flow kept
-- offering yours. Now the game's refusal is remembered for that person and
-- spell, and the next buff (or person) comes up. Asked again after a while:
-- the stronger one runs out.
E.BOUNCE_SECONDS = 300
E.bounced = {}   -- [their guid, or name] = { [spell] = when the game refused it }
-- Pure: is this the game's "a more powerful spell is already active"?
function E.IsBounce(msg, want)
    if type(msg) ~= "string" then return false end
    return (want ~= nil and msg == want) or msg:lower():find("more powerful spell", 1, true) ~= nil
end
-- Pure: the step refused was a buff or heal over time on someone else: note it.
function E.NoteBounce(s, now, store)
    if not (s and s.spell and s.unit and s.unit ~= "player") then return false end
    local who = s.guid or s.target
    if not who then return false end
    store[who] = store[who] or {}
    store[who][s.spell] = now
    return true
end
function E.Bounced(u, spell, now, store)
    store = store or E.bounced
    local who = u and (u.guid or u.name)
    local at = who and store[who] and store[who][spell]
    return at ~= nil and (now - at) < E.BOUNCE_SECONDS
end

-- Has this person got it, with more than `rebuff` seconds left?
--   read(unit, names) -> up, left (or nil: unknown); defaults to the game.
function E.GroupCovered(u, rule, now, read)
    -- The game refused it a moment ago ("A more powerful spell is already
    -- active"): they're covered, by something stronger than yours.
    if E.Bounced(u, rule.spell, now) then return true end
    local names = {}
    for _, n in ipairs(rule.aura or { rule.spell }) do names[n] = true end
    local up, left = (read or auraOn)(u.unit, names)
    local rebuff = rule.rebuff or 30
    if up ~= nil then return up and left > rebuff end
    local m = u.guid and E.buffMemory[u.guid] and E.buffMemory[u.guid][rule.spell]
    return m ~= nil and (now - m) < ((rule.minutes or 5) * 60 - rebuff)
end

-- Pure: why Flow isn't buffing your group right now (nil: it is looking).
function E.GroupHeld(list, on, ctx, resting, canCast)
    if not list then return "Flow has no buffs for others for your class yet" end
    if on == false then return "turned off (Flow Settings: Target button buffs your group)" end
    if ctx.inCombat then return "you're in a fight" end
    if ctx.hostile then return "an enemy is targeted" end
    if resting then return "you're in a city or an inn (Flow doesn't buff there)" end
    if canCast == false then return "you're in a form that can't cast them" end
    return nil
end

-- For the diagnostics ("rot why"): what Flow sees of your group's buffs, a
-- line for each person and buff. Only in a group.
function E:GroupWhy(ctx, def)
    if not (IsInGroup and IsInGroup()) then return {} end
    local list = def and def.groupBuffs
    local out = { "group buffs (on Flow's key, out of a fight, when nothing else is to press):" }
    local held = E.GroupHeld(list, ns.db.rotation.groupBuffs, ctx, E.Resting(),
        not (list and list.canCast) or (list.canCast() and true or false))
    if held then out[#out + 1] = "  held: " .. held end
    if not list then return out end
    local units = E.GroupUnits()
    local total = (GetNumGroupMembers and GetNumGroupMembers() or 1) - 1
    out[#out + 1] = string.format("  %d other(s) in the group, %d near enough, alive and online", total, #units)
    local now = GetTime()
    for _, u in ipairs(units) do
        for _, rule in ipairs(list) do
            local state
            if not self:Knows(rule.spell) then state = "you don't know it"
            elseif not rule.who(u) then state = "not for them"
            elseif E.Bounced(u, rule.spell, now) then state = "has a more powerful one (the game refused yours)"
            elseif E.GroupCovered(u, rule, now) then state = "has it"
            elseif not self:Ready(rule.spell, u.unit) then state = "missing, can't cast now (range, mana or sight)"
            else state = "MISSING: Flow's key gives it" end
            out[#out + 1] = string.format("  %s (%s, %s) %s: %s", tostring(u.name), tostring(u.class), tostring(u.kind), rule.spell, state)
        end
    end
    return out
end

local groupCache   -- { at, s }: reading 40 people's buffs 10 times a second is too much
function E:GroupBuff(ctx, def, now)
    local list = def and def.groupBuffs
    if E.GroupHeld(list, ns.db.rotation.groupBuffs, ctx, E.Resting(),
        not (list and list.canCast) or (list.canCast() and true or false)) then return nil end
    -- (The self-tests pass a time of their own: nothing of theirs is logged.)
    local testing = now ~= nil
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
    -- For "is it buffing correctly in a group?": each new suggestion, once,
    -- with how many are in the group (the log is in the diagnostics). Only in
    -- a real group: the self-tests run this with made-up members.
    local grouped = (not testing and IsInGroup and IsInGroup()) and true or false
    local what
    if grouped then what = s and (s.spell .. ">" .. tostring(s.target)) or (#units > 1 and "none" or nil) end
    if what and what ~= E.lastGroupLog then
        E.lastGroupLog = what
        ns:Log("group", s and string.format("group buff: %s on %s (%s), %d in the group", s.spell, tostring(s.target), tostring(s.unit), #units)
            or string.format("group buffs: everyone covered (%d in the group)", #units))
    end
    return s
end
function E.ClearGroupCache() groupCache = nil end

-------------------------------------------------------------------------------
-- A friendly player you have targeted (0.35.193)
-------------------------------------------------------------------------------
-- "When targeting friendly non-group players it would be nice to have
-- suggested spells for friendlies: I can give Mark and Thorns, so those show,
-- and if I cast through those the target button becomes heal; or if in combat
-- and their health is low, heal."
--
-- Out of a fight of your own, with a living friendly player targeted (in
-- your group or not), and not in an inn or city: your buffs for others
-- (def.groupBuffs, every one of them: you picked this person), then a heal.
-- Hurt and in a fight comes first. Their health is one of the things WoW:
-- Forever may hide; then Flow goes by whether they're in a fight (heal
-- them), and out of one puts a heal over time on them once.
-- Mana sense: buffs for others only with half your mana or more, heals with
-- a quarter (where the game shows your mana; where it doesn't, as long as
-- none of your own heals is out of reach).
E.FRIEND_HURT = 0.9
E.FRIEND_MANA = 0.5
E.FRIEND_HEAL_MANA = 0.25

-- Pure: can you spare the mana? share: your mana's share (nil: hidden);
-- cantAfford: one of your heals is out of reach; floor: the share to keep.
function E.CanSpare(share, cantAfford, floor)
    if share ~= nil then return share >= (floor or 0) end
    return cantAfford ~= true
end

-- Pure: what the key does for a friendly player.
--   f: { hurt = true | false | nil (the game won't say), inCombat = theirs }
--   buffs: { { spell, covered } }: your buffs for others you could cast now, in order
--   heal: { hot = a heal over time not on them yet, direct = your quick heal } (either may be nil)
--   spareBuff, spareHeal: you have the mana for each kind
-- -> { spell, kind = "buff" | "heal", why } or nil
function E.FriendStep(f, buffs, heal, spareBuff, spareHeal)
    if not f then return nil end
    local function healStep(why, hotOnly)
        if not (heal and spareHeal) then return nil end
        if heal.hot then return { spell = heal.hot, kind = "heal", why = why } end
        if heal.direct and not hotOnly then return { spell = heal.direct, kind = "heal", why = why } end
        return nil
    end
    if f.hurt == true and f.inCombat then
        local h = healStep("hurt in a fight")
        if h then return h end
    end
    if spareBuff then
        for _, b in ipairs(buffs or {}) do
            if not b.covered then return { spell = b.spell, kind = "buff", why = "missing" } end
        end
    end
    if f.hurt == true then return healStep("hurt") end
    if f.hurt == nil then
        if f.inCombat then return healStep("in a fight") end
        return healStep("top up", true)   -- (their health is hidden: one heal over time, no more)
    end
    return nil
end

-- Why, in words, for the icon's tooltip.
function E.FriendReason(pick, name)
    name = name or "your target"
    if pick.kind == "buff" then return string.format("%s for %s (your target): they don't have it", pick.spell, name) end
    if pick.why == "hurt in a fight" then return string.format("%s on %s: hurt, and in a fight", pick.spell, name) end
    if pick.why == "hurt" then return string.format("%s on %s: they're hurt", pick.spell, name) end
    if pick.why == "in a fight" then return string.format("%s on %s: in a fight (the game hides their health)", pick.spell, name) end
    return string.format("%s on %s: a heal over time (the game hides their health)", pick.spell, name)
end

local friendCache   -- { guid, at, s }: asked ten times a second
function E:FriendTarget(ctx, def, now)
    if ns.db.rotation.friendTarget == false or not def then return nil end
    if ctx.inCombat or ctx.hostile or E.Resting() then return nil end
    local list = def.groupBuffs
    if list and list.canCast and not list.canCast() then return nil end   -- (a druid in a form casts neither)
    local Yes = E.Yes
    if not (Yes(UnitExists("target"), false) and Yes(UnitIsPlayer("target"), false)) then return nil end
    if Yes(UnitIsUnit("target", "player"), false) or not Yes(UnitIsFriend("player", "target"), false)
        or Yes(UnitIsDeadOrGhost("target"), false) or not Yes(UnitIsConnected("target"), true) then return nil end
    now = now or GetTime()
    local guid = A.Safe(UnitGUID("target"))
    if friendCache and friendCache.guid == guid and now - friendCache.at < 0.5 then return friendCache.s end
    local name = A.Safe(UnitName("target")) or "your target"
    local hp, max = A.Safe(UnitHealth("target")), A.Safe(UnitHealthMax("target"))
    local hurt
    if type(hp) == "number" and type(max) == "number" and max > 0 then hurt = (hp / max) < E.FRIEND_HURT end
    local f = { hurt = hurt, inCombat = Yes(UnitAffectingCombat("target"), false) }
    local u = { unit = "target", guid = guid, name = name }
    local buffs = {}
    for _, rule in ipairs(list or {}) do
        if self:Knows(rule.spell) then
            local covered = E.GroupCovered(u, rule, now)
            if covered or self:Ready(rule.spell, "target") then buffs[#buffs + 1] = { spell = rule.spell, covered = covered } end
        end
    end
    local heal = {}
    for _, hot in ipairs(def.hots or {}) do
        local lasts = (def.hotDuration and def.hotDuration[hot]) or 12
        if not heal.hot and self:Knows(hot) and self:Ready(hot, "target")
            and not E.GroupCovered(u, { spell = hot, minutes = lasts / 60, rebuff = 2 }, now) then
            heal.hot = hot
        end
    end
    local direct = ns.cast and ((ns.cast.AnyHeal and ns.cast:AnyHeal()) or (ns.cast.HealSpell and ns.cast:HealSpell()))
    if direct and self:Ready(direct, "target") then heal.direct = direct end
    local share, cant = E.ManaShare(), E.CantAfford(def)
    local pick = E.FriendStep(f, buffs, heal, E.CanSpare(share, cant, E.FRIEND_MANA), E.CanSpare(share, cant, E.FRIEND_HEAL_MANA))
    local s
    if pick then
        s = { spell = pick.spell, kind = pick.kind, unit = "target", target = name, guid = guid,
              fightType = ctx.fightType, reason = E.FriendReason(pick, name) }
    end
    friendCache = { guid = guid, at = now, s = s }
    return s
end
function E.ClearFriendCache() friendCache = nil end

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
    E.ClearFriendCache()
    local s = E.current
    if not (s and s.guid and s.unit) then return end
    local name = A.SpellInfo(A.Safe(spellId) or 0)
    if name == s.spell then
        E.buffMemory[s.guid] = E.buffMemory[s.guid] or {}
        E.buffMemory[s.guid][s.spell] = GetTime()
    end
end)
ns:On("GROUP_ROSTER_UPDATE", function() groupCache = nil end)
ns:On("UI_ERROR_MESSAGE", function(_, msg)
    if not E.IsBounce(A.Safe(msg), _G.SPELL_FAILED_AURA_BOUNCED) then return end
    local s = E.current
    if E.NoteBounce(s, GetTime(), E.bounced) then
        groupCache = nil
        E.ClearFriendCache()
        ns:Log("group", string.format("%s on %s: the game says a more powerful spell is active; not offered again for %d min",
            tostring(s.spell), tostring(s.target), E.BOUNCE_SECONDS / 60))
    end
end)

-- Diagnostics for /flow rot why: why each rule is or isn't suggested.
function E:Explain()
    local out = {}
    local def = self:Rules()
    if def.noClass then
        out[#out + 1] = "No rotation for your class yet: only help that needs no class spells (breaking free, potions, bandage, food, drink)."
    end
    local n = 0
    for _ in pairs(known) do n = n + 1 end
    out[#out + 1] = string.format("Known spells: %d. Last error: %s", n, tostring(self.lastError or "none"))
    -- The target button: how its cooldown was drawn (readable, duration, hidden
    -- or none) and its tint (grey: can't cast now, red: out of range).
    out[#out + 1] = string.format("Button: cooldown %s, tint %s", tostring(self.cooldownShown or "?"), tostring(self.buttonTint or "none"))
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
    do
        local okD, drink = pcall(self.DrinkWhy, self, ctx)
        out[#out + 1] = okD and drink or ("Drink: " .. tostring(drink))
        local BI = ns.buffItems
        local okF, food = pcall(function() return BI and BI.FoodWhy and BI.FoodWhy() end)
        if food or not okF then out[#out + 1] = okF and food or ("Well Fed food: " .. tostring(food)) end
    end
    local hl = E._health or {}
    out[#out + 1] = string.format("Full-health check: your health changed %d time(s) out of a fight this session, and cleared the estimate %d time(s). Auto attack at the pull: %s; swinging now: %s",
        hl.out or 0, hl.cleared or 0, E.AutoAttackOn() and "on" or "off", tostring(A.Swinging()))
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
    local okG, group = pcall(self.GroupWhy, self, ctx, def)
    if okG then for _, l in ipairs(group) do out[#out + 1] = l end end
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
-- What the advice was `lookback` seconds before `now`: an instant cast lands
-- and the advice moves on in the same moment, so a cast is judged against
-- what was showing when you pressed (Choices.lua). Pure: values in.
function E.AdviceBack(current, before, changedAt, now, lookback)
    if changedAt and now - changedAt < lookback then return before end
    return current
end
local function adviceName(s) return s and (s.spell or s.label or s.item) or nil end
function E.AdviceAt(now, lookback)
    return E.AdviceBack(adviceName(E.current), E.adviceBefore, E.adviceChangedAt, now, lookback)
end

function E:Evaluate()
    local s = self:Choose()
    local was, new = adviceName(self.current), adviceName(s)
    if was ~= new then self.adviceBefore, self.adviceChangedAt = was, GetTime() end
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
        ns:Print(r.locked and "icon hidden when there is nothing to press" or "icon always shown: hold Ctrl and drag it where you want")
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

-- Full health, without reading it. Your health is hidden on Forever, but the
-- game still says WHEN it changes (UNIT_HEALTH, no numbers needed). Out of a
-- fight it regenerates in ticks, so it keeps changing until it's full, then
-- steps. A few quiet seconds out of a fight therefore mean: full. The
-- estimate goes to 0 and the "heal up" prompt clears ("after my health fills
-- the 'cast a heal' doesn't clear": the estimate only counted down by the
-- clock, 1 every 3 s, so a full bar could still read as hurt for a minute).
-- Only trusted once this session has seen your health change out of a fight
-- (a client that never sends the event changes nothing).
E.FULL_QUIET = 6   -- seconds without a change (regen ticks come every 2 s)
local health = { last = nil, since = nil, out = 0, cleared = 0 }
E._health = health   -- (tests, /flow rot why)

-- Pure: is your health full? lastChange: when it last changed; since: when
-- the quiet could start counting (the fight ended, you came back to life);
-- seen: changes seen out of a fight this session.
function E.HealthSettled(now, lastChange, since, seen, quiet)
    if (seen or 0) < 1 then return false end
    return now - math.max(lastChange or 0, since or 0) >= (quiet or E.FULL_QUIET)
end

local healthFrame = CreateFrame("Frame")
if healthFrame.RegisterUnitEvent then pcall(healthFrame.RegisterUnitEvent, healthFrame, "UNIT_HEALTH", "player")
else pcall(healthFrame.RegisterEvent, healthFrame, "UNIT_HEALTH") end
healthFrame:SetScript("OnEvent", function(_, _, unit)
    if unit ~= "player" then return end
    health.last = GetTime()
    if not UnitAffectingCombat("player") then health.out = health.out + 1 end
end)

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
    E.spent = E.StepSpent(E.spent, 0.5, inCombat, E.Drinking())
    -- Out of a fight and your health has stopped changing: it's full.
    if not inCombat and not low and E.hurt > 0 and E.HealthSettled(GetTime(), health.last, health.since, health.out) then
        ns:Log("heal", string.format("your health stopped changing (%d s): full, hurt %.0f -> 0", E.FULL_QUIET, E.hurt))
        E.hurt = 0
        health.cleared = health.cleared + 1
    end
end)

ns:On("PLAYER_REGEN_DISABLED", function()
    fightLog = { start = GetTime(), hurt = E.hurt, hit = 0, unknown = 0 }
end)
ns:On("PLAYER_REGEN_ENABLED", function()
    health.since = GetTime()   -- (regen starts now: the quiet counts from here)
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
    if not value or name == "First Aid" then return end   -- (a bandage: below)
    local def = E:Definition()
    for _, sp in ipairs(def and def.hots or {}) do if sp == name then hotCastAt[sp] = GetTime() end end
    if def and def.lingers and def.lingers[name] then hotCastAt[name] = GetTime() end
    local before = E.hurt
    E.hurt = math.max(0, E.hurt - value)
    ns:Log("heal", string.format("cast %s: hurt %.0f -> %.0f", name, before, E.hurt))
end)
-- Each cast of yours that costs mana: one more spent (E.SPENT).
function E.CostsMana(spell)
    local get = (C_Spell and C_Spell.GetSpellPowerCost) or GetSpellPowerCost
    if not get then return true end   -- (can't ask: count it)
    local ok, costs = pcall(get, spell)
    if not ok or type(costs) ~= "table" then return true end
    for _, c in ipairs(costs) do
        local cost = A.Safe(c.cost)
        if (c.type == 0 or c.name == "MANA") and (cost == nil or cost > 0) then return true end
    end
    return false
end
ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit ~= "player" then return end
    local name = A.SpellInfo(A.Safe(spellID) or 0)
    if name and known[name] and E.CostsMana(name) then E.spent = math.min(E.SPENT.max, E.spent + 1) end
end)
ns:On("PLAYER_LEVEL_UP", function() E.spent = 0 end)   -- (a new level fills your mana)

-- A bandage is a channel named "First Aid". The First Aid profession window
-- opens with a spell of the same name that isn't a channel and heals nothing.
function E.IsBandage(channelName) return channelName == "First Aid" end
ns:On("UNIT_SPELLCAST_CHANNEL_START", function(unit, _, spellID)
    if unit ~= "player" or not E.IsBandage(A.SpellInfo(A.Safe(spellID) or 0)) then return end
    local before = E.hurt
    E.hurt = math.max(0, E.hurt - E.HEAL_VALUE["First Aid"])
    ns:Log("heal", string.format("bandage: hurt %.0f -> %.0f", before, E.hurt))
end)
ns:On("PLAYER_LEVEL_UP", function() E.hurt = 0 end)                -- a new level fills your health
ns:On("PLAYER_UNGHOST", function() E.hurt = E.HURT.outBig + 5; health.since = GetTime() end)  -- back from the dead: about half

-------------------------------------------------------------------------------
-- Death reports: what happened in the fight you died in, so the target button
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
        print("  |cff888888(Claude looks at each death to improve the target button: this one goes at your next /reload.)|r")
    end
end)

-- A Flow window you can switch off (/flow rot off): the menus offer it back (Menu.lua).
ns:Register("window", "easybutton", { name = "Flow target button", order = 30,
    hidden = function() return ns.db.rotation.enabled == false end,
    show = function() ns.commands.rot("on") end,
    hide = function() ns.commands.rot("off") end })

-- Flow Settings, "Easy keys".
if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck({
        group = "key",
        label = "Start auto attack at the pull",
        note = "(the first press at a new enemy)",
        tip = "Casting at an enemy doesn't start your auto attack on WoW: Forever, and your key can't change once "
            .. "the fight is on. Ticked: with a new enemy targeted and no fight yet, the first press of your key "
            .. "turns auto attack on (instant), and your opener comes with the next press. Off: the key goes "
            .. "straight to your opener, and you only swing if you start it yourself. (While it's on and the enemy "
            .. "is out of reach, the game may say \"You are too far away\".)",
        get = function() return E.AutoAttackOn() end,
        set = function(on) ns.db.rotation.autoAttack = on and true or false end,
    })
end
