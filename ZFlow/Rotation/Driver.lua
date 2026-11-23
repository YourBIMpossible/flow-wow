local _, ns = ...

-- Rotation driver: each tick it reads the client, asks the chooser, and
-- holds the answer as a view for whoever shows it. It suggests; it presses
-- nothing: no attribute, binding, cast or frame is touched here, and the
-- key plan is only worked out, never applied.
--
--   D.Read(client, pack, ids[, role, extra]) -> read(field)
--     extra (section 232): one options table with named fields; no further
--     positional arguments. extra.food: the module's food table (below).
--     extra.chosen: the seals and blessings from the ownCasts module (below).
--     the reader ns.Snapshot takes. dead, inCombat, stealthed, hostile,
--     spells, buffs, targetDebuffs, form, current and pet are asked of the
--     client; role is the
--     one handed in; every other field answers nil (not known), never a
--     guess.
--       role       the role you chose (the setting D.ROLE), when it is
--                  "dps", "heal" or "tank" and the pack has a part for it;
--                  anything else: nil. No talent is read: the rotation
--                  plays the role you say, or none.
--       stealthed  client.stealthed() as it answered; nil when the client
--                  has no such read
--       hostile    from client.target() -> { exists, hostile, dead } or nil:
--                  true for a target that is there, hostile and alive; false
--                  when any of the three was read the other way; nil for
--                  anything else, or when the client has no such read
--       buffs      client.playerBuffs() as it answered: { [name] = seconds
--                  left or true }, {} for read and none, nil when not known
--                  or the client has no such read
--       targetDebuffs  client.targetDebuffs(): your own debuffs on the
--                  target, the same shape and the same not known (187)
--       form       client.formName(): the form name, or nil for no form
--                  and for not known alike
--       formKnown  true when client.formName() said its answer is known
--                  (a form name, or no form); nil otherwise, never false.
--                  form nil with formKnown true is no form (section 186)
--       current    { [spell name] = true or false } over the pack's spell
--                  ids, from client.currentSpell(id); a spell whose answer
--                  was not read is left out; nil when the client has no
--                  such read or no spell was read
--       pet        client.pet() as it answered (lead section 197): nil when
--                  not known or the client has no such read; { exists =
--                  false } for no pet; else exists, dead, inCombat, family,
--                  happiness, powerKind, each nil when not known
--       spells     each row also gets inRange = client.inRange(spell id)
--                  when the client has that read and the answer is true or
--                  false; otherwise range stays not known
--       buffFood   the best Well Fed food in your bags (section 226). With
--                  food (a table the module keeps, section 229 F-1): the
--                  bags are read only out of a fight (inCombat false), and
--                  a food read is kept in food until the module clears it
--                  on BAG_UPDATE_DELAYED, or the pack or role changes. In a
--                  fight, or a fight not known, the kept food answers, or
--                  nil. Not known (nil) is not kept: the next read asks
--                  again. A pick made while some food in the bags was not
--                  read yet (section 236: data arriving in parts) answers
--                  but is not kept either: the next read asks again, so a
--                  better food read late is not missed until the bags
--                  change. Without food: read each time, as before.
--                  food.on false (the D.FOOD setting off, section 230
--                  BF-3): nil, and the bags are not read
--       foodOn     food.on (true or false); nil without food
--       mounted, onTaxi  client.mounted(), client.onTaxi(): true or false,
--                  nil when the client has no such read or does not say
--       chosen     extra.chosen (CF-32, N12): the seals and blessings
--                  you cast or chose, by key, from the ownCasts module
--                  (Rotation/OwnCasts.lua); nil when it is not a table
--                  (none, or the module is not there)
--       ownBuffs   client.ownBuffs() as it answered (N13): the buffs on you
--                  that you put up yourself; nil when not known or the
--                  client has no such read
--   D.Step(client, pack[, prefs, bias, applied, role, extra]) -> view
--     extra is handed to D.Read as it is (section 232).
--     one read and one choice. A read that fails is an error (not caught
--     here; the tick catches it).
--   D.Why(snapshot, trace, keys, lockdown) -> why
--   D.Declare(k[, packs]) -> api           declares the module on kernel k
--     packs: { [class token] = pack }, ns.Packs when left out.
--     api.view()       the view held, nil when off or before the first
--     api.errors()     how many ticks failed
--     api.lastError()  the last failure as text, or nil
--   ns.use(D.NAME) -> { View = api.view, Errors = api.errors }
--
--   view = {
--     pack        true; false when there is no pack for this class, and then
--                 the view holds only pack, trace = {} and why = { pack = false }:
--                 nothing was read and the chooser was not called
--     snapshot    ns.Snapshot of the read
--     suggestion  what ns.Choose picked, or nil. suggestion.passed (below)
--                 is added when it is not empty
--     trace       ns.Choose's trace
--     lockdown    client.combatLockdown() as it answered (nil: not known)
--     keys        ns.cast.Apply(plan, applied, lockdown)
--     attrs       ns.cast.Attributes(suggestion, plan, applied, lockdown)
--     unread      the pack's spells that could not be read (sorted)
--     notRead     the reads the pack names in options.reads (formKnown,
--                 buffs, targetDebuffs, pet) that came back not known, in the
--                 pack's order; {} when every one was read (section 187)
--     missing     the pack's spells with no id (sorted)
--     passed      the spells the chooser's steps passed by only because
--                 nobody read their cooldown (sorted, each once): the trace
--                 rows' own passed lists put together. A spell no step came
--                 to is not in it
--     why         the plain reasons, see below
--     stale       true on a view kept from an earlier tick because this
--                 tick's read failed; absent on a fresh view
--   }
--   why = { dead, inCombat, lockdown    as read (nil: not known),
--           refused, reason             from keys, when the keys are refused,
--           step, result, note, spell   the last row of the trace }
--
-- The module is declared off: char setting D.SETTING. While off nothing is
-- read and no view is held. Switched on, each tick publishes its view on
-- the bus as D.EVENT; switched off, one D.EVENT with no view, then nothing.
-- A tick whose read fails keeps the last good view (a copy marked stale),
-- counts the error and never counts against the module.
--
-- Not tested in game: every client read used here is a first guess.

