local _, ns = ...

-- Tests for ZFlow/Items/CraftHint.lua. Pure: recipes, prices and snapshots
-- are made up here. The item and recipe names are invented.

local H, P, R = ns.CraftHint, ns.ItemPlan, ns.Resources
local tests = {}

local NAMES = { hide = "Hide", thread = "Thread", bar = "Bar", ore = "Ore", kit = "Kit", plate = "Plate", rod = "Rod" }

local function recipes()
    return {
        ["make:kit"] = { makes = "kit", mats = { hide = 2, thread = 1 } },
        ["make:plate"] = { makes = "plate", mats = { bar = 2 } },
        ["make:bar"] = { makes = "bar", mats = { ore = 2 } },
        -- rod: 1 bar + 1 plate; the plate needs bars too, so the bar row is shared.
        ["make:rod"] = { makes = "rod", mats = { bar = 1, plate = 1 } },
    }
end
local function context(snapshot, extra)
    local c = { recipes = recipes(), snapshot = snapshot, book = {}, names = NAMES,
                sources = { hide = { gather = "Skinning" }, ore = { gather = "Mining" }, thread = { vendor = true } } }
    for k, v in pairs(extra or {}) do c[k] = v end
    return c
end
local function has(text, part)
    return type(text) == "string" and string.find(text, part, 1, true) ~= nil
end

tests["craft hint: says what to make and makes now only what the bags hold"] = function(t)
    local h = H.Build({ recipe = "make:kit", count = 4 },
        context(R.Fake({ bags = { hide = 5, thread = 9 }, bank = { hide = 10 }, money = 0 })))
    t.eq(h.ok, true, "ok")
    t.eq(h.title, "Make 4 x Kit", "title")
    t.eq(h.makeNow, 2, "5 hides in the bags make 2; the bank's are not in the bags")
    t.eq(h.button, { recipe = "make:kit", count = 2, text = "Make 2" }, "the button asks for exactly that many")
    t.ok(has(h.lines[1], "Make 4 x Kit"), "the title leads the lines")
end

tests["craft hint: the count comes from the plan, not from a second count"] = function(t)
    local snapshot = R.Fake({ bags = { hide = 8, thread = 8 }, bank = {}, money = 0 })
    local plan = P.Build({ recipe = "make:kit", count = 4 }, context(snapshot))
    snapshot.bags.hide = 0     -- the bags change after the plan was made
    t.eq(H.MakeNow(plan, recipes()["make:kit"]), 4, "the hint reads the plan it was given")
end

tests["craft hint: what another claim holds is not counted"] = function(t)
    local snapshot = R.Fake({ bags = { hide = 8, thread = 8 }, bank = {}, money = 0 })
    local grants = R.Resolve(snapshot, { { owner = "other", activity = "x", kind = "item", key = "hide", amount = 5 } })
    local h = H.Build({ recipe = "make:kit", count = 4 }, context(snapshot, { grants = grants }))
    t.eq(h.makeNow, 1, "3 free hides make 1")
end

tests["craft hint: everything there: make them all"] = function(t)
    local h = H.Build({ recipe = "make:kit", count = 2 },
        context(R.Fake({ bags = { hide = 10, thread = 5 }, bank = {}, money = 0 })))
    t.eq(h.makeNow, 2, "never more than asked for")
    t.eq(h.button.text, "Make 2", "button")
end

tests["craft hint: nothing in the bags: no button"] = function(t)
    local h = H.Build({ recipe = "make:kit", count = 2 }, context(R.Fake({ bags = {}, bank = {}, money = 0 })))
    t.eq(h.makeNow, 0, "none")
    t.eq(h.button, nil, "no button")
end

tests["craft hint: bags not read: the count is unknown, and there is no button"] = function(t)
    local h = H.Build({ recipe = "make:kit", count = 2 }, context({ money = 0 }))
    t.eq(h.makeNow, "unknown", "not 0: unknown")
    t.eq(h.button, nil, "no button on a guess")
    local found = false
    for _, line in ipairs(h.lines) do if has(line, "bags have not been read yet") then found = true end end
    t.ok(found, "the lines say why")
end

tests["craft hint: a material made first is not counted as in the bags"] = function(t)
    local h = H.Build({ recipe = "make:plate", count = 2 },
        context(R.Fake({ bags = { bar = 2, ore = 4 }, bank = {}, money = 0 })))
    t.eq(h.makeNow, 1, "2 bars now make 1 plate; the other needs smelting first")
end

tests["craft hint: a material shared with an inner craft is counted low, never high"] = function(t)
    local h = H.Build({ recipe = "make:rod", count = 1 },
        context(R.Fake({ bags = { bar = 1, plate = 0, ore = 0 }, bank = {}, money = 0 })))
    t.eq(h.makeNow, 0, "one bar and no plate make no rod")
end

tests["craft hint: a goal that can't be read gives one line and no button"] = function(t)
    local h = H.Build({ recipe = "make:none", count = 1 }, context(R.Fake({ bags = {} })))
    t.eq(h.ok, false, "not ok")
    t.eq(h.button, nil, "no button")
    t.eq(#h.lines, 1, "one line")
    t.eq(H.Build(nil, nil).ok, false, "nothing given is not an error")
end

tests["craft hint: upgrade lines say what is missing, or that the materials are unread"] = function(t)
    local lines = H.UpgradeLines({
        { recipe = "Boots", tag = "+3", missing = { "2 Stone", "4 Hide" } },
        { recipe = "Belt", tag = "+1", missing = {}, unread = true },
        { recipe = "Cap" },
    })
    t.eq(lines[1], "Boots (+3): needs 2 Stone, 4 Hide", "what is missing")
    t.ok(has(lines[2], "open this window again"), "unread materials")
    t.ok(not has(string.lower(lines[2]), "flow"), "no product name")
    t.eq(lines[3], "Cap: nothing missing", "no tag, nothing missing")
    t.eq(H.UpgradeLines(nil), {}, "no list, no lines")
end

tests["craft hint: an upgrade's materials are read from the snapshot"] = function(t)
    local mats = H.UpgradeMats({ mats = { bar = 6, hide = 2 } },
        R.Fake({ bags = { bar = 4 }, bank = { bar = 5 } }), NAMES)
    t.eq(#mats, 2, "one line per material")
    t.eq(mats[1].text, "6 x Bar: you have 4 (+5 in the bank)", "need, bags and bank")
    t.eq(mats[1].enough, true, "bags and bank together cover it")
    t.eq(mats[2].text, "2 x Hide: you have 0", "none")
    t.eq(mats[2].enough, false, "bank seen and empty: still to get")
end

tests["craft hint: upgrade materials with the bank unseen or the bags unread stay unknown"] = function(t)
    local unseen = H.UpgradeMats({ mats = { bar = 6, hide = 1 } }, R.Fake({ bags = { bar = 4, hide = 1 } }), NAMES)
    t.eq(unseen[1].enough, "unknown", "short in the bags, bank never seen")
    t.ok(has(unseen[1].text, "bank not seen yet"), unseen[1].text)
    t.eq(unseen[2].enough, true, "the bags alone cover it")
    local unread = H.UpgradeMats({ mats = { bar = 6 } }, {}, NAMES)
    t.eq(unread[1].enough, "unknown", "bags unread")
    t.eq(unread[1].text, "6 x Bar: bags not read yet", "no count is made up")
end

return tests
