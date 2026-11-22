local _, ns = ...

-- Tests for the bank list's advisor prompt (L6-D follow-up, §111): when
-- there is something to bank, ZFlow/UI/BankList.lua registers one prompt
-- with the advisor (UI/Advisor.lua, U-A) and takes it away when there is
-- nothing, or when that can't be told. The advisor is the real one
-- (Advisor.Declare(k)); the tests read its List() and count the calls that
-- reach its Add and Remove.

local L, Present = ns.BankList, ns.ItemPresent
local tests = {}

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

-- opts: bag (stacks; false: unread), advisor (false: none), setting, noInfo
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
            return add(...)
        end
        provided.Remove = function(...)
            calls.remove = calls.remove + 1
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
    return k, c, api, prompts, calls
end

tests["bank prompt words: how many kinds of item, or nothing to say"] = function(t)
    t.eq(Present.BankPrompt({ ok = true, rows = { {}, {}, {} }, unread = 0 }), "3 kinds of item to put in the bank.")
    t.eq(Present.BankPrompt({ ok = true, rows = { {} }, unread = 0 }), "1 kind of item to put in the bank.")
    t.eq(Present.BankPrompt({ ok = true, rows = {}, unread = 0 }), nil, "nothing to bank: no prompt")
    t.eq(Present.BankPrompt({ ok = true, rows = {}, unread = 4 }), nil, "can't tell: no prompt, not a guess")
    t.eq(Present.BankPrompt({ ok = false, rows = {} }), nil, "bags not read: no prompt")
    t.eq(Present.BankPrompt(nil), nil)
end

tests["bank prompt: on entering the world, what could be banked is one prompt"] = function(t)
    local _, _, _, prompts = start()
    local p = prompts[L.PROMPT_ID]
    t.eq(L.PROMPT_ID, "l6d.bank")
    t.ok(p ~= nil, "registered")
    t.eq(p.text, "2 kinds of item to put in the bank.")
    t.eq(p.priority, L.PROMPT_PRIORITY)
end

tests["bank prompt: it follows the bags when the bank closes"] = function(t)
    local _, c, _, prompts = start()
    c.setBankOpen(true)
    c.setBagItems({ { item = 2318, count = 4 } })       -- the linen went in
    c.setBankOpen(false)
    t.eq(prompts[L.PROMPT_ID].text, "1 kind of item to put in the bank.")
    c.setBankOpen(true)
    c.setBagItems({ { item = 858, count = 5 } })
    c.setBankOpen(false)
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
    c.fire("PLAYER_ENTERING_WORLD")
    t.eq(prompts2[L.PROMPT_ID], nil, "turned off: removed at the next check")
end

tests["bank prompt: with no advisor the list still works"] = function(t)
    local k, c, api = start({ advisor = false })
    t.eq((k:ModuleState(L.NAME)), "started")
    c.setBankOpen(true)
    t.eq(api.shows(), 1)
end

return tests
