local _, ns = ...

-- Tests for the repair warning's advisor prompt (L6-C follow-up, §111):
-- while gear is low, ZFlow/Items/Repair.lua registers one prompt with the
-- advisor (UI/Advisor.lua, U-A) and takes it away when gear is fine again.
-- The advisor is the real one (Advisor.Declare(k)); the tests read its
-- List() and count the calls that reach its Add and Remove.

local R = ns.Repair
local tests = {}

local function setDurability(c, readings)
    if type(c.setDurability) == "function" then return c.setDurability(readings) end
    c.durability = function()
        if readings == nil then return nil end
        local out = {}
        for slot, r in pairs(readings) do out[slot] = { cur = r.cur, max = r.max } end
        return out
    end
end

-- opts: durability, advisor (false: none declared), refuse (Add answers false)
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    setDurability(c, opts.durability)
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    -- The real advisor (UI/Advisor.lua). `prompts[id]` reads its List() live;
    -- `calls` counts what reaches its Add and Remove.
    local calls = { add = 0, remove = 0 }
    local advisor
    local prompts = setmetatable({}, { __index = function(_, id)
        for _, p in ipairs(advisor and advisor.List() or {}) do
            if p.id == id then return { text = p.text, priority = p.priority } end
        end
        return nil
    end })
    if opts.advisor ~= false then
        advisor = ns.Advisor.Declare(k)
        local provided = k.use(ns.Advisor.NAME)
        local add, remove = provided.Add, provided.Remove
        provided.Add = function(...)
            calls.add = calls.add + 1
            if opts.raise then error("advisor add failed") end
            if opts.refuse then return false, "refused" end
            return add(...)
        end
        provided.Remove = function(...)
            calls.remove = calls.remove + 1
            if opts.raise then error("advisor remove failed") end
            return remove(...)
        end
    end
    local api = R.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api, prompts, calls
end

tests["repair prompt: low gear registers one prompt with the advisor"] = function(t)
    local _, _, _, prompts = start({ durability = { [5] = { cur = 10, max = 100 } } })
    local p = prompts[R.PROMPT_ID]
    t.eq(R.PROMPT_ID, "l6c.repair")
    t.ok(p ~= nil, "registered")
    t.eq(p.text, "An item you wear is at 10% durability. " .. R.NO_VENDOR, "one line: the warning as it is said in chat")
    t.eq(p.priority, R.PROMPT_PRIORITY)
end

tests["repair prompt: the advisor panel shows the line, and hides when gear is repaired"] = function(t)
    local _, c = start({ durability = { [5] = { cur = 10, max = 100 } } })
    local panel
    for _, p in ipairs(c.panels) do
        if type(p.spec) == "table" and p.spec.name == ns.id.framePrefix .. "Advisor" then panel = p end
    end
    t.ok(panel ~= nil, "the advisor's panel is there")
    t.eq(panel.shown, true)
    t.eq(panel.lines, { "An item you wear is at 10% durability. " .. R.NO_VENDOR })
    setDurability(c, { [5] = { cur = 100, max = 100 } })
    c.fire(R.EVENT)
    t.eq(panel.shown, false, "no prompts left: the panel hides")
end

tests["repair prompt: repaired gear takes the prompt away"] = function(t)
    local _, c, _, prompts = start({ durability = { [5] = { cur = 10, max = 100 } } })
    setDurability(c, { [5] = { cur = 100, max = 100 } })
    c.fire(R.EVENT)
    t.eq(prompts[R.PROMPT_ID], nil)
end

tests["repair prompt: a failed read leaves the prompt as it is"] = function(t)
    local _, c, _, prompts, calls = start({ durability = { [5] = { cur = 10, max = 100 } } })
    setDurability(c, nil)
    c.fire(R.EVENT)
    t.ok(prompts[R.PROMPT_ID] ~= nil, "not read is not fine: the prompt stays")
    t.eq(calls.remove, 0)
end

tests["repair prompt: a changed reading replaces the text under the same id"] = function(t)
    local _, c, _, prompts = start({ durability = { [5] = { cur = 10, max = 100 } } })
    setDurability(c, { [5] = { cur = 4, max = 100 } })
    c.fire(R.EVENT)
    t.eq(prompts[R.PROMPT_ID].text, "An item you wear is at 4% durability. " .. R.NO_VENDOR)
end

tests["repair prompt: fine gear from the start registers nothing"] = function(t)
    local _, _, _, prompts, calls = start({ durability = { [5] = { cur = 90, max = 100 } } })
    t.eq(prompts[R.PROMPT_ID], nil)
    t.eq(calls.add, 0)
end

tests["repair prompt: with no advisor the warning still works"] = function(t)
    local k, c, api = start({ durability = { [5] = { cur = 10, max = 100 } }, advisor = false })
    t.eq((k:ModuleState(R.NAME)), "started", "the module does not need the advisor to run")
    t.ok(api.current() ~= nil, "the warning is kept")
    local said = false
    for _, p in ipairs(c.printed) do
        if p:find("10% durability", 1, true) then said = true end
    end
    t.ok(said, "and said in chat")
end

tests["repair prompt: an advisor that refuses or raises does not stop the warning"] = function(t)
    local k, _, api = start({ durability = { [5] = { cur = 10, max = 100 } }, refuse = true })
    t.eq((k:ModuleState(R.NAME)), "started")
    t.ok(api.current() ~= nil)
end

tests["repair prompt: an advisor that raises on Add and on Remove costs the module nothing"] = function(t)
    local k, c, api, _, calls = start({ durability = { [5] = { cur = 10, max = 100 } }, raise = true })
    t.eq(calls.add, 1, "Add was reached, and raised")
    t.eq((k:ModuleState(R.NAME)), "started", "the error did not switch the module off")
    t.eq(k.problems:count("handler"), 0, "nor count as a handler error")
    t.ok(api.current() ~= nil, "the warning is kept")
    local said = 0
    for _, p in ipairs(c.printed) do
        if p:find("10% durability", 1, true) then said = said + 1 end
    end
    t.eq(said, 1, "and said in chat, once")
    setDurability(c, { [5] = { cur = 100, max = 100 } })
    c.fire(R.EVENT)
    t.eq(calls.remove, 1, "Remove was reached, and raised")
    t.eq(api.current(), nil, "repaired gear still clears the warning")
    t.eq((k:ModuleState(R.NAME)), "started")
end

return tests
