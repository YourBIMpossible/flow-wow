local _, ns = ...

-- Tests for ZFlow/Core/ApiReport.lua (FLOW-PARITY F-03; lead sections 580
-- item 7, 850): the "api" word's report, read from the client check the
-- diagnostics already save (diag.names from Diag.Save, diag.reads from
-- Diag.SaveReads), as Flow's /flow api (Core.lua:330-421) says which game
-- functions this client has. Fails before: there is no ApiReport.

local tests = {}

local function AR() return ns.ApiReport end

local function has(lines, text)
    for _, l in ipairs(lines) do
        if type(l) == "string" and l:find(text, 1, true) then return true end
    end
    return false
end

local DIAG = {
    names = { build = "1.16.1 (7777)", names = {
        GetBuildInfo = "function", UnitHealth = "function",
        ["C_Navigation.GetFrame"] = "nil", issecretvalue = "function", ["C_DamageMeter"] = "nil",
    } },
    reads = {
        { at = 10, build = "1.16.1 (7777)", reads = { secretFn = "function", aura = { failed = true }, gcd = {} } },
    },
}

tests["api report F-03: says the build, how many functions are there, and which are not"] = function(t)
    t.eq(type(AR()), "table")
    if type(AR()) ~= "table" then return end
    local lines = AR().Lines(DIAG)
    t.ok(has(lines, "1.16.1 (7777)"), "the build")
    t.ok(has(lines, AR().COUNT:format(3, 5)), table.concat(lines, " / "))
    t.ok(has(lines, "C_DamageMeter, C_Navigation.GetFrame"), "missing ones, a to z")
    t.ok(has(lines, AR().SECRET_YES), "hidden values")
    t.ok(has(lines, AR().FAILED .. "aura"), "a read that failed")
end

tests["api report F-03: nothing saved yet says so; a long missing list is cut"] = function(t)
    if type(AR()) ~= "table" then return t.ok(false, "no ApiReport") end
    t.eq(AR().Lines(nil), { AR().NONE })
    t.eq(AR().Lines({}), { AR().NONE })
    local many = {}
    for i = 1, AR().MISSING_MAX + 3 do many["Gone" .. string.format("%02d", i)] = "nil" end
    local lines = AR().Lines({ names = { build = "b", names = many } })
    t.ok(has(lines, AR().MORE:format(3)), table.concat(lines, " / "))
    t.ok(has(lines, AR().NO_READS), "no reads saved")
end

-- F-03 CHANGES-1 (lead section 856): "no" only when the check read
-- issecretvalue as "nil"; a read with no secretFn says it is not known.
tests["api report F-03: hidden values are no only when read as missing, else not known"] = function(t)
    if type(AR()) ~= "table" then return t.ok(false, "no ApiReport") end
    local function with(reads)
        return AR().Lines({ names = DIAG.names, reads = { { at = 1, reads = reads } } })
    end
    t.ok(has(with({ secretFn = "nil" }), AR().SECRET_NO), "read as missing")
    local unknown = with({ gcd = {} })
    t.ok(has(unknown, AR().SECRET_UNKNOWN), table.concat(unknown, " / "))
    t.ok(not has(unknown, AR().SECRET_NO), "never no without the read")
end

tests["api report F-03: Run reads the account's saved diagnostics"] = function(t)
    if type(AR()) ~= "table" then return t.ok(false, "no ApiReport") end
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { diag = DIAG })
    local lines = AR().Run(c, ns.id)
    t.ok(has(lines, AR().COUNT:format(3, 5)), table.concat(lines, " / "))
    t.eq(AR().Run(nil, ns.id), { AR().NONE })
end

return tests
