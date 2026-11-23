local _, ns = ...

-- Set icons (P-SETS branch 2, S19): a small movable row of picture buttons,
-- one for each saved Z-Flow set (Gear/Sets.lua), at most twelve, in the
-- order saved. The set you wear (every one of its pieces worn) has a gold
-- edge. Hover: its name, how much of it you wear, and its pieces. Setting
-- gear.setIcons, off by default (a new surface on the screen). The row is
-- moved by a drag on its edge; where it stands is kept account wide in
-- layout.setIcons, as the boss loot panel keeps its place.
--
-- Flow's Gear/SetIcons.lua stood the same row on the bag window and used
-- the game's own equipment sets (C_EquipmentSet); those calls were never
-- asked on 16001, so this row shows the add-on's own saved sets.
--
--   icons = GearSetIcons.Icons(sets, wornKeys, nameOf, textureOf)
--   n     = GearSetIcons.Wearing(set, wornKeys)   pieces worn, nil: not known
--   point = GearSetIcons.Point(saved)
--   api   = GearSetIcons.Declare(k)               api.row(), api.redraw()
--
-- ACTING, the click only (lead sections 227 item 4 and 230): a left click
-- on an icon puts on that set's pieces that are in the bags and not worn,
-- one client.equipItem (EquipItemByName) per piece, to the inventory slot
-- it was saved in (Gear/Sets.lua set.slots), in one pass. What
-- starts it: the player's own click (the row's act). What stops it:
-- combat, or combat not known (nothing is asked), what is worn or the bags
-- not read (nothing is asked). No timer, no event, no retry: a piece the
-- game refused stays off until the next click. It says what it did:
-- "Asked to equip N pieces of <set>; M not in your bags." Asked, not done:
-- the game may refuse a piece without a word, so none is counted as on.
--   plan, why = GearSetIcons.Plan(set, wornLinks, bagItems)
--   line      = GearSetIcons.Done(name, equipped, missing, failed)
--
-- Reads: client.wornLinks, client.bagItems, client.inCombat,
-- client.itemInfo, client.itemTexture. It saves only the row's place; never
-- a character name.

local SetIcons = {}
ns.GearSetIcons = SetIcons

SetIcons.NAME = "gearSetIcons"
SetIcons.SETTING = "gear.setIcons"
SetIcons.LAYOUT = "layout.setIcons"    -- account: { point = { anchor, relative anchor, x, y } }
SetIcons.MAX = 12
SetIcons.SIZE = 28
SetIcons.DEFAULT_POINT = { "BOTTOM", "BOTTOM", 0, 160 }
SetIcons.TEXTURE = "Interface\\Icons\\INV_Chest_Chain_04"
SetIcons.WORN = "You wear all of it."
SetIcons.WEARING = "You wear %d of its %d pieces."
SetIcons.CLICK = "Click: put on its pieces from your bags (out of combat)."
SetIcons.IN_COMBAT = "You are in combat, so nothing was equipped. Click the set again after the fight."
SetIcons.COMBAT_UNKNOWN = "Can't tell whether you are in combat, so nothing was equipped."
SetIcons.CANT_READ_WORN = "Can't read what you wear right now, so nothing was equipped."
SetIcons.CANT_READ_BAGS = "Can't read your bags right now, so nothing was equipped."
SetIcons.NO_SLOT = "Pieces with no saved slot: %d (the game picks where they go)."
SetIcons.NO_SET ="You have no set named %s."
SetIcons.ALREADY = "You already wear all of %s that is in your bags."

local function finite(n)
    return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function words(s)
    return type(s) == "string" and s ~= "" and s:find("[^%u]") == nil
end

-- A saved place when it is one, else the default: { anchor, relative
-- anchor, x, y }, a copy.
function SetIcons.Point(saved)
    local p = type(saved) == "table" and saved.point or nil
    if type(p) == "table" and words(p[1]) and words(p[2]) and finite(p[3]) and finite(p[4]) then
        return { p[1], p[2], p[3], p[4] }
    end
    local d = SetIcons.DEFAULT_POINT
    return { d[1], d[2], d[3], d[4] }
end

-- { [key] = how many } of a list of item keys.
local function tally(keys)
    local n = {}
    for _, key in ipairs(keys) do n[key] = (n[key] or 0) + 1 end
    return n
end

-- What is worn as item keys, from client.wornLinks(); nil when not known.
function SetIcons.WornKeys(links)
    if type(links) ~= "table" then return nil end
    local out = {}
    for _, link in pairs(links) do
        local key = ns.Items.Key(link)
        if key ~= nil then out[#out + 1] = key end
    end
    return out
end

-- How many of the set's pieces are worn (two of one ring count twice only
-- when two are worn); nil when what is worn is not known.
function SetIcons.Wearing(set, wornKeys)
    if type(wornKeys) ~= "table" then return nil end
    local have, n = tally(wornKeys), 0
    for _, key in ipairs(set.items) do
        if (have[key] or 0) > 0 then
            have[key] = have[key] - 1
            n = n + 1
        end
    end
    return n
