local _, ns = ...
-- Z-Flow errand stops (F2): the stop the player asked for, as a step the
-- quest arrow points at. A stop is the nearest place of one kind this
-- player has seen: a vendor, a repair vendor, a banker, an innkeeper, a
-- flight master, a mailbox (Nav/ServiceNearest.lua, from what
-- Nav/ServiceSeen.lua saved) or a trainer (the npcs Nav/ProfSeen.lua
-- saved), or, for the kinds that are an NPC, a nearer one the player's own
-- Questie add-on lists (N.Nearest, parity row A1-41; such a place has
-- unvisited = true and is said to be from Questie, never seen: lead
-- section 611). The hearthstone is said in words (Nav/HearthStep.lua has no
-- place to point at), and "route" says a short order to visit the nearest
-- of each kind (Nav/RoutePlan.lua).
--
-- Nothing is authored here: every place is one this client showed this player,
-- or one the player's own Questie gives while the game runs.
-- It only points and says: nothing is bought, repaired, banked,
-- flown or used for the player. The chosen stop is kept in memory only; a
-- reload or a login starts with none. Not tested in game.
--
-- E.KINDS       word after the command -> kind, in E.ORDER
-- E.RADIUS      yards; inside it the player is at the stop
--
-- E.TrainerOf(npcs, here) -> place, or nil
--   npcs  account "learned.places.npcs": { [name] = { map, x, y,
--           roles = { trainer = true }, trains = { [profession] = true },
--           factions = { [faction] = true } } }
--   here  { map, x, y, cont, faction, size = { w, h } } (size, faction and
--           cont optional)
--   place { kind = "trainer", key, name, map, x, y, cont, yards }
--   The nearest trainer on the map of the player, by yards when the size
--   is known, else by shares of the map; a tie goes to the lower key. An
--   npc saved for factions the player is not one of is left out; with the
--   faction of the player not known, or none saved, it stays in.
--
-- E.Step(place) -> step, or nil
--   step = { label, place = { cont, map, x, y }, radius = E.RADIUS }
--   the shape Arrow.GuideSource takes as the quest step. label is
--   "<Kind>: <name>", or the kind alone when the name is not known or the
--   label would be over N.Waypoint.LABEL_MAX bytes (never cut). A place
--   from Questie (place.unvisited) also has detail = E.FROM_QUESTIE, the
--   arrow's line under the label.
--
-- E.Find(kind, client, store, use) -> place, or nil[, N.READING while
--   Questie's list is still being gone through]
-- E.Route(client, store) -> route, reason   (N.RoutePlan over the nearest
--   place of each kind on the map of the player)
-- E.Hearth(client) -> text   the bind place and whether the stone is ready
--
-- E.Declare(k[, diag, arrow]) -> api
--   api.choose(kind) -> place or nil   makes the nearest of kind the stop
--   api.clear()                        no stop
--   api.stop()  -> place or nil        the stop chosen
--   api.step()  -> step or nil         the same as an arrow step
--   ns.use(E.NAME) -> { Step = api.step, Stop = api.stop }
--   arrow: a function answering the arrow module's api; it is asked for a
--   fresh layout when the stop changes.
ns.Nav = ns.Nav or {}
local N = ns.Nav
local E = ns.Errand or {}
ns.Errand = E

E.NAME = "errand"
E.WORD = "stop"
E.RADIUS = 10
E.NPCS = "learned.places.npcs"
E.ORDER = { "vendor", "repair", "bank", "inn", "flight", "mail", "auction", "trainer" }
E.KINDS = {
    vendor = "vendor", repair = "repair", bank = "banker", inn = "innkeeper",
    flight = "flight", mail = "mailbox", auction = "auction", trainer = "trainer",
}
E.LABELS = {
    vendor = "Vendor", repair = "Repair", banker = "Bank", innkeeper = "Inn",
    flight = "Flight master", mailbox = "Mailbox", auction = "Auction house", trainer = "Trainer",
}
-- A place from the player's own Questie: the arrow's line under the label,
-- and what is said after the stop in chat. Never said to be seen or used.
E.FROM_QUESTIE = "From your own Questie add-on."
E.MARK = " (Questie)"
E.READING = "still going through your Questie add-on's list of places; ask again in a few seconds. Nothing changed."
E.HELP = "point the arrow at the nearest stop you have seen or your Questie add-on lists: vendor, repair, bank, inn, flight,"
    .. " mail, auction or trainer; hearth, route, off"

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function text(v)
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

local function share(v)
    return finite(v) and v >= 0 and v <= 1
end

-- One read of the client, or nil when it has no such read or it fails.
local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

local function saved(store, scope, path)
    if type(store) ~= "table" or type(store.get) ~= "function" then return nil end
    local ok, v = pcall(store.get, store, scope, path)
    if not ok then return nil end
    return v
end

-- Where the player is, as E.TrainerOf and N.NearestOf take it; nil when
-- the map or the place on it is not known.
local function hereOf(client)
    local at = ask(client, "position")
    if type(at) ~= "table" or at.map == nil or not (share(at.x) and share(at.y)) then return nil end
    local zone = ask(client, "zone")
    local size = ask(client, "mapSize", at.map)
    local known = type(size) == "table" and finite(size.w) and finite(size.h) and size.w > 0 and size.h > 0
    return {
        map = at.map, x = at.x, y = at.y,
        cont = type(zone) == "table" and zone.cont or nil,
        faction = text(ask(client, "faction")),
        size = known and { w = size.w, h = size.h } or nil,
    }
end

local function mayUse(e, faction)
    if faction == nil or type(e.factions) ~= "table" or next(e.factions) == nil then return true end
    return e.factions[faction] == true
end

function E.TrainerOf(npcs, here)
    if type(npcs) ~= "table" or type(here) ~= "table" then return nil end
    if here.map == nil or not (share(here.x) and share(here.y)) then return nil end
    local size = type(here.size) == "table" and finite(here.size.w) and finite(here.size.h)
        and here.size.w > 0 and here.size.h > 0 and here.size or nil
    local w, h = size and size.w or 1, size and size.h or 1
    local faction = text(here.faction)
    local best, bestKey, bestD
    for key, e in pairs(npcs) do
        if type(e) == "table" and type(e.roles) == "table" and e.roles.trainer == true
            and e.map == here.map and share(e.x) and share(e.y) and mayUse(e, faction) then
            local dx, dy = (e.x - here.x) * w, (e.y - here.y) * h
            local d = dx * dx + dy * dy
            if best == nil or d < bestD or (d == bestD and tostring(key) < tostring(bestKey)) then
                best, bestKey, bestD = e, key, d
            end
        end
    end
    if best == nil then return nil end
    return {
        kind = "trainer", key = bestKey, name = text(bestKey),
        map = best.map, x = best.x, y = best.y, cont = here.cont,
        yards = size and math.sqrt(bestD) or nil,
    }
end

function E.Step(place)
    if type(place) ~= "table" or place.map == nil or not (share(place.x) and share(place.y)) then return nil end
    local kind = E.LABELS[place.kind]
    if not kind then return nil end
    -- A place from Questie carries that in its label too, for whoever
    -- shows the label alone (a route stop, a waypoint).
    local mark = place.unvisited == true and E.MARK or ""
    local label = kind .. mark
    local name = text(place.name)
    if name then
        local long = kind .. ": " .. name .. mark
        if #long <= (N.Waypoint and N.Waypoint.LABEL_MAX or 40) then label = long end
    end
    return {
        label = label,
        place = { cont = place.cont, map = place.map, x = place.x, y = place.y },
        radius = E.RADIUS,
        detail = place.unvisited == true and E.FROM_QUESTIE or nil,
    }
end

function E.Find(kind, client, store, use)
    if kind == "trainer" then
        local here = hereOf(client)
        if not here then return nil end
        return E.TrainerOf(saved(store, "account", E.NPCS), here)
    end
    if type(N.Nearest) ~= "function" then return nil end
    return N.Nearest(kind, client, store, use)
end

-- The nearest place of each kind on the map of the player, one entry for a
-- place that is the nearest of two kinds, in a short order to visit.
function E.Route(client, store)
    local here = hereOf(client)
    if not here then return nil, "position unknown" end
    local places, seen = {}, {}
    for _, word in ipairs(E.ORDER) do
        -- The route of stops is made of places this character used only
        -- (lead section 626): Questie is not asked here.
        local place = E.Find(E.KINDS[word], client, store)
        if place then
            local key = tostring(place.kind == "trainer" and "npc:" or "svc:") .. tostring(place.key)
            if not seen[key] then
                seen[key] = true
                places[#places + 1] = place
            end
        end
    end
    if #places == 0 then return nil, "no places" end
    if type(N.RoutePlan) ~= "function" then return nil, "no planner" end
    return N.RoutePlan(places, here.map, here.size, here)
end

function E.Hearth(client)
    local name = text(ask(client, "bindLocation"))
    local wait = ask(client, "hearthCooldown")
    local where = name and ("your hearthstone is set to " .. name) or "where your hearthstone is set is not known"
    if not finite(wait) then return where .. "; whether it is ready is not known." end
    if wait <= 0 then return where .. "; it is ready." end
    return where .. "; ready in " .. tostring(math.ceil(wait / 60)) .. " min."
end

local function yards(v)
    if not finite(v) then return "distance unknown" end
    return tostring(math.floor(v + 0.5)) .. " yd"
end

local function named(place)
    local kind = E.LABELS[place.kind] or tostring(place.kind)
    local name = text(place.name)
    return name and (kind .. " " .. name) or kind
end

-- What is said after a place from the player's own Questie, else nothing.
local function origin(place)
    if place.unvisited == true then return " " .. E.FROM_QUESTIE end
    return ""
end

function E.Declare(k, diag, arrow)
    local api = {}
    local client, store, use
    local chosen

    local function redraw()
        local a = type(arrow) == "function" and arrow() or nil
        if type(a) == "table" and type(a.relayout) == "function" then a.relayout() end
    end

    function api.stop() return chosen end
    function api.step() return E.Step(chosen) end
    function api.clear()
        chosen = nil
        redraw()
    end
    function api.choose(kind)
        if not client then return nil end
        local place, why = E.Find(kind, client, store, use)
        if not place then return nil, why end
        chosen = place
        redraw()
        return place
    end

    local function say(line)
        if client then client.print(ns.id.title .. ": " .. line) end
    end

    local function route()
        local plan, why = E.Route(client, store)
        if not plan then
            if why == "size unknown" then
                say("no route: the size of this map is not known.")
            elseif why == "position unknown" then
                say("no route: where you are is not known.")
            else
                say("no route: no stop you have seen is on this map.")
            end
            return
        end
        for i = 1, #plan.stops do
            local stop = plan.stops[i]
            say(tostring(i) .. ". " .. named(stop.place) .. (stop.leg and (", " .. yards(stop.leg)) or "")
                .. (stop.place.unvisited == true and "." .. origin(stop.place) or ""))
        end
        say("about " .. yards(plan.total) .. " in all (" .. tostring(plan.label) .. ").")
    end

    local function run(rest)
        if not client then return end
        local word = tostring(rest or ""):lower():match("^%s*(%S*)")
        if word == "" then
            if chosen then
                say("the arrow points at " .. named(chosen) .. "." .. origin(chosen) .. " " .. ns.id.slash .. " " .. E.WORD
                    .. " off ends it.")
            else
                say("no stop chosen. " .. E.HELP .. ".")
            end
        elseif word == "off" or word == "none" then
            api.clear()
            say("no stop chosen.")
        elseif word == "hearth" then
            say(E.Hearth(client))
        elseif word == "route" then
            route()
        elseif E.KINDS[word] then
            local place, why = api.choose(E.KINDS[word])
            if place then
                say("the arrow points at " .. named(place) .. " (" .. yards(place.yards) .. ")." .. origin(place))
            elseif why ~= nil and why == N.READING then
                say(E.READING)
            else
                say("no " .. word .. " you have seen is on this map. Nothing changed.")
            end
        else
            say("\"" .. word .. "\" is no stop. " .. E.HELP .. ".")
        end
    end

    k:Module({
        name = E.NAME,
        needs = { "client", "store" },
        provides = { Step = api.step, Stop = api.stop, Choose = api.choose, Clear = api.clear },
        start = function(ctx)
            client, store, use = ctx.client, ctx.store, ctx.use
        end,
    })

    if diag and type(diag.commands) == "table" then
        diag.commands[E.WORD] = run
        if type(diag.help) == "table" then diag.help[E.WORD] = E.HELP end
    end

    return api
end

-- The addon's own: declared when this file loads. It shows nothing until a
-- stop is asked for.
ns.errand = E.Declare(ns, ns.diag, function() return ns.arrow end)
