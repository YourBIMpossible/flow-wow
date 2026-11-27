-- Tests for the K-0 kit parts in UI/Kit.lua: card, grid, bar and
-- fadedLine — the four parts every modernized window shares (owner's
-- all-windows programme, 2026-11-26). Pure: the kit's own checks,
-- defaults and theme, no client and no kernel. Made-up names.
-- Fails before K-0: kind "card" is not a part of the kit, so every
-- window below is refused.
local _, ns = ...

local K = ns.Kit

local function has(t)
    local ok = type(K) == "table" and type(K.Window) == "function" and type(K.Check) == "function"
    t.ok(ok, "ns.Kit answers Window and Check")
    return ok
end

local function nop() end

local function win(children)
    return K.Window({ id = "K0", title = "K-0", children = children })
end

local function first(tree, kind)
    local got
    K.Each(tree, function(p) if p.kind == kind then got = p end end)
    return got
end

local function refused(t, tree, why, field, msg)
    t.eq(tree, nil, msg)
    t.ok(type(why) == "string" and why:find(field, 1, true) ~= nil,
        (msg or "refused") .. " — the reason names " .. field .. " (got: " .. tostring(why) .. ")")
end

return {
    ["k0: a card is checked, with its fields and defaults"] = function(t)
        if not has(t) then return end
        local tree = win({ { kind = "card", key = "d1", text = "Blackmaw Hold", sub = "Levels 24-32",
            tone = "warn", tooltip = "A dungeon", onClick = nop } })
        local card = first(tree, "card")
        t.eq(card.text, "Blackmaw Hold")
        t.eq(card.sub, "Levels 24-32")
        t.eq(card.tone, "warn")
        t.eq(card.enabled, true, "a card is enabled unless told")
        t.eq(K.TextOf(card), "Blackmaw Hold", "a card reads by its text")
    end,

    ["k0: a card may wrap, like a line (section 408: never cut)"] = function(t)
        if not has(t) then return end
        local tree = win({ { kind = "card", key = "w1", text = "A long prompt that runs on", wrap = true } })
        local card = first(tree, "card")
        t.eq(card.wrap, true, "the wrap flag is carried into the tree")
        local plain = first(win({ { kind = "card", key = "w2", text = "Short" } }), "card")
        t.eq(plain.wrap, false, "and stays off unless asked")
    end,

    ["k0: a card needs its text, and a known tone"] = function(t)
        if not has(t) then return end
        local tree, why = win({ { kind = "card", sub = "no title" } })
        refused(t, tree, why, "text", "a card with no text is refused")
        local tree2, why2 = win({ { kind = "card", text = "X", tone = "loud" } })
        refused(t, tree2, why2, "tone", "a card with an unknown tone is refused")
    end,

    ["k0: a grid holds cards, in columns"] = function(t)
        if not has(t) then return end
        local tree = win({ { kind = "grid", children = {
            { kind = "card", text = "One" }, { kind = "card", text = "Two" }, { kind = "card", text = "Three" },
        } } })
        local grid = first(tree, "grid")
        t.eq(#grid.children, 3)
        t.eq(grid.columns, 2, "columns the kit's default when not told")
        t.eq(grid.children[2].text, "Two", "the cards are checked as parts")
        local tree3 = win({ { kind = "grid", columns = 3, children = { { kind = "card", text = "One" } } } })
        t.eq(first(tree3, "grid").columns, 3, "columns as told")
        local seen = {}
        K.Each(tree, function(p) if p.kind == "card" then seen[#seen + 1] = p.text end end)
        t.eq(seen, { "One", "Two", "Three" }, "a window walk reaches the cards in the grid")
    end,

    ["k0: a grid holds cards only, never a grid, and whole columns"] = function(t)
        if not has(t) then return end
        local tree, why = win({ { kind = "grid", children = { { kind = "line", text = "not a card" } } } })
        refused(t, tree, why, "card", "a grid holding a line is refused")
        local tree2, why2 = win({ { kind = "grid", children = {
            { kind = "grid", children = { { kind = "card", text = "deep" } } } } } })
        refused(t, tree2, why2, "grid", "a grid in a grid is refused")
        local tree3, why3 = win({ { kind = "grid", columns = 0, children = { { kind = "card", text = "One" } } } })
        refused(t, tree3, why3, "columns", "columns of 0 is refused")
        local tree4, why4 = win({ { kind = "scroll", children = {
            { kind = "grid", children = { { kind = "card", text = "In a scroll" } } } } } })
        t.ok(tree4 ~= nil, "a grid may stand in a scroll (why: " .. tostring(why4) .. ")")
    end,

    ["k0: a bar carries its fill share, held between none and full"] = function(t)
        if not has(t) then return end
        local function bar(value, max)
            local tree = win({ { kind = "bar", text = "Mining", value = value, max = max } })
            if not tree then return nil end
            return first(tree, "bar")
        end
        t.eq(bar(3, 4).share, 0.75)
        t.eq(bar(5, 4).share, 1, "over full reads as full")
        t.eq(bar(-1, 4).share, 0, "under none reads as none")
        t.eq(bar(0, 4).share, 0)
        t.eq(K.TextOf(bar(1, 2)), "Mining", "a bar reads by its label")
        local tree, why = win({ { kind = "bar", text = "X", value = 1, max = 0 } })
        refused(t, tree, why, "max", "a bar with max 0 is refused")
        local tree2, why2 = win({ { kind = "bar", text = "X", max = 4 } })
        refused(t, tree2, why2, "value", "a bar with no value is refused")
    end,

    ["k0: a faded line is a line's fields, and needs its text"] = function(t)
        if not has(t) then return end
        local tree = win({ { kind = "fadedLine", text = "Old gear", sub = "from the last boss",
            right = "2", onClick = nop } })
        local line = first(tree, "fadedLine")
        t.eq(line.text, "Old gear")
        t.eq(line.sub, "from the last boss")
        t.eq(line.enabled, true)
        t.eq(K.TextOf(line), "Old gear", "a faded line reads by its text")
        local tree2, why = win({ { kind = "fadedLine", sub = "no words" } })
        refused(t, tree2, why, "text", "a faded line with no text is refused")
    end,

    ["k0: the theme names the new sizes"] = function(t)
        if not has(t) then return end
        local size = K.look.size
        t.ok(type(size.cardMin) == "number" and size.cardMin > 0, "the theme names a card's least height")
        t.ok(type(size.gridGap) == "number" and size.gridGap >= 0, "the theme names the grid's gap")
        t.ok(type(size.barHeight) == "number" and size.barHeight > 0, "the theme names the bar's height")
    end,
}