end

-- The icons to draw, at most SetIcons.MAX, in the order saved. nameOf(key)
-- and textureOf(key) are the reads (nil: not read).
function SetIcons.Icons(sets, wornKeys, nameOf, textureOf)
    local out = {}
    for _, set in ipairs(type(sets) == "table" and sets or {}) do
        if #out >= SetIcons.MAX then break end
        local total = #set.items
        local wearing = SetIcons.Wearing(set, wornKeys)
        local worn = wearing ~= nil and total > 0 and wearing == total
        local tip = { set.name }
        if worn then
            tip[#tip + 1] = SetIcons.WORN
        elseif wearing ~= nil then
            tip[#tip + 1] = SetIcons.WEARING:format(wearing, total)
        end
        for _, key in ipairs(set.items) do tip[#tip + 1] = nameOf(key) or ("item " .. tostring(key)) end
        if type(set.noSlot) == "number" and set.noSlot > 0 then tip[#tip + 1] = SetIcons.NO_SLOT:format(set.noSlot) end
        tip[#tip + 1] = SetIcons.CLICK
        local texture = SetIcons.TEXTURE
        if total > 0 then
            local got = textureOf(set.items[1])
            if got ~= nil then texture = got end
        end
        out[#out + 1] = { key = set.name, edge = worn, texture = texture, tip = tip }
    end
    return out
end

-- What one click puts on: each piece of the set not worn whose item is in
-- the bags (two of one ring take two from the bags). -> { equip = { item
-- as the bags list it, ... }, slots = { [i] = the saved inventory slot of
-- equip[i], nil for a set saved without slots }, missing = pieces neither
-- worn nor in the bags }; or nil and why when what is worn or the bags are
-- not known.
function SetIcons.Plan(set, wornLinks, bagItems)
    local worn = SetIcons.WornKeys(wornLinks)
    if worn == nil then return nil, SetIcons.CANT_READ_WORN end
    if type(bagItems) ~= "table" then return nil, SetIcons.CANT_READ_BAGS end
    local have = tally(worn)
    -- [key] = { item, ... } one entry per item in the bags.
    local bag = {}
    for _, stack in ipairs(bagItems) do
        local key
        if type(stack) == "table" then key = ns.Items.Key(stack.item) end
        if key ~= nil then
            local n = 1
            if type(stack.count) == "number" and stack.count >= 1 and stack.count < 1000 then n = math.floor(stack.count) end
            local list = bag[key] or {}
            bag[key] = list
            for _ = 1, n do list[#list + 1] = stack.item end
        end
    end
    local plan = { equip = {}, slots = {}, missing = 0 }
    local saved = set.slots
    for i, key in ipairs(set.items) do
        if (have[key] or 0) > 0 then
            have[key] = have[key] - 1
        elseif bag[key] and #bag[key] > 0 then
            plan.equip[#plan.equip + 1] = table.remove(bag[key], 1)
            if type(saved) == "table" then plan.slots[#plan.equip] = saved[i] end
        else
            plan.missing = plan.missing + 1
        end
    end
    return plan
end

local function pieces(n)
    if n == 1 then return "1 piece" end
    return n .. " pieces"
end

-- The line one click prints.
function SetIcons.Done(name, equipped, missing, failed)
    if equipped == 0 and missing == 0 and failed == 0 then return SetIcons.ALREADY:format(name) end
    local line = "Asked to equip " .. pieces(equipped) .. " of " .. name .. "; " .. missing .. " not in your bags."
    if failed > 0 then line = line .. " " .. pieces(failed) .. " could not be put on; click again to try." end
    return line
end

function SetIcons.Declare(k)
    local api = {}
    local ctx, row
    local cancels = {}
    function api.row() return row end

    -- A client read under pcall: nil when the call is missing or raised.
    local function read(name, ...)
        if not ctx then return nil end
        local fn = ctx.client[name]
        if type(fn) ~= "function" then return nil end
        local ok, v = pcall(fn, ...)
        if not ok then return nil end
        return v
    end
    local function nameOf(key)
        local info = read("itemInfo", ns.Items.Id(key))
        if type(info) == "table" and type(info.name) == "string" and info.name ~= "" then return info.name end
        return nil
    end
    local function textureOf(key)
        local tex = read("itemTexture", ns.Items.Id(key))
        if type(tex) == "string" or type(tex) == "number" then return tex end
        return nil
    end

    -- The row, made the first time it is shown; nil when the client
    -- makes no frame.
    local function made()
        if row or type(ctx.client.iconRow) ~= "function" then return row end
        local id = k.id or ns.id
        local ok, h = pcall(ctx.client.iconRow, { name = id.framePrefix .. "SetIcons", size = SetIcons.SIZE })
        if not ok or type(h) ~= "table" then return nil end
        row = h
        row.show(false)
        row.place(SetIcons.Point(ctx.store:get("account", SetIcons.LAYOUT)))
        if type(row.onMoved) == "function" then
            row.onMoved(function(point)
                ctx.store:set("account", SetIcons.LAYOUT, { point = SetIcons.Point({ point = point }) })
            end, function(err)
                if type(k.problems) == "table" then k.problems:add(SetIcons.NAME, "moved", tostring(err)) end
            end)
        end
        return row
    end

    local function say(line)
        local id = k.id or ns.id
        pcall(ctx.client.print, id.title .. ": " .. line)
    end

    local draw

    -- ACTING (S19): the only caller of client.equipItem. Reached only from
    -- act, which only the row's own left click asks (c.iconRow OnClick).
    -- One pass over the set's pieces: no timer, no event, no retry.
    local function equipSet(name)
        local set
        for _, s in ipairs(ns.GearSets.Saved(ctx.store)) do
            if s.name == name then set = s end
        end
        if not set then return say(SetIcons.NO_SET:format(tostring(name))) end
        local combat = read("inCombat")
        if combat == true then return say(SetIcons.IN_COMBAT) end
        if combat ~= false then return say(SetIcons.COMBAT_UNKNOWN) end
        local plan, why = SetIcons.Plan(set, read("wornLinks"), read("bagItems"))
        if not plan then return say(why) end
        local equipped, failed = 0, 0
        -- Each piece to its saved slot, so the second of two rings (or
        -- trinkets, or weapons) never replaces the first; no saved slot:
        -- the game's choice.
        for i, item in ipairs(plan.equip) do
            local ok, put = false, nil
            if type(ctx.client.equipItem) == "function" then
                ok, put = pcall(ctx.client.equipItem, item, plan.slots[i])
            end
            if ok and put == true then equipped = equipped + 1 else failed = failed + 1 end
        end
        say(SetIcons.Done(set.name, equipped, plan.missing, failed))
        draw()
    end

    -- The row's click: a left click on the icon of set `key`.
    local function act(key)
        if not ctx then return end
        local ok, err = pcall(equipSet, key)
        if not ok and type(k.problems) == "table" then k.problems:add(SetIcons.NAME, "click", tostring(err)) end
    end

    -- Draws what is saved and worn now. Off, or no set saved: hidden.
    draw = function()
        if not ctx then return end
        if ctx.settings:get(SetIcons.SETTING) ~= true then
            if row then
                row.draw({}, nil)
                row.show(false)
            end
            return
        end
        local sets = ns.GearSets.Saved(ctx.store)
        if #sets == 0 then
            if row then
                row.draw({}, nil)
                row.show(false)
            end
            return
        end
        if not made() then return end
        row.draw(SetIcons.Icons(sets, SetIcons.WornKeys(read("wornLinks")), nameOf, textureOf), act)
        row.show(true)
    end
    api.redraw = draw

    local function redraw()
        local ok, err = pcall(draw)
        if not ok and type(k.problems) == "table" then k.problems:add(SetIcons.NAME, "draw", tostring(err)) end
    end

    k:Module({
        name = SetIcons.NAME,
        needs = { "client", "store", "bus", "settings" },
        settings = { {
            key = SetIcons.SETTING, scope = "account", type = "bool", default = false,
            label = "Set icons",
            help = "A small row with an icon for each set you saved (set save <name>): the set you wear has a "
                .. "gold edge, and hovering one lists its pieces. Click one to put on its pieces from your bags, "
                .. "out of combat only. Drag the row by its edge to move it.",
            group = "gear", synonyms = { "set", "sets", "icons", "outfit", "equip", "swap" },
        } },
        provides = { Row = api.row },
        start = function(c)
            ctx = c
            local function watch(scope, path)
                local cancel = c.store:watch(scope, path, redraw)
                if type(cancel) == "function" then cancels[#cancels + 1] = cancel end
            end
            local setting = c.settings:row(SetIcons.SETTING)
            if type(setting) == "table" then
                watch(setting.scope, setting.path or ("settings." .. SetIcons.SETTING))
            end
            watch("char", ns.GearSets.PATH)
            -- What you wear changed, or the reads became known: drawn again.
            -- Draws only; nothing is put on.
            c.bus:on(SetIcons.NAME, "PLAYER_EQUIPMENT_CHANGED", redraw)
            c.bus:on(SetIcons.NAME, "PLAYER_ENTERING_WORLD", redraw)
            redraw()
        end,
        stop = function()
            for i = 1, #cancels do pcall(cancels[i]) end
            cancels = {}
            if row then row.show(false) end
            ctx = nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.gearSetIcons = SetIcons.Declare(ns)
