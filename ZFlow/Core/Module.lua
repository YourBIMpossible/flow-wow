-- Modules and the three load phases.
--
--   ns:Module{
--     name     = "sell",
--     needs    = { "store", "prices" },            -- kernel services or other modules
--     provides = { Decide = fn },                  -- what ns.use("sell") returns
--     settings = { { key = ..., ... } },           -- ns:Setting rows
--     events   = { MERCHANT_SHOW = function(ctx, ...) end },
--     ticks    = { { every = 0.5, when = "outOfCombat", run = function(ctx) end } },
--     start    = function(ctx) end,
--     stop     = function(ctx) end,                -- optional
--   }
--   ctx = { name, id, client, store, settings, bus, sched, use }
--
-- declare: files load and call ns:Module; setting rows are declared at once.
-- wire:    ns:Load() checks every `needs`, then registers events and ticks.
-- start:   ns:Load() enables the bus and scheduler and runs each start, in
--          dependency order.
-- A module with a missing or cyclic need, or whose start fails, is turned
-- off and reported by name; the others start. If the load guard pauses the
-- addon, Load wires and starts nothing.
-- stop:    when a started module is switched off (its own errors, or a
--          module it needs was switched off) its stop runs once, after its
--          handlers, ticks and jobs are cut. An error in stop is a recorded
--          problem, kind "stop", and is not thrown and not counted towards
--          anything. A module that never started gets no stop.
local _, ns = ...
ns.make = ns.make or {}

local KERNEL = { client = true, store = true, settings = true, bus = true, sched = true, scheduler = true }

local function specProblem(spec)
    if type(spec) ~= "table" then return "the module is not a table" end
    if type(spec.name) ~= "string" or spec.name == "" then return "no name" end
    if KERNEL[spec.name] then return "that name is a kernel service" end
    for _, field in ipairs({ "needs", "provides", "settings", "events", "ticks" }) do
        if spec[field] ~= nil and type(spec[field]) ~= "table" then return field .. " must be a table" end
    end
    if spec.start ~= nil and type(spec.start) ~= "function" then return "start must be a function" end
    if spec.stop ~= nil and type(spec.stop) ~= "function" then return "stop must be a function" end
    for _, need in ipairs(spec.needs or {}) do
        if type(need) ~= "string" then return "needs must be names" end
    end
    for event, fn in pairs(spec.events or {}) do
        if type(event) ~= "string" or type(fn) ~= "function" then return "events maps names to functions" end
    end
    for _, t in ipairs(spec.ticks or {}) do
        if type(t) ~= "table" or type(t.run) ~= "function" or type(t.every) ~= "number" or t.every <= 0 or t.every ~= t.every then
            return "a tick needs every (seconds) and run"
        end
        if t.when ~= nil and t.when ~= "always" and t.when ~= "outOfCombat" then return "unknown tick when" end
    end
    return nil
end

-- How many errors from one module's handlers, ticks and jobs, in one
-- session, switch it off. A first guess, not a measured number.
ns.FAULT_LIMIT = 5

