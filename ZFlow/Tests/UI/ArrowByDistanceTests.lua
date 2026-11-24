-- N43 (P-TRIP route display): the arrow's colour by distance, as a setting.
-- On (the default, as the predecessor's "distance" arrow colour was): far,
-- mid and near blend as before. Off: one colour whatever the distance, the
-- palette's own near colour (the predecessor's "route" colour was its
-- green). Away, here and the corpse keep their meanings either way. Over
-- the fake client; no game client. Not tested in game.
local _, ns = ...

local A = ns.Arrow
local N = ns.Nav

local PATH = "layout.arrowByDistance"

local function start(saved)
    local c = ns.make.fakeClient()
    saved = saved or {}
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
    A.Declare(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c
end

return {
    ["by distance: on (or not said) the palette is the palette row itself"] = function(t)
        t.ok(N.ArrowPaletteOf("standard", true) == N.ARROW_PALETTE.standard)
        t.ok(N.ArrowPaletteOf("colourBlind", nil) == N.ARROW_PALETTE.colourBlind)
    end,

    ["by distance: off, far, mid and near are all the palette's near colour"] = function(t)
        for _, key in ipairs({ "standard", "colourBlind" }) do
            local row = N.ARROW_PALETTE[key]
            local flat = N.ArrowPaletteOf(key, false)
            t.eq(flat.far, row.near, key .. " far")
            t.eq(flat.mid, row.near, key .. " mid")
            t.eq(flat.near, row.near, key .. " near")
            t.eq(flat.away, row.away, key .. " away keeps its meaning")
            t.eq(flat.here, row.here, key .. " here keeps its meaning")
            t.ok(N.ArrowPaletteOf(key, false) == flat, "made once")
            local r, g, b = N.ArrowColor("zone", N.COLOR_FAR * 2, flat)
            t.eq({ r, g, b }, row.near, key .. ": far away it is the near colour")
        end
    end,

    ["by distance: the row is with the arrow's, a bool, on by default"] = function(t)
        local k = start()
        t.eq(A.BY_DISTANCE, "arrow.byDistance")
        t.eq(A.BY_DISTANCE_PATH, PATH)
        local row = k.settings:row(A.BY_DISTANCE)
        t.ok(type(row) == "table", "the row is there")
        if type(row) ~= "table" then return end
        t.eq(row.scope, "account")
        t.eq(row.type, "bool")
        t.eq(row.default, true)
        t.eq(row.path, PATH)
        t.eq(row.group, "travel.arrow")
        t.eq(k.settings:get(A.BY_DISTANCE), true)
        t.ok(A.Palette(k) == N.ARROW_PALETTE.standard, "on: the palette as before")
        t.eq(k.problems:count(), 0)
    end,

    ["by distance: switched off, the arrow is painted from the one-colour palette"] = function(t)
        local k = start({ layout = { arrowPalette = "colourBlind" } })
        t.eq((k.settings:set(A.BY_DISTANCE, false)), true)
        t.eq(k.store:get("account", PATH), false)
        t.ok(A.Palette(k) == N.ArrowPaletteOf("colourBlind", false))
        t.eq((k.settings:set(A.BY_DISTANCE, true)), true)
        t.ok(A.Palette(k) == N.ARROW_PALETTE.colourBlind)
    end,
}
