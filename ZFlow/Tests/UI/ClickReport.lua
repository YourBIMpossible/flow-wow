local _, ns = ...
-- F-32 (lead sections 788, 790): the `clicks` and `under` words, as Flow's
-- Modules/ClickCheck.lua (CC.What :43-49, CC.Problems :54-80, CC.Report
-- :86-104, the words :130-163): what each mouse button does on a unit
-- frame, a warning when a plain left or right click does nothing, and what
-- is under the mouse. Read and report only. Pure parts, then the words on
-- the whole add-on with a fake client. Made-up bindings. Fails before: no
-- CC.Report, and the words are not known.
local tests = {}

local function CC() return ns.ClickCheck end
local TARGET = { type = 3, actionID = 1, button = "LeftButton", modifiers = 0 }
local MENU = { type = 3, actionID = 2, button = "RightButton", modifiers = 0 }

tests["click report: what each button does, and a dead plain click"] = function(t)
    t.eq(type(CC().Report), "function", "CC.Report")
    if type(CC().Report) ~= "function" then return end
    t.eq(CC().Report(nil), { CC().CLICKS_UNKNOWN }, "not known")
    t.eq(CC().Report({}), { CC().CLICKS_NONE }, "none listed")
    local heal = { type = 1, actionID = 2050, button = "LeftButton", modifiers = 1 }
    local lines = CC().Report({ TARGET, MENU, heal }, function(id) return id == 2050 and "Lesser Heal" or nil end)
    t.eq(lines[1], "Left button: target it")
    t.eq(lines[2], "Right button: open its menu")
    t.eq(lines[3], "Modifier 1 + left button: cast Lesser Heal")
    t.eq(#lines, 3, "nothing wrong: no warning")
    local dead = CC().Report({ MENU, heal })
    t.eq(dead[#dead - 1], CC().WARN .. CC().DeadLine("left button", "Target", true))
    t.eq(dead[#dead], CC().FIX)
    t.eq(CC().Problems({ MENU, { type = 1, actionID = 5, button = "LeftButton", modifiers = 0 } }),
        { CC().DeadLine("left button", "Target", false) }, "Target has no button at all")
end

tests["click report: what is under the mouse"] = function(t)
    if type(CC().UnderLine) ~= "function" then return t.ok(false, "CC.UnderLine") end
    t.eq(CC().UnderLine(nil), CC().UNDER_UNKNOWN)
    t.eq(CC().UnderLine({}), CC().UNDER_NOTHING)
    t.eq(CC().UnderLine({ "PartyMemberFrame1", "WorldFrame" }), CC().UNDER:format("PartyMemberFrame1 > WorldFrame"))
end

local function boot()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(2, 10)
    return c, addon
end

local function said(c, from)
    local out = {}
    for i = from + 1, #c.printed do out[#out + 1] = tostring(c.printed[i]) end
    return out
end

tests["click report: the clicks and under words"] = function(t)
    local c = boot()
    local n = #c.printed
    c.slashes[ns.id.slash]("clicks")
    local lines = said(c, n)
    t.eq(lines[1], ns.id.title .. ": " .. CC().CLICKS_HEAD)
    t.eq(lines[2], "  " .. CC().CLICKS_UNKNOWN, "the client gives no click bindings yet")
    c.setClickBindings({ TARGET, MENU })
    n = #c.printed
    c.slashes[ns.id.slash]("clicks")
    lines = said(c, n)
    t.eq(lines[2], "  Left button: target it")
    t.eq(#lines, 3)
    n = #c.printed
    c.slashes[ns.id.slash]("under")
    t.eq(said(c, n)[1], ns.id.title .. ": " .. CC().UNDER_UNKNOWN)
    c.setMouseFoci({ "PartyMemberFrame1" })
    n = #c.printed
    c.slashes[ns.id.slash]("under")
    t.eq(said(c, n)[1], ns.id.title .. ": " .. CC().UNDER:format("PartyMemberFrame1"))
end

return tests