local D = ns.RotationDriver or {}
ns.RotationDriver = D

D.NAME = "rotationDriver"
D.EVENT = "rotation.suggested"
D.SETTING = "rotation.enabled"
-- Section 230 (BF-3): suggest Well Fed food. The key Flow's import writes
-- (Import/FromFlow.lua, rotation.recoverBuffFood).
D.FOOD = "rotation.recoverBuffFood"
-- The role you chose (Rotation/Role.lua declares the row).
D.ROLE = "spec.role"
D.EVERY = 0.2

local RR = ns.RotationReader

-- Is an enemy targeted? Yes or no only from what the target read gave.
local function hostileOf(client)
    if type(client.target) ~= "function" then return nil end
    local target = client.target()
    if type(target) ~= "table" then return nil end
    if target.exists == false or target.hostile == false or target.dead == true then return false end
    if target.exists == true and target.hostile == true and target.dead == false then return true end
    return nil
end

-- What is queued or toggled on, by spell name: only answers read as yes
-- or no are kept; nil when nothing could be read (section 183).
local function currentOf(client, ids)
    if type(client.currentSpell) ~= "function" or type(ids) ~= "table" then return nil end
    local out, any = {}, false
    for name, id in pairs(ids) do
        local asked, on = pcall(client.currentSpell, id)
        if asked and type(on) == "boolean" then
            out[name] = on
            any = true
        end
    end
    return any and out or nil
end

