-- Fights: turns combat-log events into fight records (G29). Pure: no client
-- read, no frame, nothing saved. The caller hands over each event's values
-- and says when combat starts and ends.
--
-- A fight record:
--   open       true while the fight is going
--   started    when it started, in the caller's seconds (nil: not known)
--   ended      when it ended (nil while open, or not known)
--   dealt      damage you or your pet did
--   taken      damage you took
--   healed     healing you did
--   received   healing you got (a heal on yourself is in both)
-- Each of the four is { total, hits, unread, over, spells }:
--   total, hits  the amounts that were numbers, and how many there were
--   unread       events whose amount was not a number. They are not hits
--                and add nothing: an amount that could not be read is not 0.
--   over         overhealing, where the event gave it (healing only)
--   spells       { [name] = { total, hits } }
--
-- Only an event whose source is you or your pet, or whose target is you,
-- is counted, and "you" is the id given to setMe, never a name. What other
-- players do to other things is not read at all.
--
-- The places of the values in an event are a FIRST GUESS for this client
-- (the layout CombatLogGetCurrentEventInfo has had since the 8.0 client):
-- (warcraft.wiki.gg does not list that read for this client, and lists
-- the combat-log event as closed to addons since 12.0.0: needs game test)
--   1 time, 2 subevent, 4 source id, 5 source name, 8 target id, 9 target
--   name; then for SWING_DAMAGE 12 amount; for ENVIRONMENTAL_DAMAGE 12 what
--   it was, 13 amount; for every other ..._DAMAGE and ..._HEAL 12 spell id,
--   13 spell name, 15 amount, and for a heal 16 overhealing.
-- If the client's layout differs, amounts stop being numbers and show up as
-- "not read"; nothing is made up to fill them.
--
--   Fights.New(keep) -> rec        keep: how many fights are kept (KEEP)
--   rec:setMe(player, pet)         your id and your pet's; nil: not known
--   rec:knowsMe() -> bool
--   rec:enter(at)                  combat started; no second fight is
--                                  opened while one is open
--   rec:leave(at)                  combat ended
--   rec:event(at, ...) -> bool     one event's values; true when counted
--   rec:outside() -> n             events about you that came while no
--                                  fight was open (they are in no fight)
--   rec:list() -> fights           newest first, as fresh copies
--   Fights.Lines(fights, now, n) -> lines
--     the text for the list, or for fight n with its spells
--
-- Fight types (G28). A fight record also has:
--   group   true: a party or raid member was in an event of the fight;
--           false: events said who was who and none was; nil: no event said
--   elite   true: a target of the fight was read as elite, rare elite or
--           boss; false: targets were read and none was; nil: none was read
--   rec:sawRank(rank)      the rank word of the target you have now, as the
--                          client gave it. Counts only while a fight is open.
--   Fights.Kind(f) -> "group" | "elite" | "solo" | "unknown"
--     group wins over elite. "solo" is said only when both were read; a
--     fight whose group or target rank was not read is "unknown".
-- Who is in your group is taken from the flags of an event, a FIRST GUESS
-- for this client: place 6 (source) and 10 (target), with 2 the party bit
-- and 4 the raid bit. The rank words are the ones UnitClassification has
-- given: elite, rareelite, worldboss; normal, rare, trivial, minus. Any
-- other word is not read as normal.
--
-- Death report (G30). The last RECENT hits on you are remembered, in a
-- fight or not, each with when it came, what it was, its amount and the
-- name of who did it (place 5).
--   rec:died(at) -> death  what hit you in the WINDOW seconds before at.
--                          With no time: the last UNTIMED hits, not timed.
--   rec:death() -> death   the last one again, nil before any
--   Fights.DeathLines(death) -> lines
-- A death: { at, timed, window, hits = { { before, name, amount, from } } },
-- oldest first. amount nil: not read. from nil: no source name was given.
local _, ns = ...

local Fights = {}
ns.Fights = Fights

Fights.KEEP = 10
Fights.MELEE = "melee"
Fights.PET = "pet: "
Fights.UNKNOWN = "unknown"
Fights.NONE = "no fights recorded yet this session."
Fights.WINDOW = 10
Fights.RECENT = 20
Fights.UNTIMED = 5
Fights.NO_DEATH = "no death recorded this session."

