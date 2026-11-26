-- The arrows' right-click menu and hover tooltip as plain tables (inventory
-- rows 42, 45 to 50): which rows the menu has, what choosing one asks for,
-- and the lines of the tooltip. No client: nothing here draws or clicks.
local _, ns = ...

local M = ns.ArrowMenu

local STYLES = {
    { key = "modern", label = "Modern", on = true },
    { key = "3d", label = "3D (pillars)", on = false },
    { key = "flat", label = "Flat lines", on = false },
}

local function state(over)
    local s = { stacked = true, hidden = {}, text = {}, styles = STYLES, canShapes = true }
    for key, v in pairs(over or {}) do s[key] = v end
    return s
end

local row
row = function(items, key)
    for i = 1, #items do
        if items[i].key == key then return items[i], i end
        -- A row of a submenu (lead section 239, N57) is found under its heading.
        if type(items[i].children) == "table" then
            local below, at = row(items[i].children, key)
            if below then return below, at end
        end
    end
    return nil
end

-- The tests below need the module; without it each fails here.
local function has(t)
    local ok = type(M) == "table" and type(M.Items) == "function" and type(M.Action) == "function"
        and type(M.Tip) == "function"
    t.ok(ok, "ns.ArrowMenu answers Items, Action and Tip")
    return ok
end