-- Conjured food and water (lead section 197): for each row of the pack's
-- options.conjure ({ spell, items = { item name, ... } }), how many of its
-- items are in the bags, added up. A row none of whose items could be
-- counted is left out; nil when nothing could be counted (not read).
local function conjuredOf(client, pack)
    local options = type(pack) == "table" and pack.options or nil
    local rows = type(options) == "table" and options.conjure or nil
    if type(rows) ~= "table" or type(client.itemCount) ~= "function" then return nil end
    local out, any = {}, false
    for _, row in ipairs(rows) do
        local total = nil
        if type(row) == "table" and type(row.spell) == "string" and type(row.items) == "table" then
            for _, item in ipairs(row.items) do
                local asked, n = pcall(client.itemCount, item)
                if asked and type(n) == "number" then total = (total or 0) + n end
            end
        end
        if total then
            out[row.spell] = total
            any = true
        end
    end
    return any and out or nil
end

-- The pack's spell rows, each with its range when the client can tell.
local function spellRows(client, pack, ids)
    local rows = RR.SpellRows(pack, ids, client.spell, client.spellCooldown).rows
    if type(client.inRange) ~= "function" then return rows end
    for name, row in pairs(rows) do
        local asked, near = pcall(client.inRange, ids[name])
        if asked and type(near) == "boolean" then row.inRange = near end
    end
    return rows
end

local ROLES = { dps = true, heal = true, tank = true }
local function roleIn(pack, role)
    if type(role) ~= "string" or not ROLES[role] then return nil end
    if type(pack) ~= "table" or type(pack.roles) ~= "table" or type(pack.roles[role]) ~= "table" then return nil end
    return role
end

-- Section 226 (CF-30): the best Well Fed food in your bags for your role
-- (Rotation/BuffFood.lua), { name, item, score }; {} when the bags were read
-- and hold none; nil when the bags, or the facts or tooltip of a food in
-- them, could not be read. Food is consumable class 0, subclass 5; Well Fed
-- food is food whose tooltip says well fed.
-- Section 235 item 4: scored with pack.weights[role].values (the fixed role
-- tables only when the pack has none for the role). A food for a profession
-- (BuffFood.Activity) is never a fight food. pole: client.fishingPole().
-- With a pole (true) only a Fishing food is picked, and no fight food; with
-- no pole or not known, never a Fishing food.
local function weightsOf(pack, role)
    local w = type(pack) == "table" and type(pack.weights) == "table" and pack.weights[role] or nil
    if type(w) == "table" and type(w.values) == "table" then return w.values end
    return nil
end

