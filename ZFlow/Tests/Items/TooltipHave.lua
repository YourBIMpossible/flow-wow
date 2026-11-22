local _, ns = ...

-- Tests for ZFlow/Items/TooltipHave.lua. Pure: the snapshot is made with
-- Resources.Fake, which makes nothing up.

local H = ns.TooltipHave
local Fake = ns.Resources.Fake
local tests = {}

local KEY = 2318

tests["have: bags and bank both known gives the total and each part, the bank labelled"] = function(t)
    local line = H.Line(Fake({ bags = { [KEY] = 5 }, bank = { [KEY] = 7 } }), KEY)
    t.eq(line, { text = "You have 12: 5 in bags, 7 in the bank (as of your last bank visit)", tone = "none" })
end

tests["have: only in the bags, with the bank seen"] = function(t)
    local line = H.Line(Fake({ bags = { [KEY] = 5 }, bank = {} }), KEY)
    t.eq(line.text, "You have 5 in bags, none in the bank (as of your last bank visit)")
end

tests["have: only in the bank, with the bags read"] = function(t)
    local line = H.Line(Fake({ bags = {}, bank = { [KEY] = 7 } }), KEY)
    t.eq(line.text, "You have 7 in the bank (as of your last bank visit), none in bags")
end

tests["have: the bank never seen is said, not counted as none"] = function(t)
    local line = H.Line(Fake({ bags = { [KEY] = 5 } }), KEY)
    t.eq(line.text, "You have 5 in bags (bank not seen yet)")
    line = H.Line(Fake({ bags = { [KEY] = 5 }, bank = { [KEY] = 9 }, bankKnown = false }), KEY)
    t.eq(line.text, "You have 5 in bags (bank not seen yet)", "a bank marked not seen is not counted")
end

tests["have: the bags not read is said, not counted as none"] = function(t)
    local line = H.Line(Fake({ bank = { [KEY] = 7 } }), KEY)
    t.eq(line.text, "You have 7 in the bank (as of your last bank visit); bags not read")
end

tests["have: nothing held that is known of is no line"] = function(t)
    t.eq(H.Line(Fake({ bags = {}, bank = {} }), KEY), nil, "none anywhere")
    t.eq(H.Line(Fake({ bags = { [99] = 4 }, bank = { [98] = 1 } }), KEY), nil, "other items only")
    t.eq(H.Line(Fake({ bags = {} }), KEY), nil, "none in bags, bank not seen: nothing known to say")
    t.eq(H.Line(Fake({ bank = {} }), KEY), nil, "none in the bank, bags not read")
    t.eq(H.Line(Fake({}), KEY), nil, "nothing read at all")
end

tests["have: no snapshot or no item is no line"] = function(t)
    t.eq(H.Line(nil, KEY), nil)
    t.eq(H.Line("bags", KEY), nil)
    t.eq(H.Line(Fake({ bags = { [KEY] = 5 } }), nil), nil)
end

tests["have: a count that is no whole number above zero is not counted"] = function(t)
    local nan = 0 / 0
    for _, bad in ipairs({ "5", -1, 2.5, nan, math.huge, true }) do
        local snapshot = { bags = { [KEY] = bad }, bank = { [KEY] = 7 }, bankKnown = true }
        t.eq(H.Line(snapshot, KEY).text, "You have 7 in the bank (as of your last bank visit); bags not read",
            tostring(bad) .. ": that count is not known")
    end
end

tests["have: a string key is found as it is"] = function(t)
    local line = H.Line(Fake({ bags = { ["item:2318:0"] = 3 } }), "item:2318:0")
    t.eq(line.text, "You have 3 in bags (bank not seen yet)")
end

tests["have: one of something reads the same way"] = function(t)
    t.eq(H.Line(Fake({ bags = { [KEY] = 1 }, bank = {} }), KEY).text,
        "You have 1 in bags, none in the bank (as of your last bank visit)")
end

tests["have: nothing handed in is changed, and the text has no product name or bar"] = function(t)
    local snapshot = Fake({ bags = { [KEY] = 5 }, bank = { [KEY] = 7 } })
    local line = H.Line(snapshot, KEY)
    t.eq(snapshot.bags, { [KEY] = 5 })
    t.eq(snapshot.bank, { [KEY] = 7 })
    t.ok(not line.text:lower():find("flow", 1, true))
    t.ok(not line.text:find("[|%c]"))
end

return tests
