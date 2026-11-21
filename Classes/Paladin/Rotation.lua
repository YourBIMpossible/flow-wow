-- Paladin rotation. Spells you don't know yet are skipped automatically,
-- so this list can grow ahead of your level. Covers both classic-style
-- names (Judgement, seals) and modern ones (Judgment, Crusader Strike).
--
-- Rule fields: spell, kind (damage/buff/heal), reason, target (needs a
-- hostile target in range), when = function(ctx) -> bool,
-- adaptive = true (part of a group the profiler may reorder; see Engine).
--
-- Seal, blessing and Righteous Fury follow the role Flow plays you as
-- (ns:LevelingRole(): your choice, else your talents, else your class's
-- usual role), never your talent tree on its own: "Your role: DPS" with
-- Protection talents gets a DPS seal and no Righteous Fury.

local _, ns = ...
local A = ns.api

local function hasSeal()
    return A.Buff("player", function(n) return n and n:find("^Seal of") end)
end

-- Every Classic Era / Forever seal, for /flow seal.
local SEALS = { "Seal of Righteousness", "Seal of the Crusader", "Seal of Command",
                "Seal of Justice", "Seal of Light", "Seal of Wisdom", "Seal of Fury" }
local IS_SEAL = {}
for _, s in ipairs(SEALS) do IS_SEAL[s] = true end

-- The blessings you keep on yourself (not Protection, Freedom or Sacrifice:
-- those are for a moment, not a buff to keep up).
local BLESSINGS = { "Blessing of Might", "Blessing of Wisdom", "Blessing of Kings",
                    "Blessing of Salvation", "Blessing of Light", "Blessing of Sanctuary" }
local IS_BLESSING = {}
for _, b in ipairs(BLESSINGS) do IS_BLESSING[b] = true end

local function knowsWith(engine) return function(spell) return engine:Knows(spell) end end
local function myRole(role) return role or (ns.LevelingRole and ns:LevelingRole()) or "dps" end
local function roleLabel(role) return ns.ROLE_LABEL and ns.ROLE_LABEL[role] or role end

local function inGroup()
    if IsInGroup then return IsInGroup() and true or false end
    return (GetNumGroupMembers and GetNumGroupMembers() or 0) > 0
end

-- Seals and blessings: what to keep up -------------------------------------

-- Pure: the preference Flow follows, for a seal or a blessing. chosen: your
-- setting (Settings, /flow seal|blessing; nil = Auto); learned: what you
-- cast yourself in Auto, per role ({ [role] = spell }). Your setting first,
-- then what you cast for the role you're playing; each only once you know
-- it. nil: neither, so Flow picks by your role.
local function preferred(knows, role, chosen, learned)
    if chosen and knows(chosen) then return chosen end
    local cast = learned and role and learned[role]
    if cast and knows(cast) then return cast end
    return nil
end

-- Pure: does your cast of `cast` become what Flow keeps up from now on?
-- kinds: the spells that count (IS_SEAL / IS_BLESSING); fresh: what Flow
-- would put up right now; pressed: one of Flow's keys cast it (Flow's own
-- suggestion, never a choice of yours); onYou: true, false, or nil when
-- Flow can't tell (then nothing is learned). The cast, or nil.
local function keptFromCast(cast, kinds, fresh, pressed, onYou)
    if not (cast and kinds[cast]) or pressed or onYou ~= true then return nil end
    if cast == fresh then return nil end
    return cast
end

-- Did one of Flow's keys just cast `spell`? (Cast.lua notes each press.)
local function flowPressed(spell)
    return ns.cast and ns.cast.FlowPressed and ns.cast.FlowPressed(spell) or false
end

-- Pure: is an aura `name` the seal or blessing `want`? (A Greater Blessing
-- counts as the blessing.)
local function isWanted(name, want)
    return name ~= nil and want ~= nil and (name == want or name == "Greater " .. want)
end

-- Seal ---------------------------------------------------------------------

