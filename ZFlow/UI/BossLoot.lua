local _, ns = ...

-- The boss loot panel (N55; lead DISPATCH sections 237 item 5 and 238 item
-- 4; RESEARCH-N55). While you fight a boss, a small see-through panel at
-- the left edge lists the drops this account has itself seen from that
-- boss: the pieces that are an upgrade for the role you chose on top at
-- full strength, the rest of what your class can use below and faded.
--
-- LOOK ONLY. It reads and draws text. It never rolls, passes, picks, loots,
-- whispers, targets or casts, and the panel has nothing to click.
--
-- NO LOOT TABLE. Nothing here is copied from anywhere: the panel shows only
-- what this account's own loot rolls, loot lines and loot windows showed
-- after a kill of that boss. A boss never killed gets one plain line that
-- says so. The game's own journal is not read here (the capture decides
-- whether it can be; that read is Plexy's).
--
-- Which boss (in this order, RESEARCH-N55 (d)):
--   1. ENCOUNTER_START / ENCOUNTER_END: the encounter's id and name.
--   2. in a fight, client.bossUnit(): the game's first boss frame.
--   3. in a fight, a living target client.targetRank() calls "worldboss".
--   4. in a fight in an instance (client.instance()), a living "elite"
--      target whose creature id is already in the boss book: one that
--      routes 1 to 3 knew as a boss before.
-- Shown from then until the encounter ends or the fight does; hidden after.
--
-- What is learned (account wide, "learned.bossLoot"; Drops' corpse rule,
-- widened to the account and to rolls and loot lines, for bosses only):
--   { ["e:<encounter id>" or "n:<creature id>"] = {
--       name  = the encounter's or the creature's name (game data),
--       kills = how many kills this account saw,
--       npcs  = { [creature id] = true }   seen as that encounter's boss unit,
--       items = { [item key] = { times = on how many of those kills } } } }
--   A kill: ENCOUNTER_END with success; else the boss you fought is your
--   dead target; else its corpse's loot window. After a kill, items are
--   taken from: every roll the game offers (client.onLootRoll), every loot
--   line (CHAT_MSG_LOOT read by client.lootLine: the item only, the looter
--   is never read into anything), until the next fight starts or
--   BossLoot.WINDOW seconds pass; and the boss's own corpse loot window
--   (client.lootWindow with source.how "corpse", as Items/Drops.lua).
--   An item counts once a kill. Nothing saved holds a character, realm,
--   guild or account name. With "loot.record" off nothing is learned.
--   The character's own "learned.drops" (Items/Drops.lua) for the same
--   creature is read too; the larger count of the two is shown.
--
-- The order (BossLoot.Rows), by the setting spec.role and the class pack's
-- weights[role], through Gear/Verdict.lua (so "not known" is never an
-- upgrade):
--   left out   an item the game or the class table says you cannot use;
--              what is not gear; armour of another type than your class's
--              own (cloth, leather or mail for a plate wearer; cloaks are
--              everyone's) unless some role's weights score it above what
--              you wear
--   top, full  an upgrade for your role, biggest gain first
--   below, faded, in this order:
--              an upgrade for another of your class's roles (its name and
--              gain); no upgrade for any; no verdict; not known whether
--              you can use it; not read yet (the item is not loaded: the
--              line waits and is asked again, never guessed)
--   No role chosen: an upgrade for any role is on top, and a line says how
--   to choose one.
--
--   rows, waiting = BossLoot.Rows(found, facts, who)      pure
--   lines         = BossLoot.Lines(found, rows, who, id)  pure
--   found         = BossLoot.Lookup(book, drops, boss)    pure
--   api           = BossLoot.Declare(k[, packs])
--     api.view()    what is shown now: { key, via, lines, rows }, or nil
--     api.errors()  how many times something here failed (kept as problems)
--   ns.use(BossLoot.NAME) -> { View = api.view, Errors = api.errors }
--
-- Setting: "loot.bossPanel" (bool, account, on by default, topic Party and Dungeons).
-- The panel can be dragged; where it was left is kept (account,
-- "layout.bossLoot"). It starts at the left edge below the middle, clear of
-- the middle of the screen.
--
-- Not tested in game. First guesses, each in the capture: the events
-- ENCOUNTER_START, ENCOUNTER_END, GET_ITEM_INFO_RECEIVED and
-- PLAYER_TARGET_CHANGED (a name the client refuses is listed by diag), and
-- the reads in Core/Client.lua (bossUnit, instance, lootLine, targetRank,
-- guid, lootWindow, gear, itemInfo).