return {
    ["menu: Restack, Separate and Reset are there, each with words"] = function(t)
        if not has(t) then return end
        local items = M.Items(state())
        for _, key in ipairs({ "restack", "separate", "reset" }) do
            local r = row(items, key)
            t.ok(r ~= nil and type(r.text) == "string" and r.text ~= "", key .. " has a row")
        end
        t.eq(row(items, "restack").text, "Restack")
        t.eq(row(items, "reset").text, "Reset")
    end,

    ["menu: stacked arrows cannot be restacked, separate ones cannot be separated"] = function(t)
        if not has(t) then return end
        local stacked = M.Items(state({ stacked = true }))
        t.eq(row(stacked, "restack").disabled, true)
        t.ok(not row(stacked, "separate").disabled, "separate is offered")
        local apart = M.Items(state({ stacked = false }))
        t.ok(not row(apart, "restack").disabled, "restack is offered")
        t.eq(row(apart, "separate").disabled, true)
        t.ok(not row(apart, "reset").disabled, "reset is always offered")
    end,

    ["menu: the text and show rows are ticked as saved"] = function(t)
        if not has(t) then return end
        local items = M.Items(state())
        for _, key in ipairs({ "text.quest", "text.prof", "show.quest", "show.prof" }) do
            local r = row(items, key)
            t.ok(r ~= nil, key .. " has a row")
            if r then t.eq(r.checked, true, key .. " is ticked on a fresh layout") end
        end
        local changed = M.Items(state({ hidden = { prof = true }, text = { quest = false } }))
        t.eq(row(changed, "text.quest").checked, false)
        t.eq(row(changed, "text.prof").checked, true)
        t.eq(row(changed, "show.prof").checked, false)
        t.eq(row(changed, "show.quest").checked, true)
    end,

    ["menu: one style row for each style given, the one in use marked"] = function(t)
        if not has(t) then return end
        local items = M.Items(state())
        for _, s in ipairs(STYLES) do
            local r = row(items, "style." .. s.key)
            t.ok(r ~= nil, s.key .. " has a row")
            if r then
                t.eq(r.text, s.label)
                t.eq(r.radio, true)
                t.eq(r.checked, s.on)
                t.ok(not r.disabled, "offered where the client draws lines")
            end
        end
        local _, first = row(items, "style.modern")
        local _, last = row(items, "style.flat")
        t.ok(first and last and first < last, "in the order given")
    end,

    ["menu: a client that draws no lines is offered only the modern style"] = function(t)
        if not has(t) then return end
        local items = M.Items(state({ canShapes = false }))
        t.ok(not row(items, "style.modern").disabled)
        t.eq(row(items, "style.3d").disabled, true)
        t.eq(row(items, "style.flat").disabled, true)
    end,

    ["menu: no styles given, no style rows and no error"] = function(t)
        if not has(t) then return end
        local items = M.Items(state({ styles = false }))
        t.eq(row(items, "style.modern"), nil)
        t.ok(row(items, "reset") ~= nil, "the rest is still there")
        t.ok(type(M.Items(nil)) == "table", "no state at all is still a menu")
    end,

    ["menu: titles and dividers carry no key, and no key is used twice"] = function(t)
        if not has(t) then return end
        local items, seen = M.Items(state()), {}
        t.ok(#items > 0, "there are rows")
        for i = 1, #items do
            local r = items[i]
            if r.title or r.sep then
                t.eq(r.key, nil, "row " .. i .. " cannot be chosen")
            else
                t.ok(type(r.key) == "string" and not seen[r.key], "row " .. i .. " has its own key")
                seen[r.key] = true
            end
        end
    end,

    ["action: restack, separate and reset"] = function(t)
        if not has(t) then return end
        t.eq(M.Action("restack", state({ stacked = false })), { op = "restack" })
        t.eq(M.Action("separate", state()), { op = "mode", mode = "separate" })
        t.eq(M.Action("reset", state()), { op = "reset" })
    end,

    ["action: a row that is not offered asks for nothing"] = function(t)
        if not has(t) then return end
        t.eq(M.Action("restack", state({ stacked = true })), nil)
        t.eq(M.Action("separate", state({ stacked = false })), nil)
        t.eq(M.Action("style.flat", state({ canShapes = false })), nil)
    end,

    ["action: the text and show rows turn over what is saved"] = function(t)
        if not has(t) then return end
        t.eq(M.Action("text.quest", state()), { op = "text", key = "quest", on = false })
        t.eq(M.Action("text.quest", state({ text = { quest = false } })), { op = "text", key = "quest", on = true })
        t.eq(M.Action("show.prof", state()), { op = "hide", key = "prof", on = true })
        t.eq(M.Action("show.prof", state({ hidden = { prof = true } })), { op = "hide", key = "prof", on = false })
    end,

    ["action: a style row asks for that style"] = function(t)
        if not has(t) then return end
        t.eq(M.Action("style.flat", state()), { style = "flat" })
        t.eq(M.Action("style.modern", state({ canShapes = false })), { style = "modern" })
    end,

    ["action: a key the menu does not have asks for nothing"] = function(t)
        if not has(t) then return end
        t.eq(M.Action("style.round", state()), nil)
        t.eq(M.Action("text.pet", state()), nil)
        t.eq(M.Action("show.", state()), nil)
        t.eq(M.Action("cast", state()), nil)
        t.eq(M.Action(nil, state()), nil)
        t.eq(M.Action(7, state()), nil)
        t.eq(M.Action("reset", nil), { op = "reset" })
    end,

    ["tip: the arrow's name, its lines, then the hint"] = function(t)
        if not has(t) then return end
        local tip = M.Tip({ key = "quest", stacked = false,
                            lines = { quest = { "Kill ten boars", "120 yd" }, prof = { "Copper Vein" } } })
        t.eq(tip[1], "Quest arrow")
        t.eq(tip[2], "Kill ten boars")
        t.eq(tip[3], "120 yd")
        t.eq(#tip, 4, "the other arrow's lines are not here when they are apart")
        t.ok(tip[4]:find("Right-click", 1, true) ~= nil, "the hint says how to open the menu")
        t.ok(tip[4]:find("Ctrl", 1, true) ~= nil, "and how to move the arrow")
    end,

    ["tip: the needle has its own name and lines"] = function(t)
        if not has(t) then return end
        local tip = M.Tip({ key = "prof", stacked = false,
                            lines = { quest = { "Kill ten boars" }, prof = { "Copper Vein" } } })
        t.eq(tip[1], "Profession arrow")
        t.eq(tip[2], "Copper Vein")
        t.eq(#tip, 3)
    end,

    ["tip: stacked, the quest arrow's tooltip carries the needle's lines too"] = function(t)
        if not has(t) then return end
        local tip = M.Tip({ key = "quest", stacked = true, both = true,
                            lines = { quest = { "Kill ten boars" }, prof = { "Copper Vein" } } })
        t.eq(tip[2], "Kill ten boars")
        t.eq(tip[3], "Profession arrow")
        t.eq(tip[4], "Copper Vein")
        t.eq(#tip, 5)
        local alone = M.Tip({ key = "quest", stacked = true, both = false,
                              lines = { quest = { "Kill ten boars" }, prof = { "Copper Vein" } } })
        t.eq(#alone, 3, "a needle that is not showing adds nothing")
    end,

    ["tip: the other steps here follow the step and route lines, after a blank line (R-09)"] = function(t)
        if not has(t) then return end
        local here = { header = "Here as well", lines = { "Wolves - Loot 2/6", "Boars" } }
        local tip = M.Tip({ key = "quest", lines = { quest = { "Kill ten boars" } },
                            route = { "Next: Bears" }, here = here })
        t.eq(tip[2], "Kill ten boars")
        t.eq(tip[3], "Next: Bears")
        t.eq(tip[4], " ")
        t.eq(tip[5], "Here as well")
        t.eq(tip[6], "Wolves - Loot 2/6")
        t.eq(tip[7], "Boars")
        t.eq(#tip, 8)
        local prof = M.Tip({ key = "prof", lines = { prof = { "Copper Vein" } }, here = here })
        t.eq(#prof, 3, "the needle does not carry them")
        local empty = M.Tip({ key = "quest", lines = { quest = { "a" } }, here = { header = "x", lines = {} } })
        t.eq(#empty, 3, "no lines, no header")
    end,

    ["tip: a click is promised only when there is something to open"] = function(t)
        if not has(t) then return end
        local without = M.Tip({ key = "quest", lines = { quest = { "a" } } })
        t.eq(without[#without]:find("Click:", 1, true), nil, "no drawer, no promise")
        local with = M.Tip({ key = "quest", drawer = true, lines = { quest = { "a" } } })
        t.ok(with[#with]:find("Click: details", 1, true) ~= nil, "a drawer is promised")
    end,

    ["tip: no lines, an odd key or no state still gives a name and the hint"] = function(t)
        if not has(t) then return end
        t.eq(#M.Tip({ key = "quest" }), 2)
        t.eq(#M.Tip({ key = "prof", lines = { prof = "no" } }), 2)
        t.eq(M.Tip({ key = "pet" }), nil, "no such arrow, no tooltip")
        t.eq(M.Tip(nil), nil)
    end,

    ["tip and menu: no line spells the predecessor's name"] = function(t)
        if not has(t) then return end
        local old = "Fl" .. "ow"
        for _, line in ipairs(M.Tip({ key = "quest", stacked = true, both = true, drawer = true,
                                      lines = { quest = { "a" }, prof = { "b" } } })) do
            t.eq(line:find(old, 1, true), nil, line)
        end
        for _, r in ipairs(M.Items(state())) do
            if r.text then t.eq(r.text:find(old, 1, true), nil, r.text) end
        end
    end,
}
