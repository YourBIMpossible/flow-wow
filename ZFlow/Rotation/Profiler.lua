local _, ns = ...
-- Parity row D-29 (lead sections 720, 721 and 732): the fight profiler.
-- Plan, with Lazy's CHANGES: reports/wow/zflow-d29-profiler-plan.md.
--
-- It learns, from your own fights (Rotation/Fights.lua's records, through
-- UI/FightLog.lua), which spells you cast more in your best fights than in
-- your worst, and the driver hands that to ns.Choose as its bias. The bias
-- only chooses between rules a pack marks adaptive (Choose.lua steps.list);
-- it never adds a spell. As Flow's Modules/Fight/Profiler.lua: Analyze
-- (the top third against the bottom third, the third max(2, floor(n/3))),
-- Relearn (fewer than MIN_SAMPLES fights: no bias, stale learning dropped)
-- and Bias; with Flow's Insights filter made the rule for the bias itself:
-- a spell counts only when abs(bias) >= 0.25 and its top or bottom rate is
-- at least 0.5 a minute.
--
-- A fight counts when it is closed, its start and end are numbers, it
-- lasted MIN_DURATION seconds or more, its kind (Fights.Kind) is known, and
-- nothing on the side it is measured by went unread. The measure:
--   dps    damage you or your pet did, a second
--   heal   healing you did, less overhealing, a second
--   tank, or no role chosen: none (no threat is read), so no bias
-- Fights are compared within one kind (solo, elite, group), one role, and
-- levels within LEVEL_SPAN of yours now.
--
-- Saved per character: PR.PATH, newest first, at most KEEP rows of
--   { at, kind, role, level, dur, v, hits = { [spell] = hits } }
-- (no names, no targets). The bias is worked out again, never saved.
-- "<slash> profiler" says what was learned; "<slash> profiler reset"
-- clears your rows. The setting PR.SETTING (on as made) off passes no bias
-- and keeps the rows.
--
-- Spells that neither deal damage nor heal are not in the records, so they
-- get no bias and keep the written order. Not tested in game.
local PR = {}
ns.Profiler = PR

PR.NAME = "profiler"
PR.SETTING = "rotation.learn"
PR.PATH = "profiler.fights"
PR.WORD = "profiler"
PR.HELP = "what Flow learned from your best fights; profiler reset clears it"
PR.KEEP = 100
PR.MIN_DURATION = 6
PR.MIN_SAMPLES = 6
PR.LEVEL_SPAN = 3
PR.MIN_BIAS = 0.25
PR.MIN_RATE = 0.5      -- casts a minute
PR.WAIT = 0.5          -- seconds after a fight ends before its record is read

local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

local function side(f, name)
    local s = type(f) == "table" and f[name] or nil
    if type(s) ~= "table" then return nil end
    return s
end

-- Pure: a fight record as a compact row, or nil when it does not count.
function PR.Row(f, role, level)
    if type(f) ~= "table" or f.open ~= false then return nil end
    if not finite(f.started) or not finite(f.ended) then return nil end
    local dur = f.ended - f.started
    if dur < PR.MIN_DURATION then return nil end
    local kind = ns.Fights.Kind(f)
    if kind == ns.Fights.UNKNOWN then return nil end
    local dealt, healed = side(f, "dealt"), side(f, "healed")
    local v
    if role == "dps" then
        if not dealt or dealt.unread ~= 0 or not finite(dealt.total) then return nil end
        v = dealt.total / dur
    elseif role == "heal" then
        if not healed or healed.unread ~= 0 or not finite(healed.total) then return nil end
        local over = 0
        if finite(healed.over) then over = healed.over end
        v = (healed.total - over) / dur
    else
        return nil
    end
    local hits = {}
    for _, s in ipairs({ dealt, healed }) do
        if s and type(s.spells) == "table" then
            for name, e in pairs(s.spells) do
                if type(name) == "string" and type(e) == "table" and finite(e.hits) then
                    hits[name] = (hits[name] or 0) + e.hits
                end
            end
        end
    end
    return { kind = kind, role = role, level = level, dur = dur, v = v, hits = hits }
end

function PR.Third(n) return math.max(2, math.floor(n / 3)) end

