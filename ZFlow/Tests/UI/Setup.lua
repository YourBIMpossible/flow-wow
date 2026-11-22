local _, ns = ...

-- Tests for ZFlow/UI/Setup.lua (U-B, G53): setup suggestions. On a
-- character's first login with Z-Flow, the advisor (UI/Advisor.lua, U-A)
-- offers up to three suggested settings, each as text with the exact
-- `/zflow setting` command. Nothing is changed by it: the settings are read
-- through settings:get only, and the one thing written is Z-Flow's own
-- "offered" mark in the character's saved state.
-- The suggestions here are a hand-written test list. Fake client; not
-- tested in game.

local S = ns.Setup
local A = ns.Advisor
local tests = {}

-- The rows these tests declare: what the fake character can be offered.
local ROWS = {
    { key = "test.alpha", scope = "char", type = "bool", default = false, label = "Alpha" },
    { key = "test.beta", scope = "char", type = "bool", default = true, label = "Beta" },
    { key = "test.gamma", scope = "account", type = "number", default = 5, label = "Gamma", min = 1, max = 20 },
    { key = "test.delta", scope = "char", type = "choice", choices = { "Small", "Large" }, default = "Small", label = "Delta" },
    { key = "test.layout", scope = "account", type = "table", label = "A layout" },
}

local LIST = {
    { key = "test.alpha", value = true, why = "Alpha helps." },
    { key = "test.beta", value = false, why = "Beta is loud." },
    { key = "test.gamma", value = 10, why = "Gamma at 10 suits most." },
    { key = "test.delta", value = "Large", why = "Delta large reads better." },
}

