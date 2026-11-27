local _, ns = ...

-- The Professions panel as one panel (all-windows row 3; the
-- modernization assessment's section 3). The profession and its
-- skill stand at the top as a line and a bar that fills; the
-- next step is a card, not a line; each cheapest row says its
-- difficulty in words (never colour alone) and its cost in
-- coins; and a "Still to do" section gathers what ProfCard
-- (the next rank for this profession) and ProfLearn (a recipe
-- in the bags) already work out, instead of the player only
-- meeting them as advisor lines. Red before the code: the
-- panel is bare lines, there is no bar, no card, no section.

local tests = {}
local function D() return ns.ProfDock end

local NAMES = { [1] = "Test Ore", [2] = "Test Bar", [50] = "Test Buckle", [51] = "Test Nail" }
local BOOK = {
    ["Test Buckle"] = { profession = "Blacksmithing", makes = 50, mats = { [2] = 2 } },
    ["Test Nail"] = { profession = "Blacksmithing", makes = 51, mats = { [2] = 1 } },
}
local COLOURS = {
    ["Test Buckle"] = { optimal = { lo = 45, hi = 55 } },
    ["Test Nail"] = { medium = { lo = 48, hi = 60 } },
}
local function input()
    return { prof = "Blacksmithing", skill = 50, max = 75, book = BOOK, colours = COLOURS,
        bags = { [2] = 3 }, bank = {},
        price = function(item) return item == 2 and 100 or nil end,
        name = function(item) return NAMES[item] end }
end
local function keyed(view, key)
    for _, part in ipairs(view.children) do if part.key == key then return part end end
    return nil
end
local function rows()
    return D().Rows(input(), { info = function(item) return { name = NAMES[item], quality = 2 } end,
        icon = function(recipe) return "Interface\\Icons\\" .. recipe:gsub(" ", "") end })
end

tests["professions panel: the skill stands at the top as a bar that fills"] = function(t)
    local view = D().View({ prof = "Blacksmithing", skill = 50, max = 75, rows = {},
        next = D().Next({}, "no recipe", nil, input()) })
    local line, bar = keyed(view, "skill"), keyed(view, "skillBar")
    t.ok(line ~= nil and bar ~= nil, "a skill line and its bar")
    if not line or not bar then return end
    t.eq(line.text, "Blacksmithing")
    t.eq(line.right, "50 / 75")
    t.eq(bar.value, 50); t.eq(bar.max, 75); t.eq(bar.text, "50 / 75")
    t.eq(view.children[1], line, "at the very top")
    t.eq(view.children[2], bar)
    local tree = ns.Kit.Window(view)
    t.ok(tree ~= nil, "the kit takes the view")
    if tree then
        local share
        ns.Kit.Each(tree, function(p) if p.kind == "bar" then share = p.share end end)
        t.ok(share ~= nil and share > 0.66 and share < 0.67, "the bar is two thirds full")
    end
    local bare = D().View({ prof = "Blacksmithing", rows = {}, next = D().Next({}, "no recipe", nil, input()) })
    t.eq(keyed(bare, "skill"), nil, "the skill not read: no bar claimed")
    t.ok(D().Height({}, {}, { bar = true }) > D().Height({}, {}), "the bar stands taller")
end

tests["professions panel: the next step is a card"] = function(t)
    local view = D().View({ prof = "Blacksmithing", rows = rows(),
        next = D().Next({ { kind = "take_bank", item = 1, count = 6 } }, nil, nil, input()) })
    local card = keyed(view, "next")
    t.eq(card.kind, "card")
    t.eq(card.wrap, true, "a long step wraps, never cut")
    t.eq(card.text, "Take 6 Test Ore from the bank")
end

tests["professions panel: a cheapest row says its difficulty in words and its cost in coins"] = function(t)
    local view = D().View({ prof = "Blacksmithing", rows = rows(),
        next = D().Next({}, "no recipe", nil, input()) })
    local first, second = keyed(view, "row1"), keyed(view, "row2")
    t.ok(first.sub ~= nil and first.sub:find(D().CHANCE_SURE, 1, true) ~= nil,
        "orange says so in words: " .. tostring(first.sub))
    t.ok(second.sub ~= nil and second.sub:find(D().CHANCE_MIGHT, 1, true) ~= nil,
        "yellow says so in words: " .. tostring(second.sub))
    local coins = first.sub:match("· (.+)$")
    t.ok(coins ~= nil and coins ~= "", "the cost in coins on the row: " .. tostring(first.sub))
    t.eq(first.right, "Ready", "what to do stays at the right")
end

tests["professions panel: still to do gathers the rank and the bag recipes"] = function(t)
    local card = {
        { id = "aps.prof.Blacksmithing", text = "Blacksmithing is at its cap (75/75). Trainer seen: Test Smith. Expert costs 5 gold." },
        { id = "aps.prof.Tailoring", text = "Tailoring is at its cap (75/75)." },
    }
    local learn = {
        { id = "aps.proflearn.900", text = "Recipe: Test Charm is in your bags: use it to learn Test Charm." },
    }
    local todo = D().Todo(card, learn, "Blacksmithing")
    t.eq(#todo, 2, "this profession's rank, and the bag recipe; not another profession's")
    t.eq(todo[1].text, card[1].text)
    t.eq(todo[2].text, learn[1].text)
    local view = D().View({ prof = "Blacksmithing", rows = {}, todo = todo,
        next = D().Next({}, "no recipe", nil, input()) })
    t.eq(keyed(view, "todoHead").text, D().HEAD_TODO)
    t.eq(keyed(view, "todo1").text, card[1].text)
    t.eq(keyed(view, "todo1").wrap, true, "a long line wraps")
    t.ok(D().Height({}, {}, { todo = 2 }) > D().Height({}, {}), "the section stands taller")
    t.eq(#D().Todo(nil, nil, "Blacksmithing"), 0, "nothing known: nothing claimed")
end

return tests
