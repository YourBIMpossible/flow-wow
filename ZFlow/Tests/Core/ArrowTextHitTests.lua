-- A1-22 (section 844): the hit over an arrow's text, through the fake
-- client (Core/ClientFake.lua h.textClick / h.textHover). No game client.
local _, ns = ...

local tests = {}

tests["arrow text hit: a click on the text reaches onTextClick"] = function(t)
    local c = ns.make.fakeClient()
    local h = c.arrow({ name = "ProfArrow" })
    local got = {}
    h.onTextClick(function(button) got[#got + 1] = button end)
    h.show(true)
    h.text({ "Train Skinning" }, { "BOTTOM", "TOP", 0, 4 })
    h.textClick("left")
    h.textClick("right")
    t.eq(#got, 2, "two clicks told")
    t.eq(got[1], "left", "left")
    t.eq(got[2], "right", "right")
end

tests["arrow text hit: no text, no click and no hover"] = function(t)
    local c = ns.make.fakeClient()
    local h = c.arrow({ name = "ProfArrow" })
    local told = 0
    h.onTextClick(function() told = told + 1 end)
    h.onTextHover(function() told = told + 1 end)
    h.show(true)
    h.textClick("left")
    h.textHover(true)
    t.eq(told, 0, "nothing told without text")
end

tests["arrow text hit: hover comes and goes"] = function(t)
    local c = ns.make.fakeClient()
    local h = c.arrow({ name = "ProfArrow" })
    local seen = {}
    h.onTextHover(function(on) seen[#seen + 1] = on end)
    h.show(true)
    h.text({ "x" }, { "TOP", "BOTTOM", 0, -2 })
    h.textHover(true)
    h.textHover(false)
    t.eq(seen[1], true, "comes")
    t.eq(seen[2], false, "goes")
end

return tests