function ns.make.modules(k)
    local mods, order = {}, {}
    k.phase = "declare"
    k.paused = false

    local function turnOff(mod, reason)
        local was = mod.state
        mod.state, mod.reason = "off", reason
        k.bus:off(mod.spec.name)
        k.sched:off(mod.spec.name)
        k.problems:add("module", mod.spec.name, reason)
        -- Only what started is stopped, and once. The meter records an
        -- error in stop as a problem; it goes no further.
        if was == "started" and not mod.stopped and type(mod.spec.stop) == "function" then
            mod.stopped = true
            k.meter:run(mod.spec.name, "stop", nil, mod.spec.stop, mod.ctx)
        end
    end

    -- Repeated errors. The bus and the scheduler report each error of a
    -- handler, tick or job here with its owner. The count is per owner, for
    -- the session, and a success never lowers it. At FAULT_LIMIT a module
    -- that is not already off is switched off, as turnOff does, and so is
    -- every module that needs it, and theirs. It stays off until the next
    -- load of the interface. An owner that is no module is counted only.
    -- Nothing is said in chat: the reason is in k:ModuleState(name) and in
    -- the problems list, kind "module".
    local faults = {}

    local function switchOff(mod, reason)
        turnOff(mod, reason)
        local name = mod.spec.name
        for i = 1, #order do
            local other = order[i]
            if other.state ~= "off" then
                local needs = other.spec.needs or {}
                for j = 1, #needs do
                    if needs[j] == name then
                        switchOff(other, "needs " .. name .. ", which was switched off")
                        break
                    end
                end
            end
        end
    end

    function k.fault(owner, err)
        local n = (faults[owner] or 0) + 1
        faults[owner] = n
        if n ~= ns.FAULT_LIMIT then return end
        local mod = mods[owner]
        if not mod or mod.state == "off" then return end
        switchOff(mod, "switched off after " .. n .. " errors; last: " .. tostring(err))
    end

    function k:Module(spec)
        local problem = specProblem(spec)
        if not problem and mods[spec.name] then problem = "duplicate module" end
        if not problem and k.phase ~= "declare" then problem = "declared after load" end
        if problem then
            k.problems:add("module", tostring(type(spec) == "table" and spec.name or nil), problem)
            return nil
        end
        local mod = { spec = spec, state = "declared" }
        mods[spec.name] = mod
        order[#order + 1] = mod
        for _, row in ipairs(spec.settings or {}) do k:Setting(row) end
        return spec
    end

    -- The module's `provides`, or nil when it is unknown or turned off.
    -- Resolved when called, so file order does not matter.
    function k.use(name)
        local mod = mods[name]
        if not mod or mod.state == "off" then return nil end
        return mod.spec.provides or {}
    end

    -- "declared", "wired", "started" or "off" (with the reason), nil if unknown.
    function k:ModuleState(name)
        local mod = mods[name]
        if not mod then return nil end
        return mod.state, mod.reason
    end

    -- Dependency order, needs first. Turns off modules with a missing or
    -- cyclic need and everything that needs them.
    local function resolve()
        local sorted, mark, path = {}, {}, {}
        local function visit(mod)
            local name = mod.spec.name
            if mark[name] == "done" then return mod.state ~= "off" end
            if mark[name] == "open" then
                local from = 1
                for i = 1, #path do
                    if path[i] == name then from = i end
                end
                local cycle = table.concat(path, " -> ", from) .. " -> " .. name
                for i = from, #path do mods[path[i]].cycle = cycle end
                return false
            end
            mark[name] = "open"
            path[#path + 1] = name
            local fault
            for _, need in ipairs(mod.spec.needs or {}) do
                if not KERNEL[need] then
                    local other = mods[need]
                    if not other then
                        fault = fault or ("needs " .. need .. ", which is missing")
                    elseif not visit(other) then
                        fault = fault or ("needs " .. need .. ", which did not start")
                    end
                end
            end
            path[#path] = nil
            mark[name] = "done"
            if mod.cycle then fault = "needs form a cycle: " .. mod.cycle end
            if fault then
                turnOff(mod, fault)
                return false
            end
            sorted[#sorted + 1] = mod
            return true
        end
        for i = 1, #order do visit(order[i]) end
        return sorted
    end

    local function context(mod)
        return { name = mod.spec.name, id = k.id, client = k.client, store = k.store,
            settings = k.settings, bus = k.bus, sched = k.sched, use = k.use }
    end

    -- Wire and start. Returns true when the addon is running, false when
    -- the guard paused it.
    function k:Load()
        if k.phase ~= "declare" then return k.phase == "running" end
        local verdict = ns.Guard.Decide(k.client, k.id)
        if verdict.paused then
            k.phase, k.paused, k.pausePanel = "paused", true, verdict.panel
            return false
        end
        k.store:open()

        k.phase = "wire"
        local sorted = resolve()
        for i = 1, #sorted do
            local mod = sorted[i]
            local name, ctx = mod.spec.name, context(mod)
            mod.ctx = ctx
            for event, fn in pairs(mod.spec.events or {}) do
                k.bus:on(name, event, function(...) return fn(ctx, ...) end)
            end
            for _, t in ipairs(mod.spec.ticks or {}) do
                k.sched:every(name, t.every, function() return t.run(ctx) end, { when = t.when })
            end
            mod.state = "wired"
        end

        k.phase = "start"
        k.bus:enable()
        k.sched:enable()
        for i = 1, #sorted do
            local mod = sorted[i]
            local name = mod.spec.name
            local blocked
            for _, need in ipairs(mod.spec.needs or {}) do
                if mods[need] and mods[need].state == "off" then blocked = need end
            end
            -- A module already off was switched off by its errors while
            -- earlier modules started: it is not started, and its reason
            -- stands. The same if that happens during its own start.
            if mod.state ~= "off" then
                if blocked then
                    turnOff(mod, "needs " .. blocked .. ", which did not start")
                elseif mod.spec.start then
                    local ok, err = k.meter:run(name, "start", nil, mod.spec.start, mod.ctx)
                    if not ok then
                        turnOff(mod, "start failed: " .. tostring(err))
                    elseif mod.state ~= "off" then
                        mod.state = "started"
                    end
                else
                    mod.state = "started"
                end
            end
        end

        k.phase = "running"
        k.bus:emit("kernel:started")
        return true
    end

    -- Loads at login, when every enabled addon and all saved data are in.
    -- This one listener is the kernel's own and is dropped before the guard
    -- decides, so a paused addon listens to nothing of its own (the diagnostics and
    -- the dev panel keep theirs).
    function k:Boot()
        local cancel
        cancel = k.client.listen("PLAYER_LOGIN", function()
            cancel()
            k:Load()
        end)
    end
end
