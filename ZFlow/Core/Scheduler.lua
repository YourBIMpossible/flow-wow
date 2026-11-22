-- Scheduler: the one place work is timed. It subscribes to the client's
-- frame tick only while it has work, and reads the client's clock, so the
-- fake clock drives it in tests.
--
--   sched:every(owner, seconds, fn[, { when = "always" | "outOfCombat" }]) -> cancel
--   sched:after(owner, seconds, fn) -> cancel
--   sched:nextFrame(owner, fn) -> cancel
--   sched:afterCombat(owner, fn) -> cancel   -- now if out of combat, else when it ends
--   sched:off(owner)                         -- cancels everything of that owner
--   sched:held() -> count, unknown   work waiting for combat to end; unknown is
--                                    true when the client cannot say if it has
--   sched:report() -> { [owner] = { calls, ms, errors } }  (event handlers included)
--
-- Nothing runs until sched:enable(): the kernel calls it only after the load
-- guard passes. A job's error is recorded against its owner; the job stays.
local _, ns = ...
ns.make = ns.make or {}

local COMBAT_END = "PLAYER_REGEN_ENABLED"

function ns.make.sched(k)
    local sched = { enabled = false }
    local jobs = {}          -- timed and next-frame jobs
    local waiting = {}       -- afterCombat queue
    local stopTick, stopCombat
    local ticking = false
    local tickCount = 0

    local function run(job)
        -- An error is counted against the owner (Core/Module.lua), which
        -- may switch the owner off: sched:off is safe during a tick.
        local ok, err = k.meter:run(job.owner, "tick", job.label, job.fn)
        if not ok and k.fault then k.fault(job.owner, err) end
    end

    local tick

    local function sync()
        if not sched.enabled then return end
        if #jobs > 0 and not stopTick then
            stopTick = k.client.onFrame(tick)
        elseif #jobs == 0 and stopTick and not ticking then
            stopTick()
            stopTick = nil
        end
        if #waiting > 0 and not stopCombat then
            stopCombat = k.client.listen(COMBAT_END, function() sched:flushCombat() end)
        elseif #waiting == 0 and stopCombat then
            stopCombat()
            stopCombat = nil
        end
    end

    -- true unless the client says plainly that the player is out of combat.
    -- The client answers nil when it could not read combat; work that has to
    -- wait for combat to end waits then too.
    local function inCombat()
        return k.client.inCombat() ~= false
    end

    local function sweep(list)
        local kept = 0
        for i = 1, #list do
            local job = list[i]
            list[i] = nil
            if not job.dead then
                kept = kept + 1
                list[kept] = job
            end
        end
    end

    tick = function()
        ticking = true
        tickCount = tickCount + 1
        local now = k.client.now()
        local count = #jobs      -- jobs added during this tick wait for the next
        for i = 1, count do
            local job = jobs[i]
            if not job.dead then
                if job.frame then
                    if job.born < tickCount then
                        job.dead = true
                        run(job)
                    end
                elseif now >= job.due - 1e-9 then
                    if job.when == "outOfCombat" and inCombat() then
                        -- held: it runs on the first frame after combat
                    elseif job.interval then
                        job.due = now + job.interval
                        run(job)
                    else
                        job.dead = true
                        run(job)
                    end
                end
            end
        end
        sweep(jobs)
        ticking = false
        sync()
    end

    local function add(list, job)
        if type(job.owner) ~= "string" or job.owner == "" or type(job.fn) ~= "function"
            or (job.seconds ~= nil and (type(job.seconds) ~= "number" or job.seconds < 0 or job.seconds ~= job.seconds)) then
            k.problems:add("sched", tostring(job.owner), "bad " .. job.label .. " job")
            return function() end
        end
        list[#list + 1] = job
        sync()
        return function()
            job.dead = true
            if not ticking then
                sweep(list)
                sync()
            end
        end
    end

    function sched:every(owner, seconds, fn, opts)
        local when = opts and opts.when or "always"
        if when ~= "always" and when ~= "outOfCombat" then
            k.problems:add("sched", tostring(owner), "unknown when: " .. tostring(when))
            return function() end
        end
        if type(seconds) ~= "number" or seconds <= 0 or seconds ~= seconds then
            k.problems:add("sched", tostring(owner), "bad every job")
            return function() end
        end
        return add(jobs, { owner = owner, fn = fn, label = "every", seconds = seconds,
            interval = seconds, due = k.client.now() + seconds, when = when })
    end

    function sched:after(owner, seconds, fn)
        return add(jobs, { owner = owner, fn = fn, label = "after", seconds = seconds,
            due = k.client.now() + (type(seconds) == "number" and seconds or 0) })
    end

    function sched:nextFrame(owner, fn)
        return add(jobs, { owner = owner, fn = fn, label = "nextFrame", frame = true, born = tickCount })
    end

    function sched:afterCombat(owner, fn)
        local job = { owner = owner, fn = fn, label = "afterCombat" }
        if self.enabled and not inCombat() and type(owner) == "string" and owner ~= "" and type(fn) == "function" then
            run(job)
            return function() end
        end
        return add(waiting, job)
    end

    -- Runs the afterCombat queue; the kernel does not call this, the combat
    -- end event does.
    function sched:flushCombat()
        if not self.enabled or inCombat() then return end
        local batch = waiting
        waiting = {}
        for i = 1, #batch do
            if not batch[i].dead then run(batch[i]) end
        end
        sync()
    end

    function sched:off(owner)
        for i = 1, #jobs do
            if jobs[i].owner == owner then jobs[i].dead = true end
        end
        for i = 1, #waiting do
            if waiting[i].owner == owner then waiting[i].dead = true end
        end
        if not ticking then
            sweep(jobs)
            sweep(waiting)
            sync()
        end
    end

    function sched:report()
        return k.meter:report()
    end

    -- How much work waits for combat to end: the afterCombat queue and the
    -- outOfCombat jobs that are due. 0 when the player is plainly out of
    -- combat. The second answer is true when the client could not say
    -- whether the player is in combat, so the wait may never end.
    function sched:held()
        local state = k.client.inCombat()
        if state == false then return 0, false end
        local n, now = 0, k.client.now()
        for i = 1, #waiting do
            if not waiting[i].dead then n = n + 1 end
        end
        for i = 1, #jobs do
            local job = jobs[i]
            if not job.dead and job.when == "outOfCombat" and now >= job.due - 1e-9 then n = n + 1 end
        end
        return n, state == nil
    end

    function sched:enable()
        self.enabled = true
        sync()
        self:flushCombat()
    end

    return sched
end
