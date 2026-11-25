local _, ns = ...
-- Z-Flow: the waypoint words past "x y" (lead section 460, parity rows
-- A1-39, A1-41, A1-42). The /way command hands its text here first; a
-- text this file does not take goes on to N.Waypoint.Set as before.
--   A1-39  "Zone Name x y [label]" for a zone the player is not in: the
--          zone's map is found by its name (client.mapName over the map
--          numbers, read once). The player's own zone stays N.Waypoint's.
--   A1-41  "repair", "vendor", "flight", "inn", "bank", "auction", "mail":
--          a waypoint at the nearest one this character has seen
--          (N.Errand.Find), or a nearer one the player's own Questie
--          add-on lists (as Flow's Modules/Nav/Services.lua; the answer
--          then says it is from Questie, never that it was seen).
--   A1-42  a party member's name: a waypoint where they stand now. It
--          stays where it was set; "follow" is the word that keeps pointing
--          at them. The arrow menu's row "Waypoint at <name>" does the same.
-- Compared with Flow Modules/Nav/Waypoint.lua: W.Parse (zone names through
-- C_Map.GetMapInfo over map numbers 1 to 2500) and W:SetFromText (a name
-- follows the member there; here it is a waypoint, follow stays its own
-- word). LOOK ONLY: nothing moves, targets or speaks for the player.
-- Not tested in game: the map-name scan is a first guess.
--
--   WW.Declare(k, diag) -> api
--     api.Take(text) -> true, line when the text was one of these words
--                       (set or turned down), false when it is not
--     api.At(which)  -> true, line or nil, line: which is a party unit or name
ns.Nav = ns.Nav or {}
local N = ns.Nav

local WW = {}
N.WayWords = WW

WW.NAME = "wayWords"
WW.MAP_MAX = 2500      -- map numbers read for a zone's name, as Flow does
-- The word typed -> N.Errand's kind.
WW.ERRANDS = { repair = "repair", vendor = "vendor", flight = "flight", inn = "inn",
    bank = "bank", auction = "auction", mail = "mail" }

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function WW.Declare(k, diag)
    local api = {}
    local ctx
    -- Lower-cased map name -> map number, read once and kept for the
    -- session (until the module stops); a map renamed mid-session is not
    -- seen until then.
    local zoneIds

    local function client() return ctx and ctx.client or k.client end

    local function ask(name, ...)
        local c = client()
        if type(c) ~= "table" or type(c[name]) ~= "function" then return nil end
        local ok, v = pcall(c[name], ...)
        if ok then return v end
        return nil
    end

    local function slot()
        local W = N.Waypoint
        local store = ctx and ctx.store or k.store
        if not W then return nil end
        return W.Slot(store)
    end

    -- -> true, the line to say, and was the waypoint set?
    local function setAt(map, x, y, label)
        local W = N.Waypoint
        if type(W) ~= "table" then return true, "waypoints are not loaded." end
        if label and #label > W.LABEL_MAX then label = label:sub(1, W.LABEL_MAX) end
        local wp, why = W.SetAt(slot(), map, x, y, label)
        if not wp then return true, tostring(why) .. "; nothing changed.", false end
        return true, "waypoint set: " .. tostring(W.Text(wp)) .. ".", true
    end

    local function set(map, x, y, label)
        local done, line = setAt(map, x, y, label)
        return done, line
    end

    local function zoneByName(name)
        if not zoneIds then
            zoneIds = {}
            for id = 1, WW.MAP_MAX do
                local n = ask("mapName", id)
                if type(n) == "string" and n ~= "" and not zoneIds[n:lower()] then zoneIds[n:lower()] = id end
            end
        end
        return zoneIds[name:lower()]
    end

    local function member(which)
        local party = ask("party")
        if type(party) ~= "table" or type(which) ~= "string" then return nil end
        local want = which:lower()
        for _, m in ipairs(party) do
            if type(m) == "table" and type(m.unit) == "string"
                and (m.unit == which or (type(m.name) == "string" and m.name:lower() == want)) then
                return m
            end
        end
        return nil
    end

    function api.At(which)
        local m = member(which)
        if not m then return nil, "no party member " .. tostring(which) .. "." end
        local name = type(m.name) == "string" and m.name or m.unit
        local at = ask("unitPosition", m.unit)
        if type(at) ~= "table" or at.map == nil or not finite(at.x) or not finite(at.y) then
            return nil, "where " .. name .. " is is not known (another map or an instance); nothing changed."
        end
        return set(at.map, at.x, at.y, name)
    end

    local function errand(word)
        local E = ns.Errand
        local kind = E and E.KINDS and E.KINDS[WW.ERRANDS[word]]
        if not kind or type(E.Find) ~= "function" then return true, "nearest places are not loaded." end
        local ok, place, why = pcall(E.Find, kind, client(), ctx and ctx.store or k.store, ctx and ctx.use or k.use)
        if not ok or type(place) ~= "table" or place.map == nil then
            -- Questie's list is still being gone through: a later ask may have one.
            if ok and why ~= nil and why == N.READING and type(E.READING) == "string" then return true, E.READING end
            return true, "no " .. word .. " seen on this map yet; nothing changed."
        end
        local step
        if type(E.Step) == "function" then step = E.Step(place) end
        local done, line, isSet = setAt(place.map, place.x, place.y, step and step.label or E.LABELS[kind])
        -- A place from the player's own Questie is said to be that.
        if isSet and place.unvisited == true and type(E.FROM_QUESTIE) == "string" then
            line = line .. " " .. E.FROM_QUESTIE
        end
        return done, line
    end

    function api.Take(text)
        if type(text) ~= "string" then return false end
        local body = text:match("^%s*(.-)%s*$")
        local head, rest = body:match("^(%S+)%s*(.*)$")
        if head and (head:lower() == "way" or head:lower() == "/way") then body = rest end
        local word = body:lower()
        if WW.ERRANDS[word] then return errand(word) end
        if not body:find("%d") and body:find("^%S+$") then
            if member(body) then
                local _, line = api.At(body)
                return true, line
            end
            return false
        end
        local W = N.Waypoint
        if type(W) ~= "table" then return false end
        local parsed = W.Parse(body)
        if not parsed or not parsed.zone then return false end
        local here = ask("position")
        local mine
        if type(here) == "table" then mine = ask("mapName", here.map) end
        if type(mine) == "string" and mine:lower() == parsed.zone:lower() then return false end
        local map = zoneByName(parsed.zone)
        if not map then return true, "no zone named " .. parsed.zone .. " is known; nothing changed." end
        return set(map, parsed.x, parsed.y, parsed.label)
    end

    k:Module({
        name = WW.NAME,
        needs = { "client", "store" },
        provides = {
            Take = function(text) return api.Take(text) end,
            At = function(which) return api.At(which) end,
        },
        start = function(c) ctx = c end,
        stop = function() zoneIds = nil end,
    })

    return api
end

ns.wayWords = WW.Declare(ns, ns.diag)
