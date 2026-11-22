-- S25 export (UI/Export.lua; ported from legacy Flow's Modules/Export.lua).
-- Hand-made reads only.
local _, ns = ...

local X = ns.Export
local tests = {}
local BAR = "|"

tests["export: a value is cleaned of what breaks a line or a field"] = function(t)
    t.eq(X.Clean(nil), "")
    t.eq(X.Clean(true), "1")
    t.eq(X.Clean(false), "0")
    t.eq(X.Clean(12), "12")
    t.eq(X.Clean(2.34), "2.3")
    t.eq(X.Clean(0 / 0), "", "not a number is left empty, never guessed")
    t.eq(X.Clean("a^b\nc"), "a b c")
    t.eq(X.Clean(BAR .. "cffff0000Red" .. BAR .. "r wolf"), "Red wolf")
    t.eq(X.Clean(BAR .. "Hitem:6948" .. BAR .. "h[Hearthstone]" .. BAR .. "h"), "[Hearthstone]")
    t.eq(X.Clean("a  " .. BAR .. "  b"), "a b")
end

tests["export: a record, and read back"] = function(t)
    local line = X.Line("quest", { { "id", 7 }, { "gone", nil }, { "complete", false }, { "title", "Wolves^Too" } })
    t.eq(line, "E^quest^id=7^complete=0^title=Wolves Too")
    local back = X.Parse(line)
    t.eq(back, { kind = "quest", id = "7", complete = "0", title = "Wolves Too" })
    t.eq(X.Parse("quest^id=7"), nil)
    t.eq(X.Parse(nil), nil)
end

tests["export: every record from the reads, in order, with a count at the end"] = function(t)
    local lines = X.Lines({
        at = 100, addon = "ZFlow", class = "DRUID", faction = "Alliance", level = 12, money = 345, bagsFree = 9,
        zone = { cont = 1, zone = 1438 }, position = { map = 1438, x = 0.5, y = 0.25 },
        quests = { { id = 7, title = "Wolves", complete = false, objectives = { { text = "Wolf: 2/8", done = false } } } },
        skills = { Mining = { skill = 40, max = 75 }, Herbalism = { skill = 1, max = 75 } },
    })
    t.eq(lines, {
        "E^export^v=1^at=100^addon=ZFlow",
        "E^you^class=DRUID^faction=Alliance^level=12^money=345^bagsfree=9^cont=1^zone=1438^map=1438^x=50^y=25",
        "E^quest^id=7^complete=0^n=1^title=Wolves",
        "E^obj^quest=7^i=1^done=0^text=Wolf: 2/8",
        "E^skill^rank=1^max=75^name=Herbalism",
        "E^skill^rank=40^max=75^name=Mining",
        "E^end^lines=7",
    })
end

tests["export: what is not read is left out, never guessed"] = function(t)
    local lines = X.Lines(nil)
    t.eq(lines, { "E^export^v=1", "E^you", "E^end^lines=3" })
    lines = X.Lines({ level = 0 / 0, quests = { "x", { id = 3, failed = true, complete = true } }, skills = { Mining = 5 } })
    t.eq(lines, { "E^export^v=1", "E^you", "E^quest^id=3^complete=1^failed=1^n=0", "E^end^lines=4" })
end

local function start()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setClass("DRUID")
    c.setLevel(12)
    c.setMoney(345)
    c.setClock(5000)
    c.setQuestLog({ { id = 7, title = "Wolves", complete = false, objectives = { { text = "Wolf: 2/8", done = false } } } })
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local api = X.Declare(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api
end

tests["export module: /zflow export keeps the lines for this character and says how many"] = function(t)
    local k, c, api = start()
    k.store:set("char", "learned.facts.profSkill", { Mining = { line = 186, skill = 40, max = 75, at = 1 } })
    local before = #c.printed
    c.slashes[ns.id.slash]("export")
    t.eq(#c.printed, before + 1, "the count only, no lines")
    t.ok(c.printed[before + 1]:find("export: 6 lines", 1, true) ~= nil, c.printed[before + 1])
    local saved = k.store:get("char", X.PATH)
    t.eq(saved.at, 5000)
    t.eq(saved.lines, api.lines())
    t.eq(saved.lines[3], "E^quest^id=7^complete=0^n=1^title=Wolves")
    t.eq(saved.lines[5], "E^skill^rank=40^max=75^name=Mining")
    t.ok(saved.lines ~= api.lines(), "a copy is saved")
end

tests["export module: export dump also prints every line"] = function(t)
    local _, c, api = start()
    local before = #c.printed
    c.slashes[ns.id.slash]("export dump")
    local lines = api.lines()
    t.eq(#c.printed, before + 1 + #lines)
    t.eq(c.printed[#c.printed], lines[#lines])
    t.eq(lines[#lines], "E^end^lines=" .. #lines)
end

return tests
