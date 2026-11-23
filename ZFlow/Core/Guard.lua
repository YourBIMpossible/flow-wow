-- Load guard. This addon and the one it replaces would both claim the same
-- keys, both act at a vendor and both hook the same client functions, so
-- they never run together: if the predecessor is loaded this addon pauses.
--
-- Decide is a pure function over the client boundary. It builds no frame:
-- `panel` is plain data for whoever draws it.
local _, ns = ...

ns.Guard = {}

function ns.Guard.Decide(client, id)
    local old = id.predecessor
    -- Two signs, because neither is confirmed on this client: the addon-loaded
    -- query, and the presence of the predecessor's account table.
    local loaded = client.addonLoaded(old) or client.savedExists(id.predecessorDB)
    if not loaded then return { paused = false } end
    return {
        paused = true,
        reason = old .. " is loaded",
        panel = {
            text = old .. " is also enabled. " .. id.title .. " is paused.",
            actions = {
                { id = "import", label = "Import from " .. old },
                { id = "disable-flow-and-reload", label = "Turn " .. old .. " off and reload" },
            },
        },
    }
end

-- Lead section 286: the old add-on's flight points, your own flight times
-- and your flight rate, copied into this add-on's saved tables at a load
-- the guard pauses (the only load at which the old tables are there). The
-- old tables are read through copies and never changed. Each point, time
-- and the rate is written only where this add-on has none yet, by key, so
-- a later load copies nothing again and says nothing. Needs game test:
-- whether the client loads the old tables at all.
--   n = ns.Guard.CopyFlights(client, id)   points newly written; one line
--   said when n > 0.
ns.Guard.IMPORTED = "%s: copied the old add-on's flight points (%d new). Turn the old add-on off and reload to use them."

local function sub(t, key)
    if type(t[key]) ~= "table" then t[key] = {} end
    return t[key]
end

local function at(t, ...)
    for i = 1, select("#", ...) do
        if type(t) ~= "table" then return nil end
        t = t[select(i, ...)]
    end
    return t
end

function ns.Guard.CopyFlights(client, id)
    local Import = ns.Import
    if not (Import and type(Import.FromFlow) == "function") then return 0 end
    if not client.savedExists(id.predecessorDB) then return 0 end
    local copy = ns.make.deepCopy
    local charName = id.predecessorCharDB
    local result = Import.FromFlow(copy(client.saved(id.predecessorDB)),
        client.savedExists(charName) and copy(client.saved(charName)) or nil)
    if type(result) ~= "table" or not result.ok then return 0 end
    local nodes = at(result.char, "learned", "flights", "nodes")
    local times = at(result.account, "learned", "flights", "times")
    local rate = at(result.account, "learned", "flights", "rate")
    local written = 0
    if type(nodes) == "table" and next(nodes) ~= nil then
        local into = sub(sub(sub(client.saved(id.charDB), "learned"), "flights"), "nodes")
        for name, p in pairs(nodes) do
            if into[name] == nil then
                into[name] = copy(p)
                written = written + 1
            end
        end
    end
    if (type(times) == "table" and next(times) ~= nil) or rate ~= nil then
        local flights = sub(sub(client.saved(id.accountDB), "learned"), "flights")
        if type(times) == "table" then
            local into = sub(flights, "times")
            for key, sec in pairs(times) do
                if into[key] == nil then into[key] = sec end
            end
        end
        if rate ~= nil and flights.rate == nil then flights.rate = rate end
    end
    if written > 0 then client.print(ns.Guard.IMPORTED:format(id.title, written)) end
    return written
end
