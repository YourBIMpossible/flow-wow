-- The palette of the arrow colours (G56, L-D): a setting row that picks
-- which colours stand for the meanings. The meanings stay the same (away,
-- far, mid, near, here); only the colours change. Over the fake client; no
-- game client. Not tested in game.
local _, ns = ...

local A = ns.Arrow
local N = ns.Nav

local PATH = "layout.arrowPalette"

-- opts: saved (the account table).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    local saved = opts.saved or {}
    if type(saved.layout) ~= "table" then saved.layout = {} end
    saved.layout.arrowIntroSeen = true
    c.setSaved(ns.id.accountDB, saved)
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFacing(0)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local a = A.Declare(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, a, d
end

local function steps()
    return { quest = { map = 1411, x = 0.5, y = 0.25, label = "Test step" } }
end

local MEANINGS = { "away", "far", "mid", "near", "here" }

return {
    -- ------------------------------------------------------------ the pure part
    ["palette: the choices are the standard one first, then the colour-blind one"] = function(t)
        t.eq(N.ARROW_PALETTES, { { "standard", "Standard" }, { "colourBlind", "Colour-blind" } })
        for i = 1, #N.ARROW_PALETTES do
            t.ok(type(N.ARROW_PALETTE[N.ARROW_PALETTES[i][1]]) == "table", "each choice has its colours")
        end
    end,

    ["palette: every choice has a colour for every meaning, and no other"] = function(t)
        for i = 1, #N.ARROW_PALETTES do
            local row = N.ARROW_PALETTE[N.ARROW_PALETTES[i][1]]
            local n = 0
            for _ in pairs(row) do n = n + 1 end
            t.eq(n, #MEANINGS, "the same meanings in each")
            for j = 1, #MEANINGS do
                local rgb = row[MEANINGS[j]]
                t.ok(type(rgb) == "table" and #rgb == 3, MEANINGS[j])
                for m = 1, 3 do t.ok(rgb[m] >= 0 and rgb[m] <= 1, "a share of 1") end
            end
        end
    end,

    ["palette: the saved word names its choice; anything else is the standard one"] = function(t)
        t.eq(N.ArrowPaletteKey("colourBlind"), "colourBlind")
        t.eq(N.ArrowPaletteKey("standard"), "standard")
        t.eq(N.ArrowPaletteKey(nil), "standard")
        t.eq(N.ArrowPaletteKey("colourblind"), "standard", "the word is exact")
        t.eq(N.ArrowPaletteKey(2), "standard")
        t.eq(N.ArrowPaletteKey({}), "standard")
    end,

    ["palette: the colours of a saved word are the row the arrow is painted from"] = function(t)
        t.ok(N.ArrowPaletteOf("colourBlind") == N.ARROW_PALETTE.colourBlind)
        t.ok(N.ArrowPaletteOf("standard") == N.ARROW_PALETTE.standard)
        t.ok(N.ArrowPaletteOf(nil) == N.ARROW_PALETTE.standard)
        t.ok(N.ArrowPaletteOf("no such") == N.ARROW_PALETTE.standard)
    end,

    ["palette: the meaning of a state is the same in each; only the colour differs"] = function(t)
        local cb = N.ArrowPaletteOf("colourBlind")
        local r, g, b = N.ArrowColor("normal", N.COLOR_NEAR, cb)
        t.eq({ r, g, b }, cb.near, "near is the near colour of the palette")
        r, g, b = N.ArrowColor("normal", N.COLOR_FAR, cb)
        t.eq({ r, g, b }, cb.far, "far is the far colour of the palette")
        local sr, sg, sb = N.ArrowColor("normal", N.COLOR_NEAR, N.ArrowPaletteOf("standard"))
        t.ok(sr ~= cb.near[1] or sg ~= cb.near[2] or sb ~= cb.near[3], "the colours are not the same")
    end,

    -- ------------------------------------------------------------- the row
    ["palette row: declared with the arrows, a choice, standard by default"] = function(t)
        local k = start()
        t.eq(A.PALETTE, "arrow.palette")
        t.eq(A.PALETTE_PATH, PATH)
        local row = k.settings:row(A.PALETTE)
        t.ok(type(row) == "table", "the row is there")
        if type(row) ~= "table" then return end
        t.eq(row.scope, "account")
        t.eq(row.type, "choice")
        t.eq(row.choices, { "standard", "colourBlind" })
        t.eq(row.default, "standard")
        t.eq(row.path, PATH)
        t.eq(row.group, "travel.arrow")
        t.eq(row.label, "Arrow colours")
        t.eq(k.settings:get(A.PALETTE), "standard")
        t.eq(k.problems:count(), 0)
    end,

    ["palette row: asked for twice it is the one row"] = function(t)
        local k = start()
        t.ok(A.PaletteRow(k) == k.settings:row(A.PALETTE))
        t.ok(A.PaletteRow(k) == A.PaletteRow(k))
        t.eq(k.problems:count(), 0)
    end,

    ["palette row: setting it saves the word where the arrow reads it"] = function(t)
        local k = start()
        t.eq(k.store:get("account", PATH), nil, "nothing is written until it is set")
        t.eq((k.settings:set(A.PALETTE, "colourBlind")), true)
        t.eq(k.store:get("account", PATH), "colourBlind")
        t.ok(A.Palette(k) == N.ARROW_PALETTE.colourBlind)
        t.eq((k.settings:set(A.PALETTE, "standard")), true)
        t.ok(A.Palette(k) == N.ARROW_PALETTE.standard)
    end,

    ["palette row: a word that is no choice is refused and nothing changes"] = function(t)
        local k = start({ saved = { layout = { arrowPalette = "colourBlind" } } })
        t.ok((k.settings:set(A.PALETTE, "rainbow")) ~= true, "refused")
        t.eq(k.store:get("account", PATH), "colourBlind")
    end,

    ["palette: a saved word that is no choice is read as the standard one"] = function(t)
        local k = start({ saved = { layout = { arrowPalette = "rainbow" } } })
        t.ok(A.Palette(k) == N.ARROW_PALETTE.standard)
    end,

    -- ------------------------------------------------- what the arrow is given
    ["palette: the guide view is given the palette that was picked"] = function(t)
        local _, c = start()
        local src = A.GuideSource(c, {}, steps(), nil, N.ARROW_PALETTE.colourBlind)
        t.ok(src.view.palette == N.ARROW_PALETTE.colourBlind)
        src = A.GuideSource(c, {}, steps())
        t.eq(src.view.palette, nil, "none handed in: the standard one, as before")
    end,

    ["palette: a guide that names its own palette keeps it"] = function(t)
        local _, c = start()
        local guide = steps()
        guide.view = { palette = N.ARROW_PALETTE.standard }
        local src = A.GuideSource(c, {}, guide, nil, N.ARROW_PALETTE.colourBlind)
        t.ok(src.view.palette == N.ARROW_PALETTE.standard)
    end,

    ["palette: the demo is given the palette that was picked"] = function(t)
        local _, c = start()
        local src = A.DemoSource(c, {}, false, N.ARROW_PALETTE.colourBlind)
        t.ok(src.view.palette == N.ARROW_PALETTE.colourBlind)
        t.eq(A.DemoSource(c, {}, false).view.palette, nil)
    end,

    ["palette: switched while the arrows are up, nothing goes wrong"] = function(t)
        local k, c, _, d = start()
        d.commands.arrow("demo")
        c.advance(0.1, 2)
        t.eq((k.settings:set(A.PALETTE, "colourBlind")), true)
        c.advance(0.1, 2)
        t.ok(c.arrows[1].draws > 0, "still drawn")
        t.eq(k.problems:count(), 0)
    end,
}