-- The last seal you cast yourself (not with Flow's key) since your last
-- fight ended. Flow keeps suggesting it until you leave combat, so
-- switching seals for one fight is just casting the other one, even with a
-- seal chosen in Settings (that choice stays).
local ownSeal

-- Pure: the seal for your role. Tanking: Fury; DPS: Command (a Retribution
-- talent: known only once you've taken it); healing in a group: Wisdom;
-- Righteousness otherwise, and until you know those.
local function roleSeal(knows, role, grouped)
    if role == "tank" and knows("Seal of Fury") then return "Seal of Fury" end
    if role == "dps" and knows("Seal of Command") then return "Seal of Command" end
    if role == "heal" and grouped and knows("Seal of Wisdom") then return "Seal of Wisdom" end
    return "Seal of Righteousness"
end

-- Which seal Flow puts up: the one you cast this fight; else the one you
-- chose (settings, /flow seal), if you know it; else, in Auto, the one you
-- last cast yourself while playing this role; else your role's. `s` can
-- hold own / grouped / learned (tests; false = none); missing ones are read
-- from the game. role: nil = ns:LevelingRole().
local function pickSeal(engine, role, s)
    s = s or {}
    local knows = knowsWith(engine)
    local own = s.own
    if own == nil then own = ownSeal end
    if own and knows(own) then return own end
    role = myRole(role)
    local learned = s.learned
    if learned == nil then learned = ns.db and ns.db.paladinSealCast end
    local pref = preferred(knows, role, ns.db and ns.db.paladinSeal, learned or nil)
    if pref then return pref end
    local grouped = s.grouped
    if grouped == nil then grouped = inGroup() end
    return roleSeal(knows, role, grouped)
end

-- A seal you cast yourself (a seal only ever goes on you) that isn't the
-- one Flow suggests: kept for this fight; and in Auto also remembered for
-- the role you're playing, every fight from then on, until you cast another.
-- "You think somebody's gonna go through all of that to change their
-- stuff?" A seal you chose in Settings is never changed by a cast: with one
-- chosen, a cast lasts the fight.
ns:PerCharacter("paladinSeal")
ns:PerCharacter("paladinSealCast")   -- { [role] = seal } you cast yourself in Auto
ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit ~= "player" or not spellID then return end
    local name = A.SpellInfo(A.Safe(spellID) or 0)   -- (Flow's own: the bare GetSpellInfo isn't on every client)
    if not (IS_SEAL[name or ""] and ns.rotation) then return end
    local role = myRole()
    local keep = keptFromCast(name, IS_SEAL, pickSeal(ns.rotation, role), flowPressed(name), true)
    if not keep then return end
    ownSeal = keep
    if ns.db.paladinSeal then return end
    ns.db.paladinSealCast = ns.db.paladinSealCast or {}
    if ns.db.paladinSealCast[role] == keep then return end
    ns.db.paladinSealCast[role] = keep
    ns:Print(string.format("%s: Flow suggests this seal while you play %s (Auto). Cast another to switch; /flow seal auto: back to your role's.",
        keep, roleLabel(role)))
end)
ns:On("PLAYER_REGEN_ENABLED", function() ownSeal = nil end)

-- Your choice (a seal's name, or nil for Auto). A new choice applies at
-- once, even mid-fight; either way the seals you cast are forgotten.
local function setSeal(name)
    ns.db.paladinSeal = name
    ns.db.paladinSealCast = nil
    ownSeal = nil
end

-- `want` missing or about to drop. In Forever, Judgement no longer uses up
-- the seal, so it only ends by running out: refresh it just before that
-- (a few seconds in combat; a little earlier right before a pull). Another
-- seal up counts as missing: a new choice applies at once.
local function needSeal(c, want)
    local up, left
    if want then
        up, left = A.Buff("player", function(n) return isWanted(n, want) end)
    else
        up, left = hasSeal()
    end
    if not up then return true end
    return left < (c.inCombat and 3 or 8)
end

-- When to put `want` on: missing or running out at a pull or in a fight,
-- and also out of combat whenever you have no seal at all, so it's already
-- up when a fight starts. (A fight that started without one locked the key
-- to Judgement, which fails with no seal: "cast failed: Judgement" in the
-- log.) Out of combat with another seal up, nothing: no recasting between
-- pulls. Not in inns and cities: the engine skips buffs while you're
-- resting. want: nil = any seal.
local function wantSeal(c, want)
    if c.hostile or c.inCombat then return needSeal(c, want) end
    return not hasSeal()
end

-- Blessing -----------------------------------------------------------------

-- Pure: the blessing for your role, like the seal: healing Wisdom for mana;
-- tanking Kings once you have it; else Might; Kings if you have no Might.
-- "Do blessings work the same as seals?"
local function roleBlessing(knows, role)
    if role == "heal" and knows("Blessing of Wisdom") then return "Blessing of Wisdom" end
    if role == "tank" and knows("Blessing of Kings") then return "Blessing of Kings" end
    if knows("Blessing of Might") then return "Blessing of Might" end
    if knows("Blessing of Kings") then return "Blessing of Kings" end
    return "Blessing of Might"
end

-- Which blessing Flow keeps on you: the one you chose (settings, /flow
-- blessing); else, in Auto, the one you last cast on yourself while
-- playing this role; else your role's. role: nil = ns:LevelingRole().
-- learned: the cast ones (tests; nil = this character's).
local function pickBlessing(engine, role, learned)
    local knows = knowsWith(engine)
    role = myRole(role)
    if learned == nil then learned = ns.db and ns.db.paladinBlessingCast end
    return preferred(knows, role, ns.db and ns.db.paladinBlessing, learned) or roleBlessing(knows, role)
end

-- Pure: did a cast go on you? name: the target name the game gave as you
-- cast (UNIT_SPELLCAST_SENT; nil or "" = none given); me: your name; at:
-- your target then, { exists, isYou, friendly }. A blessing with no target,
-- or an enemy targeted, goes on you. true / false, or nil when Flow can't
-- tell (a friend targeted and no name given).
local function recipientIsYou(name, me, at)
    local function bare(n) return (tostring(n or ""):gsub("%-.*$", "")) end
    if type(name) == "string" and name ~= "" then
        return me ~= nil and bare(name) == bare(me)
    end
    at = at or {}
    if not at.exists or at.isYou then return true end
    if at.friendly == false then return true end
    return nil
end

-- The blessing you're casting now and whether it's going on you, from the
-- moment you cast it (UNIT_SPELLCAST_SENT): by the time it lands your
-- target may have changed.
local sent
ns:On("UNIT_SPELLCAST_SENT", function(unit, target, castGUID, spellID)
    if unit ~= "player" then return end
    local name = A.SpellInfo(A.Safe(spellID) or 0)
    if not IS_BLESSING[name or ""] then sent = nil return end
    local exists = UnitExists and A.Safe(UnitExists("target")) == true or false
    local at = { exists = exists }
    if exists then
        at.isYou = UnitIsUnit and A.Safe(UnitIsUnit("target", "player")) == true or false
        local friend = UnitIsFriend and A.Safe(UnitIsFriend("player", "target"))
        if friend ~= nil then at.friendly = friend and true or false end
    end
    local me = UnitName and A.Safe((UnitName("player"))) or nil
    sent = { guid = A.Safe(castGUID), spell = name, onYou = recipientIsYou(A.Safe(target), me, at) }
end)

ns:PerCharacter("paladinBlessing")
ns:PerCharacter("paladinBlessingCast")   -- { [role] = blessing } you cast on yourself in Auto
ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, castGUID, spellID)
    if unit ~= "player" or not spellID then return end
    local name = A.SpellInfo(A.Safe(spellID) or 0)
    if not IS_BLESSING[name or ""] then return end
    local s = sent
    sent = nil
    local guid = A.Safe(castGUID)
    local onYou
    if s and s.spell == name and (s.guid == nil or guid == nil or s.guid == guid) then onYou = s.onYou end
    -- A blessing you chose (Settings, /flow blessing) stays: casts don't change it.
    if ns.db.paladinBlessing or not ns.rotation then return end
    local role = myRole()
    local keep = keptFromCast(name, IS_BLESSING, pickBlessing(ns.rotation, role), flowPressed(name), onYou)
    if not keep then return end
    ns.db.paladinBlessingCast = ns.db.paladinBlessingCast or {}
    ns.db.paladinBlessingCast[role] = keep
    ns:Print(string.format("%s: Flow keeps this blessing on you while you play %s (Auto). Cast another on yourself to switch; /flow blessing auto: back to your role's.",
        keep, roleLabel(role)))
end)

-- Your choice (a blessing's name, or nil for Auto). Either way the ones you
-- cast in Auto are forgotten: a choice of yours starts fresh.
local function setBlessing(name)
    ns.db.paladinBlessing = name
    ns.db.paladinBlessingCast = nil
end

-- `want` missing (another blessing up counts as missing: a new choice
-- applies at once), or under 30 seconds left. (Out of combat only: the
-- rules below.)
local function needBlessing(want)
    local up, left = A.Buff("player", function(n) return isWanted(n, want) end)
    return not up or left < 30
end

-- Only your own paladin auras count (not e.g. a hunter's Trueshot Aura).
local PALADIN_AURAS = {
    ["Devotion Aura"] = true, ["Retribution Aura"] = true, ["Concentration Aura"] = true,
    ["Shadow Resistance Aura"] = true, ["Frost Resistance Aura"] = true,
    ["Fire Resistance Aura"] = true, ["Sanctity Aura"] = true, ["Crusader Aura"] = true,
}
local function hasAura()
    -- An active aura on the stance bar counts even if it isn't shown as a buff.
    for _, s in ipairs(A.StanceSpells()) do
        if s.active and PALADIN_AURAS[s.name] then return true end
    end
    return A.Buff("player", function(n) return PALADIN_AURAS[n] end)
end

-- Righteous Fury: when you're tanking (your role: chosen, or by your
-- Protection talents in Auto), so what you hit stays on you. Never
-- otherwise: it only adds threat. "Why isn't it suggesting Righteous Fury if
-- I'm prot?" Pure: role (dps/heal/tank).
local function wantFury(role)
    return role == "tank"
end
local function needFury(c)
    local up, left = A.Buff("player", function(n) return n == "Righteous Fury" end)
    return not up or (not c.inCombat and left < 30)
end

local buffs = {
    { spell = "Devotion Aura", kind = "buff", reason = "No aura",
      when = function() return not hasAura() end },
    { spell = "Righteous Fury", kind = "buff", reason = "Tanking: Righteous Fury (threat)",
      when = function(c) return wantFury(c.role) and needFury(c) end },
}
-- One rule per blessing; only the one pickBlessing chooses can fire.
for _, b in ipairs(BLESSINGS) do
    buffs[#buffs + 1] = { spell = b, kind = "buff", reason = "Blessing missing or running out",
        when = function(c) return not c.inCombat and pickBlessing(c.engine, c.role) == b and needBlessing(b) end }
end
-- One rule per seal; only the one pickSeal chooses can fire.
for _, seal in ipairs(SEALS) do
    buffs[#buffs + 1] = { spell = seal, kind = "buff", reason = "No seal, or running out",
        when = function(c) return pickSeal(c.engine, c.role) == seal and wantSeal(c, seal) end }
end

-- Auto attack: suggested when you have a hostile target and aren't swinging.
-- Older clients call it "Attack", newer ones "Auto Attack"; only the one you
-- know is used.
local melee = {
    { spell = "Attack", target = true, reason = "Start attacking",
      when = function(c) return c.hostile and not A.IsCurrent("Attack") end },
    { spell = "Auto Attack", target = true, reason = "Start attacking",
      when = function(c) return c.hostile and not A.IsCurrent("Auto Attack") end },
}

local execute = {
    { spell = "Hammer of Wrath", target = true, reason = "Execute",
      when = function(c) return c.hostile end },
}

-- Roughly equal single-target hits: the profiler may reorder these.
local singleTarget = {
    { spell = "Judgement", target = true, reason = "Judge the seal", adaptive = true,
      -- Needs a seal up. (In Forever judging no longer uses the seal up.)
      when = function(c) return c.hostile and hasSeal() end },
    { spell = "Holy Strike", target = true, reason = "Holy Strike", adaptive = true,
      when = function(c) return c.hostile end },
    { spell = "Judgment", target = true, reason = "Judgment", adaptive = true,
      when = function(c) return c.hostile end },
    { spell = "Crusader Strike", target = true, reason = "Crusader Strike", adaptive = true,
      when = function(c) return c.hostile end },
    { spell = "Shield of the Righteous", target = true, reason = "Spend Holy Power", adaptive = true,
      when = function(c) return c.hostile end },
}

local aoe = {
    { spell = "Consecration", reason = "Several enemies",
      when = function(c) return c.inCombat end },
    { spell = "Holy Wrath", reason = "Several enemies",
      when = function(c) return c.inCombat end },
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
    if k("Devotion Aura") then add("  - Devotion Aura on (stays on; it's on your stance bar).") end
    local blessing = pickBlessing(e)
    if k(blessing) then add("  - " .. blessing .. " (re-cast when under 30s left; change it: /flow blessing, or cast another on yourself).") end
    local seal = pickSeal(e)
    if k(seal) then add("  - " .. seal .. ", cast just before you pull (change it: cast the one you want, or /flow seal).") end
    add("Fight:")
    if k("Judgement") then
        add("  1. Judgement to open (in Forever it doesn't use up your seal), then again on every cooldown.")
    end
    add("  2. Auto attack: keep swinging (Flow suggests Attack if you aren't).")
    if k("Holy Strike") then add("  3. Holy Strike on every cooldown.") end
    if k(seal) then add("  4. Refresh " .. seal .. " when it has ~3s left.") end
    if k("Hammer of Justice") then add("  - Hammer of Justice: stun a runner or buy time to heal.") end
    if k("Consecration") then add("  - Several enemies: Consecration (full damage on up to 4).") end
    add("Healing:")
    if k("Holy Light") then
        add("  - Holy Light between pulls, or mid-fight only when Flow flashes gold (heal now).")
    end
    if k("Divine Protection") then add("  - Divine Protection if a fight goes badly, then heal.") end
    if k("Lay on Hands") then add("  - Lay on Hands: last resort.") end
    return out
end

-- Your party or raid (Engine GroupBuff): one blessing each, the one that
-- helps them most. Kings for a tank; Might for melee (warriors, rogues,
-- paladins, a druid in Cat Form); Wisdom for casters, healers and hunters
-- (Might doesn't help ranged attacks); Kings for anyone else once you have it.
local function physical(u) return u.kind == "melee" or u.kind == "tank" end
local function usesMana(u) return u.kind == "caster" or u.kind == "healer" or u.kind == "ranged" end
local groupBuffs = {
    { spell = "Blessing of Kings", group = "blessing", minutes = 5, rebuff = 30,
      who = function(u) return u.kind == "tank" end },
    { spell = "Blessing of Might", group = "blessing", minutes = 5, rebuff = 30, who = physical },
    { spell = "Blessing of Wisdom", group = "blessing", minutes = 5, rebuff = 30, who = usesMana },
    { spell = "Blessing of Kings", group = "blessing", minutes = 5, rebuff = 30, who = function() return true end },
}

-- /flow seal [name|auto]: choose the seal Flow suggests (this character only).

local function findSeal(text)
    text = (text or ""):lower():gsub("^seal of%s*", ""):gsub("^the%s+", "")
    if text == "" then return nil end
    for _, s in ipairs(SEALS) do
        if s:lower():gsub("^seal of%s*", ""):gsub("^the%s+", ""):find(text, 1, true) == 1 then return s end
    end
end

ns.commands.seal = function(arg)
    arg = (arg or ""):match("^%s*(.-)%s*$")
    if arg:lower() == "auto" then
        setSeal(nil)
        ns:Print("seal: back to automatic (by your role: " .. roleLabel(myRole()) .. ")")
        return
    end
    if arg ~= "" then
        local s = findSeal(arg)
        if not s then
            ns:Print("no seal called '" .. arg .. "'. Try: righteousness, crusader, command, justice, light, wisdom, fury, or auto")
            return
        end
        setSeal(s)
        local known = ns.api.KnownSpells()[s]
        ns:Print("seal: Flow now suggests " .. s
            .. (known and "" or " (you don't know it yet: Flow keeps its usual seal until you do)"))
        return
    end
    ns:Print("seal: " .. (ns.db.paladinSeal or "automatic")
        .. ". /flow seal <righteousness|crusader|command|justice|light|wisdom|fury|auto>")
end

-- /flow blessing [name|auto]: the blessing Flow keeps on you.
ns.commands.blessing = function(arg)
    arg = (arg or ""):lower():match("^%s*(.-)%s*$"):gsub("^blessing of%s*", "")
    if arg == "auto" then
        setBlessing(nil)
        ns:Print("blessing: back to automatic (by your role: " .. roleLabel(myRole()) .. ")")
        return
    end
    if arg ~= "" then
        for _, b in ipairs(BLESSINGS) do
            if b:lower():gsub("^blessing of%s*", ""):find(arg, 1, true) == 1 then
                setBlessing(b)
                ns:Print("blessing: Flow now keeps " .. b .. " on you"
                    .. (ns.api.KnownSpells()[b] and "" or " (you don't know it yet: Flow keeps its usual one until you do)"))
                return
            end
        end
        ns:Print("no blessing called '" .. arg .. "'. Try: might, wisdom, kings, salvation, light, sanctuary, or auto")
        return
    end
    local learned = ns.db.paladinBlessingCast and ns.db.paladinBlessingCast[myRole()]
    ns:Print("blessing: " .. (ns.db.paladinBlessing or (learned and ("automatic, following the one you cast: " .. learned)) or "automatic")
        .. ". /flow blessing <might|wisdom|kings|salvation|light|sanctuary|auto>; in Auto, cast one on yourself to switch.")
end

ns:Register("help", "blessing", { order = 33, title = "Paladin blessing", lines = {
    "Automatic: by your role (Settings, \"Your role\"; Auto: your talents). Healing: Wisdom; tanking: Kings once you have it; otherwise Might.",
    "In Auto, cast another blessing on yourself and Flow keeps that one for the role you're playing, until you cast another. (Not one Flow's key cast, nor one on someone else.)",
    "To pick one for good: /flow blessing might (wisdom, kings, salvation, light, sanctuary), or Settings, Easy keys, \"Paladin blessing\".",
    "Blessings on your group are separate (Might for melee, Wisdom for casters, Kings for tanks).",
    "Back to automatic: /flow blessing auto (or Settings, Easy keys, \"Paladin blessing\": Auto).",
} })

ns:Register("help", "seal", { order = 32, title = "Paladin seal", lines = {
    "Automatic: by your role (Settings, \"Your role\"; Auto: your talents). Tanking: Fury; DPS: Command once you have it; healing in a group: Wisdom; otherwise Righteousness.",
    "To change it, just cast the seal you want: in Auto, Flow suggests that one from then on while you play that role, until you cast another. Casts from Flow's own keys don't count.",
    "Settings, Easy keys: \"Paladin seal\" picks one for good (a cast then lasts only the fight); or /flow seal command (righteousness, crusader, justice, light, wisdom, fury). /flow seal auto: back to your role's, forgetting the seals you cast.",
} })

ns:Register("rotation", "PALADIN", {
    guide = guide,
    wantSeal = wantSeal,   -- (tests)
    pickSeal = pickSeal,   -- (tests)
    SetSeal = setSeal,     -- (settings)
    wantFury = wantFury,   -- (tests)
    pickBlessing = pickBlessing,         -- (tests)
    SetBlessing = setBlessing,           -- (settings)
    needBlessing = needBlessing,         -- (tests)
    Preferred = preferred,               -- (tests)
    KeptFromCast = keptFromCast,         -- (tests)
    RecipientIsYou = recipientIsYou,     -- (tests)
    IS_SEAL = IS_SEAL, IS_BLESSING = IS_BLESSING, -- (tests)
    SEALS = SEALS,         -- (tests)
    groupBuffs = groupBuffs,
    -- Poisons, diseases (and magic, with Cleanse) on you or your group (Engine Dispel).
    dispels = {
        { spell = "Cleanse", types = { Poison = true, Disease = true, Magic = true } },
        { spell = "Purify", types = { Poison = true, Disease = true } },
    },

    -- Self-heals, considered before anything else (see Engine HealDecision).
    heals = { "Flash of Light", "Holy Light", "Word of Glory" },

    -- What the cast key stays on for a fight (it can't change in combat).
    -- The pull suggestion if it's a real attack; a seal only if you have none
    -- (Judgement needs one); otherwise Judgement, your main hit.
    pullLock = function(s, engine)
        -- A heal suggested at the pull is the after-fight prompt from the last
        -- fight: never lock the key to it for this one.
        if s and (s.kind == "heal" or s.kind == "emergency") then s = nil end
        if s and s.kind ~= "buff" and s.spell ~= "Attack" and s.spell ~= "Auto Attack" then return s.spell end
        if s and s.spell:find("^Seal of") and not hasSeal() then return s.spell end
        for _, spell in ipairs({ "Judgement", "Judgment", "Crusader Strike", "Holy Strike" }) do
            if engine:Knows(spell) then return spell end
        end
        return s and s.spell
    end,

    -- The target button's queue (Queue.lua): Ctrl + key is your next strike
    -- beside the key's own (the first you know that the key doesn't hold),
    -- Alt + key the stun that stops a cast. Shift + key is your heal; Alt is
    -- your healthstone or potion if you carry one.
    fightKeys = function()
        return { ctrl = { "Crusader Strike", "Holy Strike", "Judgement", "Judgment", "Shield of the Righteous", "Consecration", "Exorcism" },
                 alt = { "Hammer of Justice" } }
    end,

    -- Default priority (first match wins).
    priority = join(buffs, melee, execute, singleTarget),

    -- Per fight type (see Modules/Fight/FightTypes.lua). Missing types use `priority`.
    priorities = {
        aoe = join(buffs, melee, aoe, execute, singleTarget),
        -- boss / elite: same as default for now. As fights get recorded, the
        -- profiler learns a separate order for each type anyway.
    },
})
