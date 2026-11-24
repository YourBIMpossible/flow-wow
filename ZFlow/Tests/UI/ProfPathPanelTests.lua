local _, ns = ...

-- Tests for ZFlow/UI/ProfPathPanel.lua (lead section 449, P-PATH-2): the
-- pure parts. The one line, a bracket, a material, the folded and unfolded
-- view, and the minimap menu row. Every recipe and number is made up.
-- Offline test. Not tested in game.
-- Red before the code: ns.ProfPathPanel does not exist.

local tests = {}

local function P() return ns.ProfPathPanel end
local function has(t)
    t.eq(type(P()), "table", "ns.ProfPathPanel")
    return type(P()) == "table"
end

local PLAN = {
    id = "Blacksmithing", rev = 1, prof = "Blacksmithing", skill = 50, max = 75, status = "ok",
    selected = 1,
    ranges = {
        { from = 50, to = 60, recipe = "Test Buckle", crafts = 10, sure = true },
        { from = 60, to = 75, recipe = "Test Nail", crafts = 18, sure = false, learnAt = 50 },
    },
    materials = {
        { name = "Test Bar", need = 20, net = 0 },
        { name = "Test Ore", need = 12, net = 7 },
        { name = "Test Cloth", need = 3, net = "unknown", bankSeen = false },
    },
}

tests["prof path panel: no plan says it is not computed yet, never blank"] = function(t)
    if not has(t) then return end
    t.eq(P().Summary(nil, "Blacksmithing"), P().NOT_YET)
    t.eq(P().Summary(nil, nil), P().NO_PROF)
    t.eq(P().Summary({}, "Blacksmithing"), P().NOT_YET, "a plan with no skill read")
end

tests["prof path panel: the one line names the selected bracket"] = function(t)
    if not has(t) then return end
    t.eq(P().Summary(PLAN), "Blacksmithing 50/75: 50-60 Test Buckle")
    local done = { prof = "Blacksmithing", skill = 75, max = 75, ranges = {} }
    t.eq(P().Summary(done), "Blacksmithing 75/75: nothing more to plan")
end

tests["prof path panel: a bracket says how many crafts and when to train"] = function(t)
    if not has(t) then return end
    local said, right = P().RangeText(PLAN.ranges[1])
    t.eq(said, "50-60 Test Buckle")
    t.eq(right, "x10")
    said, right = P().RangeText(PLAN.ranges[2])
    t.eq(right, "about x18, Train at 50")
    t.eq(P().RangeText({ from = 1 }), nil)
end

tests["prof path panel: a material says short, have all, or bank not seen"] = function(t)
    if not has(t) then return end
    local _, right, tone = P().MaterialText(PLAN.materials[1])
    t.eq(right, "have all")
    t.eq(tone, "good")
    _, right, tone = P().MaterialText(PLAN.materials[2])
    t.eq(right, "short 7")
    t.eq(tone, "warn")
    _, right = P().MaterialText(PLAN.materials[3])
    t.eq(right, "bank not seen", "unknown stays unknown")
end

local function keys(view)
    local out = {}
    for _, c in ipairs(view.children) do out[#out + 1] = c.key end
    return table.concat(out, ",")
end

tests["prof path panel: folded it is one line; open it lists brackets and materials"] = function(t)
    if not has(t) then return end
    t.eq(keys(P().View({ plan = PLAN, open = false })), "head")
    local v = P().View({ plan = PLAN, open = true })
    t.eq(keys(v), "head,rangesHead,range1,range2,matsHead,mat1,mat2,mat3")
    t.eq(v.children[3].tone, "good", "the current bracket is marked")
    t.eq(v.children[4].tone, nil)
    local moved = P().View({ plan = PLAN, open = true, selected = 2 })
    t.eq(moved.children[4].tone, "good", "the bracket the player picked")
    t.eq(keys(P().View({ plan = nil, open = true, prof = "Mining" })), "head", "no plan: one line")
end

tests["prof path panel: the minimap menu has a row for it"] = function(t)
    if not has(t) then return end
    local found = false
    for _, item in ipairs(ns.MinimapButton.Menu({ prof = true })) do
        if item.key == "prof" then found = true end
    end
    t.ok(found, "a Profession path row")
    for _, item in ipairs(ns.MinimapButton.Menu({})) do
        t.ok(item.key ~= "prof", "no row when the panel is not there")
    end
end

return tests