-- opts: list (suggestions), char (character saved data), rows (false: none).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    if opts.char then c.setSaved(ns.id.charDB, opts.char) end
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    if opts.rows ~= false then
        for _, row in ipairs(ROWS) do k:Setting(row) end
    end
    local calls = {}
    if opts.countCalls then
        -- Record every settings call made for one of the suggested keys.
        for _, name in ipairs({ "get", "set", "reset", "row", "each", "available" }) do
            local real = k.settings[name]
            k.settings[name] = function(self, key, ...)
                if type(key) == "string" and key:find("^test%.") then
                    calls[#calls + 1] = name .. ":" .. key
                end
                return real(self, key, ...)
            end
        end
    end
    local advisor = A.Declare(k)
    local api = S.Declare(k, opts.list or LIST)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api, advisor, calls
end

local function texts(advisor)
    local out = {}
    for i, p in ipairs(advisor.List()) do out[i] = p.text end
    return out
end

tests["setup suggestions: the first login offers up to three, each with its exact command"] = function(t)
    local k, _, api, advisor = start()
    t.eq((k:ModuleState(S.NAME)), "started")
    t.eq(texts(advisor), {
        "Alpha helps. Type: /zflow setting test.alpha on",
        "Beta is loud. Type: /zflow setting test.beta off",
        "Gamma at 10 suits most. Type: /zflow setting test.gamma 10",
    }, "three, in list order")
    t.eq(#api.offered(), 3, "three offered")
    t.eq(S.MAX, 3)
end

tests["setup suggestions: the command words for each kind of row"] = function(t)
    t.eq(S.Command("a.b", true), "/zflow setting a.b on")
    t.eq(S.Command("a.b", false), "/zflow setting a.b off")
    t.eq(S.Command("a.b", 2.5), "/zflow setting a.b 2.5")
    t.eq(S.Command("a.b", "Large"), "/zflow setting a.b Large")
end

tests["setup suggestions: a setting already at the suggested value, or with no row, is not offered"] = function(t)
    local _, _, _, advisor = start({
        char = { settings = { test = { alpha = true } } },
        list = {
            { key = "test.alpha", value = true, why = "Already on." },
            { key = "test.missing", value = true, why = "No such row." },
            { key = "test.delta", value = "Large", why = "Delta large reads better." },
        },
    })
    t.eq(texts(advisor), { "Delta large reads better. Type: /zflow setting test.delta Large" }, "only the one that differs")
end

tests["setup suggestions: a table row or a bad entry is never offered"] = function(t)
    local _, _, _, advisor = start({ list = {
        { key = "test.layout", value = {}, why = "A table cannot be typed." },
        { key = "", value = true, why = "No key." },
        { key = "test.alpha", value = true, why = "" },
        { key = "test.alpha", value = nil, why = "No value." },
        "not a table",
    } })
    t.eq(texts(advisor), {}, "nothing offered")
end

tests["setup suggestions: it changes no setting and reads them only through settings:get"] = function(t)
    local k, _, _, _, calls = start({ countCalls = true })
    for _, call in ipairs(calls) do
        t.ok(call:find("^get:") ~= nil, "only get for a suggested key: " .. call)
    end
    t.ok(#calls > 0, "the suggested settings were read")
    t.eq(k.settings:get("test.alpha"), false, "alpha unchanged")
    t.eq(k.settings:get("test.beta"), true, "beta unchanged")
    t.eq(k.settings:get("test.gamma"), 5, "gamma unchanged")
end

tests["setup suggestions: offered once per character; the next login offers nothing"] = function(t)
    local k, _, _, advisor = start()
    t.eq(k.store:get("char", S.OFFERED_PATH), true, "marked as offered")
    t.eq(#advisor.List(), 3)
    local _, _, api2, advisor2 = start({ char = { state = { setup = { offered = true } } } })
    t.eq(texts(advisor2), {}, "a later login: nothing")
    t.eq(#api2.offered(), 0)
end

tests["setup suggestions: nothing to offer leaves the character unmarked"] = function(t)
    local k, _, api, advisor = start({ list = {} })
    t.eq(texts(advisor), {})
    t.eq(#api.offered(), 0)
    t.eq(k.store:get("char", S.OFFERED_PATH), nil, "not marked, so a later list can still be offered")
end

tests["setup suggestions: the shipped list is a list of well-formed entries"] = function(t)
    t.ok(type(S.SUGGESTIONS) == "table", "a list")
    for i, s in ipairs(S.SUGGESTIONS) do
        t.ok(type(s.key) == "string" and s.key ~= "", "key: " .. i)
        t.ok(type(s.why) == "string" and s.why ~= "", "why: " .. i)
        t.ok(type(s.value) == "boolean" or type(s.value) == "number" or type(s.value) == "string", "value: " .. i)
    end
    t.ok(type(ns.setup) == "table", "the addon's own is declared")
end

tests["setup suggestions: Pick is pure and keeps list order"] = function(t)
    local values = { ["x.a"] = false, ["x.b"] = true, ["x.c"] = 1, ["x.d"] = false, ["x.e"] = false }
    local settings = { get = function(_, key) return values[key] end }
    local picks = S.Pick(settings, {
        { key = "x.a", value = true, why = "A." },
        { key = "x.b", value = true, why = "B." },
        { key = "x.c", value = 2, why = "C." },
        { key = "x.d", value = true, why = "D." },
        { key = "x.e", value = true, why = "E." },
    })
    t.eq(#picks, 3, "at most three")
    t.eq(picks[1].key, "x.a")
    t.eq(picks[2].key, "x.c")
    t.eq(picks[3].key, "x.d")
    t.eq(picks[1].text, "A. Type: /zflow setting x.a on")
    t.eq(values, { ["x.a"] = false, ["x.b"] = true, ["x.c"] = 1, ["x.d"] = false, ["x.e"] = false }, "nothing changed")
end

tests["setup suggestions: look only - no acting functions"] = function(t)
    local _, _, api = start()
    for _, tbl in ipairs({ S, api }) do
        for name in pairs(tbl) do
            local n = tostring(name):lower()
            t.ok(not (n:find("^set$") or n:find("apply") or n:find("click") or n:find("secure")),
                "no acting function: " .. n)
        end
    end
end

return tests