local ELITE = { elite = true, rareelite = true, worldboss = true }
local PLAIN = { normal = true, rare = true, trivial = true, minus = true }

-- nil: the flags were not a number. Else whether the party or raid bit is
-- set (2 and 4), by arithmetic: no bit library is assumed.
local function grouped(flags)
    if type(flags) ~= "number" or flags ~= flags or flags < 0 then return nil end
    flags = math.floor(flags)
    return math.floor(flags / 2) % 2 == 1 or math.floor(flags / 4) % 2 == 1
end

local function named(value)
    return (type(value) == "string" and value ~= "") and value or nil
end

local function copyDeath(d)
    if not d then return nil end
    local out = { at = d.at, timed = d.timed, window = d.window, hits = {} }
    for i = 1, #d.hits do
        local h = d.hits[i]
        out.hits[i] = { before = h.before, name = h.name, amount = h.amount, from = h.from }
    end
    return out
end

local SIDES = { "dealt", "taken", "healed", "received" }

local function bucket()
    return { total = 0, hits = 0, unread = 0, over = 0, spells = {} }
end

local function add(b, name, amount, over)
    if type(amount) ~= "number" or amount ~= amount then
        b.unread = b.unread + 1
        return
    end
    b.total = b.total + amount
    b.hits = b.hits + 1
    local s = b.spells[name]
    if not s then
        s = { total = 0, hits = 0 }
        b.spells[name] = s
    end
    s.total = s.total + amount
    s.hits = s.hits + 1
    if type(over) == "number" and over == over and over > 0 then b.over = b.over + over end
end

local function spellName(id, name)
    if type(name) == "string" and name ~= "" then return name end
    if type(id) == "number" then return "spell " .. id end
    return Fights.UNKNOWN
end

-- What one event is: "damage" or "heal", the spell's name, the amount and
-- the overhealing. nil for anything else.
local function parse(sub, a12, a13, a15, a16)
    if type(sub) ~= "string" then return nil end
    if sub == "SWING_DAMAGE" then return "damage", Fights.MELEE, a12 end
    if sub == "ENVIRONMENTAL_DAMAGE" then
        return "damage", (type(a12) == "string" and a12 ~= "") and a12:lower() or Fights.UNKNOWN, a13
    end
    if sub:sub(-7) == "_DAMAGE" then return "damage", spellName(a12, a13), a15 end
    if sub:sub(-5) == "_HEAL" then return "heal", spellName(a12, a13), a15, a16 end
    return nil
end

local function newFight(at)
    local f = { open = true, started = at }
    for i = 1, #SIDES do f[SIDES[i]] = bucket() end
    return f
end

local function copyFight(f)
    local out = { open = f.open, started = f.started, ended = f.ended, group = f.group, elite = f.elite }
    for i = 1, #SIDES do
        local b = f[SIDES[i]]
        local spells = {}
        for name, s in pairs(b.spells) do spells[name] = { total = s.total, hits = s.hits } end
        out[SIDES[i]] = { total = b.total, hits = b.hits, unread = b.unread, over = b.over, spells = spells }
    end
    return out
end

local function id(value)
    return (type(value) == "string" and value ~= "") and value or nil
end

