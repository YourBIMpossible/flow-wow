local _, ns = ...

-- The advisor's prompts as cards (all-windows row: Advice; the
-- modernization assessment's section 1). One card per prompt with
-- the icon of its kind, the prompt's words on the card, the
-- urgency carried as the card's tone; the "how many more" row is
-- a faded line that counts the rest in plain words. The plain
-- panel behind the kit keeps the same words as lines.
-- Red before the code: prompts are still line parts, the count
-- still reads "and N more", and there is no KIND_ICONS table.

local A = ns.Advisor
local tests = {}

local ID = "Advisor"

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    local api = A.Declare(k)
    k:Module({
        name = "fakePromptSource",
        needs = { A.NAME },
        start = function(ctx)
            local advisor = ctx.use(A.NAME)
            for _, p in ipairs(opts.prompts or {}) do advisor.Add(p[1], p[2], p[3], p[4]) end
        end,
    })
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api
end

local function parts(c)
    local w = c.kitWindows()[ID]
    if w == nil then return {} end
    return w.parts
end

local function byKind(c, kind)
    local out = {}
    for _, p in ipairs(parts(c)) do
        if p.kind == kind then out[#out + 1] = p end
    end
    return out
end

tests["advice cards: a prompt is a card with its kind's icon"] = function(t)
    t.ok(type(A.KIND_ICONS) == "table", "Advisor.KIND_ICONS")
    if type(A.KIND_ICONS) ~= "table" then return end
    t.ok(type(A.KIND_ICONS.repair) == "string", "a repair prompt has an icon")
    -- Plexy's changes (§945): the table is keyed on the kinds the
    -- shipped prompts actually use — the last part of their ids —
    -- and the four kinds no prompt uses are gone.
    for _, kind in ipairs({ "turnIn", "questHandIn", "progress", "riding", "trainer", "bank" }) do
        t.ok(type(A.KIND_ICONS[kind]) == "string", "a real prompt kind has an icon: " .. kind)
    end
    for _, kind in ipairs({ "vendor", "setup", "attune", "learn" }) do
        t.eq(A.KIND_ICONS[kind], nil, "no prompt uses this kind: " .. kind)
    end
    local _, c2 = start({ prompts = { { "quest.turnIn", "Ready to hand in: Test wolves.", 10 } } })
    local turnIn = byKind(c2, "card")
    t.eq(#turnIn, 1)
    local view2 = A.View({ "Ready to hand in: Test wolves." }, nil, nil, nil, { "turnIn" })
    local tree2
    ns.Kit.Each(view2, function(p) if p.kind == "card" then tree2 = p end end)
    t.ok(tree2 ~= nil and tree2.icon == A.KIND_ICONS.turnIn, "the turn-in card carries its icon")
    local _, c = start({ prompts = { { "l6c.repair", "Repair your gear.", 10 } } })
    local cards = byKind(c, "card")
    t.eq(#cards, 1, "one card for one prompt")
    t.eq(cards[1].text, "Repair your gear.")
    local view = A.View({ "Repair your gear." }, nil, nil, nil, { "repair" })
    local tree
    ns.Kit.Each(view, function(p) if p.kind == "card" then tree = p end end)
    t.ok(tree ~= nil, "the view's prompt part is a card")
    if tree then
        t.eq(tree.icon, A.KIND_ICONS.repair, "the card carries the kind's icon")
        t.eq(tree.wrap, true, "a prompt's words wrap on its card, never cut (section 408)")
    end
end

tests["advice cards: urgency is the card's tone, and stays on it as data"] = function(t)
    local view = A.View({ "Now one.", "Soon one.", "Info one." }, nil, nil,
        { "now", "soon", nil }, { "repair", "repair", "repair" })
    local tones, levels = {}, {}
    ns.Kit.Each(view, function(p)
        if p.kind == "card" then
            tones[#tones + 1] = p.tone
            levels[#levels + 1] = p.urgency
        end
    end)
    t.eq(tones, { "bad", "warn", nil }, "now reads bad, soon warn, info untinted")
    t.eq(levels, { "now", "soon" }, "the pressing levels stay on their cards")
end

tests["advice cards: the rest are counted on a faded line, in plain words"] = function(t)
    local _, c, api = start()
    local n = A.MAX_SHOWN + 2
    for i = 1, n do api.Add("p" .. i, "Prompt " .. i .. ".", i) end
    t.eq(#byKind(c, "card"), A.MAX_SHOWN, "the shown prompts are cards")
    local faded = byKind(c, "fadedLine")
    t.eq(#faded, 1, "one faded line")
    t.eq(faded[1].text, "2 more prompts", "a real count, in plain words")
    t.eq(A.MoreText(3), "3 more prompts")
end

tests["advice cards: no kind, no card — the empty words stay a line"] = function(t)
    local view = A.View({ A.NONE })
    local kinds = {}
    ns.Kit.Each(view, function(p) kinds[#kinds + 1] = p.kind end)
    t.eq(kinds[#kinds], "line", "a line with no kind is a line, as before")
    local _, c, api = start()
    api.Open()
    local rows = byKind(c, "line")
    t.eq(#rows, 1)
    t.eq(rows[1].text, A.NONE)
end

tests["advice cards: cards stand taller than the lines they replace"] = function(t)
    local lined = A.View({ "One.", "Two." })
    local carded = A.View({ "One.", "Two." }, nil, nil, nil, { "repair", "bank" })
    t.ok(carded.height > lined.height, "the window grows for its cards")
end

return tests
