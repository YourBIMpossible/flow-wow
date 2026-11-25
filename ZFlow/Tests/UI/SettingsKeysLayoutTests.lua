local _, ns = ...

-- Tests for the self button key in the Combined button layout (lead section
-- 624 Step 5; UI/SettingsKeys.lua): the key is refused, with the agreed
-- words, while the layout is Combined. Pure part.

local tests = {}

local function SK() return ns.SettingsKeys end

tests["keys: the self button key is refused in the Combined layout"] = function(t)
    t.eq(SK().CombinedWhy("selfButton", "combined"), "Combined layout: the Flow button's key casts your buffs too.")
end

tests["keys: the self button key is taken in the Separate layout or with no layout"] = function(t)
    t.eq(SK().CombinedWhy("selfButton", "separate"), nil)
    t.eq(SK().CombinedWhy("selfButton", nil), nil)
end

tests["keys: the Flow button key is taken in either layout"] = function(t)
    t.eq(SK().CombinedWhy("flowButton", "combined"), nil)
    t.eq(SK().CombinedWhy("careKey", "combined"), nil)
end

-- Lead sections 647 item 3a, 797: in the Combined layout with the self
-- button switched off, the self key's row gives the Combined refusal, not
-- "switch it on first" (the self button is never made in that layout).
-- Through SK.New's rows with a stand-in settings table. Fails before
-- ff04a768: the switch-on check came first.
tests["keys: Combined with the self button off says Combined, not switch it on"] = function(t)
    local c = ns.make.fakeClient()
    c.setLockdown(false)
    if type(c.setBindings) == "function" then c.setBindings({}) end
    local values = { [SK().LAYOUT_SETTING] = "combined", [ns.FlowButton.SELF_SETTING] = false }
    local settings = {
        row = function(_, key) if key == SK().LAYOUT_SETTING then return { key = key } end return nil end,
        get = function(_, key) return values[key] end,
    }
    local keys = SK().New({ id = ns.id, settings = settings })
    keys.attach(c)
    local selfRow
    for _, r in ipairs(keys.rows()) do
        if r.key == "keys.self" then selfRow = r end
    end
    t.ok(selfRow ~= nil, "the self key row")
    t.eq(selfRow and selfRow.why, SK().COMBINED_WHY, "the Combined refusal comes first")
    t.eq(selfRow and selfRow.settable, false)
    values[SK().LAYOUT_SETTING] = "separate"
    for _, r in ipairs(keys.rows()) do
        if r.key == "keys.self" then selfRow = r end
    end
    t.ok(selfRow and type(selfRow.why) == "string" and selfRow.why:find("Switch on", 1, true) ~= nil,
        "Separate, the button off: switch it on first: " .. tostring(selfRow and selfRow.why))
end

return tests