function Fights.New(keep)
    if type(keep) ~= "number" or keep < 1 then keep = Fights.KEEP end
    keep = math.floor(keep)
    local rec = {}
    local kept = {}      -- ended fights, oldest first
    local open           -- the fight that is going
    local me, pet
    local outside = 0
    local recent = {}    -- the last hits on me, oldest first
    local lastDeath

    -- The open fight counts toward the fixed number.
    local function trim()
        local room = open and keep - 1 or keep
        while #kept > room do table.remove(kept, 1) end
    end

    function rec:setMe(player, itsPet)
        me, pet = id(player), id(itsPet)
    end

    function rec:knowsMe() return me ~= nil end

    function rec:enter(at)
        if open then return end
        open = newFight(type(at) == "number" and at or nil)
        trim()
    end

    function rec:leave(at)
        if not open then return end
        open.open = false
        open.ended = type(at) == "number" and at or nil
        kept[#kept + 1] = open
        open = nil
        trim()
    end

    -- The rank word of the target you have now. Elite sticks for the fight.
    function rec:sawRank(rank)
        if not open or type(rank) ~= "string" then return end
        if ELITE[rank] then
            open.elite = true
        elseif PLAIN[rank] and open.elite == nil then
            open.elite = false
        end
    end

    -- The values of one event, in the order the client gives them. `at` is
    -- the caller's time for it.
    function rec:event(at, _, sub, _, src, srcName, srcFlags, _, dst, _, dstFlags, _, a12, a13, _, a15, a16)
        if open and open.group ~= true then
            local a, b = grouped(srcFlags), grouped(dstFlags)
            if a or b then
                open.group = true
            elseif (a ~= nil or b ~= nil) and open.group == nil then
                open.group = false
            end
        end
        local kind, name, amount, over = parse(sub, a12, a13, a15, a16)
        if not kind then return false end
        local mine = me ~= nil and src == me
        local pets = pet ~= nil and src == pet
        local onMe = me ~= nil and dst == me
        if kind == "damage" and onMe then
            recent[#recent + 1] = {
                at = (type(at) == "number" and at == at) and at or nil,
                name = name,
                amount = (type(amount) == "number" and amount == amount) and amount or nil,
                from = named(srcName),
            }
            while #recent > Fights.RECENT do table.remove(recent, 1) end
        end
        local counts
        if kind == "damage" then
            counts = mine or pets or onMe
        else
            counts = mine or onMe
        end
        if not counts then return false end
        if not open then
            outside = outside + 1
            return false
        end
        if kind == "damage" then
            if mine then add(open.dealt, name, amount) end
            if pets then add(open.dealt, Fights.PET .. name, amount) end
            if onMe then add(open.taken, name, amount) end
        else
            if mine then add(open.healed, name, amount, over) end
            if onMe then add(open.received, name, amount, over) end
        end
        return true
    end

    function rec:outside() return outside end

    -- You died at `at`. Without a time nothing can be said about how long
    -- before a hit came, so the last few are given and marked as not timed.
    function rec:died(at)
        local timed = type(at) == "number" and at == at
        local d = { at = timed and at or nil, timed = timed, window = Fights.WINDOW, hits = {} }
        if timed then
            for i = 1, #recent do
                local h = recent[i]
                if h.at and h.at <= at and at - h.at <= Fights.WINDOW then
                    d.hits[#d.hits + 1] = { before = at - h.at, name = h.name, amount = h.amount, from = h.from }
                end
            end
        else
            for i = math.max(1, #recent - Fights.UNTIMED + 1), #recent do
                local h = recent[i]
                d.hits[#d.hits + 1] = { name = h.name, amount = h.amount, from = h.from }
            end
        end
        lastDeath = d
        return copyDeath(d)
    end

    function rec:death() return copyDeath(lastDeath) end

    function rec:list()
        local out = {}
        if open then out[1] = copyFight(open) end
        for i = #kept, 1, -1 do out[#out + 1] = copyFight(kept[i]) end
        return out
    end

    return rec
end

local function whole(x)
    return tostring(math.floor(x + 0.5))
end

-- The type of a fight, from what was read. Anything not read: "unknown".
function Fights.Kind(f)
    if type(f) ~= "table" then return Fights.UNKNOWN end
    if f.group == true then return "group" end
    if f.group ~= false then return Fights.UNKNOWN end
    if f.elite == true then return "elite" end
    if f.elite == false then return "solo" end
    return Fights.UNKNOWN
end

local function hits(n)
    return n .. (n == 1 and " hit" or " hits")
end

local function length(f, now)
    local known = type(f.started) == "number"
    if f.open then
        if known and type(now) == "number" and now >= f.started then
            return "still going, " .. whole(now - f.started) .. "s so far"
        end
        return "still going, length not known"
    end
    if known and type(f.ended) == "number" and f.ended >= f.started then
        return whole(f.ended - f.started) .. "s"
    end
    return "length not known"
end

local function row(i, f, now)
    local function damage(label, b)
        if b.hits == 0 then return label .. " 0" end
        return label .. " " .. whole(b.total) .. " in " .. hits(b.hits)
    end
    local kind = Fights.Kind(f)
    if kind == Fights.UNKNOWN then kind = "type unknown" end
    local text = i .. ". " .. length(f, now) .. " (" .. kind .. "): "
        .. damage("dealt", f.dealt) .. ", " .. damage("taken", f.taken)
        .. ", healing done " .. whole(f.healed.total) .. ", healing received " .. whole(f.received.total)
    local unread = 0
    for s = 1, #SIDES do unread = unread + f[SIDES[s]].unread end
    if unread > 0 then
        text = text .. ", " .. unread .. (unread == 1 and " amount" or " amounts") .. " not read"
    end
    return text
end

local LABELS = { dealt = "dealt", taken = "taken", healed = "healing done", received = "healing received" }

local function spellLine(side, b)
    local names = {}
    for name in pairs(b.spells) do names[#names + 1] = name end
    if #names == 0 then return nil end
    table.sort(names, function(x, y)
        if b.spells[x].total ~= b.spells[y].total then return b.spells[x].total > b.spells[y].total end
        return x < y
    end)
    local parts = {}
    for i = 1, #names do
        local s = b.spells[names[i]]
        parts[i] = names[i] .. " " .. whole(s.total) .. " (" .. hits(s.hits) .. ")"
    end
    local text = LABELS[side] .. ": " .. table.concat(parts, ", ")
    if b.over > 0 then text = text .. ", " .. whole(b.over) .. " of it overhealing" end
    return text
end

-- The text of the fights. fights is what rec:list() gave; now is the
-- caller's time, for the length of a fight that is still going; n (optional)
-- picks one fight and lists its spells.
function Fights.Lines(fights, now, n)
    if type(fights) ~= "table" or #fights == 0 then return { Fights.NONE } end
    if n ~= nil then
        local f = fights[n]
        if not f then
            return { "there is no fight " .. tostring(n) .. "; " .. #fights
                .. (#fights == 1 and " is" or " are") .. " kept." }
        end
        local lines = { row(n, f, now) }
        for i = 1, #SIDES do
            lines[#lines + 1] = spellLine(SIDES[i], f[SIDES[i]])
        end
        return lines
    end
    local lines = { "fights (" .. #fights .. " kept, newest first):" }
    for i = 1, #fights do lines[#lines + 1] = row(i, fights[i], now) end
    return lines
end

-- The text of a death, as rec:died or rec:death gave it.
function Fights.DeathLines(death)
    if type(death) ~= "table" or type(death.hits) ~= "table" then return { Fights.NO_DEATH } end
    local n = #death.hits
    local span = whole(type(death.window) == "number" and death.window or Fights.WINDOW) .. "s"
    if n == 0 then
        if death.timed then return { "you died. No damage to you was read in the last " .. span .. "." } end
        return { "you died. No damage to you was read before it." }
    end
    local total, read, unread = 0, 0, 0
    for i = 1, n do
        local amount = death.hits[i].amount
        if type(amount) == "number" then
            total, read = total + amount, read + 1
        else
            unread = unread + 1
        end
    end
    local lines = {}
    if death.timed then
        local head = "you died. Damage taken in the last " .. span .. ": " .. whole(total) .. " in " .. hits(read)
        if unread > 0 then
            head = head .. ", " .. unread .. (unread == 1 and " amount" or " amounts") .. " not read"
        end
        lines[1] = head .. ". Oldest first:"
    else
        lines[1] = "you died. The last " .. hits(n) .. " on you (times not known), oldest first:"
    end
    for i = 1, n do
        local h = death.hits[i]
        local line = tostring(h.name) .. " "
            .. (type(h.amount) == "number" and whole(h.amount) or "(amount not read)")
        if type(h.from) == "string" and h.from ~= "" then line = line .. " from " .. h.from end
        if death.timed and type(h.before) == "number" then
            line = string.format("%.1fs before: ", h.before) .. line
        end
        lines[#lines + 1] = line
    end
    return lines
end
