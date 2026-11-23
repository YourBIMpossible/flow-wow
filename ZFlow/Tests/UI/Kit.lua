-- UI/Kit.lua (lead sections 287 and 291 item 1): the shared window kit's
-- pure half. Every part validates and gets its defaults; a bad spec is
-- refused with a reason naming the field; the money parts with their coin
-- icons; the stock quality colours; the empty-state line needs both what is
-- missing and how to get it. Pure: no client, no kernel. Made-up names.
-- Fails before the kit: ns.Kit is absent, so every test fails its first
-- check ("ns.Kit answers Window, Check, Money, Quality, Place and BindText").
local _, ns = ...

local K = ns.Kit

local function has(t)
    local ok = type(K) == "table" and type(K.Window) == "function" and type(K.Check) == "function"
        and type(K.Money) == "function" and type(K.Quality) == "function" and type(K.Place) == "function"
        and type(K.BindText) == "function"
    t.ok(ok, "ns.Kit answers Window, Check, Money, Quality, Place and BindText")
    return ok
end

local function nop() end

local GOLD, SILVER, COPPER = "Interface\\MoneyFrame\\UI-GoldIcon", "Interface\\MoneyFrame\\UI-SilverIcon",
    "Interface\\MoneyFrame\\UI-CopperIcon"

-- One of every part, in one window.
local function full()
    return {
        id = "Demo", title = "Demo window",
        children = {
            { kind = "header", key = "find", title = "Things", search = { onText = nop } },
            { kind = "tabs", key = "tabs", items = { "One", "Two" }, onSelect = nop },
            { kind = "topicList", items = { "Bags", "Bank" }, selected = 2, onSelect = nop },
            { kind = "section", text = "General" },
            { kind = "row", label = "Sell grey items", control = { kind = "checkbox", key = "grey", onToggle = nop } },
            { kind = "row", label = "Key", tooltip = "The key", control = { kind = "bind", onClick = nop } },
            { kind = "button", key = "sell", text = "Sell", onClick = nop },
            { kind = "scroll", children = {
                { kind = "itemLine", name = "Linen Cloth", quality = 2, count = 4, money = 120005, item = 2589 },
            } },
            { kind = "empty", text = "No items to sell.", how = "Loot something grey first." },
        },
    }
end

-- One part of each kind on its own.
local function eachPart()
    return {
        { kind = "header", title = "T" },
        { kind = "header", title = "T", search = { placeholder = "Find", onText = nop } },
        { kind = "tabs", items = { "A" }, onSelect = nop },
        { kind = "topicList", items = { "A", "B" }, selected = 1, onSelect = nop },
        { kind = "section", text = "S" },
        { kind = "row", label = "L" },
        { kind = "row", label = "L", control = { kind = "button", text = "B", onClick = nop } },
        { kind = "button", text = "B", onClick = nop, enabled = false, tooltip = "Why" },
        { kind = "checkbox", checked = true, onToggle = nop, label = "On" },
        { kind = "bind", key = "CTRL-F", onClick = nop },
        { kind = "scroll", height = 120, children = {} },
        { kind = "itemLine", name = "Rock", icon = "Interface\\Icons\\INV_Stone_01" },
        { kind = "empty", text = "Nothing here.", how = "Open a bag." },
    }
end

-- What a refusal says must name the field.
local function refused(t, ok, why, field, label)
    t.eq(ok, nil, label .. ": refused")
    t.ok(type(why) == "string" and why:find(field, 1, true) ~= nil,
        label .. ": the reason names " .. field .. " (got " .. tostring(why) .. ")")
end

