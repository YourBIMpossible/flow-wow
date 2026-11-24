local _, ns = ...

-- ServiceSeen (G37): the module that saves where this player met a vendor,
-- a repair vendor, a banker, an innkeeper, a flight master, a mailbox or
-- an auctioneer (G36),
-- for N.Nearest (Nav/ServiceNearest.lua) to read. The same pattern as
-- Nav/ProfSeen.lua: only what this client showed, nothing authored,
-- nothing printed. It only reads; it opens no window and talks to no one.
--
-- What is taken as seen, each from one event the player caused:
--   MERCHANT_SHOW     a vendor; also a repair vendor when
--                     client.merchantRepairs() says true. A plain false
--                     takes a repair mark off again; no answer leaves it.
--   BANKFRAME_OPENED  a banker
--   TAXIMAP_OPENED    a flight master
--   CONFIRM_BINDER    an innkeeper (the player asked to make the inn home)
--   MAIL_SHOW         a mailbox
--   AUCTION_HOUSE_SHOW  an auctioneer (the auction house window opened)
--
-- Saved per character, char "learned.places.services"[key] =
--   { name, guid, map, x, y, kinds = { [kind] = true }, seen, n }
-- map, x, y are client.position() at the event: where the player stood,
-- which is beside the npc, not on it. seen is client.clock() (a date
-- already saved stays when the clock is not known), n counts the sightings.
-- key is the GUID of the npc, else its name; a mailbox has neither and its
-- key is its map and place to a hundredth of the map, so the same box is
-- one entry. Everything else already on an entry is kept.
--
-- The npc is client.serviceNpc() -> { guid, name } (CLIENT NEED), either
-- left out when not known. With neither known, or with no position,
-- nothing is written at all. A new place past ServiceSeen.MAX entries is
-- not written. A store that refuses a write is left as it was.
--
--   ServiceSeen.Seen(kind, client, store) -> report   one sighting read
--   ServiceSeen.Declare(k)                -> api      declares the module
--     api.last()   the report of the last event read, nil before the first
--   ns.use(ServiceSeen.NAME) -> { Last = api.last }
--
--   report = { kind = "service", service (the kind), ok, reason (when not
--              ok), key, name, repair (vendor: true / false / nil) }
--
-- Keys are names and GUIDs the client gave and may hold a dot, so the
-- table is written by key and never through a dotted path.
--
-- Not tested in game: the event names and every client read used here are
-- first guesses.
-- The event names are on warcraft.wiki.gg (BANKFRAME_OPENED,
-- CONFIRM_BINDER, MAIL_SHOW, MERCHANT_SHOW, TAXIMAP_OPENED,
-- AUCTION_HOUSE_SHOW).

local ServiceSeen = ns.ServiceSeen or {}
ns.ServiceSeen = ServiceSeen

ServiceSeen.NAME = "serviceSeen"
ServiceSeen.PLACES = "learned.places.services"
ServiceSeen.MAX = 400
-- The order the events are listened for; each names the kind it shows.
ServiceSeen.EVENTS = {
    { event = "MERCHANT_SHOW", kind = "vendor" },
    { event = "BANKFRAME_OPENED", kind = "banker" },
    { event = "TAXIMAP_OPENED", kind = "flight" },
    { event = "CONFIRM_BINDER", kind = "innkeeper" },
    { event = "MAIL_SHOW", kind = "mailbox" },
    { event = "AUCTION_HOUSE_SHOW", kind = "auction" },
}

local KINDS = { vendor = true, banker = true, flight = true, innkeeper = true, mailbox = true, auction = true }

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function text(v)
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

-- One read of the client; nil when it has no such read. An error is not
-- caught: the kernel counts it against the module.
local function ask(client, read)
    if type(client) ~= "table" or type(client[read]) ~= "function" then return nil end
    return client[read]()
end

local function refuse(report, reason)
    report.ok, report.reason = false, reason
    return report
end

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

function ServiceSeen.Seen(kind, client, store)
    local report = { kind = "service", service = kind }
    if not KINDS[kind] then return refuse(report, "not a kind of service") end
    -- Every read comes before the first write.
    local guid, name
    if kind ~= "mailbox" then
        local npc = ask(client, "serviceNpc")
        if type(npc) == "table" then guid, name = text(npc.guid), text(npc.name) end
        if not guid and not name then return refuse(report, "the npc is not known") end
        report.name = name
    end
    local pos = ask(client, "position")
    if type(pos) ~= "table" or not (finite(pos.map) and finite(pos.x) and finite(pos.y)) then
        return refuse(report, "the position is not known")
    end
    local repair
    if kind == "vendor" then
        repair = ask(client, "merchantRepairs")
        if type(repair) ~= "boolean" then repair = nil end
        report.repair = repair
    end
    local now = ask(client, "clock")
    if not finite(now) then now = nil end

    local key = guid or name
    if kind == "mailbox" then
        key = string.format("mailbox:%s:%d:%d", tostring(pos.map),
            math.floor(pos.x * 100 + 0.5), math.floor(pos.y * 100 + 0.5))
    end
    report.key = key

    if type(store) ~= "table" or type(store.get) ~= "function" or type(store.set) ~= "function" then
        return refuse(report, "the places cannot be saved")
    end
    local places = store:get("char", ServiceSeen.PLACES)
    if places ~= nil and type(places) ~= "table" then return refuse(report, "the places cannot be saved") end
    places = places or {}
    local old = places[key]
    if type(old) ~= "table" and count(places) >= ServiceSeen.MAX then
        return refuse(report, "the list of places is full")
    end

    local e = {}
    if type(old) == "table" then
        for k, v in pairs(old) do e[k] = v end
    end
    local kinds = {}
    if type(e.kinds) == "table" then
        for k, v in pairs(e.kinds) do kinds[k] = v end
    end
    kinds[kind] = true
    if repair == true then kinds.repair = true elseif repair == false then kinds.repair = nil end
    e.kinds = kinds
    if guid then e.guid = guid end
    if name then e.name = name end
    e.map, e.x, e.y = pos.map, pos.x, pos.y
    if now then e.seen = now end
    e.n = (finite(e.n) and e.n or 0) + 1

    -- The store is asked first, with the table as it is; only when it says
    -- yes is the key set.
    if store:set("char", ServiceSeen.PLACES, places) ~= true then
        return refuse(report, "the places cannot be saved")
    end
    places[key] = e
    report.ok = true
    return report
end

-- Declares the module on kernel k. Usable at once: before the first event
-- last() is nil.
function ServiceSeen.Declare(k)
    local api = {}
    local last
    function api.last() return last end
    k:Module({
        name = ServiceSeen.NAME,
        needs = { "client", "store", "bus" },
        provides = { Last = api.last },
        -- Registered here, after the watches of the client, and not in
        -- `events`, so the client hears each window before this does (the
        -- same order as Nav/ProfSeen.lua).
        start = function(ctx)
            if type(ctx.client.watchMerchant) == "function" then ctx.client.watchMerchant() end
            if type(ctx.client.watchBank) == "function" then ctx.client.watchBank() end
            for _, row in ipairs(ServiceSeen.EVENTS) do
                ctx.bus:on(ServiceSeen.NAME, row.event, function()
                    last = ServiceSeen.Seen(row.kind, ctx.client, ctx.store)
                end)
            end
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.serviceSeen = ServiceSeen.Declare(ns)
