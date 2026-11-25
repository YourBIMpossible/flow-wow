local _, ns = ...
-- F-34 (lead sections 792, 794), on zflow-btn-resize 97c6f747, which has
-- the Ctrl + wheel resize, its clamp and step (St.Scale, FB.SCALE_STEP) and
-- the saved size. What it lacks against Flow's handle (Modules/
-- MoveHandle.lua:96, "wheel to resize (N%)"): the size said on the button,
-- with how to change it. Pure. Fails before: no FB.SizeLine.
local tests = {}

local function FB() return ns.FlowButton end

tests["flow button size: the size line, as a share"] = function(t)
    t.eq(type(FB().SizeLine), "function", "FB.SizeLine")
    if type(FB().SizeLine) ~= "function" then return end
    t.eq(FB().SizeLine(1), FB().SIZE_LINE:format(100))
    t.eq(FB().SizeLine(0.55), FB().SIZE_LINE:format(55))
    t.eq(FB().SizeLine(2), FB().SIZE_LINE:format(200))
    t.eq(FB().SizeLine(nil), FB().SIZE_LINE:format(100), "not known: full size, the default")
    t.eq(FB().SizeLine(0 / 0), FB().SIZE_LINE:format(100))
    t.eq(FB().Tip("flow", "Nothing to cast.", nil, nil, 1.5),
        FB().FLOW_NAME .. ". Nothing to cast. " .. FB().SizeLine(1.5), "the Flow button's tip ends with it")
    t.eq(FB().Tip("self", "Nothing to cast.", nil, nil, 1.5), FB().SELF_NAME .. ". Nothing to cast.",
        "not on the self button, which does not resize")
end

return tests
