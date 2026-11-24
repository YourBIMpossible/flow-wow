-- Training advice (lead sections 387 R7, 388 b): a class-pack spell at or
-- below the player's level that the player has not learned gets one advisor
-- prompt, "Train Charge at your class trainer (improves DPS)"; the alerts
-- list numbers them in chat. Pure: a made-up pack, a fake advisor.
-- Red before the code: ns.TrainAdvice does not exist.
local _, ns = ...

local function fakeAdvisor()
    local items, a = {}, {}
    function a.Add(id, text, priority)
        if type(id) ~= "string" or id == "" or type(text) ~= "string" or text == "" then return false end
        items[id] = { id = id, text = text, priority = priority or 0 }
        return true
    end
    function a.Remove(id)
        if items[id] then items[id] = nil; return true end
        return false
    end
    function a.List()
        local out = {}
        for _, v in pairs(items) do out[#out + 1] = v end
        table.sort(out, function(x, y) return x.id < y.id end)
        return out
    end
    return a
end

local PACK = { spells = {
    ["Test Strike"] = { level = 1, improves = { "DPS" } },
    ["Test Charge"] = { level = 4, improves = { "DPS" } },
    ["Test Guard"] = { level = 6, improves = { "Tanking", "Health" } },
    ["Test Stance"] = { level = 6, improves = { "Tanking" }, note = "from a class quest" },
    ["Test Later"] = { level = 20, improves = { "DPS" } },
    ["Test Unread"] = { level = 2, improves = { "Mana" } },
} }
local KNOWN = { ["Test Strike"] = true, ["Test Charge"] = false, ["Test Guard"] = false,
    ["Test Stance"] = false, ["Test Later"] = false }
local function known(name) return KNOWN[name] end

local function T() return ns.TrainAdvice end

return {
    ["train advice: the module exists"] = function(t)
        t.eq(type(T()), "table", "ns.TrainAdvice")
        if type(T()) ~= "table" then return end
        t.eq(type(T().Prompts), "function")
        t.eq(type(T().Sync), "function")
    end,

    ["train advice: spells at your level you have not learned, lowest level first"] = function(t)
        if type(T()) ~= "table" then return t.ok(false, "ns.TrainAdvice") end
        local p = T().Prompts(PACK, 6, known)
        local texts = {}
        for i, x in ipairs(p) do texts[i] = x.text end
        t.eq(texts, {
            "Train Test Charge at your class trainer (improves DPS)",
            "Train Test Guard at your class trainer (improves Tanking and Health)",
        }, "known, above level, a class-quest spell and an unread one are left out")
        t.eq(p[1] and p[1].id, "aps.trainer.advice.Test Charge")
    end,

    ["train advice: no level, no pack or no reading: no prompt"] = function(t)
        if type(T()) ~= "table" then return t.ok(false, "ns.TrainAdvice") end
        t.eq(T().Prompts(PACK, nil, known), {})
        t.eq(T().Prompts(nil, 6, known), {})
        t.eq(T().Prompts(PACK, 6, nil), {})
    end,

    ["train advice: sync adds the prompts and removes the learned"] = function(t)
        if type(T()) ~= "table" then return t.ok(false, "ns.TrainAdvice") end
        local a = fakeAdvisor()
        local shown = T().Sync(a, PACK, 6, known, nil)
        t.eq(#a.List(), 2)
        KNOWN["Test Charge"] = true
        shown = T().Sync(a, PACK, 6, known, shown)
        KNOWN["Test Charge"] = false
        local ids = {}
        for i, x in ipairs(a.List()) do ids[i] = x.id end
        t.eq(ids, { "aps.trainer.advice.Test Guard" })
        t.eq(shown, { ["aps.trainer.advice.Test Guard"] = true })
    end,
}
