-- Bus: client events and the addon's own events share one place.
--
--   bus:on(owner, event, fn) -> cancel
--   bus:off(owner[, event])  -- everything the owner registered, or one event
--   bus:emit(event, ...)
--
-- A name in capitals (PLAYER_LOGIN) is a client event: the bus asks the
-- client for it once it is enabled (the kernel enables it only after the
-- load guard passes). Any other name ("store:ready") is internal. Each
-- handler runs under pcall and is timed against its owner; an error is
-- recorded with owner and event and the other handlers still run.
local _, ns = ...
ns.make = ns.make or {}

function ns.make.bus(k)
    local bus = { enabled = false }
    local handlers = {}     -- event -> list of { owner, fn }
    local cancels = {}      -- client event -> cancel of the client listener

    local function isClientEvent(event)
        return event:find("^[A-Z][A-Z0-9_]*$") ~= nil
    end

    local function attach(event)
        if not bus.enabled or cancels[event] or not isClientEvent(event) then return end
        cancels[event] = k.client.listen(event, function(...) bus:emit(event, ...) end)
    end

    local function prune(event)
        local list = handlers[event]
        if list and #list == 0 then
            handlers[event] = nil
            if cancels[event] then
                cancels[event]()
                cancels[event] = nil
            end
        end
    end

    function bus:on(owner, event, fn)
        if type(owner) ~= "string" or owner == "" or type(event) ~= "string" or event == "" or type(fn) ~= "function" then
            k.problems:add("bus", tostring(owner), "bad handler registration for " .. tostring(event))
            return function() end
        end
        local list = handlers[event] or {}
        handlers[event] = list
        local entry = { owner = owner, fn = fn }
        list[#list + 1] = entry
        attach(event)
        return function()
            if entry.dead then return end
            entry.dead = true
            for i = #list, 1, -1 do
                if list[i] == entry then table.remove(list, i) end
            end
            prune(event)
        end
    end

    function bus:off(owner, event)
        for name, list in pairs(handlers) do
            if event == nil or name == event then
                for i = #list, 1, -1 do
                    if list[i].owner == owner then
                        list[i].dead = true
                        table.remove(list, i)
                    end
                end
            end
        end
        -- pruning changes `handlers`, so collect the empty ones first
        local empty = {}
        for name, list in pairs(handlers) do
            if #list == 0 then empty[#empty + 1] = name end
        end
        for i = 1, #empty do prune(empty[i]) end
    end

    function bus:emit(event, ...)
        local list = handlers[event]
        if not list then return 0 end
        local snapshot = {}
        for i = 1, #list do snapshot[i] = list[i] end
        local ran = 0
        for i = 1, #snapshot do
            local entry = snapshot[i]
            if not entry.dead then
                -- An error is counted against the owner (Core/Module.lua).
                -- That may switch the owner off, which marks the rest of
                -- its handlers in this snapshot dead.
                local ok, err = k.meter:run(entry.owner, "handler", event, entry.fn, ...)
                if not ok and k.fault then k.fault(entry.owner, err) end
                ran = ran + 1
            end
        end
        return ran
    end

    -- Starts listening to the client for every client event with a handler.
    function bus:enable()
        self.enabled = true
        for event in pairs(handlers) do attach(event) end
    end

    return bus
end
