local _, ns = ...
-- Z-Flow guide read: the guide (Nav/Guide.lua) fed from a client. Pure given
-- a client: it asks the client where the player is, which way they face and
-- how big the player's map is, builds the link the guide takes, and calls
-- N.Guide. No frames, nothing remembered, and no size table: a map's size is
-- only ever what the client says (client.mapSize). Since S44 a step on
-- another map is related to the player's through client.mapCorners, when
-- the client gives the corners of both (see placeByWorld).
-- Needs Nav/Guide.lua.
--
-- Unknown stays unknown: a read the client does not answer, or that fails,
-- is passed on as nil, and the guide then gives no distance or no turn.
ns.Nav = ns.Nav or {}
local N = ns.Nav

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- One read of the client: nil when there is no such read or it fails.
local function ask(client, name, arg)
    if type(client) ~= "table" then return nil end
    local f = client[name]
    if type(f) ~= "function" then return nil end
    local ok, v = pcall(f, arg)
    if ok then return v end
    return nil
end

-- The size the client gives for a map, { w, h } in yards, or nil.
local function sizeOf(client, map)
    if map == nil then return nil end
    local size = ask(client, "mapSize", map)
    if type(size) == "table" and finite(size.w) and finite(size.h) and size.w > 0 and size.h > 0 then
        return size
    end
    return nil
end

-- S44 (lead section 173): another map placed beside the player's through
-- the world, when the caller gives no offsets. client.mapCorners(map) gives
-- each map's corners in world yards. The player's map sits at 0, 0; another
-- map's corner is put in the player's map's frame along its east and south
-- edges. Only a map on the same continent as the player's, with its size
-- known and no offset yet, is placed; the corners are asked for only when
-- there is such a map. Anything not known: the map is left unplaced, and
-- N.Bearing answers "zone" as before.
local function placeByWorld(client, link, here, want)
    if here == nil or type(link[here]) ~= "table" or link[here].x == nil then return end
    local others = {}
    for _, map in ipairs(want) do
        local e = link[map]
        if map ~= here and type(e) == "table" and finite(e.w) and e.x == nil then others[#others + 1] = map end
    end
    if #others == 0 then return end
    local home = ask(client, "mapCorners", here)
    if type(home) ~= "table" or home.cont == nil then return end
    for _, key in ipairs({ "ox", "oy", "ex", "ey", "sx", "sy" }) do
        if not finite(home[key]) then return end
    end
    local ex, ey = home.ex - home.ox, home.ey - home.oy
    local sx, sy = home.sx - home.ox, home.sy - home.oy
    local el, sl = math.sqrt(ex * ex + ey * ey), math.sqrt(sx * sx + sy * sy)
    if not (finite(el) and finite(sl) and el > 0 and sl > 0) then return end
    ex, ey, sx, sy = ex / el, ey / el, sx / sl, sy / sl
    for _, map in ipairs(others) do
        local o = ask(client, "mapCorners", map)
        if type(o) == "table" and o.cont ~= nil and o.cont == home.cont and finite(o.ox) and finite(o.oy) then
            local dx, dy = o.ox - home.ox, o.oy - home.oy
            local x, y = dx * ex + dy * ey, dx * sx + dy * sy
            if finite(x) and finite(y) then link[map].x, link[map].y = x, y end
        end
    end
end

local function build(client, position, given, maps)
    local link = {}
    local framed = false
    if type(given) == "table" then
        for zone, e in pairs(given) do
            -- Offsets are the caller's; a size is never taken from them.
            if type(e) == "table" then
                link[zone] = { x = e.x, y = e.y }
                -- Only an entry with an offset puts the link in the caller's
                -- frame; one with none (or only a size) says nothing of it.
                if finite(e.x) and finite(e.y) then framed = true end
            end
        end
    end
    local want = {}
    local here = type(position) == "table" and position.map or nil
    if here ~= nil then want[#want + 1] = here end
    if type(maps) == "table" then
        for _, m in ipairs(maps) do want[#want + 1] = m end
    end
    for _, map in ipairs(want) do
        local size = sizeOf(client, map)
        if size then
            -- Only the player's map sits at 0, 0 by default, and only when the
            -- caller gives no offsets at all: a caller's offsets are in the
            -- caller's frame, where the player's map has no known place. Any
            -- other map gets its size but no offset unless the caller gives
            -- one, so N.Bearing answers "zone" rather than treat two maps as
            -- sharing one corner.
            local e = link[map] or ((map == here and not framed) and { x = 0, y = 0 } or {})
            e.w, e.h = size.w, size.h
            link[map] = e
        end
    end
    if not framed then placeByWorld(client, link, here, want) end
    return link
end

-- The link the guide takes, for the player's map.
--   client: asked for position() and mapSize(map), and for mapCorners(map)
--     when a further map has a size and no offset (S44).
--   given: optional link of offsets, { [zone] = { x, y } } (as N.Bearing).
--     Its offsets are kept; any w and h in it are dropped.
--   maps: optional list of further maps to ask the size of.
-- -> { [map] = { x, y, w, h } }. A map the client gives no size for gets no
--    w and h; with no `given` entry it is left out altogether. With no
--    `given`, the player's map sits at offset 0, 0; a further map on the
--    same continent is placed beside it when the client gives both maps'
--    corners (placeByWorld), else it gets w and h only, so it cannot be
--    related to the player's map. With a
--    `given` that does not name the player's map, that map too gets w and h
--    only. The answer is for the map the player stood on when it was made:
--    handed back in after the player has moved, it names that old map.
function N.GuideLink(client, given, maps)
    return build(client, ask(client, "position"), given, maps)
end

local function stepMap(step)
    local place = type(step) == "table" and step.place or nil
    return type(place) == "table" and place.map or nil
end

-- The arrow view's state, read from the client.
--   client: asked for position(), zone(), facing() and mapSize(map), each
--     once per map, and for mapCorners(map) only when a step is on a map
--     other than the player's (S44); for nothing else.
--   steps = { quest, prof, separate, view, link }: as N.Guide's input; link
--     is optional and carries only offsets between zones (see N.GuideLink).
-- -> what N.Guide gives.
function N.GuideRead(client, steps)
    steps = type(steps) == "table" and steps or {}
    local position = ask(client, "position")
    local maps, seen = {}, {}
    if type(position) == "table" and position.map ~= nil then seen[position.map] = true end
    for _, m in ipairs({ stepMap(steps.quest) or false, stepMap(steps.prof) or false }) do
        if m ~= false and not seen[m] then
            seen[m] = true
            maps[#maps + 1] = m
        end
    end
    return N.Guide({
        position = position,
        zone = ask(client, "zone"),
        facing = ask(client, "facing"),
        link = build(client, position, steps.link, maps),
        quest = steps.quest,
        prof = steps.prof,
        separate = steps.separate,
        view = steps.view,
    })
end
