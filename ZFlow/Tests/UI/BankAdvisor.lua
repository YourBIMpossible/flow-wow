local _, ns = ...

-- Tests for the bank list's advisor prompt (L6-D follow-up, §111): when
-- there is something to bank, ZFlow/UI/BankList.lua registers one prompt
-- with the advisor (UI/Advisor.lua, U-A) and takes it away when there is
-- nothing, or when that can't be told. The advisor is the real one
-- (Advisor.Declare(k)); the tests read its List() and count the calls that
-- reach its Add and Remove.

local L, Present = ns.BankList, ns.ItemPresent
local tests = {}
-- Item names carry the game's quality colour (Items/Present.lua, Tint; the
-- colour itself is tested in Tests/Items/ItemColourTests.lua). These tests are
-- about the words, so they read them with the colour taken off.
local plain = ns.ItemPresent.Plain

local INFO = {
    [2589] = { name = "Linen Cloth", quality = 1, sellPrice = 13, classID = 7 },
    [2318] = { name = "Light Leather", quality = 1, sellPrice = 15, classID = 7 },
    [858] = { name = "Lesser Healing Potion", quality = 1, sellPrice = 20, classID = 0 },
}

local function info(item)
    local i = INFO[ns.Items.Id(item) or 0]
    if not i then return nil end
    local out = {}
    for k, v in pairs(i) do out[k] = v end
    return out
end

-- opts: bag (stacks; false: unread), advisor (false: none), setting, noInfo,
-- away (true: the bank is not opened). Since lead sections 340/341 the
-- prompt is raised only at the bank, so start opens it unless told not to.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    if opts.bag ~= false then c.setBagItems(opts.bag or { { item = 2589, count = 20 }, { item = 2318, count = 4 } }) end
    if not opts.noInfo then
        if type(c.setItemInfo) == "function" then c.setItemInfo(INFO) else c.itemInfo = info end
    end
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
    if opts.setting ~= nil then
        k:Setting({ key = L.SETTING, scope = "char", type = "bool", default = true, label = "Bank list" })
    end
    local api = L.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    if opts.setting == false then k.settings:set(L.SETTING, false) end
    c.fire("PLAYER_ENTERING_WORLD")
    if not opts.away then c.setBankOpen(true) end
    return k, c, api, prompts, calls
end

-- Words changed (sections 340/341): the prompt names the items, not a count of kinds.
tests["bank prompt words: the items by name, or nothing to say"] = function(t)
    t.eq(Present.BankPrompt({ ok = true, rows = { { name = "A", count = 2 }, { name = "B" }, {} }, unread = 0 }),
        "Bank: A x2, B, item not read yet")
    t.eq(Present.BankPrompt({ ok = true, rows = { { name = "Linen Cloth", count = 1 } }, unread = 0 }),
        "Bank: Linen Cloth x1")
    t.eq(Present.BankPrompt({ ok = true, rows = {}, unread = 0 }), nil, "nothing to bank: no prompt")
    t.eq(Present.BankPrompt({ ok = true, rows = {}, unread = 4 }), nil, "can't tell: no prompt, not a guess")
    t.eq(Present.BankPrompt({ ok = false, rows = {} }), nil, "bags not read: no prompt")
    t.eq(Present.BankPrompt(nil), nil)
end

-- At the bank now, not on entering the world (sections 340/341).
tests["bank prompt: at the bank, what could be banked is one prompt"] = function(t)
    local _, _, _, away = start({ away = true })
    t.eq(away[L.PROMPT_ID], nil, "away from the bank: none")
    local _, _, _, prompts = start()
    local p = prompts[L.PROMPT_ID]
    t.eq(L.PROMPT_ID, "l6d.bank")
    t.ok(p ~= nil, "registered")
    t.eq(p and p.text, "Bank: Linen Cloth x20, Light Leather x4")
    t.eq(p.priority, L.PROMPT_PRIORITY)
end

-- The prompt now follows the bags at the bank and goes when it closes (sections 340/341).
tests["bank prompt: it follows the bags at the bank, and goes when the bank closes"] = function(t)
    local _, c, _, prompts = start()
    c.setBagItems({ { item = 2318, count = 4 } })       -- the linen went in
    c.fire(L.BAG_EVENT)
    t.eq(prompts[L.PROMPT_ID] and prompts[L.PROMPT_ID].text, "Bank: Light Leather x4")
    c.setBankOpen(false)
    t.eq(prompts[L.PROMPT_ID], nil, "the bank closed: the prompt is gone")
    c.setBankOpen(true)
    c.setBagItems({ { item = 858, count = 5 } })
    c.fire(L.BAG_EVENT)
    t.eq(prompts[L.PROMPT_ID], nil, "nothing left to bank: the prompt is gone")
end

tests["bank prompt: nothing to bank, bags unread or facts unread: no prompt"] = function(t)
    local _, _, _, p1, calls1 = start({ bag = { { item = 858, count = 5 } } })
    t.eq(p1[L.PROMPT_ID], nil)
    t.eq(calls1.add, 0)
    local _, _, _, p2 = start({ bag = false })
    t.eq(p2[L.PROMPT_ID], nil, "bags not read")
    local _, _, _, p3 = start({ noInfo = true })
    t.eq(p3[L.PROMPT_ID], nil, "item facts not read: not known, so nothing is claimed")
end

tests["bank prompt: bank.list off gives no prompt, and takes one away"] = function(t)
    local _, _, _, prompts = start({ setting = false })
    t.eq(prompts[L.PROMPT_ID], nil)
    local k, c, _, prompts2 = start({ setting = true })
    t.ok(prompts2[L.PROMPT_ID] ~= nil)
    k.settings:set(L.SETTING, false)
    c.fire(L.BAG_EVENT)
    t.eq(prompts2[L.PROMPT_ID], nil, "turned off: removed at the next check")
end

tests["bank prompt: with no advisor the list still works"] = function(t)
    local k, c, api = start({ advisor = false, away = true })
    t.eq((k:ModuleState(L.NAME)), "started")
    c.setBankOpen(true)
    t.eq(api.shows(), 1)
end

tests["bank prompt: an advisor that refuses leaves the list working and no prompt behind"] = function(t)
    local k, c, api, prompts, calls = start({ refuse = true, away = true })
    c.setBankOpen(true)
    t.eq(calls.add, 1, "Add was reached, and refused")
    t.eq(prompts[L.PROMPT_ID], nil, "nothing was registered")
    t.eq((k:ModuleState(L.NAME)), "started")
    t.eq(api.shows(), 1, "the bank list still shows")
end

tests["bank prompt: an advisor that raises on Add and on Remove costs the module nothing"] = function(t)
    local k, c, api, _, calls = start({ raise = true, away = true })
    c.setBankOpen(true)
    t.eq(calls.add, 1, "Add was reached, and raised")
    t.eq((k:ModuleState(L.NAME)), "started", "the error did not switch the module off")
    t.eq(k.problems:count("handler"), 0, "nor count as a handler error")
    t.eq(api.shows(), 1, "the bank list still shows")
    c.setBagItems({ { item = 858, count = 5 } })
    c.setBankOpen(false)
    t.eq(calls.remove, 1, "Remove was reached, and raised")
    t.eq((k:ModuleState(L.NAME)), "started")
end

for name, fn in pairs(tests) do
    tests[name] = function(t)
        return fn(setmetatable({ eq = function(got, want, msg) return t.eq(plain(got), plain(want), msg) end },
            { __index = t }))
    end
end

return tests
