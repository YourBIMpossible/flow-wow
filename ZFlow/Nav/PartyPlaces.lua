local _, ns = ...
-- Party places (FLOW-PARITY A2-29, lead section 831.2; Flow
-- Modules/Nav/Places.lua:213-259 shares learned NPC spots by a file the
-- player sends in, not in game). Here party members who run the add-on
-- tell each other where the services they met in game are: vendors,
-- repair, bankers, flight masters, innkeepers, auctioneers. The data half
-- only: the route and the arrow do not read the shared places yet.
--
-- WHAT IS SENT: only the player's own sightings, char
-- "learned.places.services" (Nav/ServiceSeen.lua), each place with a name,
-- a map and a spot, and only the roles in P.ROLES. Never account
-- "learned.places.npcs" (it also holds places brought in from the older
-- add-on, which cannot be told apart from the player's own), never quest
-- spots, never anything read from another add-on (Questie included):
-- this file reads no other table. Mailboxes have no name and are not sent.
--
-- WHERE RECEIVED PLACES GO: account "learned.places.party", keyed
-- "id:<npc id>" or "name:<name>", each { id, name, map, x, y, kinds,
-- from = the member's name, source = "party", seen }. Nothing received is
-- ever written to the player's own learned places.
--
-- SAFETY: add-on messages only, on the "PARTY" channel only, only in a
-- party (not alone, not in a raid), only while party.placesShare is on
-- (off by default; it gates sending and keeping alike). A send at most
-- every EVERY seconds, only places new or changed since the last send
-- (everything again once when a member joins), at most MAX_PARTS messages
-- a send and PER_MINUTE places a minute. Received: own echo, anyone not
-- in the party, another channel and anything P.Decode refuses are
-- dropped; at most TAKE_PER_MINUTE places a minute from one member, at
-- most MAX_SHARED kept. Nothing received is run, printed or used as a
-- format.
--
-- Messages (prefix P.Prefix(): ns.id.commPrefix and "L"), each at most
-- MAX_BYTES:
--   "<ver>|L|<seq>|<count>|<place>~<place>..."
--   place = "<npc id or 0>,<map>,<x>,<y>,<role>+<role>,<name>"
-- x and y in ten-thousandths of the map (0..10000). Every place stands
-- alone, so each message is kept as it comes.
--
-- Pure:
--   P.Mine(services) -> rows { id, map, x, y, roles = { [role] = true }, name }
--   P.Encode(rows, ver) -> messages, number of rows that fit
--   P.Decode(message, ver) -> { seq, count, places = rows } or nil, why
-- Module "partyPlaces" provides Shared().
-- Not tested in game: the two-client game test is an owner item.
ns.Nav = ns.Nav or {}
local N = ns.Nav
local P = {}
N.PartyPlaces = P

P.NAME = "partyPlaces"
P.SETTING = "party.placesShare"
P.SOURCE = "learned.places.services"
P.STORE = "learned.places.party"
P.CHANNEL = "PARTY"
P.KIND = "L"
P.MAX_BYTES = 255
P.MAX_PARTS = 3
P.MAX_PER_MESSAGE = 12
P.PER_MINUTE = 24
P.TAKE_PER_MINUTE = 48
P.MAX_SHARED = 400
P.MAX_NAME = 48
P.MAX_ID_DIGITS = 7
P.MAX_MAP_DIGITS = 6
P.SCALE = 10000
P.EVERY = 30         -- seconds between sends, at least

-- The roles ServiceSeen saves that may be shared, in the order sent.
P.ROLES = { "auction", "banker", "flight", "innkeeper", "repair", "vendor" }
local ALLOWED = {}
for _, r in ipairs(P.ROLES) do ALLOWED[r] = true end

function P.Prefix()
    return tostring(ns.id.commPrefix) .. P.KIND
end

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- A place's name fit to send and keep: no control characters, none of the
-- message's own separators, no "%", capped.
local function goodName(s)
    if type(s) ~= "string" or s == "" or #s > P.MAX_NAME then return false end
    if s:find("[%c|~,%%]") then return false end
    return true
end

local function npcId(guid)
    if type(guid) ~= "string" then return 0 end
    local id = tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
    if not id or id < 1 or #tostring(id) > P.MAX_ID_DIGITS then return 0 end
    return id
end

local function onMap(v)
    return finite(v) and v >= 0 and v <= 1
end

function P.Mine(services)
    local rows = {}
    if type(services) ~= "table" then return rows end
    for _, e in pairs(services) do
        if type(e) == "table" and type(e.kinds) == "table" and goodName(e.name)
            and finite(e.map) and e.map >= 0 and e.map == math.floor(e.map)
            and #tostring(e.map) <= P.MAX_MAP_DIGITS and onMap(e.x) and onMap(e.y) then
            local roles, any = {}, false
            for _, r in ipairs(P.ROLES) do
                if e.kinds[r] == true then
                    roles[r] = true
                    any = true
                end
            end
            if any then
                rows[#rows + 1] = { id = npcId(e.guid), map = e.map, x = e.x, y = e.y, roles = roles, name = e.name }
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return rows
end

-- One place as text; also the key the change check compares.
function P.Text(row)
    local roles = {}
    for _, r in ipairs(P.ROLES) do
        if row.roles[r] then roles[#roles + 1] = r end
    end
    return ("%d,%d,%d,%d,%s,%s"):format(row.id, row.map, math.floor(row.x * P.SCALE + 0.5),
        math.floor(row.y * P.SCALE + 0.5), table.concat(roles, "+"), row.name)
end

function P.Encode(rows, ver)
    if type(rows) ~= "table" then rows = {} end
    local room = P.MAX_BYTES - #(("%s|%s|%d|%d|"):format(tostring(ver), P.KIND, P.MAX_PARTS, P.MAX_PARTS))
    local bodies, cur, inCur, used = {}, "", 0, 0
    for _, row in ipairs(rows) do
        local text = P.Text(row)
        if #text <= room then
            if cur ~= "" and (#cur + 1 + #text > room or inCur >= P.MAX_PER_MESSAGE) then
                if #bodies + 1 >= P.MAX_PARTS then break end
                bodies[#bodies + 1] = cur
                cur, inCur = "", 0
            end
            if cur == "" then cur = text else cur = cur .. "~" .. text end
            inCur = inCur + 1
        end
        used = used + 1
    end
    if cur ~= "" then bodies[#bodies + 1] = cur end
    local msgs = {}
    for i, b in ipairs(bodies) do
        msgs[i] = ("%s|%s|%d|%d|%s"):format(tostring(ver), P.KIND, i, #bodies, b)
    end
    return msgs, used
end

local function number(s, digits)
    if type(s) ~= "string" or s == "" or #s > digits or s:find("^%d+$") == nil then return nil end
    return tonumber(s)
end

local function decodePlace(text)
    local idT, mapT, xT, yT, rolesT, name = text:match("^([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*)$")
    if not idT then return nil end
    local id, map = number(idT, P.MAX_ID_DIGITS), number(mapT, P.MAX_MAP_DIGITS)
    local x, y = number(xT, 5), number(yT, 5)
    if not id or not map or not x or not y then return nil end
    if x > P.SCALE or y > P.SCALE then return nil end
    if not goodName(name) or rolesT == "" then return nil end
    local roles = {}
    for r in (rolesT .. "+"):gmatch("([^+]*)%+") do
        if not ALLOWED[r] or roles[r] then return nil end
        roles[r] = true
    end
    return { id = id, map = map, x = x / P.SCALE, y = y / P.SCALE, roles = roles, name = name }
end

function P.Decode(msg, ver)
    if type(msg) ~= "string" then return nil, "not text" end
    if #msg > P.MAX_BYTES then return nil, "too long" end
    local v, kind, seqText, countText, body = msg:match("^(%d+)|(%a)|(%d+)|(%d+)|(.*)$")
    if not v then return nil, "malformed" end
    if tonumber(v) ~= tonumber(ver) then return nil, "unknown version" end
    if kind ~= P.KIND then return nil, "unknown kind" end
    local seq, count = number(seqText, 2), number(countText, 2)
    if not seq or not count or seq < 1 or count < 1 or count > P.MAX_PARTS or seq > count then
        return nil, "bad part number"
    end
    if body == "" then return nil, "no places" end
    local places = {}
    for text in (body .. "~"):gmatch("([^~]*)~") do
        if #places >= P.MAX_PER_MESSAGE then return nil, "too many places" end
        local row = decodePlace(text)
        if not row then return nil, "bad place" end
        places[#places + 1] = row
    end
    return { seq = seq, count = count, places = places }
end

-- A sender's name without its realm, capped; nil when not a name.
local function plain(name)
    if type(name) ~= "string" then return nil end
    local base = name:match("^([^%-]+)")
    if not base or #base > P.MAX_NAME or base:find("[%c|%%]") then return nil end
    return base
end

local function keyOf(row)
    if row.id > 0 then return "id:" .. tostring(row.id) end
    return "name:" .. row.name
end

function P.Declare(k)
    local ctx
    local cancels = {}
    local sentText = {}         -- key -> the text last sent for it
    local members = nil
    local sentAt, minuteAt, minuteSent = nil, nil, 0
    local taken = {}            -- member -> { at, n }
    local prefixOk = false

    local function client()
        if not ctx then return nil end
        return ctx.client
    end

    local function on()
        if not ctx then return false end
        local s = ctx.settings
        if type(s) ~= "table" or type(s.get) ~= "function" then return false end
        local ok, v = pcall(s.get, s, P.SETTING)
        return ok and v == true
    end

    local function me()
        local c = client()
        if type(c) ~= "table" or type(c.playerName) ~= "function" then return nil end
        local ok, name = pcall(c.playerName)
        if not ok then return nil end
        return plain(name)
    end

    -- The other party members' names, or nil when not in a party (alone, a
    -- raid, or not known).
    local function party()
        local c = client()
        if type(c) ~= "table" then return nil end
        local okG, grouped = pcall(c.grouped)
        if not okG or grouped ~= true then return nil end
        local okP, rows = pcall(c.party)
        if not okP or type(rows) ~= "table" then return nil end
        local names = {}
        for _, r in ipairs(rows) do
            if type(r) == "table" and type(r.unit) == "string" and r.unit:find("^raid") then return nil end
            if type(r) == "table" then
                local n = plain(r.name)
                if n then names[n] = true end
            end
        end
        return names
    end

    local function now()
        local c = client()
        local ok, t = pcall(c.now)
        if ok and finite(t) then return t end
        return nil
    end

    local function saved(scope, path)
        local st = ctx and ctx.store
        if type(st) ~= "table" or type(st.get) ~= "function" then return nil end
        local ok, v = pcall(st.get, st, scope, path)
        if ok and type(v) == "table" then return v end
        return nil
    end

    local function check()
        if not on() or not prefixOk then return end
        local t = now()
        if not t then return end
        if sentAt and t - sentAt < P.EVERY then return end
        if not party() then return end
        if not minuteAt or t - minuteAt >= 60 then minuteAt, minuteSent = t, 0 end
        local room = P.PER_MINUTE - minuteSent
        if room < 1 then return end
        local fresh = {}
        for _, row in ipairs(P.Mine(saved("char", P.SOURCE))) do
            if #fresh >= room then break end
            if sentText[keyOf(row)] ~= P.Text(row) then fresh[#fresh + 1] = row end
        end
        sentAt = t
        if not fresh[1] then return end
        local msgs, used = P.Encode(fresh, ns.id.commVersion)
        local c = client()
        for _, m in ipairs(msgs) do
            local ok, done = pcall(c.addonSend, P.Prefix(), m, P.CHANNEL)
            if not ok or done ~= true then return end
        end
        for i = 1, used do
            sentText[keyOf(fresh[i])] = P.Text(fresh[i])
        end
        minuteSent = minuteSent + used
    end

    local function roster()
        local names = party()
        if not names then
            members, sentText, taken = nil, {}, {}
            return
        end
        for who in pairs(taken) do
            if not names[who] then taken[who] = nil end
        end
        -- Someone new: everything again at the next send.
        for who in pairs(names) do
            if not members or not members[who] then sentText = {} end
        end
        members = names
    end

    local function keep(who, rows)
        local st = ctx and ctx.store
        if type(st) ~= "table" or type(st.set) ~= "function" then return end
        local t = now() or 0
        local tk = taken[who]
        if not tk or t - tk.at >= 60 then
            tk = { at = t, n = 0 }
            taken[who] = tk
        end
        local old = saved("account", P.STORE) or {}
        local out, n = {}, 0
        for key, e in pairs(old) do
            out[key] = e
            n = n + 1
        end
        local c = client()
        local seen
        if type(c) == "table" and type(c.clock) == "function" then
            local ok, v = pcall(c.clock)
            if ok and finite(v) then seen = v end
        end
        local changed = false
        for _, row in ipairs(rows) do
            if tk.n >= P.TAKE_PER_MINUTE then break end
            local key = keyOf(row)
            if out[key] ~= nil or n < P.MAX_SHARED then
                if out[key] == nil then n = n + 1 end
                local kinds = {}
                for r in pairs(row.roles) do kinds[r] = true end
                local e = { name = row.name, map = row.map, x = row.x, y = row.y, kinds = kinds,
                    from = who, source = "party", seen = seen }
                if row.id > 0 then e.id = row.id end
                out[key] = e
                tk.n = tk.n + 1
                changed = true
            end
        end
        if changed then pcall(st.set, st, "account", P.STORE, out) end
    end

    local function receive(prefix, text, channel, sender)
        if prefix ~= P.Prefix() or channel ~= P.CHANNEL then return end
        if not on() then return end
        local who = plain(sender)
        if not who or who == me() then return end
        local names = party()
        if not names or not names[who] then return end
        local d = P.Decode(text, ns.id.commVersion)
        if not d then return end
        keep(who, d.places)
    end

    local api = {}
    function api.Shared()
        local out = {}
        for key, e in pairs(saved("account", P.STORE) or {}) do out[key] = e end
        return out
    end

    k:Setting({ key = P.SETTING, scope = "account", type = "bool", default = false,
        label = "Share learned places with your party", group = "travel.route",
        help = "While you are in a party, tells party members who use this add-on where the vendors,"
            .. " bankers, flight masters, innkeepers and auctioneers you met are, and keeps the ones"
            .. " they send apart from your own. Add-on data only, never to chat, a raid or anyone else.",
        synonyms = { "party", "share", "places", "vendor", "group" } })

    k:Module({
        name = P.NAME,
        needs = { "client", "settings", "store" },
        provides = { Shared = api.Shared },
        start = function(c)
            ctx = c
            local cl = c.client
            if type(cl.addonPrefix) == "function" then
                local ok, v = pcall(cl.addonPrefix, P.Prefix())
                prefixOk = ok and v == true
            end
            cancels[#cancels + 1] = cl.listen("GROUP_ROSTER_UPDATE", function() pcall(roster) end)
            cancels[#cancels + 1] = cl.listen("CHAT_MSG_ADDON", function(...) pcall(receive, ...) end)
            cancels[#cancels + 1] = cl.onFrame(function() pcall(check) end)
        end,
        stop = function()
            for _, cancel in ipairs(cancels) do
                if type(cancel) == "function" then pcall(cancel) end
            end
            cancels = {}
            ctx = nil
            sentText, members, taken = {}, nil, {}
            sentAt, minuteAt, minuteSent = nil, nil, 0
        end,
    })
    return api
end

P.Declare(ns)
