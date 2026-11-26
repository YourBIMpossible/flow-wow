local _, ns = ...

-- Tests for ZFlow/UI/KeyBindingNames.lua and ZFlow/Bindings.xml
-- (FLOW-PARITY F-19; lead sections 580 item 10, 850): one entry in the
-- game's Key Bindings screen under a Z-Flow heading, as Flow's Bindings.xml
-- (one CLICK binding on its cast button under a FLOW header). The binding
-- clicks the rotation key button Rotation/KeyFrame.lua makes
-- (ns.id.framePrefix .. "RotationKey"); no secure attribute is changed.
-- The XML itself is checked in game only. Fails before: no KeyBindingNames.

local tests = {}

local function KB() return ns.KeyBindingNames end

tests["key binding F-19: the binding clicks the rotation key button, under a Z-Flow heading"] = function(t)
    t.eq(type(KB()), "table")
    if type(KB()) ~= "table" then return end
    t.eq(KB().ACTION, "CLICK " .. ns.id.framePrefix .. "RotationKey:LeftButton")
    t.eq(KB().HEADER, "ZFLOW")
end

tests["key binding F-19: the names the Key Bindings screen shows"] = function(t)
    if type(KB()) ~= "table" then return t.ok(false, "no KeyBindingNames") end
    local g = KB().Globals()
    t.eq(g["BINDING_HEADER_" .. KB().HEADER], KB().HEADER_TEXT)
    t.eq(g["BINDING_NAME_" .. KB().ACTION], KB().NAME_TEXT)
    local n = 0
    for _ in pairs(g) do n = n + 1 end
    t.eq(n, 2, "those two names only")
end

return tests
