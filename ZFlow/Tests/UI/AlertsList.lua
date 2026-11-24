local _, ns = ...
-- Alerts (P-QOL): the list of ways to improve said in chat at login and at
-- a level-up, as Flow's advisor did (flow-wow Modules/Advisor/Advisor.lua
-- lines 333-341: the top 3 six seconds after login when there are any, the
-- top 5 two seconds after a level-up, "nothing to improve" when empty).
-- On by default as Flow's advisor.enabled was. Made-up prompts.
local tests = {}

local A = ns.Alerts

-- opts.atStart: prompts there at login { { id, text, priority } };
-- opts.off: the list setting off before login.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    local advisor = ns.Advisor.Declare(k)
    A.Declare(k)
    k:Module({
        name = "fakePromptSource",
        needs = { ns.Advisor.NAME },
        start = function()
            for _, p in ipairs(opts.atStart or {}) do advisor.Add(p[1], p[2], p[3] or 0) end
        end,
    })
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    if opts.off then k.settings:set(A.LIST, false) end
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, advisor
end

local function lines(c, from)
    local out = {}
    for i = (from or 0) + 1, #c.printed do out[#out + 1] = tostring(c.printed[i]) end
    return out
end

local function has(list, text)
    for _, l in ipairs(list) do
        if l:find(text, 1, true) then return true end
    end
    return false
end

local FIVE = {
    { "a.1", "Train Heroic Strike", 50 }, { "a.2", "Repair your gear", 40 },
    { "a.3", "Bank the ore", 30 }, { "a.4", "Equip the better sword", 20 },
    { "a.5", "Learn First Aid", 10 }, { "a.6", "Sell the grey items", 5 },
}

tests["alerts list: on by default, filed under general"] = function(t)
    local k = start()
    local row = k.settings:row(A.LIST)
    t.eq(row and row.type, "bool")
    t.eq(row and row.group, "general")
    t.eq(k.settings:get(A.LIST), true)
end

tests["alerts list: at login, the top 3 after the login wait, once"] = function(t)
    local _, c = start({ atStart = FIVE })
    local from = #c.printed
    c.advance(A.LIST_LOGIN - 1, 2)
    t.eq(#lines(c, from), 0, "not before the wait")
    c.advance(2, 2)
    local got = lines(c, from)
    t.eq(#got, 4, table.concat(got, "\n"))
    t.ok(has({ got[1] }, A.LIST_HEAD), got[1])
    t.ok(has({ got[2] }, "1. Train Heroic Strike"), got[2])
    t.ok(has({ got[4] }, "3. Bank the ore"), got[4])
    c.advance(60, 10)
    t.eq(#lines(c, from), 4, "said once")
end

tests["alerts list: nothing to improve at login - nothing said"] = function(t)
    local _, c = start()
    local from = #c.printed
    c.advance(A.LIST_LOGIN + 5, 4)
    t.eq(#lines(c, from), 0)
end

tests["alerts list: a level-up says the top 5, or that there is nothing"] = function(t)
    local _, c = start({ atStart = FIVE })
    c.advance(A.LIST_LOGIN + 5, 4)
    local from = #c.printed
    c.fire("PLAYER_LEVEL_UP", 11)
    c.advance(A.LIST_LEVEL + 1, 2)
    local got = lines(c, from)
    t.eq(#got, 6, table.concat(got, "\n"))
    t.ok(has({ got[6] }, "5. Learn First Aid"), got[6])
    t.ok(not has(got, "Sell the grey items"), "only five")

    local _, e = start()
    e.advance(A.LIST_LOGIN + 5, 4)
    from = #e.printed
    e.fire("PLAYER_LEVEL_UP", 11)
    e.advance(A.LIST_LEVEL + 1, 2)
    got = lines(e, from)
    t.eq(#got, 1)
    t.ok(has(got, A.LIST_NONE), got[1])
end

tests["alerts list: off - nothing at login or at a level-up"] = function(t)
    local _, c = start({ atStart = FIVE, off = true })
    local from = #c.printed
    c.advance(A.LIST_LOGIN + 5, 4)
    c.fire("PLAYER_LEVEL_UP", 11)
    c.advance(A.LIST_LEVEL + 1, 2)
    t.eq(#lines(c, from), 0)
end

tests["alerts list: the pure lines, numbered, at most n"] = function(t)
    local list = { { text = "One" }, { text = "Two" }, { text = "Three" } }
    t.eq(A.ListLines(list, 2), { A.LIST_HEAD, "  1. One", "  2. Two" })
    t.eq(A.ListLines({}, 3), nil)
    t.eq(A.ListLines(nil, 3), nil)
end

return tests
