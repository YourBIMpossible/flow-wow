-- Fight profiler: records every fight (damage, healing, threat, damage
-- taken, what you cast, whether you followed Flow's suggestion), then
-- compares your best fights of each type with your worst to find what was
-- different. The rotation engine uses the result ("bias") to choose between
-- roughly equal options, so it adapts to how you actually do best.
--
-- Extension points:
--   ns:Register("metric", key, { label, role, higherBetter, value = function(fight) end })
--   ns:Register("fightProbe", key, { start = fn(fight), tick = fn(fight, dt),
--                                    finish = fn(fight), events = { EVENT = fn(fight, ...) } })

local _, ns = ...
local A = ns.api
local P = {}
ns.profiler = P

local MAX_FIGHTS = 300    -- fights kept in saved data
local MIN_DURATION = 6    -- shorter fights are too noisy to learn from
local MIN_SAMPLES = 6     -- fights of one type needed before learning kicks in
local LEVEL_SPAN = 3      -- only compare fights within this many levels (new spells change things)

local fight               -- the fight in progress, or nil
local playerGUID

local function db() return ns.db.profiler end

-------------------------------------------------------------------------------
-- Metrics
-------------------------------------------------------------------------------

-- With the combat log: real damage per second. Without it (Forever): kill
-- speed, i.e. the mob's max health / fight length, for fights where you
-- killed a single mob. Good enough to tell your best fights from your worst.
ns:Register("metric", "dps", {
    label = "DPS", role = "dps", higherBetter = true,
    value = function(f)
        if f.combatLog then return f.damage / f.duration end
        if f.killed and f.targetMaxHp and (f.maxAttackers or 1) <= 1 then
            return f.targetMaxHp / f.duration
        end
        return nil
    end,
})
ns:Register("metric", "hps", {
    label = "HPS", role = "heal", higherBetter = true,
    value = function(f) return f.combatLog and f.healing / f.duration or nil end,
})
ns:Register("metric", "tps", {
    label = "Threat/s", role = "tank", higherBetter = true,
    value = function(f) return f.threat and f.threat / f.duration or nil end,
})
ns:Register("metric", "dtps", {
    label = "Damage taken/s", higherBetter = false,
    value = function(f) return f.combatLog and f.taken / f.duration or nil end,
})

-- Kill-speed inputs (works without the combat log): the target's max health
-- (whenever the client shows it), whether it died, and how many enemies hit you.
ns:Register("fightProbe", "killProxy", {
    start = function(f) f.maxAttackers = 0 end,
    tick = function(f)
        local Safe = A.Safe
        if UnitExists("target") and UnitCanAttack("player", "target") then
            -- (In a group the game hides the target's ID in a fight: comparing a
            -- hidden value is an error, 0.35.243. No ID, nothing to note.)
            local guid = Safe(UnitGUID("target"))
            if guid and not f.mainTarget then f.mainTarget = guid end
            if guid and guid == f.mainTarget then
                local max = Safe(UnitHealthMax("target"))
                if max and max > 0 then f.targetMaxHp = max end
                if UnitIsDead("target") then f.killed = true end
            end
        end
        local n = ns.tracker and ns.tracker:AttackerCount() or 0
        if n > f.maxAttackers then f.maxAttackers = n end
    end,
    finish = function(f)
        local guid = UnitExists("target") and A.Safe(UnitGUID("target"))
        if not f.killed and guid and guid == f.mainTarget
            and UnitIsDead("target") then
            f.killed = true
        end
        f.mainTarget = nil
    end,
})

-- The metric that defines a "good fight" for a role.
function P:PrimaryMetric(role)
    for key, m in ns:Each("metric") do
        if m.role == role then return key, m end
    end
    return "dps", ns:Get("metric", "dps")
end

-------------------------------------------------------------------------------
-- Built-in probes
-------------------------------------------------------------------------------

-- Damage and healing you do, damage you take (combat log).
ns:Register("fightProbe", "combatLog", {
    events = {
        COMBAT_LOG_EVENT_UNFILTERED = function(f)
            local _, sub, _, src, _, _, _, dst, _, _, _,
                  a12, _, _, a15, a16 = CombatLogGetCurrentEventInfo()
            playerGUID = playerGUID or A.Safe(UnitGUID("player"))
            src = A.Safe(src)
            local pet = A.Safe(UnitGUID("pet"))
            local mine = src ~= nil and (src == playerGUID or src == pet)
            if mine then
                if sub == "SWING_DAMAGE" then
                    f.damage = f.damage + (a12 or 0)
                elseif sub == "SPELL_DAMAGE" or sub == "SPELL_PERIODIC_DAMAGE" or sub == "RANGE_DAMAGE" then
                    f.damage = f.damage + (a15 or 0)
                elseif sub == "SPELL_HEAL" or sub == "SPELL_PERIODIC_HEAL" then
                    local over = a16 or 0
                    f.healing = f.healing + math.max(0, (a15 or 0) - over)
                    f.overheal = f.overheal + over
                end
            end
            if dst == playerGUID then
                if sub == "SWING_DAMAGE" then
                    f.taken = f.taken + (a12 or 0)
                elseif sub == "SPELL_DAMAGE" or sub == "SPELL_PERIODIC_DAMAGE" or sub == "RANGE_DAMAGE" then
                    f.taken = f.taken + (a15 or 0)
                end
            end
        end,
    },
})

-- What you cast, your opener, and whether you pressed what Flow suggested.
-- The suggestion is captured when the cast STARTS (it changes while you
-- cast), and only spells the rotation knows about count towards "followed".
local suggestedAtStart = {}

local function rotationSpells()
    local set = {}
    local def = ns.rotation and ns.rotation:Definition()
    if not def then return set end
    for _, r in ipairs(def.priority or {}) do set[r.spell] = true end
    for _, list in pairs(def.priorities or {}) do for _, r in ipairs(list) do set[r.spell] = true end end
    for _, h in ipairs(def.heals or {}) do set[h] = true end
    return set
end

ns:Register("fightProbe", "casts", {
    start = function(f) f.rotationSpells = rotationSpells() end,
    finish = function(f) f.rotationSpells = nil end,
    events = {
        UNIT_SPELLCAST_START = function(_, unit, castGUID)
            if unit ~= "player" then return end
            local s = ns.rotation and ns.rotation.current
            if castGUID then suggestedAtStart[castGUID] = s and s.spell or false end
        end,
        UNIT_SPELLCAST_SUCCEEDED = function(f, unit, castGUID, spellID)
            if unit ~= "player" or not spellID then return end
            local name = A.SpellInfo(spellID)
            if not name then return end
            f.casts[name] = (f.casts[name] or 0) + 1
            if #f.opener < 4 then f.opener[#f.opener + 1] = name end
            if f.rotationSpells and f.rotationSpells[name] then
                local suggested = castGUID and suggestedAtStart[castGUID]
                if suggested == nil then
                    local s = ns.rotation.current
                    suggested = s and s.spell
                end
                if suggested then
                    f.suggested = f.suggested + 1
                    if suggested == name then f.followed = f.followed + 1 end
                end
            end
            if castGUID then suggestedAtStart[castGUID] = nil end
        end,
    },
})

-- Threat on your target (if the client exposes it). Highest value seen per mob.
-- Forever hides the target's GUID (a secret), while the threat value itself can
-- still be readable. Without a GUID the threat goes under one shared key, so a
-- fight still records your threat instead of none at all (it can't be split
-- per mob then; the highest value on your target stands for the fight).
local NO_GUID = "target"
function P.RecordThreat(f, guid, value)
    if type(value) ~= "number" then return end
    local key = guid or NO_GUID
    if value > (f.threatByMob[key] or 0) then f.threatByMob[key] = value end
end

ns:Register("fightProbe", "threat", {
    start = function(f) f.threatByMob = {} end,
    tick = function(f)
        if not UnitDetailedThreatSituation or not UnitExists("target") then return end
        local _, _, _, _, value = UnitDetailedThreatSituation("player", "target")
        P.RecordThreat(f, A.Safe(UnitGUID("target")), A.Safe(value))
    end,
    finish = function(f)
        local sum, any = 0, false
        for _, v in pairs(f.threatByMob) do sum = sum + v; any = true end
        f.threat = any and sum / 100 or nil   -- the API reports threat x100
        f.threatByMob = nil
    end,
})

-- How long the fight spent as each fight type; the fight is labelled with the
-- one it spent most time as, except that any real boss time makes it a boss fight.
ns:Register("fightProbe", "fightType", {
    start = function(f) f.typeTime = {} end,
    tick = function(f, dt)
        local t = ns.fight:Classify()
        f.typeTime[t] = (f.typeTime[t] or 0) + dt
        if not f.target and UnitExists("target") and UnitCanAttack("player", "target") then
            f.target = UnitName("target")
        end
    end,
    finish = function(f)
        local best, bestT = "normal", 0
        for t, secs in pairs(f.typeTime) do
            if secs > bestT then best, bestT = t, secs end
        end
        if (f.typeTime.boss or 0) >= f.duration * 0.3 then best = "boss" end
        f.type = best
        f.typeTime = nil
    end,
})

-------------------------------------------------------------------------------
-- Recording
-------------------------------------------------------------------------------

local function eachProbe(method, ...)
    for key, probe in ns:Each("fightProbe") do
        if probe[method] then
            local ok, err = pcall(probe[method], ...)
            if not ok and ns.db.rotation.debug then ns:Print("probe " .. key .. ": " .. tostring(err)) end
        end
    end
end

local function startFight()
    fight = {
        t = time(), started = GetTime(), level = UnitLevel("player"),
        role = ns:LevelingRole(), damage = 0, healing = 0, overheal = 0, taken = 0,
        casts = {}, opener = {}, suggested = 0, followed = 0,
        combatLog = A.CombatLogAllowed(),
    }
    eachProbe("start", fight)
end

local function finishFight()
    if not fight then return end
    fight.duration = GetTime() - fight.started
    fight.started = nil
    eachProbe("finish", fight)
    local f = fight
    fight = nil
    if f.duration < 2 then return end

    local list = db().fights
    list[#list + 1] = f
    while #list > MAX_FIGHTS do table.remove(list, 1) end
    P:Relearn(f.type, f.role)

    if ns.db.profiler.report then
        local _, m = P:PrimaryMetric(f.role)
        local v = m.value(f)
        ns:Print(string.format("%s fight, %.0fs: %s %.1f", ns.fight:Label(f.type), f.duration,
            m.label, v or 0))
    end
end

-------------------------------------------------------------------------------
-- Analysis
-------------------------------------------------------------------------------

local function cpm(f, spell)
    return (f.casts[spell] or 0) / (f.duration / 60)
end

-- Compares the best third of comparable fights with the worst third.
-- Returns nil, count when there aren't enough fights yet.
function P:Analyze(fightType, role)
    role = role or ns:LevelingRole()
    local _, metric = self:PrimaryMetric(role)
    local level = UnitLevel("player")
    local rows = {}
    for _, f in ipairs(db().fights) do
        if f.type == fightType and f.role == role and f.duration >= MIN_DURATION
            and math.abs((f.level or level) - level) <= LEVEL_SPAN then
            local v = metric.value(f)
            if v then rows[#rows + 1] = { f = f, v = v } end
        end
    end
    if #rows < MIN_SAMPLES then return nil, #rows end
    table.sort(rows, function(a, b)
        if metric.higherBetter then return a.v > b.v end
        return a.v < b.v
    end)

    local third = math.max(2, math.floor(#rows / 3))
    local top, bottom = {}, {}
    for i = 1, third do top[#top + 1] = rows[i] end
    for i = #rows - third + 1, #rows do bottom[#bottom + 1] = rows[i] end

    local function avg(group, fn)
        local s = 0
        for _, r in ipairs(group) do s = s + fn(r) end
        return s / #group
    end

    local spells = {}
    for _, r in ipairs(rows) do
        for spell in pairs(r.f.casts) do spells[spell] = true end
    end
    local diffs = {}
    for spell in pairs(spells) do
        local t = avg(top, function(r) return cpm(r.f, spell) end)
        local b = avg(bottom, function(r) return cpm(r.f, spell) end)
        local bias = (t - b) / math.max(t, b, 0.5)
        diffs[#diffs + 1] = { spell = spell, top = t, bottom = b, bias = math.max(-1, math.min(1, bias)) }
    end
    table.sort(diffs, function(a, b) return math.abs(a.bias) > math.abs(b.bias) end)

    local function follow(group)
        return avg(group, function(r)
            return r.f.suggested > 0 and r.f.followed / r.f.suggested or 0
        end)
    end

    local openers = {}
    for _, r in ipairs(top) do
        local o = r.f.opener[1]
        if o then openers[o] = (openers[o] or 0) + 1 end
    end
    local opener, best = nil, 0
    for o, n in pairs(openers) do if n > best then opener, best = o, n end end

    return {
        count = #rows, metric = metric,
        best = rows[1].v,
        avg = avg(rows, function(r) return r.v end),
        topAvg = avg(top, function(r) return r.v end),
        bottomAvg = avg(bottom, function(r) return r.v end),
        spells = diffs,
        followTop = follow(top), followBottom = follow(bottom),
        opener = opener,
    }
end

-- Recomputes the learned preferences for one fight type and role.
function P:Relearn(fightType, role)
    local a = self:Analyze(fightType, role)
    db().bias[role] = db().bias[role] or {}
    if not a then
        db().bias[role][fightType] = nil  -- not enough recent data: stop using old learning
        return
    end
    local b = {}
    for _, d in ipairs(a.spells) do b[d.spell] = d.bias end
    db().bias[role][fightType] = b
end

-- How strongly a spell is linked to your best fights of this type: -1..1.
-- Uses in-game learning first; falls back to what the combat log analyser
-- learned (Learned\CombatLog.lua), first for this fight type, then overall.
function P:Bias(fightType, spell)
    local role = ns:LevelingRole()
    local r = db().bias[role]
    local t = r and r[fightType]
    if t then return t[spell] or 0 end
    local learned = ns:Get("learned", "combatlog")
    local lb = learned and learned.bias and learned.bias[role]
    if lb then
        local lt = lb[fightType] or lb.all
        if lt then return lt[spell] or 0 end
    end
    return 0
end

-- Plain-language findings, used by /flow fights and by the advisor.
function P:Insights(fightType, role)
    local a, n = self:Analyze(fightType, role)
    if not a then return {}, n end
    local out = {}
    local label = ns.fight:Label(fightType)
    for i = 1, math.min(3, #a.spells) do
        local d = a.spells[i]
        if math.abs(d.bias) >= 0.25 and (d.top >= 0.5 or d.bottom >= 0.5) then
            out[#out + 1] = string.format("%s fights: you cast %s %.1f/min in your best vs %.1f/min in your worst%s.",
                label, d.spell, d.top, d.bottom,
                d.bias > 0 and ", so Flow now leans towards it" or ", so Flow now leans away from it")
        end
    end
    if a.followTop - a.followBottom >= 0.15 then
        out[#out + 1] = string.format("%s fights: you followed Flow %d%% of the time in your best fights vs %d%% in your worst.",
            label, a.followTop * 100, a.followBottom * 100)
    end
    if a.opener then
        out[#out + 1] = string.format("%s fights: your best fights usually open with %s.", label, a.opener)
    end
    return out, a.count
end

-------------------------------------------------------------------------------
-- Wiring
-------------------------------------------------------------------------------

-- Your fights are your character's (they drive "Ways to improve"). From the
-- old shared history, keep the fights where one of your class's spells was
-- cast; plain-Attack fights can't be told apart and are left out. The
-- learned bias is worked out again from your own fights.
local function fightOfClass(f, mine)
    for spell in pairs(f.casts or {}) do if mine[spell] then return true end end
    for _, spell in ipairs(f.opener or {}) do if mine[spell] then return true end end
    return false
end
ns:PerCharacter("profiler", { adopt = function(old, ctx)
    local mine, fights = ns:ClassSpellSet(ctx.class), {}
    for _, f in ipairs(old.fights or {}) do
        if fightOfClass(f, mine) then fights[#fights + 1] = f end
    end
    return { fights = fights, bias = {} }
end })

ns:OnLoad(function(saved)
    saved.profiler = saved.profiler or {}
    saved.profiler.fights = saved.profiler.fights or {}
    saved.profiler.bias = saved.profiler.bias or {}

    local f = CreateFrame("Frame")
    local handlers = {}
    for _, probe in ns:Each("fightProbe") do
        for event, fn in pairs(probe.events or {}) do
            local allowed = event ~= "COMBAT_LOG_EVENT_UNFILTERED" or A.CombatLogAllowed()
            if allowed then
                if not handlers[event] then
                    handlers[event] = {}
                    pcall(f.RegisterEvent, f, event)
                end
                table.insert(handlers[event], fn)
            end
        end
    end
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_REGEN_DISABLED" then startFight(); return end
        if event == "PLAYER_REGEN_ENABLED" then
            local ok, err = pcall(finishFight)
            if not ok then fight = nil; if ns.db.rotation.debug then ns:Print("profiler: " .. tostring(err)) end end
            return
        end
        if not fight then return end
        for _, fn in ipairs(handlers[event] or {}) do pcall(fn, fight, ...) end
    end)

    local acc = 0
    f:SetScript("OnUpdate", function(_, dt)
        if not fight then acc = 0 return end  -- don't carry idle time into the next fight
        acc = acc + dt
        if acc < 0.25 then return end
        eachProbe("tick", fight, acc)
        acc = 0
    end)
end)

ns.commands.fights = function(arg)
    arg = (arg or ""):lower()
    if arg == "report" then
        db().report = not db().report
        ns:Print("per-fight report " .. (db().report and "on" or "off"))
        return
    elseif arg == "reset" then
        wipe(db().fights); wipe(db().bias)
        ns:Print("forgot all recorded fights")
        return
    end
    local role = ns:LevelingRole()
    local _, metric = P:PrimaryMetric(role)
    ns:Print(string.format("%d fights recorded. Judging by %s (%s role).", #db().fights, metric.label, ns.ROLE_LABEL[role]))
    for key in ns:Each("fightType") do
        local a, n = P:Analyze(key, role)
        if a then
            print(string.format("  %s: %d fights, best %.1f, average %.1f (best third %.1f, worst third %.1f)",
                ns.fight:Label(key), a.count, a.best, a.avg, a.topAvg, a.bottomAvg))
            for _, line in ipairs((P:Insights(key, role))) do print("    - " .. line) end
        elseif n and n > 0 then
            print(string.format("  %s: %d usable fights, need %d to learn", ns.fight:Label(key), n, MIN_SAMPLES))
        end
    end
    print("  /flow fights report|reset")
end