local B = {}
ns.BossLoot = B

B.NAME = "bossLoot"
B.SETTING = "loot.bossPanel"
-- When the panel appears, in one line, for its settings row (lead section 294).
B.APPEARS = "The panel appears only while you fight a boss, and hides when the fight ends."
B.ROLE = "spec.role"            -- Rotation/Role.lua's setting
B.RECORD = "loot.record"        -- Items/Drops.lua's setting: off, nothing is learned
B.PATH = "learned.bossLoot"     -- account
B.DROPS = "learned.drops"       -- char: Items/Drops.lua's book, read only
B.LAYOUT = "layout.bossLoot"    -- account: { point = { anchor, relative anchor, x, y } }
-- Seconds after a kill that rolls and loot lines are its. A FIRST GUESS,
-- not a measured number. What would settle it: how long after ENCOUNTER_END
-- the rolls and loot lines of that kill really come. No capture field holds
-- that today (a snapshot's `at` is the snapshot's own time only); one is
-- needed, e.g. account diag.bossLoot.gaps = the seconds from each kill to
-- each roll and loot line that followed it (numbers only, no names).
B.WINDOW = 180
-- The client events this module listens to. They are not globals, so they
-- are not in Diag.NAMES; one the client refuses is saved by the capture in
-- each snapshot's kernel.eventsNotRegistered (Core/Diag.lua).
B.EVENTS = { "ENCOUNTER_START", "ENCOUNTER_END", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
             "PLAYER_TARGET_CHANGED", "GET_ITEM_INFO_RECEIVED", "LOOT_OPENED", "CHAT_MSG_LOOT" }
B.TICK = 1                      -- seconds between looks while the add-on runs
B.REFRESH = 5                   -- seconds a worked-out list is kept while nothing changed
B.MAX_SHOWN = 10
B.WIDTH, B.HEIGHT = 320, 190
B.DEFAULT_POINT = { "LEFT", "LEFT", 20, -120 }
B.FULL, B.FADED, B.END = "|cffffffff", "|cff808080", "|r"
B.CLOAK = "INVTYPE_CLOAK"
B.EMPTY = "no loot seen from this boss yet. What drops is remembered from now on."
B.NO_NAME = "This boss"

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function isCount(n)
    return finite(n) and n >= 0
end

local function words(v)
    return type(v) == "string" and v ~= ""
end

-- ------------------------------------------------------------------ keys

-- The creature id in a creature's GUID, or nil. As Core/Client.lua's loot
-- read: only the type (first part) and the id (sixth of seven) are read.
function B.NpcId(guid)
    if type(guid) ~= "string" then return nil end
    local kind, id = guid:match("^(%a+)%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)%-[^-]*$")
    if kind ~= "Creature" then return nil end
    id = tonumber(id)
    if not id or id <= 0 then return nil end
    return id
end

-- An item string for an item key (Items/Key.lua), for the item reads.
function B.Link(key)
    if type(key) == "number" then return "item:" .. key end
    if type(key) == "string" then
        local id, suffix = key:match("^(%d+):(%-?%d+)$")
        if id then return "item:" .. id .. ":0:0:0:0:0:" .. suffix .. ":0" end
    end
    return nil
end

-- ------------------------------------------------------------------ the book

local function fillName(entry, name)
    if not words(entry.name) and words(name) then entry.name = name end
end

-- One more kill of the boss `key`. A name fills a gap only. npc: the
-- creature seen as an encounter's boss unit, kept beside the encounter.
function B.Kill(book, key, name, npc)
    if type(book) ~= "table" or not words(key) then return nil end
    local entry = book[key]
    if type(entry) ~= "table" then
        entry = { kills = 0, items = {} }
        book[key] = entry
    end
    if type(entry.items) ~= "table" then entry.items = {} end
    entry.kills = (isCount(entry.kills) and entry.kills or 0) + 1
    fillName(entry, name)
    if finite(npc) and key:sub(1, 2) == "e:" then
        if type(entry.npcs) ~= "table" then entry.npcs = {} end
        entry.npcs[npc] = true
    end
    return entry