-- Pure: newest first, at most KEEP (a fresh list).
function PR.Keep(list, row)
    local out = { row }
    for _, r in ipairs(type(list) == "table" and list or {}) do
        if #out >= PR.KEEP then break end
        out[#out + 1] = r
    end
    return out
end

-- Pure: { [spell] = bias } for one bucket, or nil when fewer than
-- MIN_SAMPLES fights count (Relearn: stale learning is dropped).
function PR.Bias(rows, kind, role, level)
    if type(rows) ~= "table" or not finite(level) then return nil end
    local use = {}
    for _, r in ipairs(rows) do
        if type(r) == "table" and r.kind == kind and r.role == role and finite(r.v) and finite(r.dur)
            and r.dur > 0 and finite(r.level) and math.abs(r.level - level) <= PR.LEVEL_SPAN then
            use[#use + 1] = r
        end
    end
    if #use < PR.MIN_SAMPLES then return nil end
    table.sort(use, function(a, b) return a.v > b.v end)
    local third = PR.Third(#use)
    local function rate(r, spell)
        local h = type(r.hits) == "table" and r.hits[spell] or nil
        if not finite(h) then return 0 end
        return h / (r.dur / 60)
    end
    local function avg(from, to, spell)
        local s = 0
        for i = from, to do s = s + rate(use[i], spell) end
        return s / (to - from + 1)
    end
    local spells = {}
    for _, r in ipairs(use) do
        for spell in pairs(type(r.hits) == "table" and r.hits or {}) do spells[spell] = true end
    end
    local out = {}
    for spell in pairs(spells) do
        local top, bottom = avg(1, third, spell), avg(#use - third + 1, #use, spell)
        local b = (top - bottom) / math.max(top, bottom, 0.5)
        b = math.max(-1, math.min(1, b))
        if math.abs(b) >= PR.MIN_BIAS and (top >= PR.MIN_RATE or bottom >= PR.MIN_RATE) then out[spell] = b end
    end
    return out
end

-- fightsOf() -> Fights.lua's list, newest first (UI/FightLog.lua's
-- fights()); given for tests.
function PR.Declare(k, diag, fightsOf)
    local api = {}
    local ctx, pending
    local version, cache = 0, {}
    if type(fightsOf) ~= "function" then
        fightsOf = function()
            local log = ns.fightLog
            if type(log) == "table" and type(log.fights) == "function" then return log.fights() end
            return nil
        end
    end

    local function on() return ctx ~= nil and ctx.settings:get(PR.SETTING) ~= false end
    local function rows() return ctx.store:get("char", PR.PATH) or {} end
    local function level()
        local client = ctx.client
        if type(client.level) ~= "function" then return nil end
        local ok, v = pcall(client.level)
        if ok and finite(v) then return v end
        return nil
    end
    local function role()
        local r = ctx.settings:get("spec.role")
        if r == "dps" or r == "heal" or r == "tank" then return r end
        return nil
    end

    -- The newest closed fight, kept once.
    local function take()
        pending = nil
        if not ctx then return end
        local ok, list = pcall(fightsOf)
        if not ok or type(list) ~= "table" then return end
        local f = list[1]
        if type(f) ~= "table" or not finite(f.started) then return end
        local kept = rows()
        for _, r in ipairs(kept) do
            if r.at == f.started then return end
        end
        local row = PR.Row(f, role(), level())
        if not row then return end
        row.at = f.started
        ctx.store:set("char", PR.PATH, PR.Keep(kept, row))
        version = version + 1
    end

    -- { [spell] = bias } for this kind and role, or nil (off, not enough).
    function api.Bias(kind, r)
        if not ctx or not on() then return nil end
        local lv = level()
        if lv == nil then return nil end
        local key = tostring(kind) .. "|" .. tostring(r) .. "|" .. lv .. "|" .. version
        if cache[key] == nil then
            local b = PR.Bias(rows(), kind, r, lv)
            if b == nil then cache[key] = false else cache[key] = b end
        end
        if cache[key] == false then return nil end
        local out = {}
        for spell, v in pairs(cache[key]) do out[spell] = v end
        return out
    end

    local function reset()
        ctx.store:set("char", PR.PATH, {})
        version, cache = version + 1, {}
    end

    k:Module({
        name = PR.NAME,
        needs = { "client", "settings", "store", "sched", "bus" },
        provides = { Bias = api.Bias },
        settings = { {
            key = PR.SETTING, scope = "char", type = "bool", default = true,
            label = "Learn from your best fights",
            help = "Among spells of about equal worth, the key leans to the one you cast more in your best fights. "
                .. "It never adds a spell. Say " .. PR.WORD .. " reset to forget.",
            group = "combat.rotation", synonyms = { "learn", "profiler", "best fights", "adaptive" },
        } },
        start = function(c)
            ctx = c
            c.bus:on(PR.NAME, "PLAYER_REGEN_ENABLED", function()
                if pending or not on() then return end
                pending = c.sched:after(PR.NAME, PR.WAIT, take)
            end)
        end,
        stop = function()
            if type(pending) == "function" then pcall(pending) end
            pending, ctx = nil, nil
        end,
    })

    local function say(line)
        if ctx then ctx.client.print(ns.id.title .. ": " .. line) end
    end
    if diag and type(diag.commands) == "table" then
        diag.commands[PR.WORD] = function(rest)
            if not ctx then return end
            if tostring(rest or ""):lower():match("^%s*reset") then
                reset()
                say("profiler: your fights are forgotten; nothing learned now.")
                return
            end
            local n = #rows()
            say(string.format("profiler: %s; %d fight(s) kept.", on() and "on" or "off", n))
        end
        if type(diag.help) == "table" then diag.help[PR.WORD] = PR.HELP end
    end
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.profiler = PR.Declare(ns, ns.diag)
