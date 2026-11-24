local _, ns = ...
-- Lead section 402 item 4 (G19): buy-tool and buy-materials steps, with the
-- cost. The gathering tool comes from a vendor only, never the auction
-- house; a material with no vendor price seen still offers the auction
-- house (lead section 407 item 1). The cost is a vendor
-- price this account saw (learned.prices). Through the real planner entry
-- (addon.profPlan.plan) on the whole add-on and a fake client; made-up items
-- and prices. Nothing is bought: the step is a line. Not tested in game.
local tests = {}

local PICK, BAR = 2901, 2
local BOOK = { ["Test Belt"] = { profession = "Blacksmithing", makes = 50, mats = { [BAR] = 2 } } }
local COLOURS = { ["Test Belt"] = { optimal = { lo = 45, hi = 60 } } }

local function book(vendor)
    local b = {}
    for key, value in pairs(vendor or {}) do
        ns.Prices.Record(b, key, "vendor", value, { source = "merchant", seenAt = 1000 })
    end
    return b
end

local function cost(copper)
    return ns.Prices.Text({ value = copper, basis = ns.Prices.OBSERVED })
end

-- opts: prof, skill, bags ({ [item] = n }), vendor ({ [item] = copper })
local function start(opts)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { learned = { prices = book(opts.vendor) } })
    c.setSaved(ns.id.charDB, { learned = {
        facts = { profSkill = { [opts.prof] = { skill = opts.skill or 50, max = 75 } }, recipeBook = BOOK },
        recipeColors = COLOURS,
    } })
    c.setZone(1, 1411); c.setFaction("Horde"); c.setFacing(0)
    c.setPosition(1411, 0.5, 0.5); c.setMapSize(1411, 1000, 500); c.setMapCont(1411, 1)
    c.setItemInfo({ [PICK] = { name = "Mining Pick" }, [BAR] = { name = "Test Bar" } })
    local bags = {}
    for item, n in pairs(opts.bags or {}) do bags[#bags + 1] = { item = item, count = n } end
    c.setBagItems(bags)
    c.setProfessions({ opts.prof })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function kinds(steps)
    local out = {}
    for _, s in ipairs(steps or {}) do out[#out + 1] = s.kind end
    return out
end

tests["prof buy e2e: no pick in the bags, a vendor price seen: buy the pick first, with the cost"] = function(t)
    local _, addon = start({ prof = "Mining", skill = 30, vendor = { [PICK] = 82 } })
    local steps = addon.profPlan.plan("Mining")
    t.eq(kinds(steps), { "buy_tool", "gather_skill" })
    t.eq(steps[1] and steps[1].text, "Buy a Mining Pick from a vendor (" .. cost(82) .. ")")
    t.eq(steps[1] and steps[1].item, PICK)
    t.eq(steps[1] and steps[1].cost, 82)
end

tests["prof buy e2e: the pick in the bags: no buy step"] = function(t)
    local _, addon = start({ prof = "Mining", skill = 30, bags = { [PICK] = 1 }, vendor = { [PICK] = 82 } })
    t.eq(kinds(addon.profPlan.plan("Mining")), { "gather_skill" })
end

tests["prof buy e2e: no pick and no vendor price seen: the gather line alone, no guess"] = function(t)
    local _, addon = start({ prof = "Mining", skill = 30 })
    t.eq(kinds(addon.profPlan.plan("Mining")), { "gather_skill" })
end

tests["prof buy e2e: bars short, a vendor price seen: buy them from a vendor with the cost, then craft"] = function(t)
    local _, addon = start({ prof = "Blacksmithing", vendor = { [BAR] = 50 } })
    local steps = addon.profPlan.plan("Blacksmithing")
    t.eq(steps[1] and steps[1].kind, "buy_vendor")
    t.ok(steps[1] and steps[1].text:find("from a trade goods vendor (" .. cost(50) .. " each)", 1, true) ~= nil,
        "the cost is on the line: " .. tostring(steps[1] and steps[1].text))
    t.eq(steps[#steps] and steps[#steps].kind, "craft")
end

tests["prof buy e2e: bars short, no vendor price seen: the auction house (section 407)"] = function(t)
    local _, addon = start({ prof = "Blacksmithing" })
    local steps = addon.profPlan.plan("Blacksmithing")
    t.eq(steps[1] and steps[1].kind, "buy_auction", "a material, not the tool")
    t.eq(steps[#steps] and steps[#steps].kind, "craft")
end

return tests