return {
    ["kit: a window with one of every part validates, with its defaults filled in"] = function(t)
        if not has(t) then return end
        local tree, why = K.Window(full())
        t.ok(type(tree) == "table", "a tree: " .. tostring(why))
        if type(tree) ~= "table" then return end
        t.eq(tree.kind, "window")
        t.eq({ tree.movable, tree.closable, tree.escape, tree.resizable }, { true, true, true, true },
            "movable, closable, Escape closes, resizable since it lists things")
        t.eq({ tree.width, tree.height }, { K.WIDTH, K.HEIGHT })
        t.eq(tree.point, K.POINT)
        local kids = tree.children
        t.eq(#kids, 9)
        t.eq(kids[1].search.placeholder, K.SEARCH)
        t.eq(kids[2].selected, 1, "the first tab by default")
        t.eq(kids[3].selected, 2)
        t.eq(kids[5].control.checked, false)
        t.eq(kids[6].control.text, K.NOT_BOUND, "a key not bound says so")
        t.eq(kids[7].enabled, true)
        t.eq(kids[8].height, K.SCROLL_HEIGHT)
        local line = kids[8].children[1]
        t.eq(line.color.hex, "1eff00", "uncommon green")
        t.eq(line.coins.text, "12g 0s 5c")
        t.eq({ kids[1].path, kids[5].control.path, kids[8].children[1].path, kids[9].path }, { "1", "5.1", "8.1", "9" },
            "each part has its place in the tree")
    end,

    ["kit: a window that lists nothing is not resizable unless asked"] = function(t)
        if not has(t) then return end
        local tree = K.Window({ id = "Small", title = "Small", children = { { kind = "section", text = "S" } } })
        t.eq(type(tree) == "table" and tree.resizable, false)
        tree = K.Window({ id = "Small", title = "Small", resizable = true, children = {} })
        t.eq(type(tree) == "table" and tree.resizable, true)
    end,

    ["kit: every part checks on its own"] = function(t)
        if not has(t) then return end
        for i, p in ipairs(eachPart()) do
            local ok, why = K.Check(p)
            t.eq(ok, true, "part " .. i .. " (" .. p.kind .. "): " .. tostring(why))
        end
    end,

    ["kit: a bad spec is refused, and the reason names the field"] = function(t)
        if not has(t) then return end
        local cases = {
            { { title = "T", children = {} }, "id", "window without an id" },
            { { id = "Has space", title = "T", children = {} }, "id", "window id with a space" },
            { { id = "W", children = {} }, "title", "window without a title" },
            { { id = "W", title = "T", children = "no" }, "children", "children not a list" },
            { { id = "W", title = "T", width = -5, children = {} }, "width", "negative width" },
            { { id = "W", title = "T", movable = "yes", children = {} }, "movable", "movable not true or false" },
        }
        for _, case in ipairs(cases) do
            local ok, why = K.Window(case[1])
            refused(t, ok, why, case[2], case[3])
        end
        local parts = {
            { { kind = "sparkle" }, "kind", "an unknown kind" },
            { { kind = "header" }, "title", "header without a title" },
            { { kind = "header", title = "T", search = {} }, "onText", "search without onText" },
            { { kind = "tabs", items = {}, onSelect = nop }, "items", "no tabs" },
            { { kind = "tabs", items = { "A", "B" }, selected = 3, onSelect = nop }, "selected", "tab 3 of 2" },
            { { kind = "topicList", items = { "A" } }, "onSelect", "topics without onSelect" },
            { { kind = "section" }, "text", "section without text" },
            { { kind = "row" }, "label", "row without a label" },
            { { kind = "row", label = "L", control = { kind = "section", text = "S" } }, "control", "a section as a control" },
            { { kind = "button", text = "B" }, "onClick", "button without onClick" },
            { { kind = "button", text = "B", onClick = nop, enabled = "yes" }, "enabled", "enabled not true or false" },
            { { kind = "checkbox", checked = "x", onToggle = nop }, "checked", "checked not true or false" },
            { { kind = "bind", key = 5, onClick = nop }, "key", "a key that is not text" },
            { { kind = "scroll", children = { { kind = "scroll", children = {} } } }, "scroll", "a scroll in a scroll" },
            { { kind = "itemLine" }, "name", "item line without a name" },
            { { kind = "itemLine", name = "N", quality = 9 }, "quality", "quality 9" },
            { { kind = "itemLine", name = "N", count = -1 }, "count", "count below 0" },
            { { kind = "itemLine", name = "N", money = 1.5 }, "money", "money not whole copper" },
        }
        for _, case in ipairs(parts) do
            local ok, why = K.Check(case[1])
            refused(t, ok, why, case[2], case[3])
        end
        local twice = { id = "W", title = "T", children = {
            { kind = "section", key = "a", text = "S" }, { kind = "section", key = "a", text = "S" } } }
        local ok, why = K.Window(twice)
        refused(t, ok, why, "key", "a key given twice")
    end,

    ["kit: money is coin parts with the stock coin icons, and a text"] = function(t)
        if not has(t) then return end
        t.eq(K.Money(0), { text = "0c", coins = { { coin = "copper", amount = 0, icon = COPPER } } })
        t.eq(K.Money(5), { text = "5c", coins = { { coin = "copper", amount = 5, icon = COPPER } } })
        t.eq(K.Money(102), { text = "1s 2c", coins = {
            { coin = "silver", amount = 1, icon = SILVER }, { coin = "copper", amount = 2, icon = COPPER } } })
        t.eq(K.Money(120005), { text = "12g 0s 5c", coins = {
            { coin = "gold", amount = 12, icon = GOLD }, { coin = "silver", amount = 0, icon = SILVER },
            { coin = "copper", amount = 5, icon = COPPER } } })
        t.eq({ K.Money(-1), K.Money(1.5), K.Money("5") }, {}, "not whole copper: nil")
    end,

    ["kit: quality is the stock colour for 0 to 5, and common white for anything else"] = function(t)
        if not has(t) then return end
        local want = { [0] = "9d9d9d", "ffffff", "1eff00", "0070dd", "a335ee", "ff8000" }
        for q = 0, 5 do
            local col = K.Quality(q)
            t.eq({ col.hex, col.known }, { want[q], true }, "quality " .. q)
            t.ok(type(col.r) == "number" and type(col.g) == "number" and type(col.b) == "number", "r, g, b " .. q)
        end
        t.eq({ K.Quality(9).hex, K.Quality(9).known }, { "ffffff", false }, "unknown quality")
        t.eq({ K.Quality(nil).hex, K.Quality(nil).known }, { "ffffff", false }, "no quality")
        t.eq({ K.Quality(2).r, K.Quality(2).g, K.Quality(2).b }, { 0.12, 1, 0 })
    end,

    ["kit: the empty-state line needs both what is missing and how to get it"] = function(t)
        if not has(t) then return end
        local ok, why = K.Check({ kind = "empty", text = "No bank seen." })
        refused(t, ok, why, "how", "no how")
        ok, why = K.Check({ kind = "empty", how = "Visit a banker." })
        refused(t, ok, why, "text", "no text")
        ok, why = K.Check({ kind = "empty", text = "", how = "Visit a banker." })
        refused(t, ok, why, "text", "empty text")
        t.eq((K.Check({ kind = "empty", text = "No bank seen.", how = "Visit a banker." })), true)
    end,

    ["kit: a key not bound reads Not Bound"] = function(t)
        if not has(t) then return end
        t.eq(K.BindText(nil), "Not Bound")
        t.eq(K.BindText(""), "Not Bound")
        t.eq(K.BindText("CTRL-F"), "CTRL-F")
    end,

    ["kit: a saved place is used when it is whole, else the window's own"] = function(t)
        if not has(t) then return end
        local tree = K.Window(full())
        if type(tree) ~= "table" then t.ok(false, "a tree") return end
        local p, w, h = K.Place({ point = { "TOPLEFT", "TOPLEFT", 10, -20 }, width = 500, height = 360 }, tree)
        t.eq({ p, w, h }, { { "TOPLEFT", "TOPLEFT", 10, -20 }, 500, 360 })
        p, w, h = K.Place({ point = { "TOPLEFT", 5, "x" }, width = 3 }, tree)
        t.eq({ p, w, h }, { K.POINT, K.WIDTH, K.HEIGHT }, "a broken saved place: the window's own")
        p, w, h = K.Place(nil, tree)
        t.eq({ p, w, h }, { K.POINT, K.WIDTH, K.HEIGHT })
        local fixed = K.Window({ id = "F", title = "F", children = {} })
        p, w, h = K.Place({ point = { "CENTER", "CENTER", 1, 2 }, width = 500, height = 360 }, fixed)
        t.eq({ w, h }, { K.WIDTH, K.HEIGHT }, "a window that cannot be resized keeps its size")
    end,
}
