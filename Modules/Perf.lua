-- How much of your computer Flow uses: time spent in each of its update
-- loops (arrow, rotation, route planning, map, tracker) and its memory.
-- /flow perf shows it; the diagnostics snapshot saves it, so a slow spot
-- shows up in tools\read-diag.ps1 without anyone having to notice it.

local _, ns = ...
local P = { stats = {}, since = nil }
ns.perf = P

local clock = debugprofilestop

-- fn wrapped so each call's time is added to `name`. Errors pass through
-- (callers keep their own pcall).
-- Own time only: when a timed function calls another timed one (the arrow
-- update planning the route), the inner one's time and memory count for
-- the inner one alone, so no time is counted twice and the total is true.
local depth, childMs, childKb = 0, {}, {}
function P.Wrap(name, fn)
    if not clock then return fn end
    local st = P.stats[name] or { calls = 0, total = 0, max = 0, kb = 0 }
    P.stats[name] = st
    return function(...)
        depth = depth + 1
        local lvl = depth
        childMs[lvl], childKb[lvl] = 0, 0
        local m0, t0 = collectgarbage("count"), clock()
        local ok, a, b, c, d = pcall(fn, ...)
        local ms, made = clock() - t0, collectgarbage("count") - m0
        depth = lvl - 1
        if depth > 0 then
            childMs[depth] = childMs[depth] + ms
            if made > 0 then childKb[depth] = childKb[depth] + made end
        end
        local own, ownKb = ms - childMs[lvl], made - childKb[lvl]
        st.calls, st.total = st.calls + 1, st.total + own
        if own > st.max then st.max = own end
        -- Memory it made (garbage to clean up later): the cleaner's work is
        -- CPU too, and a big number here is what swells "memory".
        if ownKb > 0 then st.kb = st.kb + ownKb end
        if not ok then error(a, 0) end
        return a, b, c, d
    end
end
P._depth = function() return depth end   -- (tests)

function P:Reset()
    for _, st in pairs(self.stats) do st.calls, st.total, st.max, st.kb = 0, 0, 0, 0 end
    self.since = GetTime()
end

local function memoryKB()
    local update = (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage) or UpdateAddOnMemoryUsage
    local get = (C_AddOns and C_AddOns.GetAddOnMemoryUsage) or GetAddOnMemoryUsage
    if not (update and get) then return nil end
    pcall(update)
    local ok, kb = pcall(get, "Flow")
    return ok and kb or nil
end

-- Lines for /flow perf and the snapshot. `quick` (the snapshot) skips the
-- full garbage clean-up and the second memory scan: a full clean-up walks
-- every addon's memory in one frame, a hitch you can feel.
function P:Report(quick)
    local secs = math.max(GetTime() - (self.since or GetTime()), 1)
    local out, rows, sum = {}, {}, 0
    for name, st in pairs(self.stats) do
        if st.calls > 0 then rows[#rows + 1] = { name = name, st = st }; sum = sum + st.total end
    end
    table.sort(rows, function(a, b) return a.st.total > b.st.total end)
    local kb = memoryKB()
    local kept
    if not quick then
        -- What Flow really keeps: after a full clean-up of the garbage.
        collectgarbage("collect")
        kept = memoryKB()
    end
    out[#out + 1] = string.format("over %d s: Flow used %.2f ms per second (%.2f%% of one CPU core), memory %s (%s)",
        secs, sum / secs, sum / secs / 10, kb and string.format("%.1f MB", kb / 1024) or "?",
        quick and "/flow perf for what's kept after clean-up"
            or ((kept and string.format("%.1f MB", kept / 1024) or "?") .. " kept after clean-up"))
    for _, r in ipairs(rows) do
        local st = r.st
        out[#out + 1] = string.format("  %-32s %6.2f ms/s  avg %5.2f ms  worst %6.1f ms  makes %6.1f KB/s  (%d calls)",
            r.name, st.total / secs, st.total / st.calls, st.max, (st.kb or 0) / secs, st.calls)
    end
    -- One frame at 60 fps is ~16 ms: anything near that is a hitch you'd feel.
    for _, r in ipairs(rows) do
        if r.st.max > 16 then
            out[#out + 1] = string.format("  ! %s once took %.0f ms (a visible hitch)", r.name, r.st.max)
        end
    end
    return out
end

ns:On("PLAYER_LOGIN", function() P.since = GetTime() end)

ns.commands.perf = function(arg)
    arg = (arg or ""):lower()
    if arg == "reset" then P:Reset(); ns:Print("perf counters reset") return end
    ns:Print("performance:")
    for _, line in ipairs(P:Report(arg == "quick")) do print(line) end
    print("  /flow perf reset")
end

-- Lite mode: inside a dungeon or raid, or during a boss fight, Flow eases off
-- the parts you don't need there (route planning, the arrow and minimap at
-- full speed, map and tracker refreshes) so it never adds to lag in a boss
-- fight. The rotation, the Flow key and bags keep running as normal.
local liteAt, liteVal = 0, false
function ns.Lite()
    local now = GetTime()
    if now - liteAt < 1 then return liteVal end
    liteAt = now
    local inInstance, kind = false, nil
    if IsInInstance then inInstance, kind = IsInInstance() end
    local boss = IsEncounterInProgress and IsEncounterInProgress() or false
    liteVal = (inInstance and (kind == "party" or kind == "raid")) or boss or false
    if ns.db and ns.db.perf and ns.db.perf.lite == false then liteVal = false end
    return liteVal
end
ns:On("ENCOUNTER_START", function() liteAt = 0 end)
ns:On("ENCOUNTER_END", function() liteAt = 0 end)
ns:On("PLAYER_ENTERING_WORLD", function() liteAt = 0 end)
