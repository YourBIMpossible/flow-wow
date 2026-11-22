local _, ns = ...

-- S9: your casts against the advice. In every fight each spell you cast is
-- set beside what the rotation suggested at that moment:
--   "advice"  you cast what it suggested
--   "key"     you pressed your key (set to one spell while the fight lasts)
--             while the suggestion was another spell
--   "own"     you cast something else: your own choice
-- For "key" and "own" the situation is noted (the enemy on you, the advice
-- out of range...), so the pattern says why you chose otherwise, and each
-- fight remembers its choices, so fights with a choice can be set beside
-- fights without it. A port of Flow 0.35.377, Modules/Fight/Choices.lua:
-- the same kinds, tags, limits and texts.
--
-- It watches and counts. Nothing is cast, pressed or changed.
--
--   Ch.Kind(cast, advice, keySpell) -> "advice" | "key" | "own"
--   Ch.Tags(situation) -> { tag, ... }
--   Ch.Note(data, cast, advice, keySpell, tags, now) -> key | nil, kind
--   Ch.Trim(data, max) -> how many kinds were dropped
--   Ch.TagLine(rec[, n]) -> "enemy on you 92%, target close 67%"
--   Ch.Outcome(key, fights, value) -> { with, without, speedWith, ... } | nil
--   Ch.Report(data, fights, value, title) -> lines
--   Ch.AdviceBack(current, before, changedAt, now, lookback) -> advice
--   Ch.KeySpell(plan, form) -> the spell the key is set to | nil
--   Ch.Situation(snapshot, advice, form, opening) -> the table Ch.Tags reads
--   Ch.Since(since, clock) -> "today" | "the last N days" | nil
--   Ch.Declare(k[, diag[, packs]]) -> { data, report, reset, fight }
--
-- Where ZFlow differs from Flow, each for a reason:
--   * The spells that count are the class pack's spells (Flow: every class
--     spell). The client names no spell from an id here; the pack's names
--     are asked for their ids and a cast is matched by id.
--   * Health and power amounts are hidden from addons on this client, so
--     the module gives no "low mana", "target nearly dead" or "target
--     healthy". Moving and the number of enemies are not read either. The
--     tags stay in Ch.Tags for a client that gives them; not given, no tag.
--   * A cooldown is known here as yes or no, not in seconds.
--   * Fight logging is another file's and is left alone, so this keeps its
--     own short list of fights (how long, the rank of the first target,
--     the choices made). Kill speed is not known to it: fights are compared
--     by how long they lasted.
--   * Counted only while the rotation is giving a view: without advice
--     every cast would be counted as your own choice.
-- Not tested in game.
local Ch = {}
ns.Choices = Ch

local D = ns.RotationDriver

Ch.NAME = "choices"
Ch.PATH = "learned.fights.choices"   -- per character; where the import puts the tally Flow kept
Ch.SETTING = "rotation.choices"
Ch.WORD = "choices"
Ch.HELP = "what you cast in fights beside what the rotation suggested, and when you chose otherwise; choices reset forgets it"
Ch.MAX = 60                  -- as Flow: kinds of choice kept (the rarest go first)
Ch.LOOKBACK = 0.3            -- as Flow: an instant is judged against the advice this long before it landed
Ch.MIN_FIGHTS = 3            -- as Flow: fights on each side before they are compared
Ch.SHOWN = 8                 -- as Flow: choices listed of each kind
Ch.FIGHTS = 200              -- fights kept for the comparison
Ch.PENDING = 16              -- casts begun and not yet landed that are remembered
Ch.START = "UNIT_SPELLCAST_START"        -- unit, castGUID, spellID
Ch.DONE = "UNIT_SPELLCAST_SUCCEEDED"     -- unit, castGUID, spellID
Ch.UNKNOWN_TYPE = "not known"

-- ---------------------------------------------------------------- pure
function Ch.Kind(cast, advice, keySpell)
    if advice and cast == advice then return "advice" end
    if keySpell and cast == keySpell then return "key" end
    return "own"
end

