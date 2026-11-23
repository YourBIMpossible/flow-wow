-- The fake of c.kitWindow and c.kitProbe (Core/ClientFake.lua): what it
-- records of a kit window, and the test controls that stand in for the
-- player (a click, a choice, typed text, a drag, a close). Fake client only.
-- Fails before the fake: c.kitWindow is nil, so every window test fails its
-- first check ("the fake answers kitWindow", got nil); c.kitProbe is nil, so
-- the probe test fails "the fake answers kitProbe".
local _, ns = ...

local K = ns.Kit

-- A window of the parts the controls act on, its handle, the fake and what
-- the caller functions were told: got[name] = the list of first arguments.
local function open(t, extra)
    local c = ns.make.fakeClient()
    t.eq(type(c.kitWindow), "function", "the fake answers kitWindow")
    if type(c.kitWindow) ~= "function" then return nil end
    local got = {}
    local function fn(name)
        got[name] = {}
        return function(v)
            if v == nil then v = true end
            got[name][#got[name] + 1] = v
        end
    end
    local tree, why = K.Window({
        id = "FakeDemo", title = "Demo",
        children = {
            { kind = "header", key = "find", title = "Things", search = { onText = fn("search") } },
            { kind = "tabs", key = "tabs", items = { "One", "Two" }, onSelect = fn("tab") },
            { kind = "topicList", key = "topics", items = { "Bags", "Bank" }, onSelect = fn("topic") },
            { kind = "row", label = "Sell grey items", control = { kind = "checkbox", key = "grey", onToggle = fn("toggle") } },
            { kind = "row", label = "Key", control = { kind = "bind", onClick = fn("bind") } },
            { kind = "row", label = "Style", control = { kind = "choice", key = "style", items = { "A", "B", "C" }, onSelect = fn("choice") } },
            { kind = "row", label = "Size", control = { kind = "number", key = "size", value = 4, min = 1, max = 9, onChange = fn("number") } },
            { kind = "row", label = "Name", control = { kind = "text", key = "name", text = "a", onText = fn("text") } },
            { kind = "row", label = "Locked", enabled = false, reason = "Not now",
              control = { kind = "button", key = "locked", text = "Go", onClick = fn("locked") } },
            { kind = "button", key = "sell", text = "Sell", onClick = fn("button") },
            { kind = "button", key = "off", text = "Off", onClick = fn("off"), enabled = false },
            { kind = "scroll", children = {
                { kind = "itemLine", key = "cloth", name = "Linen Cloth", quality = 2, count = 4, money = 120005 },
            } },
            { kind = "footer", text = "Total", buttons = { { kind = "button", key = "refresh", text = "Refresh", onClick = fn("refresh") } } },
        },
    })
    t.ok(type(tree) == "table", "the tree: " .. tostring(why))
    local h = c.kitWindow("FakeDemo", tree, extra or {})
    return h, c, got, tree
end

local tests = {}

tests["fake kitWindow: the record holds the window and every part in Kit.Each order"] = function(t)
    local h, c, _, tree = open(t, { point = { "TOPLEFT", "TOPLEFT", 3, -4 }, width = 500, height = 400 })
    if h == nil then t.ok(false, "a handle") return end
    for _, name in ipairs({ "update", "show", "shown", "close", "art", "slot" }) do
        t.eq(type(h[name]), "function", "handle." .. name)
    end
    local rec = c.kitWindows().FakeDemo
    t.ok(type(rec) == "table", "a record by id")
    if type(rec) ~= "table" then return end
    t.eq(rec.shown, false, "a new window is hidden")
    t.eq(rec.point, { "TOPLEFT", "TOPLEFT", 3, -4 })
    t.eq({ rec.width, rec.height }, { 500, 400 })
    local want = {}
    K.Each(tree, function(part) want[#want + 1] = { kind = part.kind, path = part.path, key = part.key, text = K.TextOf(part) } end)
    t.eq(rec.parts, want)
    t.eq(rec.parts[1], { kind = "header", path = "1", key = "find", text = "Things" })
    h.show(true)
    t.eq(c.kitWindows().FakeDemo.shown, true)
    t.eq(h.shown(), true)
    rec.shown = false
    t.eq(c.kitWindows().FakeDemo.shown, true, "the record handed out is a copy")
end

tests["fake kitWindow: with no place or size given it is the tree's own"] = function(t)
    local h, c = open(t)
    if h == nil then t.ok(false, "a handle") return end
    local rec = c.kitWindows().FakeDemo
    t.eq(rec.point, { K.POINT[1], K.POINT[2], K.POINT[3], K.POINT[4] })
    t.eq({ rec.width, rec.height }, { K.WIDTH, K.HEIGHT })
end

tests["fake kitWindow: a click runs a button, a bind and a check box, by key or by path"] = function(t)
    local h, c, got = open(t)
    if h == nil then t.ok(false, "a handle") return end
    t.eq(c.kitClick("FakeDemo", "sell"), true)
    t.eq(c.kitClick("FakeDemo", "refresh"), true, "a footer button")
    t.eq(c.kitClick("FakeDemo", "5.1"), true, "the bind button, by its path")
    t.eq(c.kitClick("FakeDemo", "grey"), true)
    t.eq(c.kitClick("FakeDemo", "grey"), true)
    t.eq(#got.button, 1)
    t.eq(#got.refresh, 1)
    t.eq(#got.bind, 1)
    t.eq(got.toggle, { true, false }, "each click turns the box over")
    t.eq(c.kitClick("FakeDemo", "nothing"), false, "no such part")
    t.eq(c.kitClick("FakeDemo", "cloth"), false, "an item line takes no click")
    t.eq(c.kitClick("Nowhere", "sell"), false, "no such window")
end

tests["fake kitWindow: a disabled part, or a part in a disabled row, does not fire"] = function(t)
    local h, c, got = open(t)
    if h == nil then t.ok(false, "a handle") return end
    t.eq(c.kitClick("FakeDemo", "off"), false)
    t.eq(c.kitClick("FakeDemo", "locked"), false)
    t.eq(#got.off, 0)
    t.eq(#got.locked, 0)
end

tests["fake kitWindow: a choice, typed text and a number reach their own functions"] = function(t)
    local h, c, got = open(t)
    if h == nil then t.ok(false, "a handle") return end
    t.eq(c.kitSelect("FakeDemo", "tabs", 2), true)
    t.eq(c.kitSelect("FakeDemo", "topics", 2), true)
    t.eq(c.kitSelect("FakeDemo", "style", 3), true)
    t.eq(c.kitSelect("FakeDemo", "style", 4), false, "not one of its items")
    t.eq(c.kitSelect("FakeDemo", "sell", 1), false, "a button has nothing to choose")
    t.eq(c.kitType("FakeDemo", "find", "lin"), true)
    t.eq(c.kitType("FakeDemo", "name", "b"), true)
    t.eq(c.kitType("FakeDemo", "sell", "x"), false)
    t.eq(c.kitChange("FakeDemo", "size", 7), true)
    t.eq(c.kitChange("FakeDemo", "size", 10), false, "above its max")
    t.eq(c.kitChange("FakeDemo", "name", 1), false)
    t.eq(got.tab, { 2 })
    t.eq(got.topic, { 2 })
    t.eq(got.choice, { 3 })
    t.eq(got.search, { "lin" })
    t.eq(got.text, { "b" })
    t.eq(got.number, { 7 })
end

tests["fake kitWindow: the player closing it tells onClose once; a drag tells onMoved"] = function(t)
    local closed, moves = 0, {}
    local h, c = open(t, { onClose = function() closed = closed + 1 end,
        onMoved = function(point, w, ht) moves[#moves + 1] = { point, w, ht } end })
    if h == nil then t.ok(false, "a handle") return end
    t.eq(c.kitClose("FakeDemo"), false, "not shown: nothing to close")
    h.show(true)
    t.eq(c.kitClose("FakeDemo"), true)
    t.eq(closed, 1)
    t.eq(h.shown(), false)
    c.kitClose("FakeDemo")
    t.eq(closed, 1, "once")
    h.show(true)
    h.close()
    t.eq(closed, 1, "the add-on closing it is not the player")
    t.eq(h.shown(), false)
    t.eq(c.kitDrag("FakeDemo", { "TOPLEFT", "TOPLEFT", 9, -9 }, 430, 500), true)
    t.eq(moves, { { { "TOPLEFT", "TOPLEFT", 9, -9 }, 430, 500 } })
    local rec = c.kitWindows().FakeDemo
    t.eq(rec.point, { "TOPLEFT", "TOPLEFT", 9, -9 })
    t.eq({ rec.width, rec.height }, { 430, 500 })
end

tests["fake kitWindow: a caller function that raises goes to failed, as on the real client"] = function(t)
    local c = ns.make.fakeClient()
    t.eq(type(c.kitWindow), "function", "the fake answers kitWindow")
    if type(c.kitWindow) ~= "function" then return end
    local errs = {}
    local tree = K.Window({ id = "FakeBoom", title = "Boom", children = {
        { kind = "button", key = "boom", text = "Boom", onClick = function() error("boom-click") end },
    } })
    local h = c.kitWindow("FakeBoom", tree, { failed = function(err) errs[#errs + 1] = tostring(err) end })
    t.ok(h ~= nil, "a handle")
    local ok = pcall(c.kitClick, "FakeBoom", "boom")
    t.ok(ok, "the click does not raise")
    t.eq(#errs, 1)
    t.ok(errs[1] ~= nil and errs[1]:find("boom-click", 1, true) ~= nil, "with the error")
end

tests["fake kitWindow: update replaces the parts; the slot and the art answer"] = function(t)
    local h, c = open(t)
    if h == nil then t.ok(false, "a handle") return end
    local small = K.Window({ id = "FakeDemo", title = "Small", children = {
        { kind = "empty", text = "No bank data yet.", how = "Open your bank once." },
        { kind = "footer", slot = "sellAction" },
    } })
    t.eq(h.update(small), true)
    local rec = c.kitWindows().FakeDemo
    t.eq(#rec.parts, 2)
    t.eq(rec.parts[1], { kind = "empty", path = "1", text = "No bank data yet." })
    t.eq(c.kitClick("FakeDemo", "sell"), false, "the old button is gone")
    t.eq(type(h.slot("sellAction")), "table", "a slot the tree names")
    t.eq(h.slot("other"), nil)
    t.eq(h.art().frame, "fallback", "the fake draws as the default client does")
    t.eq(h.update(nil), false)
    t.eq(#c.kitWindows().FakeDemo.parts, 2, "a bad tree changes nothing")
end

tests["fake kitWindow: setKitFails makes the next windows fail, then it works again"] = function(t)
    local c = ns.make.fakeClient()
    t.eq(type(c.kitWindow), "function", "the fake answers kitWindow")
    if type(c.kitWindow) ~= "function" then return end
    local tree = K.Window({ id = "FakeFail", title = "Fail", children = {} })
    local told = 0
    c.setKitFails(2)
    t.eq(c.kitWindow("FakeFail", tree, { failed = function() told = told + 1 end }), nil)
    t.eq(c.kitWindow("FakeFail", tree, {}), nil)
    t.eq(told, 1, "failed is told, as the real client tells it")
    t.eq(c.kitWindows().FakeFail, nil, "nothing recorded")
    t.ok(c.kitWindow("FakeFail", tree, {}) ~= nil, "the third works")
    c.setFrames(false)
    t.eq(c.kitWindow("FakeOther", K.Window({ id = "FakeOther", title = "Other", children = {} }), {}), nil,
        "a client that cannot make frames")
end

return tests