local function buffFoodOf(client, pack, role, pole)
    local BF = ns.BuffFood
    if type(BF) ~= "table" or type(client.bagItems) ~= "function" or type(client.itemInfo) ~= "function"
        or type(client.itemLines) ~= "function" then return nil end
    local ok, stacks = pcall(client.bagItems)
    if not ok or type(stacks) ~= "table" then return nil end
    local mana, as = BF.UsesMana(pack), roleIn(pack, role) or "dps"
    local values = weightsOf(pack, as)
    local foods, fishing, seen, unread = {}, {}, {}, false
    for _, st in ipairs(stacks) do
        local id = type(st) == "table" and ns.Items.Id(st.item) or nil
        if id and not seen[id] and (st.count == nil or (type(st.count) == "number" and st.count > 0)) then
            seen[id] = true
            local okI, info = pcall(client.itemInfo, id)
            if not okI or type(info) ~= "table" then
                unread = true
            elseif info.classID == BF.CLASS and info.subclassID == BF.SUBCLASS then
                local okL, lines = pcall(client.itemLines, id)
                if not okL or type(lines) ~= "table" then
                    unread = true
                elseif BF.IsBuffFood(lines) and type(info.name) == "string" and info.name ~= "" then
                    local act = BF.Activity(lines)
                    if next(act) ~= nil then
                        local n = act.Fishing
                        if pole == true and type(n) == "number" then
                            fishing[#fishing + 1] = { id = id, name = info.name, score = n }
                        end
                    elseif pole ~= true then
                        local gain = BF.Gain(lines)
                        local score
                        if values then score = BF.Score(gain, values) else score = BF.ScoreByRole(gain, as, mana) end
                        foods[#foods + 1] = { id = id, name = info.name, score = score }
                    end
                end
            end
        end
    end
    -- The second answer: true when some item could not be read, so the
    -- answer may change when it arrives (section 236).
    local best = BF.Best(pole == true and fishing or foods)
    if best then return { name = best.name, item = best.id, score = best.score }, unread end
    if unread then return nil, true end
    return {}, false
end

-- Section 229 (F-1): the food read, kept between bag changes and skipped in
-- a fight. food: the module's table { kept, value, pack, role }; nil reads
-- each time.
-- Section 235 item 4: a fishing pole in your main hand: true, false, nil
-- when the client has no such read or does not say.
local function poleOf(client)
    if type(client.fishingPole) ~= "function" then return nil end
    local ok, v = pcall(client.fishingPole)
    if ok and type(v) == "boolean" then return v end
    return nil
end

local function buffFoodKept(client, pack, role, food)
    if type(food) ~= "table" then return (buffFoodOf(client, pack, role, poleOf(client))) end
    if food.on == false then return nil end
    -- The pole changes with no bag change: a kept pick is for one pole answer.
    local pole = poleOf(client)
    local fresh = food.kept == true and food.pack == pack and food.role == role and food.pole == pole
    if fresh then return food.value end
    if client.inCombat() ~= false then return nil end
    local got, partial = buffFoodOf(client, pack, role, pole)
    if got ~= nil and not partial then
        food.kept, food.value, food.pack, food.role, food.pole = true, got, pack, role, pole
    else
        food.kept, food.value = false, nil
    end
    return got
end

function D.Read(client, pack, ids, role, extra)
    local food = type(extra) == "table" and extra.food or nil
    local chosen = type(extra) == "table" and extra.chosen or nil
    -- Lead section 187: the form is asked of the client once for a read,
    -- and both fields (form, formKnown) come from that one answer.
    -- The answer is kept only for the other field of the pair, and used
    -- once: a field asked again asks the client again.
    local kept
    local function form(field)
        if kept ~= nil and kept.field ~= field then
            local name, known = kept.name, kept.known
            kept = nil
            return name, known
        end
        local name, known = client.formName()
        kept = { field = field, name = name, known = known }
        return name, known
    end
    return function(field)
        if field == "role" then return roleIn(pack, role) end
        if field == "dead" then return client.dead() end
        if field == "inCombat" then return client.inCombat() end
        if field == "stealthed" then
            if type(client.stealthed) ~= "function" then return nil end
            return client.stealthed()
        end
        if field == "hostile" then return hostileOf(client) end
        if field == "spells" then return spellRows(client, pack, ids) end
        if field == "buffs" then
            if type(client.playerBuffs) ~= "function" then return nil end
            return client.playerBuffs()
        end
        if field == "targetDebuffs" then
            if type(client.targetDebuffs) ~= "function" then return nil end
            return client.targetDebuffs()
        end
        if field == "form" then
            if type(client.formName) ~= "function" then return nil end
            local name = form("form")
            return type(name) == "string" and name or nil
        end
        if field == "formKnown" then
            if type(client.formName) ~= "function" then return nil end
            local name, known = form("formKnown")
            if known ~= true then return nil end
            if name == nil or type(name) == "string" then return true end
            return nil
        end
        if field == "current" then return currentOf(client, ids) end
        if field == "pet" then
            if type(client.pet) ~= "function" then return nil end
            return client.pet()
        end
        if field == "conjured" then return conjuredOf(client, pack) end
        if field == "chosen" then return type(chosen) == "table" and chosen or nil end
        if field == "ownBuffs" then
            if type(client.ownBuffs) ~= "function" then return nil end
            return client.ownBuffs()
        end
        if field == "buffFood" then return buffFoodKept(client, pack, role, food) end
        -- Section 230: no "and ... or nil" here; false must stay false.
        if field == "foodOn" then
            if type(food) ~= "table" or type(food.on) ~= "boolean" then return nil end
            return food.on
        end
        -- Section 230 (BF-2) and GT-2: one read of each for both the food and the gather guards.
        if field == "mounted" or field == "onTaxi" or field == "fishingPole" then
            if type(client[field]) ~= "function" then return nil end
            local ok, v = pcall(client[field])
            if ok and type(v) == "boolean" then return v end
            return nil
        end
        -- GT-1: is any tracking on (Rotation/Gather.lua).
        if field == "trackingAny" then
            if type(ns.Gather) ~= "table" then return nil end
            return ns.Gather.Read(client, field)
        end
        -- P-GATHER: the gathering tracking reads (Rotation/Gather.lua).
        if field == "tracking" or field == "trackKnown" or field == "professions" or field == "gatherOn" then
            -- Lead: no "and ... or nil" here; a false answer (the setting off) must stay false.
            if type(ns.Gather) ~= "table" then return nil end
            return ns.Gather.Read(client, field)
        end
        return nil
    end
end

-- The spells the steps passed by for a cooldown nobody read: the trace
-- rows' passed lists as one (sorted, each once).
local function passedIn(trace)
    local seen, out = {}, {}
    for _, row in ipairs(trace) do
        for _, name in ipairs(row.passed or {}) do
            if not seen[name] then
                seen[name] = true
                out[#out + 1] = name
            end
        end
    end
    table.sort(out)
    return out
end

function D.Why(snapshot, trace, keys, lockdown)
    local why = {}
    if type(snapshot) == "table" then
        why.dead, why.inCombat = snapshot.dead, snapshot.inCombat
    end
    why.lockdown = lockdown
    if type(keys) == "table" and keys.ok ~= true then
        why.refused, why.reason = keys.refused, keys.reason
    end
    local n = type(trace) == "table" and #trace or 0
    -- Section 226 (CF-30): food is the step after the rotation. Skipped, its
    -- row is not the rotation's reason; the row before it is.
    -- Lead (merge of P-FOOD and P-GATHER): the same holds for "track".
    while n > 1 and type(trace[n]) == "table" and (trace[n].step == "food" or trace[n].step == "track")
        and trace[n].result ~= "pick" do
        n = n - 1
    end
    local last = n > 0 and trace[n] or nil
    -- Lead section 187: with nothing picked, the reason shown is the last
    -- step that was stopped by a read nobody gave ("not known ..."), not
    -- the step after it. A list that had rules ready but could not read
    -- their range was followed by "nothing out of range", and that was
    -- what the player was told.
    if type(last) == "table" and last.result ~= "pick" then
        for i = n, 1, -1 do
            local row = trace[i]
            if type(row) == "table" and type(row.note) == "string" and row.note:find("not known", 1, true) then
                last = row
                break
            end
        end
    end
    if type(last) == "table" then
        why.step, why.result, why.note, why.spell = last.step, last.result, last.note, last.spell
    end
    return why
end

function D.Step(client, pack, prefs, bias, applied, role, extra)
    if type(pack) ~= "table" then
        return { pack = false, trace = {}, why = { pack = false } }
    end
    local ids, missing = RR.SpellIds(pack, client.spellId)
    local snapshot = ns.Snapshot(D.Read(client, pack, ids, role, extra))
    local suggestion, trace = ns.Choose(snapshot, pack, prefs, bias)
    local passed = passedIn(trace)
    if suggestion and #passed > 0 then suggestion.passed = passed end

    local lockdown = client.combatLockdown()
    local plan = ns.KeyPlan(pack, prefs)
    local keys = ns.cast.Apply(plan, applied, lockdown)
    local attrs = ns.cast.Attributes(suggestion, plan, applied, lockdown, nil)

    -- Not read: no id, or no row came back for it.
    local notRead = {}
    for _, name in ipairs(RR.SpellNames(pack)) do
        if type(snapshot.spells) ~= "table" or snapshot.spells[name] == nil then notRead[#notRead + 1] = name end
    end
    table.sort(notRead)

    -- The reads the pack leans on that came back not known (section 187).
    local readsMissing = {}
    local options = type(pack.options) == "table" and pack.options or {}
    for _, field in ipairs(type(options.reads) == "table" and options.reads or {}) do
        if snapshot[field] == nil then readsMissing[#readsMissing + 1] = field end
    end

    return {
        pack = true,
        snapshot = snapshot,
        suggestion = suggestion,
        trace = trace,
        lockdown = lockdown,
        keys = keys,
        attrs = attrs,
        unread = notRead,
        notRead = readsMissing,
        missing = missing,
        passed = passed,
        why = D.Why(snapshot, trace, keys, lockdown),
    }
end

-- One tick's work: the class's pack, then a step.
local function work(client, packs, role, extra)
    local class = type(client.class) == "function" and client.class() or nil
    local pack = type(class) == "string" and type(packs) == "table" and packs[class] or nil
    return D.Step(client, pack, nil, nil, nil, role, extra)
end

-- CF-32: what the ownCasts module keeps (Rotation/OwnCasts.lua), asked
-- each tick; nil when the kernel has no such module, it is off, or it
-- keeps nothing. Resolved when called, so file order does not matter.
local function chosenOf(k)
    if type(k) ~= "table" or type(k.use) ~= "function" then return nil end
    local ok, own = pcall(k.use, "ownCasts")
    if not ok or type(own) ~= "table" or type(own.Chosen) ~= "function" then return nil end
    local asked, got = pcall(own.Chosen)
    if asked and type(got) == "table" then return got end
    return nil
end

function D.Declare(k, packs)
    local api = {}
    local view, errors, lastError = nil, 0, nil
    -- Section 229 (F-1): the Well Fed food read, kept until the bags change.
    local food = {}
    function api.view() return view end
    function api.errors() return errors end
    function api.lastError() return lastError end

    local function tick(ctx)
        if ctx.settings:get(D.SETTING) ~= true then
            if view ~= nil then
                view = nil
                ctx.bus:emit(D.EVENT, nil)
            end
            return
        end
        food.on = ctx.settings:get(D.FOOD) ~= false
        local ok, got = pcall(work, ctx.client, packs or ns.Packs, ctx.settings:get(D.ROLE), { food = food, chosen = chosenOf(k) })
        if ok then
            view = got
        else
            errors, lastError = errors + 1, tostring(got)
            if view == nil then return end
            if view.stale ~= true then
                local kept = {}
                for key, value in pairs(view) do kept[key] = value end
                kept.stale = true
                view = kept
            end
        end
        ctx.bus:emit(D.EVENT, view)
    end

    k:Module({
        name = D.NAME,
        needs = { "client", "store", "bus" },
        settings = { {
            key = D.SETTING, scope = "char", type = "bool", default = false,
            label = "Suggest the next spell",
            help = "Works out which spell to press next. It presses nothing for you.",
            group = "Rotation",
        }, {
            key = D.FOOD, scope = "account", type = "bool", default = true,
            label = "Suggest Well Fed food",
            help = "Out of a fight, with no Well Fed on you, suggests the best Well Fed food in your bags. It eats nothing for you.",
            group = "Rotation",
        } },
        provides = { View = api.view, Errors = api.errors },
        ticks = { { every = D.EVERY, run = tick } },
        start = function(c)
            food = {}
            -- The bags changed: the food kept may be gone, or a better one there.
            c.bus:on(D.NAME, "BAG_UPDATE_DELAYED", function() food = {} end)
        end,
        stop = function() food = {} end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login, off
-- until the setting is switched on.
ns.rotationDriver = D.Declare(ns)