-- The situation as short tags. s: { opening, moving, targetCasting, onYou
-- (1 / 0 / anything else: not known), near (true / false / nil), hurt,
-- mana (0..1), targetHp (0..1), attackers, shifted, adviceRange,
-- adviceUsable, adviceCooldown (seconds, or true) }. A field not given
-- adds no tag.
function Ch.Tags(s)
    local t = {}
    if type(s) ~= "table" then return t end
    local function add(tag) t[#t + 1] = tag end
    local function num(v) return type(v) == "number" and v or nil end
    if s.opening then add("opening cast") end
    if s.moving then add("moving") end
    if s.targetCasting then add("target casting") end
    if s.onYou == 1 then add("enemy on you") elseif s.onYou == 0 then add("enemy not on you") end
    if s.near == true then add("target close") elseif s.near == false then add("target far") end
    if (num(s.hurt) or 0) >= 8 then add("hurt") end
    if num(s.mana) and s.mana < 0.3 then add("low mana") end
    if num(s.targetHp) and s.targetHp < 0.25 then add("target nearly dead")
    elseif num(s.targetHp) and s.targetHp > 0.8 then add("target healthy") end
    if (num(s.attackers) or 0) >= 2 then add("several enemies") end
    if s.shifted then add("shapeshifted") end
    if s.adviceRange == false then add("advice out of range") end
    if s.adviceUsable == false then add("advice not usable") end
    if s.adviceCooldown == true or (num(s.adviceCooldown) or 0) > 1.5 then add("advice on cooldown") end
    return t
end

-- One cast into the tally (data: the saved table). Returns the key of the
-- choice (nil when you followed the advice) and its kind.
function Ch.Note(data, cast, advice, keySpell, tags, now)
    local kind = Ch.Kind(cast, advice, keySpell)
    data.casts = (data.casts or 0) + 1
    data.kinds = data.kinds or {}
    data.kinds[kind] = (data.kinds[kind] or 0) + 1
    if kind == "advice" then return nil, kind end
    data.list = data.list or {}
    local key = kind .. ": " .. cast .. " < " .. (advice or "nothing")
    local rec = data.list[key]
    if not rec then
        rec = { cast = cast, advice = advice, kind = kind, n = 0, tags = {} }
        data.list[key] = rec
    end
    rec.n, rec.last = rec.n + 1, now
    for _, tag in ipairs(tags or {}) do rec.tags[tag] = (rec.tags[tag] or 0) + 1 end
    return key, kind
end

-- Keeps the tally small: over `max` kinds, the rarest (then oldest) go.
function Ch.Trim(data, max)
    local keys = {}
    for key in pairs(data.list or {}) do keys[#keys + 1] = key end
    if #keys <= max then return 0 end
    table.sort(keys, function(a, b)
        local x, y = data.list[a], data.list[b]
        if x.n ~= y.n then return x.n > y.n end
        local lx, ly = x.last or 0, y.last or 0
        if lx ~= ly then return lx > ly end
        return a < b
    end)
    for i = max + 1, #keys do data.list[keys[i]] = nil end
    return #keys - max
end

-- "enemy on you 92%, target close 67%": the commonest situations of a choice.
function Ch.TagLine(rec, n)
    local list = {}
    for tag, count in pairs(rec.tags or {}) do
        list[#list + 1] = { tag = tag, share = count / math.max(1, rec.n) }
    end
    table.sort(list, function(a, b)
        if a.share ~= b.share then return a.share > b.share end
        return a.tag < b.tag
    end)
    local bits = {}
    for i = 1, math.min(n or 4, #list) do
        if list[i].share >= 0.3 then
            bits[#bits + 1] = string.format("%s %d%%", list[i].tag, math.floor(list[i].share * 100 + 0.5))
        end
    end
    return table.concat(bits, ", ")
end

-- Fights with this choice beside fights of the same types without it:
-- { with, without, speedWith, speedWithout, secsWith, secsWithout } (an
-- average is nil when too few fights have the value), or nil with fewer
-- than Ch.MIN_FIGHTS on a side. value(fight) -> its kill speed, or nil.
function Ch.Outcome(key, fights, value)
    local types, with, without = {}, {}, {}
    for _, f in ipairs(fights) do
        if f.own and f.own[key] then
            types[f.type or "normal"] = true
            with[#with + 1] = f
        end
    end
    for _, f in ipairs(fights) do
        if types[f.type or "normal"] and not (f.own and f.own[key]) then without[#without + 1] = f end
    end
    if #with < Ch.MIN_FIGHTS or #without < Ch.MIN_FIGHTS then return nil end
    local function avg(list, fn)
        local sum, n = 0, 0
        for _, f in ipairs(list) do
            local v = fn(f)
            if type(v) == "number" then sum, n = sum + v, n + 1 end
        end
        return n >= Ch.MIN_FIGHTS and sum / n or nil
    end
    local function secs(f) return f.duration end
    return {
        with = #with, without = #without,
        speedWith = avg(with, value), speedWithout = avg(without, value),
        secsWith = avg(with, secs), secsWithout = avg(without, secs),
    }
end

-- The lines of the report. title: the name the advice goes by.
function Ch.Report(data, fights, value, title)
    local out = {}
    title = type(title) == "string" and title or "the rotation"
    data = type(data) == "table" and data or {}
    local total = data.casts or 0
    if total == 0 then
        out[1] = "no casts recorded yet: fight a few mobs with the rotation on."
        return out
    end
    local kinds = data.kinds or {}
    local function pct(n) return math.floor((n or 0) / total * 100 + 0.5) end
    out[#out + 1] = string.format(
        "%d casts in fights: %d%% what %s advised, %d%% your key while it advised another spell, %d%% your own choice",
        total, pct(kinds.advice), title, pct(kinds.key), pct(kinds.own))
    local list = {}
    for key, rec in pairs(data.list or {}) do list[#list + 1] = { key = key, rec = rec } end
    table.sort(list, function(a, b)
        if a.rec.n ~= b.rec.n then return a.rec.n > b.rec.n end
        return a.key < b.key
    end)
    local noValue = function() return nil end
    for _, kind in ipairs({ "own", "key" }) do
        local shown = 0
        for _, e in ipairs(list) do
            local rec = e.rec
            if rec.kind == kind and shown < Ch.SHOWN then
                if shown == 0 then
                    out[#out + 1] = kind == "own" and "  your own choices:" or "  your key instead of the advice:"
                end
                shown = shown + 1
                local line = string.format("    %s when %s advised %s: %dx", rec.cast, title, rec.advice or "nothing", rec.n)
                local tags = Ch.TagLine(rec)
                if tags ~= "" then line = line .. ". Mostly: " .. tags end
                local o = Ch.Outcome(e.key, fights or {}, value or noValue)
                if o and o.speedWith and o.speedWithout and o.speedWithout > 0 then
                    line = line .. string.format(". Kill speed %+d%% in the %d fights with it (%d without)",
                        math.floor((o.speedWith / o.speedWithout - 1) * 100 + 0.5), o.with, o.without)
                elseif o and o.secsWith and o.secsWithout then
                    line = line .. string.format(". Fights with it lasted %.0f s, without %.0f s (%d and %d fights)",
                        o.secsWith, o.secsWithout, o.with, o.without)
                end
                out[#out + 1] = line
            end
        end
    end
    return out
end

-- What the advice was `lookback` seconds before `now`: an instant cast
-- lands and the advice moves on in the same moment, so a cast is judged
-- against what was showing when you pressed. (Flow: Engine.AdviceBack.)
function Ch.AdviceBack(current, before, changedAt, now, lookback)
    if type(changedAt) == "number" and type(now) == "number" and now - changedAt < lookback then return before end
    return current
end

-- The spell the key is set to in this form; nil when the plan or the form
-- is not known.
function Ch.KeySpell(plan, form)
    if type(plan) ~= "table" or type(plan.states) ~= "table" or type(form) ~= "number" then return nil end
    local row = plan.states[form]
    if type(row) ~= "table" or type(row.key) ~= "string" or row.key == "" then return nil end
    return row.key
end

-- The table Ch.Tags reads, from the snapshot the rotation decided on. A
-- field the snapshot does not have is left out: not known adds no tag.
function Ch.Situation(snapshot, advice, form, opening)
    local s = { opening = opening and true or false }
    if type(form) == "number" then s.shifted = form > 0 end
    if type(snapshot) ~= "table" then return s end
    s.targetCasting = snapshot.targetCasting ~= nil and snapshot.targetCasting ~= false
    if snapshot.targetOnYou == true then s.onYou = 1 elseif snapshot.targetOnYou == false then s.onYou = 0 end
    if snapshot.targetNear == true or snapshot.targetNear == false then s.near = snapshot.targetNear end
    if type(snapshot.hurt) == "number" then s.hurt = snapshot.hurt end
    local row = type(advice) == "string" and type(snapshot.spells) == "table" and snapshot.spells[advice] or nil
    if type(row) == "table" then
        if row.inRange == false then s.adviceRange = false end
        if row.usable == false then s.adviceUsable = false end
        if row.onCooldown == true then s.adviceCooldown = true end
    end
    return s
end

-- How long the tally has run, in words; nil when either time is not known.
function Ch.Since(since, clock)
    if type(since) ~= "number" or type(clock) ~= "number" or clock < since then return nil end
    local days = math.floor((clock - since) / 86400)
    if days < 1 then return "today" end
    if days == 1 then return "the last day" end
    return string.format("the last %d days", days)
end

-- ---------------------------------------------------------------- module
function Ch.Declare(k, diag, packs)
    local client
    local view, plan
    local advice, adviceBefore, adviceChangedAt
    local fight            -- { at, type, own, casts } while a fight is on
    local names            -- [spell id] = name, for the fight in progress
    local pending, pendingN = {}, 0
    local api = {}

    local function read(fn, ...)
        if type(fn) ~= "function" then return nil end
        local ok, v = pcall(fn, ...)
        if ok then return v end
        return nil
    end

    -- The saved table. Asked for at each use: it is not there before the
    -- client has loaded it.
    local function data()
        if not client then return nil end
        local d = k.store:table("char", Ch.PATH)
        if type(d) ~= "table" then return nil end
        if type(d.list) ~= "table" then d.list = {} end
        if type(d.fights) ~= "table" then d.fights = {} end
        if d.since == nil then d.since = read(client.clock) end
        return d
    end

    local function on() return k.settings:get(Ch.SETTING) ~= false end

    local function adviceOf(v)
        local s = type(v) == "table" and v.suggestion or nil
        local spell = type(s) == "table" and s.spell or nil
        return (type(spell) == "string" and spell ~= "") and spell or nil
    end

    local function onView(v)
        view = v
        if type(v) ~= "table" then
            plan = nil
        elseif type(v.keys) == "table" and type(v.keys.plan) == "table" then
            plan = v.keys.plan
        end
        local new = adviceOf(v)
        if new ~= advice then
            adviceBefore, adviceChangedAt = advice, read(client.now)
            advice = new
        end
    end

    local function keySpell() return Ch.KeySpell(plan, read(client.form)) end

    -- The pack's spells by id: the casts that count.
    local function spellNames()
        local out = {}
        local class = read(client.class)
        local all = packs or ns.Packs
        local pack = type(class) == "string" and type(all) == "table" and all[class] or nil
        if type(pack) ~= "table" or type(pack.spells) ~= "table" then return out end
        for name in pairs(pack.spells) do
            if type(name) == "string" then
                local id = read(client.spellId, name)
                if type(id) == "number" then out[id] = name end
            end
        end
        return out
    end

    local function forget()
        pending, pendingN = {}, 0
    end

    local function begin()
        fight = { at = read(client.now), type = read(client.targetRank) or Ch.UNKNOWN_TYPE, own = {}, casts = 0 }
        names = spellNames()
        forget()
    end

    local function finish()
        local f = fight
        fight, names = nil, nil
        forget()
        if not f or f.casts == 0 then return end
        local d = data()
        if not d then return end
        local row = { type = f.type, own = f.own }
        local t = read(client.now)
        if type(t) == "number" and type(f.at) == "number" and t >= f.at then row.duration = t - f.at end
        d.fights[#d.fights + 1] = row
        while #d.fights > Ch.FIGHTS do table.remove(d.fights, 1) end
        Ch.Trim(d, Ch.MAX)
    end

    -- Counting needs a fight, the setting on and the rotation giving a view.
    local function counting()
        return fight ~= nil and on() and type(view) == "table" and view.pack == true
    end

    local function situationNow(against)
        return Ch.Tags(Ch.Situation(view.snapshot, against, read(client.form), fight.casts == 0))
    end

    local function started(unit, castGUID)
        if unit ~= "player" or type(castGUID) ~= "string" or not counting() then return end
        if pending[castGUID] == nil then
            if pendingN >= Ch.PENDING then forget() end
            pendingN = pendingN + 1
        end
        pending[castGUID] = { advice = advice, key = keySpell(), tags = situationNow(advice) }
    end

    local function landed(unit, castGUID, spellId)
        if unit ~= "player" then return end
        local began
        if type(castGUID) == "string" and pending[castGUID] ~= nil then
            began = pending[castGUID]
            pending[castGUID] = nil
            pendingN = pendingN - 1
        end
        if type(spellId) ~= "number" or not counting() then return end
        local name = names and names[spellId] or nil
        if not name then return end
        local d = data()
        if not d then return end
        local was, key, tags
        if began then
            was, key, tags = began.advice, began.key, began.tags
        else
            was = Ch.AdviceBack(advice, adviceBefore, adviceChangedAt, read(client.now), Ch.LOOKBACK)
            key = keySpell()
            tags = situationNow(was)
        end
        local choice = Ch.Note(d, name, was, key, tags, read(client.clock))
        fight.casts = fight.casts + 1
        if choice then fight.own[choice] = (fight.own[choice] or 0) + 1 end
    end

    function api.data() return data() end
    function api.fight() return fight end
    function api.report()
        local d = data()
        return Ch.Report(d, d and d.fights or {}, nil, k.id.title)
    end
    function api.reset()
        local d = data()
        if not d then return end
        d.list, d.fights = {}, {}
        d.casts, d.kinds = nil, nil
        d.since = read(client.clock)
    end

    local function say(text) client.print(k.id.title .. ": " .. text) end

    local function run(rest)
        local d = data()
        if not d then return end
        if type(rest) == "string" and rest:lower():match("^%s*reset%s*$") then
            api.reset()
            say("forgot your recorded choices")
            return
        end
        local since = Ch.Since(d.since, read(client.clock))
        say("your casts against the advice" .. (since and (" (" .. since .. ")") or "") .. ":")
        local lines = api.report()
        for i = 1, #lines do say("  " .. lines[i]) end
        if not on() then say("  recording is switched off in the settings") end
    end

    k:Module({
        name = Ch.NAME,
        needs = { "client", "store", "bus", D.NAME },
        settings = { {
            key = Ch.SETTING, scope = "account", type = "bool", default = true,
            label = "Compare your casts with the advice",
            help = "In fights, counts what you cast beside what the rotation suggested. It only counts.",
            group = "Rotation",
        } },
        start = function(ctx)
            client = ctx.client
            ctx.bus:on(Ch.NAME, D.EVENT, onView)
            client.listen("PLAYER_REGEN_DISABLED", begin)
            client.listen("PLAYER_REGEN_ENABLED", finish)
            client.listen(Ch.START, started)
            client.listen(Ch.DONE, landed)
        end,
    })

    if diag and type(diag.commands) == "table" then
        diag.commands[Ch.WORD] = run
        if type(diag.help) == "table" then diag.help[Ch.WORD] = Ch.HELP end
    end

    return api
end

-- The addon's own.
ns.choices = Ch.Declare(ns, ns.diag)
