local _, ns = ...

-- Tests for ZFlow/Items/DispositionTip.lua (G4, CAPABILITY-RECONCILE row
-- G4, lead section 395): every item tooltip says what the sell rules would
-- do with the item, by Disposition.Decide and TooltipDisposition.Lines, the
-- sell list's rule. Look only: nothing is sold, kept or moved. Fake client.
--
-- Red before the code: ns.DispositionTip does not exist, so every test fails.

local tests = {}

local INFO = {
    [97] = { name = "Broken Fang", quality = 0, sellPrice = 4 },
    [2318] = { name = "Light Leather", quality = 1, sellPrice = 15, classID = 7 },
}

local function info(item)
    local id = ns.Items.Id(item)
    local i = id and INFO[id]
    if not i then return nil end
    local out = {}
    for k, v in pairs(i) do out[k] = v end
    return out
end

local function D() return ns.DispositionTip end

local function start(char)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, char or {})
    c.itemInfo = info
    local k = ns.Kernel({}, c)
    ns.Reservations.Declare(k)
    local api = D().Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api
end

local function texts(lines)
    local out = {}
    for i, l in ipairs(lines or {}) do out[i] = l.text end
    return out
end

local function has(lines, prefix)
    for _, l in ipairs(lines or {}) do
        if type(l.text) == "string" and l.text:sub(1, #prefix) == prefix then return true end
    end
    return false
end

tests["disposition tip: the module and its words exist"] = function(t)
    t.eq(type(D()), "table", "ns.DispositionTip")
    if type(D()) ~= "table" then return end
    t.eq(D().NAME, "dispositionTip")
    t.eq(D().SETTING, "items.dispositionTip")
    t.eq(type(D().Lines), "function")
    t.eq(type(D().Declare), "function")
end

tests["disposition tip: junk says it would sell, by the sell list's rule"] = function(t)
    if type(D()) ~= "table" then return t.ok(false, "ns.DispositionTip") end
    local _, c, api = start()
    t.eq(api.hooked(), true)
    local lines = c.showItemTooltip("item:97")
    t.ok(has(lines, "Would sell: junk"), table.concat(texts(lines), " | "))
end

tests["disposition tip: on the never-sell list, no sell line"] = function(t)
    if type(D()) ~= "table" then return t.ok(false, "ns.DispositionTip") end
    local _, c = start({ settings = { sell = { never = { [97] = true } } } })
    t.ok(not has(c.showItemTooltip("item:97"), "Would sell"), "never sold")
end

tests["disposition tip: no facts, not an item, or the setting off: no line"] = function(t)
    if type(D()) ~= "table" then return t.ok(false, "ns.DispositionTip") end
    local k, c = start()
    t.eq(texts(c.showItemTooltip("item:4444")), {}, "no facts read")
    t.eq(texts(c.showItemTooltip("nonsense")), {}, "not an item")
    k.settings:set(D().SETTING, false)
    t.eq(texts(c.showItemTooltip("item:97")), {}, "off")
end

tests["disposition tip: pure lines from a link, facts and a context"] = function(t)
    if type(D()) ~= "table" then return t.ok(false, "ns.DispositionTip") end
    t.ok(has(D().Lines("item:97", info, {}), "Would sell: junk"))
    t.eq(D().Lines("item:97", nil, {}), nil, "no item read")
    t.eq(D().Lines("item:4444", info, {}), nil, "no facts")
end

return tests
