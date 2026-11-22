local _, ns = ...
-- Z-Flow guide read: the guide (Nav/Guide.lua) fed from a client. Pure given
-- a client: it asks the client where the player is, which way they face and
-- how big the player's map is, builds the link the guide takes, and calls
-- N.Guide. No frames, nothing remembered, and no size table: a map's size is
-- only ever what the client says (client.mapSize).
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

local function build(client, position, given, maps)
    local link = {}
    if type(given) == "table" then
        for zone, e in pairs(given) do
            -- Offsets are the caller's; a size is never taken from them.
            if type(e) == "table" then link[zone] = { x = e.x, y = e.y } end
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
            -- Only the player's map sits at 0, 0 by default. Any other map
            -- gets its size but no offset unless the caller gives one, so
            -- N.Bearing answers "zone" rather than treat two maps as sharing
            -- one corner.
            local e = link[map] or (map == here and { x = 0, y = 0 } or {})
            e.w, e.h = size.w, size.h
            link[map] = e
        end
    end
    return link
end

-- The link the guide takes, for the player's map.
--   client: asked for position() and mapSize(map).
--   given: optional link of offsets, { [zone] = { x, y } } (as N.Bearing).
--     Its offsets are kept; any w and h in it are dropped.
--   maps: optional list of further maps to ask the size of.
-- -> { [map] = { x, y, w, h } }. A map the client gives no size for gets no
--    w and h; with no `given` entry it is left out altogether. With no
--    `given`, the player's map sits at offset 0, 0; any further map gets
--    w and h only, so it cannot be related to the player's map.
function N.GuideLink(client, given, maps)
    return build(client, ask(client, "position"), given, maps)
end

local function stepMap(step)
    local place = type(step) == "table" and step.place or nil
    return type(place) == "table" and place.map or nil
end

-- The arrow view's state, read from the client.
--   client: asked for position(), zone(), facing() and mapSize(map), each
--     once per map, and for nothing else.
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
