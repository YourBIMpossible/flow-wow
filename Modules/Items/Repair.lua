-- Worn gear: an early warning, and a stop at the nearest repair vendor.
-- When any item you wear is under 20% durability (items without durability
-- don't count), a small status icon shows above Flow's key (hover: which
-- item, how worn, the nearest vendor Flow knows) and the route gets a
-- "Repair" stop. No chat lines beyond one when it first happens.
-- At the vendor, Vendor.lua repairs (after auto-sell, so the sale pays).

local _, ns = ...
local A = ns.api
local R = {}
ns.repair = R

R.THRESHOLD = 0.20   -- warn when any worn item is below this share of its durability
local SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }   -- (the slots that can wear)
local ICON = "Interface\\Icons\\Trade_BlackSmithing"

-- The most worn item: read(slot) -> cur, max (nil or max 0: no durability,
-- skipped). Returns pct (0..1), slot, how many are under the threshold; or
-- nil when nothing you wear has durability (or the game won't say).
function R.Worst(read, threshold)
    threshold = threshold or R.THRESHOLD
    local worst, slot, low = nil, nil, 0
    for _, s in ipairs(SLOTS) do
        local cur, max = read(s)
        if type(cur) == "number" and type(max) == "number" and max > 0 then
            local pct = cur / max
            if pct < threshold then low = low + 1 end
            if not worst or pct < worst then worst, slot = pct, s end
        end
    end
    return worst, slot, low
end

-- Warn? pct = R.Worst's first return (nil: unknown, never a warning).
function R.Low(pct, threshold)
    return pct ~= nil and pct < (threshold or R.THRESHOLD)
end

local function readSlot(slot)
    if not GetInventoryItemDurability then return nil end
    local ok, cur, max = pcall(GetInventoryItemDurability, slot)
    if not ok then return nil end
    return A.Safe(cur), A.Safe(max)
end

local cache, cacheAt = nil, -999
function R:State()
    local now = GetTime()
    if cache and now - cacheAt < 2 then return cache end
    local pct, slot, low = R.Worst(readSlot)
    cache, cacheAt = { pct = pct, slot = slot, low = low, warn = R.Low(pct) }, now
    return cache
end

function R:On() return not (ns.db.sell and ns.db.sell.repairWarn == false) end

-- The lines of the warning. st = R:State(); item = the worn item's name;
-- near = the nearest repair vendor { name, yards } or nil; scanning = the
-- vendor list is still loading; hearth = the hearthstone estimate line or nil.
function R.Lines(st, item, near, scanning, hearth, autoRepair)
    local out = { string.format("%s is at %d%% durability%s.", item or "An item you wear", math.floor(st.pct * 100 + 0.5),
        (st.low or 0) > 1 and string.format(" (%d items under %d%%)", st.low, R.THRESHOLD * 100) or "") }
    if near then
        out[#out + 1] = string.format("Nearest repair Flow knows: %s, about %d yd.", near.name, near.yards)
    elseif scanning then
        out[#out + 1] = "Looking up repair vendors..."
    else
        out[#out + 1] = "Flow doesn't know a repair vendor on this continent yet (it learns each one you use)."
    end
    if hearth then out[#out + 1] = hearth end
    out[#out + 1] = autoRepair and "At the vendor Flow repairs for you (after selling, so the sale helps pay). The cost shows there."
        or "Auto-repair is off: press the vendor's repair button yourself."
    return out
end

local function nearest()
    local S = ns.services
    if not S then return nil, false end
    local state = S:Scan()
    return S:Nearest("repair"), state == "running"
end

ns:Register("status", "repair", { order = 20, get = function()
    if not R:On() then return nil end
    local st = R:State()
    if not st.warn then return nil end
    local near, scanning = nearest()
    local link = GetInventoryItemLink and GetInventoryItemLink("player", st.slot)
    local item = link and link:match("%[(.-)%]")
    local hearth = near and ns.hearth and ns.hearth.Advice and ns.hearth:Advice(near.map, near.x, near.y, near.yards) or nil
    return {
        icon = ICON, text = string.format("%d%%", math.floor(st.pct * 100 + 0.5)),
        color = st.pct < 0.1 and { 1, 0.3, 0.3 } or { 1, 0.65, 0.2 },
        tip = table.concat(R.Lines(st, item, near, scanning, hearth, ns.db.sell.autoRepair ~= false), "\n"),
        click = near and function() ns.services:GoTo("repair") end or nil,
        clickText = "point the arrow at the repair vendor",
    }
end })

-- A stop on the route while you're under the threshold.
ns:Register("navGoal", "repair", {
    collect = function()
        if not R:On() or (ns.db.sell and ns.db.sell.repairStop == false) then return nil end
        local st = R:State()
        if not st.warn then return nil end
        local near = nearest()
        if not near then return nil end
        return { {
            key = "repair", weight = 1.2, points = { { map = near.map, x = near.x, y = near.y } },
            title = "Repair",
            text = string.format("Repair: %s (worn gear at %d%%)", near.name, math.floor(st.pct * 100 + 0.5)),
            details = { "Something you wear is nearly broken: a broken item gives you nothing.",
                        "Right-click this stop on the map to hide it." },
        } }
    end,
})

-- Crossing the threshold (either way): one line, and the route rebuilt.
local wasLow
local function check()
    cache = nil
    if not (ns.db and R:On()) then return end
    local st = R:State()
    if st.warn == wasLow then return end
    local first = wasLow == nil
    wasLow = st.warn
    if st.warn then
        ns:Print(string.format("your gear is wearing out (%d%%): repair soon. Hover the anvil above Flow's key for the nearest vendor.",
            math.floor(st.pct * 100 + 0.5)))
        ns:Log("repair", string.format("warn: worst %d%%, %d item(s) low, slot %s", math.floor(st.pct * 100 + 0.5), st.low, tostring(st.slot)))
    elseif not first then
        ns:Log("repair", "gear repaired or swapped: warning off")
    end
    if ns.nav and ns.nav.Collect and (st.warn or not first) then pcall(ns.nav.Collect, ns.nav) end
end
ns:On("UPDATE_INVENTORY_DURABILITY", check)
ns:On("PLAYER_EQUIPMENT_CHANGED", check)
ns:On("PLAYER_LOGIN", function() if C_Timer then C_Timer.After(8, check) end end)

ns:Register("setupItem", "repairWarn", {
    order = 17.5, label = "Warn early when gear wears out",
    why = "When anything you wear drops under 20% durability, an anvil shows above Flow's key and the route gets a stop at the nearest repair vendor Flow knows.",
    isOn = function() return R:On() end,
    set = function(on) ns.db.sell.repairWarn = on; wasLow = nil; check() end,
})
