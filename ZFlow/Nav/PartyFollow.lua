local _, ns = ...
-- Share where you are with the party member who follows you (FLOW-PARITY
-- A1-49, lead section 828.3; Flow Nav/Follow.lua:172-210 sent "W|name"
-- asks and "X|map|x|y" spots through Party.lua's channel). The arrow can
-- point at a party member (Nav/Follow.lua) only while the game gives their
-- position, which it does not on another map or in an instance. Here a
-- member who follows another asks them for their spot, and the one asked
-- sends their own map and spot (the game's read of the player's position,
-- nothing typed in) while they are being followed.
--
-- SAFETY: add-on messages only (never chat text, whispers or a public
-- channel), on the "PARTY" channel only, only in a party (not alone, not a
-- raid), only from and to members of the party, and only while the
-- setting party.followShare is on. It is OFF by default: the player turns
-- it on, on both sides. Your spot is sent at most every EVERY seconds, only
-- when it changed, and only while a member asked for it in the last HOLD
-- seconds. A follower asks at most every ASK_EVERY seconds, only while
-- its arrow wants the spot. Everything received is checked by S.Decode;
-- nothing received is run, printed or used as a format.
--
-- Messages (prefix S.Prefix(): ns.id.commPrefix and "F", so the party route
-- and party progress never see them; version ns.id.commVersion), each at
-- most MAX_BYTES:
--   "<ver>|A|<name>"          I follow <name>: send me your spot
--   "<ver>|S|<map>|<x>|<y>"   my spot (map id, x and y from 0 to 1)
--
-- Pure:
--   S.EncodeAsk(name, ver), S.EncodeSpot(map, x, y, ver) -> message or nil
--   S.Decode(message, ver) -> { kind = "ask", name } or
--                             { kind = "spot", map, x, y } or nil, why
-- Module "partyFollow" provides Want(name) (the follower wants that
-- member's spot; call it again to keep wanting) and Where(name) (the last
-- spot that member sent, { map, x, y }, or nil when none or too old).
-- Not tested in game: the two-client game test is an owner item.
ns.Nav = ns.Nav or {}
local N = ns.Nav
local S = {}
N.PartyFollow = S

S.NAME = "partyFollow"
S.SETTING = "party.followShare"
S.CHANNEL = "PARTY"
S.MAX_BYTES = 64
S.MAX_NAME = 48
S.MAX_MAP_DIGITS = 7
S.MAX_NUMBER = 8      -- characters in x or y
S.EVERY = 5           -- seconds between checks of your own spot
S.HOLD = 30           -- seconds an ask keeps your spot being sent
S.ASK_EVERY = 10      -- seconds between a follower's asks
S.WANT_LIVE = 3       -- seconds a Want lasts without another
S.STALE = 20          -- seconds a received spot is used

function S.Prefix()
    return tostring(ns.id.commPrefix) .. "F"
end

-- A name without its realm, capped; nil when not a usable name.
local function plain(name)
    if type(name) ~= "string" then return nil end
    local base = name:match("^([^%-]+)")
    if not base or #base > S.MAX_NAME or base:find("[%c%%|]") then return nil end
    return base
end

local function unit(v)
    return type(v) == "number" and v == v and v >= 0 and v <= 1
end

local function mapId(v)
    return type(v) == "number" and v >= 1 and v == math.floor(v) and #tostring(v) <= S.MAX_MAP_DIGITS
end

function S.EncodeAsk(name, ver)
    local who = plain(name)
    if not who then return nil end
    return ("%s|A|%s"):format(tostring(ver), who)
end

function S.EncodeSpot(map, x, y, ver)
    if not mapId(map) or not unit(x) or not unit(y) then return nil end
    return ("%s|S|%d|%.4f|%.4f"):format(tostring(ver), map, x, y)
end

local function share(s)
    if type(s) ~= "string" or #s > S.MAX_NUMBER or s:find("^%d+%.?%d*$") == nil then return nil end
    local v = tonumber(s)
    if not unit(v) then return nil end
    return v
end

function S.Decode(msg, ver)
    if type(msg) ~= "string" then return nil, "not text" end
    if #msg > S.MAX_BYTES then return nil, "too long" end
    local v, kind, rest = msg:match("^(%d+)|(%a)|(.*)$")
    if not v then return nil, "malformed" end
    if tonumber(v) ~= tonumber(ver) then return nil, "unknown version" end
    if kind == "A" then
        if rest:find("|", 1, true) then return nil, "bad name" end
        local name = plain(rest)
        if not name or name == "" then return nil, "bad name" end
        return { kind = "ask", name = name }
    end
    if kind ~= "S" then return nil, "unknown kind" end
    local m, xs, ys = rest:match("^(%d+)|([^|]+)|([^|]+)$")
    if not m or #m > S.MAX_MAP_DIGITS then return nil, "bad spot" end
    local map, x, y = tonumber(m), share(xs), share(ys)
    if not mapId(map) or not x or not y then return nil, "bad spot" end
    return { kind = "spot", map = map, x = x, y = y }
end

function S.Declare(k)
    local ctx
    local cancels = {}
    local prefixOk = false
    -- wanted = { name, at }: whom this player follows; askedAt: last ask.
    local wanted, askedAt = nil, nil
    -- followers[name] = when they last asked for this player's spot.
    local followers, spots = {}, {}
    local lastKey, checkedAt = nil, nil

    local function client()
        if not ctx then return nil end
        return ctx.client
    end

    local function on()
        if not ctx then return false end
        local s = ctx.settings
        if type(s) ~= "table" or type(s.get) ~= "function" then return false end
        local ok, v = pcall(s.get, s, S.SETTING)
        return ok and v == true
    end

    local function call(name, ...)
        local c = client()
        if type(c) ~= "table" or type(c[name]) ~= "function" then return nil end
        local ok, v = pcall(c[name], ...)
        if not ok then return nil end
        return v
    end

    local function now()
        local t = call("now")
        if type(t) == "number" then return t end
        return nil
    end

    local function me() return plain(call("playerName")) end

    -- The other members' names, or nil when not in a party (alone, a raid,
    -- or not known).
    local function party()
        if call("grouped") ~= true then return nil end
        local rows = call("party")
        if type(rows) ~= "table" then return nil end
        local names = {}
        for _, r in ipairs(rows) do
            if type(r) == "table" then
                if type(r.unit) == "string" and r.unit:find("^raid") then return nil end
                local n = plain(r.name)
                if n then names[n] = true end
            end
        end
        return names
    end

    local function send(text)
        if not text then return false end
        return call("addonSend", S.Prefix(), text, S.CHANNEL) == true
    end

    local function followed(t)
        for _, at in pairs(followers) do
            if t - at <= S.HOLD then return true end
        end
        return false
    end

    local function check()
        if not on() or not prefixOk then return end
        local t = now()
        if not t then return end
        local names = party()
        if not names then return end
        -- The follower: ask while the arrow wants the spot.
        if wanted and t - wanted.at <= S.WANT_LIVE and names[wanted.name]
            and (askedAt == nil or t - askedAt >= S.ASK_EVERY) then
            askedAt = t
            send(S.EncodeAsk(wanted.name, ns.id.commVersion))
        end
        -- The one followed: send the spot, throttled, when it changed.
        if checkedAt and t - checkedAt < S.EVERY then return end
        if not followed(t) then return end
        checkedAt = t
        local p = call("position")
        if type(p) ~= "table" then return end
        local text = S.EncodeSpot(p.map, p.x, p.y, ns.id.commVersion)
        if not text or text == lastKey then return end
        if send(text) then lastKey = text end
    end

    local function roster()
        local names = party()
        if not names then
            followers, spots, lastKey = {}, {}, nil
            return
        end
        for who in pairs(followers) do
            if not names[who] then followers[who] = nil end
        end
        for who in pairs(spots) do
            if not names[who] then spots[who] = nil end
        end
    end

    local function receive(prefix, text, channel, sender)
        if prefix ~= S.Prefix() or channel ~= S.CHANNEL or not on() then return end
        local who = plain(sender)
        if not who or who == me() then return end
        local names = party()
        if not names or not names[who] then return end
        local d = S.Decode(text, ns.id.commVersion)
        if not d then return end
        local t = now()
        if not t then return end
        if d.kind == "ask" then
            if d.name == me() then
                -- A new follower gets the spot at the next check.
                if not followers[who] then lastKey = nil end
                followers[who] = t
            end
            return
        end
        spots[who] = { map = d.map, x = d.x, y = d.y, at = t }
    end

    local api = {}
    function api.Want(name)
        local who = plain(name)
        local t = now()
        if not who or not t then return end
        if not wanted or wanted.name ~= who then askedAt = nil end
        wanted = { name = who, at = t }
    end
    function api.Where(name)
        local who = plain(name)
        if not who or not on() then return nil end
        local e = spots[who]
        local t = now()
        if not e or not t or t - e.at > S.STALE then return nil end
        return { map = e.map, x = e.x, y = e.y }
    end

    k:Setting({ key = S.SETTING, scope = "account", type = "bool", default = false,
        label = "Share your spot with a party member who follows you", group = "travel.route",
        help = "While you are in a party, a party member who uses this add-on and points the arrow at you"
            .. " gets your map and spot as add-on data, at most every few seconds and only when you moved,"
            .. " so the arrow finds you on another map. Turn it on to ask for theirs too."
            .. " Never sent to chat, a raid or anyone else.",
        synonyms = { "party", "share", "follow", "position", "group", "arrow" } })

    k:Module({
        name = S.NAME,
        needs = { "client", "settings" },
        provides = { Want = api.Want, Where = api.Where },
        start = function(c)
            ctx = c
            local cl = c.client
            if type(cl.addonPrefix) == "function" then
                local ok, v = pcall(cl.addonPrefix, S.Prefix())
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
            wanted, askedAt = nil, nil
            followers, spots = {}, {}
            lastKey, checkedAt = nil, nil
        end,
    })
    return api
end

S.Declare(ns)