end

-- One item seen on the kill whose items are in `seen`: counted once a kill.
function B.Teach(entry, seen, item)
    if type(entry) ~= "table" or type(seen) ~= "table" then return false end
    local key = ns.Items.Key(item)
    if key == nil or seen[key] then return false end
    seen[key] = true
    if type(entry.items) ~= "table" then entry.items = {} end
    local e = entry.items[key]
    if type(e) ~= "table" or not isCount(e.times) then
        e = { times = 0 }
        entry.items[key] = e
    end
    e.times = e.times + 1
    return true
end

-- The book's key for a creature id: its own entry, else the encounter that
-- saw it as its boss unit (the lowest key when there are several), else nil.
function B.KeyOf(book, npc)
    if type(book) ~= "table" or not finite(npc) then return nil end
    local own = "n:" .. npc
    if type(book[own]) == "table" then return own end
    local found
    for key, entry in pairs(book) do
        if type(key) == "string" and key:sub(1, 2) == "e:" and type(entry) == "table"
            and type(entry.npcs) == "table" and entry.npcs[npc] == true then
            if found == nil or key < found then found = key end
        end
    end
    return found
end

-- Everything seen from a boss: { name, kills, items = { [item key] = times }, n }.
-- boss: { key, npc, name }. Each kill is saved under one key, so the
-- entries that are this boss (its key, its creature's own entry, the
-- encounters that saw the creature, and their creatures' entries) add up.
-- drops: the character's Items/Drops.lua book; for the same creatures the
-- larger of the two counts stands (the same kill may be in both).
function B.Lookup(book, drops, boss)
    local out = { kills = 0, items = {}, n = 0 }
    if type(boss) ~= "table" then return out end
    book = type(book) == "table" and book or {}
    if words(boss.name) then out.name = boss.name end
    local taken, list, npcs = {}, {}, {}
    local function take(key)
        local entry = book[key]
        if type(entry) == "table" and not taken[key] then
            taken[key] = true
            list[#list + 1] = entry
        end
    end
    if words(boss.key) then take(boss.key) end
    if finite(boss.npc) then
        npcs[boss.npc] = true
        take("n:" .. boss.npc)
        for key, entry in pairs(book) do
            if type(key) == "string" and key:sub(1, 2) == "e:" and type(entry) == "table"
                and type(entry.npcs) == "table" and entry.npcs[boss.npc] == true then
                take(key)
            end
        end
    end
    local direct = #list
    for i = 1, direct do
        if type(list[i].npcs) == "table" then
            for id in pairs(list[i].npcs) do
                if finite(id) then
                    npcs[id] = true
                    take("n:" .. id)
                end
            end
        end
    end
    for i = 1, #list do
        local entry = list[i]
        if out.name == nil and words(entry.name) then out.name = entry.name end
        if isCount(entry.kills) then out.kills = out.kills + entry.kills end
        if type(entry.items) == "table" then
            for item, e in pairs(entry.items) do
                local key = ns.Items.Key(item)
                if key ~= nil and type(e) == "table" and isCount(e.times) and e.times > 0 then
                    out.items[key] = (out.items[key] or 0) + e.times
                end
            end
        end
    end
    if type(drops) == "table" then
        for id in pairs(npcs) do
            local d = drops[id]
            if type(d) == "table" then
                if out.name == nil and words(d.name) then out.name = d.name end
                if isCount(d.looted) and d.looted > out.kills then out.kills = d.looted end
                if type(d.items) == "table" then
                    for item, e in pairs(d.items) do
                        local key = ns.Items.Key(item)
                        if key ~= nil and type(e) == "table" and isCount(e.times) and e.times > 0
                            and e.times > (out.items[key] or 0) then
                            out.items[key] = e.times
                        end
                    end
                end
            end
        end
    end
    for _ in pairs(out.items) do out.n = out.n + 1 end
    return out
end

-- ------------------------------------------------------------------ the order

-- The roles a pack has weights for, sorted.
local function rolesOf(pack)
    local out = {}
    if type(pack) == "table" and type(pack.weights) == "table" then
        for role, w in pairs(pack.weights) do
            if type(role) == "string" and type(w) == "table" then out[#out + 1] = role end
        end
    end
    table.sort(out)
    return out
end

-- The heaviest armour the class wears at this level, as the item subclass
-- number (1 cloth, 2 leather, 3 mail, 4 plate), by the pack's own table;
-- nil when that is not known.
function B.OwnArmour(pack, level)
    local kinds = type(pack) == "table" and type(pack.proficiency) == "table" and pack.proficiency[4] or nil
    if type(kinds) ~= "table" then return nil end
    local own
    for sub = 1, 4 do
        local allowed = kinds[sub]
        if allowed == true or (finite(allowed) and finite(level) and level >= allowed) then own = sub end
    end
    return own
end

local RANK = { top = 1, other = 2, plain = 3, none = 4, unsure = 5, wait = 6 }

-- found: BossLoot.Lookup's answer. facts: { [item key] = { name, loaded,
-- gear } }: the item's name, whether the client has it loaded, and what
-- client.gear answered for it (nil: not read). who: { pack, role, level }.
-- rows: { { key, times, name, state, role, delta, score } ... } in shown
-- order; state is "top", "other", "plain", "none", "unsure" or "wait".
-- waiting: how many rows wait for the item to be read.
function B.Rows(found, facts, who)
    who = type(who) == "table" and who or {}
    local pack = type(who.pack) == "table" and who.pack or nil
    local roles = rolesOf(pack)
    local chosen
    for i = 1, #roles do
        if roles[i] == who.role then chosen = roles[i] end
    end
    local own = B.OwnArmour(pack, who.level)
    local rows, waiting = {}, 0
    local items = type(found) == "table" and type(found.items) == "table" and found.items or {}

    for key, times in pairs(items) do
        local f = type(facts) == "table" and facts[key] or nil
        local row = { key = key, times = times, name = type(f) == "table" and words(f.name) and f.name or nil }
        if type(f) ~= "table" or f.loaded ~= true or type(f.gear) ~= "table" then
            row.state = "wait"
            waiting = waiting + 1
            rows[#rows + 1] = row
        else
            local gear = f.gear
            local isGear, use = true, nil
            local best, bestOther, plain
            for i = 1, math.max(#roles, 1) do
                local role = roles[i]
                local lines, detail = ns.GearVerdict.Lines(gear, { pack = pack, role = role, level = who.level })
                if lines == nil or type(detail) ~= "table" then
                    isGear = false
                    break
                end
                use = detail.use
                local res = type(detail.result) == "table" and detail.result or {}
                if role ~= nil then
                    local mine = chosen == nil or role == chosen
                    if res.verdict == "upgrade" and finite(res.delta) and res.delta >= ns.GearTooltip.SAME then
                        if mine then
                            if not best or res.delta > best.delta then best = { role = role, delta = res.delta } end
                        elseif not bestOther or res.delta > bestOther.delta then
                            bestOther = { role = role, delta = res.delta }
                        end
                    elseif mine and (res.verdict == "upgrade" or res.verdict == "same" or res.verdict == "worse")
                        and finite(res.score) then
                        if plain == nil or res.score > plain then plain = res.score end
                    end
                end
            end
            -- Not `x and v or nil`: that turns "cannot use" into "not known".
            local can
            if type(use) == "table" then can = use.can end
            if isGear and can ~= false then
                if can ~= true then
                    row.state = "unsure"
                elseif best then
                    row.state, row.role, row.delta = "top", best.role, best.delta
                elseif bestOther then
                    row.state, row.role, row.delta = "other", bestOther.role, bestOther.delta
                elseif plain ~= nil then
                    row.state, row.score = "plain", plain
                else
                    row.state = "none"
                end
                local otherType = own ~= nil and gear.classID == 4 and finite(gear.subclassID)
                    and gear.subclassID >= 1 and gear.subclassID <= 4 and gear.subclassID ~= own
                    and gear.kind ~= B.CLOAK
                if not otherType or row.state == "top" or row.state == "other" then
                    rows[#rows + 1] = row
                end
            end
        end
    end

    table.sort(rows, function(a, b)
        local ra, rb = RANK[a.state], RANK[b.state]
        if ra ~= rb then return ra < rb end
        local na, nb = a.delta or a.score or 0, b.delta or b.score or 0
        if na ~= nb then return na > nb end
        local la, lb = a.name or "", b.name or ""
        if la ~= lb then return la < lb end
        return tostring(a.key) < tostring(b.key)
    end)
    return rows, waiting
end

-- ------------------------------------------------------------------ the text

-- A gain with its sign, whole or to one decimal place: "+6", "+2.3".
local function signed(n)
    local size = math.floor(math.abs(n) * 10 + 0.5) / 10
    local text = size == math.floor(size) and string.format("%d", size) or string.format("%.1f", size)
    return (n < 0 and "-" or "+") .. text
end

-- The pack's own name for a role ("Protection"), else the role's word.
local function roleName(pack, role)
    local row = type(pack) == "table" and type(pack.roles) == "table" and pack.roles[role] or nil
    if type(row) == "table" and words(row.name) then return row.name end
    return tostring(role)
end

local function seenText(times, kills)
    times = isCount(times) and times or 0
    if isCount(kills) and kills > 0 and times <= kills then
        return "seen " .. times .. " of " .. kills .. (kills == 1 and " kill" or " kills")
    end
    return "seen " .. times .. (times == 1 and " time" or " times")
end

function B.Lines(found, rows, who, id)
    found = type(found) == "table" and found or {}
    rows = type(rows) == "table" and rows or {}
    who = type(who) == "table" and who or {}
    local pack = type(who.pack) == "table" and who.pack or nil
    local boss = words(found.name) and found.name or B.NO_NAME
    local n = isCount(found.n) and found.n or 0
    if n == 0 then return { boss .. ": " .. B.EMPTY } end
    if #rows == 0 then
        return { boss .. ": nothing for your class among the " .. n .. (n == 1 and " item" or " items")
            .. " seen from this boss." }
    end
    local lines = { boss .. ": loot you have seen drop" }
    local roles = rolesOf(pack)
    local chosen = false
    for i = 1, #roles do
        if roles[i] == who.role then chosen = true end
    end
    if not chosen and #roles > 1 and type(id) == "table" and words(id.slash) then
        lines[#lines + 1] = "Say " .. id.slash .. " role to put your own role's pieces first."
    end
    for i = 1, math.min(#rows, B.MAX_SHOWN) do
        local row = rows[i]
        local label = row.name or ("Item " .. tostring(ns.Items.Id(row.key) or row.key))
        local seen = seenText(row.times, found.kills)
        local text, tint
        if row.state == "top" then
            tint = B.FULL
            text = label .. ": upgrade " .. signed(row.delta) .. " for " .. roleName(pack, row.role) .. ", " .. seen
        elseif row.state == "other" then
            text = label .. ": " .. signed(row.delta) .. " for " .. roleName(pack, row.role) .. ", " .. seen
        elseif row.state == "plain" then
            text = label .. ": no upgrade, " .. seen
        elseif row.state == "none" then
            text = label .. ": no verdict, " .. seen
        elseif row.state == "unsure" then
            text = label .. ": not known whether you can use it, " .. seen
        else
            text = label .. ": not read yet, " .. seen
        end
        lines[#lines + 1] = (tint or B.FADED) .. text .. B.END
    end
    if #rows > B.MAX_SHOWN then lines[#lines + 1] = "and " .. (#rows - B.MAX_SHOWN) .. " more" end
    return lines
end

-- A saved place when it is one, else the default: { anchor, relative
-- anchor, x, y }, a copy.
function B.Point(saved)
    local p = type(saved) == "table" and saved.point or nil
    if type(p) == "table" and words(p[1]) and words(p[2]) and finite(p[3]) and finite(p[4]) then
        return { p[1], p[2], p[3], p[4] }
    end
    local d = B.DEFAULT_POINT
    return { d[1], d[2], d[3], d[4] }
end

-- ------------------------------------------------------------------ the module

function B.Declare(k, packs)
    local api = {}
    local ctx, panel
    local cancels = {}
    local enc              -- { id, name, npc, guid } while an encounter is on
    local last             -- the boss last recognised with no encounter event: { key, npc, guid, name }
    local latest = {}      -- [key] = { guid, seen = { [item key] = true } }: this session's last kill
    local counted = {}     -- [creature GUID] = true: its kill is in the book already
    local win              -- { key, at }: the kill that rolls and loot lines now belong to
    local shown            -- what the panel shows: { key, npc, via, lines, rows, waiting }
    local dirty, computedAt = true, nil
    local errors, said = 0, {}

    function api.errors() return errors end
    function api.view()
        if not shown then return nil end
        return { key = shown.key, via = shown.via, lines = shown.lines, rows = shown.rows }
    end

    local function fail(where, err)
        errors = errors + 1
        local text = tostring(err)
        if not said[text] then
            said[text] = true
            k.problems:add(B.NAME, where, text)
        end
    end

    -- One read of the client: nil when it has no such read or the read
    -- raised. Looked up each time, never kept.
    local function read(name, ...)
        local client = ctx and ctx.client
        if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
        local ok, a, b = pcall(client[name], ...)
        if not ok then return nil end
        return a, b
    end

    local function now()
        local t = read("uptime")
        return finite(t) and t or nil
    end

    local function bookNow()
        local book = ctx.store:get("account", B.PATH)
        return type(book) == "table" and book or nil
    end

    local function learning()
        return ctx.settings:get(B.RECORD) ~= false
    end

    local function kill(key, name, npc, guid)
        if not learning() then return end
        local book = ctx.store:table("account", B.PATH)
        if type(book) ~= "table" then return end
        if not B.Kill(book, key, name, npc) then return end
        latest[key] = { guid = guid, seen = {} }
        if words(guid) then counted[guid] = true end
        win = { key = key, at = now() }
        dirty = true
    end

    local function teach(key, item)
        local kept, book = latest[key], bookNow()
        local entry = book and book[key] or nil
        if not kept or type(entry) ~= "table" then return end
        if B.Teach(entry, kept.seen, item) then dirty = true end
    end

    -- The kill a roll or a loot line belongs to now, or nil.
    local function open()
        if not win then return nil end
        local t = now()
        if t ~= nil and win.at ~= nil and t - win.at > B.WINDOW then
            win = nil
            return nil
        end
        return win
    end

    -- The boss you are fighting, or nil: { key, npc, guid, name, via }.
    local function recognise()
        if enc then
            local unit = read("bossUnit")
            local npc = type(unit) == "table" and unit.exists == true and B.NpcId(unit.guid) or nil
            if npc then enc.npc, enc.guid = npc, unit.guid end
            return { key = "e:" .. enc.id, npc = enc.npc, guid = enc.guid, name = enc.name, via = "encounter" }
        end
        if read("inCombat") ~= true then return nil end
        local unit = read("bossUnit")
        if type(unit) == "table" and unit.exists == true then
            local npc = B.NpcId(unit.guid)
            if npc then
                return { key = "n:" .. npc, npc = npc, guid = unit.guid,
                         name = words(unit.name) and unit.name or nil, via = "boss unit" }
            end
        end
        local target = read("target")
        if type(target) ~= "table" or target.exists ~= true or target.dead == true or target.hostile == false then
            return nil
        end
        local guid = read("guid", "target")
        local npc = B.NpcId(guid)
        if not npc then return nil end
        local rank = read("targetRank")
        if rank == "worldboss" then
            return { key = "n:" .. npc, npc = npc, guid = guid, via = "world boss" }
        end
        if rank == "elite" then
            local place = read("instance")
            if type(place) == "table" and place.inside == true then
                local key = B.KeyOf(bookNow(), npc)
                if key then return { key = key, npc = npc, guid = guid, via = "known boss" } end
            end
        end
        return nil
    end

    -- True while the kill that rolls and loot lines belong to is an encounter's.
    local function encounterKill()
        local to = open()
        return to ~= nil and to.key:sub(1, 2) == "e:"
    end

    -- A boss known without an encounter event has no end event: it is
    -- killed when it is your dead target. Counted once for that creature.
    -- It is looked for until BossLoot.WINDOW seconds after it was last seen.
    local function deadBoss()
        if not last or not words(last.guid) then return end
        local t = now()
        if t ~= nil and last.at ~= nil and t - last.at > B.WINDOW then
            last = nil
            return
        end
        -- Already in the book; or an encounter just ended with a kill and no
        -- new fight has started, so a dead boss now is that encounter's.
        if counted[last.guid] or encounterKill() then
            last = nil
            return
        end
        local target = read("target")
        if type(target) ~= "table" or target.exists ~= true or target.dead ~= true then return end
        if read("guid", "target") ~= last.guid then return end
        kill(last.key, last.name, last.npc, last.guid)
        last = nil
    end

    local function hide()
        shown = nil
        if panel then panel.show(false) end
    end

    local function build(boss, t)
        local drops = ctx.store:get("char", B.DROPS)
        local found = B.Lookup(bookNow(), drops, boss)
        local class = read("class")
        local all = packs or ns.Packs
        local pack = class ~= nil and type(all) == "table" and all[class] or nil
        local who = { pack = type(pack) == "table" and pack or nil, role = ctx.settings:get(B.ROLE), level = read("level") }
        local facts = {}
        for key in pairs(found.items) do
            local info = read("itemInfo", ns.Items.Id(key))
            local f = { name = type(info) == "table" and words(info.name) and info.name or nil }
            -- The client names an item only once it is loaded; until then
            -- nothing about it is taken as read.
            f.loaded = f.name ~= nil
            local link = B.Link(key)
            if f.loaded and link then
                local gear = read("gear", link)
                if type(gear) == "table" then f.gear = gear end
            end
            facts[key] = f
        end
        local rows, waiting = B.Rows(found, facts, who)
        local lines = B.Lines(found, rows, who, k.id or ns.id)
        panel.setLines(lines)
        panel.show(true)
        shown = { key = boss.key, npc = boss.npc, via = boss.via, lines = lines, rows = rows, waiting = waiting }
        dirty, computedAt = false, t
    end

    local function look()
        if not ctx then return end
        deadBoss()
        local boss = recognise()
        if boss and boss.via ~= "encounter" then
            last = boss
            last.at = now()
        end
        if not panel then return end
        if not boss or ctx.settings:get(B.SETTING) ~= true then
            hide()
            return
        end
        local t = now()
        local fresh = t ~= nil and computedAt ~= nil and t - computedAt < B.REFRESH
        if shown and shown.key == boss.key and shown.npc == boss.npc and not dirty
            and shown.waiting == 0 and fresh then
            return
        end
        build(boss, t)
    end

    -- Nothing here may raise into the client: a failure is counted and kept
    -- as a problem, and the panel shows nothing it could not work out.
    local function evaluate()
        local ok, err = pcall(look)
        if not ok then
            fail("look", err)
            pcall(hide)
        end
    end

    -- fn (when given) first, then a look. same = true: the event changes
    -- who is fought, not what is known of the drops, so a list already
    -- worked out for the same boss stands.
    local function listen(event, fn, same)
        ctx.bus:on(B.NAME, event, function(...)
            if fn then
                local ok, err = pcall(fn, ...)
                if not ok then fail(event, err) end
            end
            if not same then dirty = true end
            evaluate()
        end)
    end

    local function onLoot()
        if not learning() then return end
        local r = read("lootWindow")
        local src = type(r) == "table" and r.source or nil
        -- Items/Drops.lua's rule: only a creature's corpse; a skinning or a
        -- pickpocket window carries the same creature and is no drop.
        if type(src) ~= "table" or src.kind ~= "creature" then return end
        if src.how ~= (ns.Drops and ns.Drops.CORPSE or "corpse") then return end
        if not words(src.guid) or not finite(src.id) or src.id <= 0 or type(r.items) ~= "table" then return end
        -- Only a creature known as a boss: in the book, or the one just fought.
        -- (Not while an encounter's kill is open and the book does not tie
        -- this creature to it: that would count the one kill twice.)
        local key = B.KeyOf(bookNow(), src.id)
        if not key and not encounterKill() and last and last.npc == src.id then key = last.key end
        if not key then return end
        local kept = latest[key]
        if not kept or (kept.guid ~= nil and kept.guid ~= src.guid) then
            kill(key, src.name, src.id, src.guid)
            kept = latest[key]
        end
        if not kept then return end
        kept.guid = src.guid
        if last and last.guid == src.guid then last = nil end
        local book = bookNow()
        if book and type(book[key]) == "table" then fillName(book[key], src.name) end
        for i = 1, #r.items do
            local it = r.items[i]
            if type(it) == "table" then teach(key, it.item) end
        end
    end

    local function watch(key)
        local row = ctx.settings:row(key)
        if type(row) ~= "table" then return end
        local cancel = ctx.store:watch(row.scope, row.path or ("settings." .. key), function()
            dirty = true
            evaluate()
        end)
        if type(cancel) == "function" then cancels[#cancels + 1] = cancel end
    end

    k:Module({
        name = B.NAME,
        needs = { "client", "store", "bus", "settings" },
        settings = { {
            key = B.SETTING, scope = "account", type = "bool", default = true,
            label = "Boss loot panel",
            help = B.APPEARS .. " "
                .. "It lists the drops you have seen from it before, your role's upgrades first. "
                .. "It only shows them: it never rolls or picks for you. "
                .. "What is rolled or looted in the 3 minutes after a kill counts as that boss's; "
                .. "the 3 minutes are a first guess.",
            -- A topic of Settings/Topics.lua (zflow-settings-groups, N56).
            group = "party",
            synonyms = { "boss", "loot", "drops", "dungeon", "upgrade", "panel" },
        } },
        provides = { View = api.view, Errors = api.errors },
        ticks = { { every = B.TICK, when = "always", run = function() evaluate() end } },
        start = function(c)
            ctx = c
            -- What each event does; they are registered from B.EVENTS below,
            -- the one list (MyBuddy PT-1): an event missing from it is not heard.
            local handlers = {}
            local function on(event, fn, same) handlers[event] = { fn = fn, same = same } end
            on("ENCOUNTER_START", function(id, name)
                win = nil
                if finite(id) then enc = { id = id, name = words(name) and name or nil } end
            end)
            on("ENCOUNTER_END", function(id, name, _, _, success)
                local was = enc
                enc = nil
                if success ~= 1 and success ~= true then return end
                if not finite(id) then id = was and was.id or nil end
                if not finite(id) then return end
                local same = was and was.id == id
                kill("e:" .. id, words(name) and name or (same and was.name or nil),
                    same and was.npc or nil, same and was.guid or nil)
            end)
            -- A new fight: what is rolled or looted from here on is not the last kill's.
            on("PLAYER_REGEN_DISABLED", function() win = nil end, true)
            on("PLAYER_REGEN_ENABLED", nil, true)
            on("PLAYER_TARGET_CHANGED", nil, true)
            on("GET_ITEM_INFO_RECEIVED")
            on("LOOT_OPENED", onLoot)
            on("CHAT_MSG_LOOT", function(line)
                if not learning() then return end
                local to = open()
                if not to then return end
                -- The item only: the looter in the line is never read out of it.
                local link = read("lootLine", line)
                if link ~= nil then teach(to.key, link) end
            end)
            for _, event in ipairs(B.EVENTS) do
                local h = handlers[event]
                if h then listen(event, h.fn, h.same) end
            end
            if type(c.client.onLootRoll) == "function" then
                local ok, cancel = pcall(c.client.onLootRoll, function(_, link)
                    -- Reads the item offered. Never rolls, and shows nothing on the roll.
                    local done, err = pcall(function()
                        if not learning() then return end
                        local to = open()
                        if to then teach(to.key, link) end
                    end)
                    if not done then fail("roll", err) end
                end)
                if ok and type(cancel) == "function" then cancels[#cancels + 1] = cancel end
            end
            watch(B.SETTING)
            watch(B.ROLE)
            -- The frame last, after everything that can switch the module off.
            local id = k.id or ns.id
            panel = c.client.panel({ name = id.framePrefix .. "BossLoot", width = B.WIDTH, height = B.HEIGHT })
            if panel then
                panel.show(false)
                panel.place(B.Point(c.store:get("account", B.LAYOUT)))
                if type(panel.onMoved) == "function" then
                    panel.onMoved(function(point)
                        local to = B.Point({ point = point })
                        c.store:set("account", B.LAYOUT, { point = to })
                    end, function(err) fail("moved", err) end)
                end
            end
            evaluate()
        end,
        stop = function()
            for i = 1, #cancels do pcall(cancels[i]) end
            cancels = {}
            if panel then panel.show(false) end
            shown, ctx = nil, nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.bossLoot = B.Declare(ns)
