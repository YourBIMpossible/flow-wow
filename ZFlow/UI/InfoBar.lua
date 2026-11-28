local _, ns = ...
-- N59 (lead section 243): the info bar. A small movable strip or box that
-- shows the metrics the player chose (four by default): gold, free bag
-- slots, durability, experience, the watched reputation, server time,
-- hearthstone cooldown, frame rate and latency. Shown by default (lead
-- section 294: it is the info display); the player can turn it off, and a
-- saved choice is kept. Each metric is read from its own game event; the clock, frame rate,
-- latency and hearthstone on a slow timer only while the bar is shown. A
-- read the client does not answer shows as not available, never as zero.
-- Hover gives the details; a click opens the settings page only. A hidden
-- bar reads nothing and registers nothing. It never acts in the game.
-- Not tested in game.
local IB = {}
ns.InfoBar = IB

IB.NAME = "infoBar"
IB.TICK = 5
IB.WIDTH, IB.HEIGHT = 320, 20
IB.BOX_WIDTH, IB.BOX_HEIGHT = 160, 80
IB.CLICK = "Click to open the settings."
IB.DEFAULT = "gold bags durability xp"
IB.PLACE = "layout.infoBar"

-- id, the short word on the bar, the name in the tip.
IB.METRICS = {
    { id = "gold", label = "Gold", name = "Gold" },
    { id = "bags", label = "Bags", name = "Free bag slots" },
    { id = "durability", label = "Dur", name = "Durability" },
    { id = "xp", label = "XP", name = "Experience" },
    { id = "rep", label = "Rep", name = "Reputation" },
    { id = "clock", label = "Clock", name = "Server time" },
    { id = "hearth", label = "Hearth", name = "Hearthstone" },
    { id = "fps", label = "FPS", name = "Frame rate" },
    { id = "latency", label = "Latency", name = "Latency" },
}

local BY_ID = {}
for _, m in ipairs(IB.METRICS) do BY_ID[m.id] = m end

IB.NOT_AVAILABLE = "Not available"

-- An icon per metric (all-windows row 4): a small table in the bar,
-- not a new game read — the tile drawing is the client's, and these
-- are the pictures it draws from. First guesses, as elsewhere.
IB.ICONS = {
    gold = "Interface\\Icons\\INV_Misc_Coin_01",
    bags = "Interface\\Icons\\INV_Misc_Bag_07",
    durability = "Interface\\Icons\\Trade_BlackSmithing",
    xp = "Interface\\Icons\\INV_Misc_Star_01",
    rep = "Interface\\Icons\\INV_Banner_01",
    clock = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    hearth = "Interface\\Icons\\INV_Misc_Rune_01",
    fps = "Interface\\Icons\\INV_Misc_Gear_01",
    latency = "Interface\\Icons\\INV_Misc_Gear_02",
}

function IB.Icon(id) return IB.ICONS[id] end

-- The game events each metric is read on. The timed ones are read on the
-- slow timer while shown (hearthstone also when a cooldown changes).
IB.EVENTS = {
    gold = { "PLAYER_MONEY" },
    bags = { "BAG_UPDATE_DELAYED" },
    durability = { "UPDATE_INVENTORY_DURABILITY" },
    xp = { "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP" },
    rep = { "UPDATE_FACTION" },
    hearth = { "BAG_UPDATE_COOLDOWN" },
}
IB.TIMED = { clock = true, hearth = true, fps = true, latency = true }

local function finite(n) return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge end

-- The chosen ids, in the order given; unknown words and repeats left out.
function IB.Parse(s)
    local out, seen = {}, {}
    if type(s) ~= "string" then return out end
    for word in s:lower():gmatch("[^%s,]+") do
        if BY_ID[word] and not seen[word] then
            seen[word] = true
            out[#out + 1] = word
        end
    end
    return out
end

-- The money read is what the client said: an observed sum, written the
-- one way every price is (Items/Prices.lua).
local function money(n)
    local P = ns.Prices
    return P.Text({ value = math.floor(n), basis = P.OBSERVED }, "money")
end

local function freeSlots(rows)
    if type(rows) ~= "table" then return nil end
    local free, total = 0, 0
    for _, r in ipairs(rows) do
        if type(r) == "table" and (r.family == nil or r.family == 0) then
            if not finite(r.free) or not finite(r.total) then return nil end
            free, total = free + r.free, total + r.total
        end
    end
    return free, total
end

local function worst(slots)
    if type(slots) ~= "table" then return nil end
    local low
    for _, r in pairs(slots) do
        if type(r) == "table" and finite(r.cur) and finite(r.max) and r.max > 0 then
            local pct = math.floor(r.cur / r.max * 100)
            if low == nil or pct < low then low = pct end
        end
    end
    return low
end

local function xpOk(v)
    return type(v) == "table" and finite(v.cur) and finite(v.max) and v.max > 0
end

local function xpPct(v) return math.floor(v.cur / v.max * 100) end

local function repOk(v)
    return type(v) == "table" and type(v.name) == "string" and finite(v.min) and finite(v.max) and finite(v.value)
end

local function repPct(v)
    local width = v.max - v.min
    if width <= 0 then return 0 end
    return math.floor((v.value - v.min) / width * 100)
end

local function clockOk(v) return type(v) == "table" and finite(v.hour) and finite(v.minute) end
local function clock(v) return string.format("%02d:%02d", v.hour, v.minute) end
local function latencyOk(v) return type(v) == "table" and finite(v.home) and finite(v.world) end

-- The words on the bar: plain, with nothing abbreviated that needs
-- the tooltip to be sure what it is.
local SHORT = {
    gold = function(v) if finite(v) and v >= 0 then return money(v) end end,
    bags = function(v)
        local free = freeSlots(v)
        if free then return "Bags " .. free end
    end,
    durability = function(v)
        local low = worst(v)
        if low then return "Durability " .. low .. "%" end
    end,
    xp = function(v) if xpOk(v) then return "Experience " .. xpPct(v) .. "%" end end,
    rep = function(v)
        if v == false then return "Reputation: No faction watched" end
        if repOk(v) then
            local word = "Reputation"
            if type(v.label) == "string" then word = v.label end
            return word .. " " .. repPct(v) .. "%"
        end
    end,
    clock = function(v) if clockOk(v) then return clock(v) end end,
    hearth = function(v)
        if not finite(v) or v < 0 then return nil end
        if v == 0 then return "Hearthstone ready" end
        return "Hearthstone " .. math.ceil(v / 60) .. " min"
    end,
    fps = function(v) if finite(v) and v >= 0 then return math.floor(v) .. " fps" end end,
    latency = function(v) if latencyOk(v) then return v.world .. " ms" end end,
}

-- The longer line in the tip.
local DETAIL = {
    gold = function(v) if finite(v) and v >= 0 then return "Gold: " .. money(v) end end,
    bags = function(v)
        local free, total = freeSlots(v)
        if free then return "Free bag slots: " .. free .. " of " .. total end
    end,
    durability = function(v)
        local low = worst(v)
        if low then return "Durability: " .. low .. "% on the most worn item" end
    end,
    xp = function(v)
        if not xpOk(v) then return nil end
        local rested = finite(v.rested) and v.rested > 0 and ("rested " .. v.rested) or "not rested"
        return string.format("Experience: %d / %d (%d%%), %s", v.cur, v.max, xpPct(v), rested)
    end,
    rep = function(v)
        if v == false then return "Reputation: No faction watched" end
        if not repOk(v) then return nil end
        local parts = { v.name }
        if type(v.label) == "string" then parts[#parts + 1] = v.label end
        parts[#parts + 1] = string.format("%d / %d", v.value - v.min, v.max - v.min)
        return "Reputation: " .. table.concat(parts, ", ")
    end,
    clock = function(v) if clockOk(v) then return "Server time: " .. clock(v) end end,
    hearth = function(v)
        if not finite(v) or v < 0 then return nil end
        if v == 0 then return "Hearthstone: ready" end
        return "Hearthstone: " .. math.ceil(v / 60) .. " min"
    end,
    fps = function(v) if finite(v) and v >= 0 then return "Frame rate: " .. math.floor(v) .. " fps" end end,
    latency = function(v)
        if latencyOk(v) then return "Latency: home " .. v.home .. " ms, world " .. v.world .. " ms" end
    end,
}

function IB.Short(id, v)
    local m, fn = BY_ID[id], SHORT[id]
    if not m then return nil end
    local ok, s = pcall(fn, v)
    if ok and type(s) == "string" then return s end
    return m.name .. ": not available"
end

function IB.Detail(id, v)
    local m, fn = BY_ID[id], DETAIL[id]
    if not m then return nil end
    local ok, s = pcall(fn, v)
    if ok and type(s) == "string" then return s end
    return m.name .. ": not available"
end

-- A tile's value alone (the label stands under or beside it, in the
-- tile drawing): the same reads as the strip's words, without the
-- label folded in.
local VALUE = {
    gold = function(v) if finite(v) and v >= 0 then return money(v) end end,
    bags = function(v)
        local free = freeSlots(v)
        if free then return tostring(free) end
    end,
    durability = function(v)
        local low = worst(v)
        if low then return low .. "%" end
    end,
    xp = function(v) if xpOk(v) then return xpPct(v) .. "%" end end,
    rep = function(v)
        if v == false then return "No faction watched" end
        if repOk(v) then
            if type(v.label) == "string" then return v.label .. " " .. repPct(v) .. "%" end
            return repPct(v) .. "%"
        end
    end,
    clock = function(v) if clockOk(v) then return clock(v) end end,
    hearth = function(v)
        if not finite(v) or v < 0 then return nil end
        if v == 0 then return "Ready" end
        return math.ceil(v / 60) .. " min"
    end,
    fps = function(v) if finite(v) and v >= 0 then return tostring(math.floor(v)) end end,
    latency = function(v) if latencyOk(v) then return v.world .. " ms" end end,
}

-- The tiles (all-windows row 4): one per chosen metric, in order —
-- its icon, its full label, its value in plain words, and whether it
-- could be read. A metric that cannot be read keeps its tile and
-- says "Not available" in it, so absence is visible, never silent.
function IB.Tiles(ids, values)
    local out = {}
    if type(values) ~= "table" then values = {} end
    for _, id in ipairs(ids or {}) do
        local m, fn = BY_ID[id], VALUE[id]
        if m and fn then
            local ok, s = pcall(fn, values[id])
            local tile = { id = id, icon = IB.ICONS[id], label = m.name, available = false }
            if ok and type(s) == "string" then
                tile.text, tile.available = s, true
            else
                tile.text = IB.NOT_AVAILABLE
            end
            out[#out + 1] = tile
        end
    end
    return out
end

-- A strip on one line, a box one metric a line.
function IB.Text(ids, values, layout)
    local parts = {}
    values = type(values) == "table" and values or {}
    for _, id in ipairs(ids or {}) do parts[#parts + 1] = IB.Short(id, values[id]) end
    return table.concat(parts, layout == "box" and "\n" or "  |  ")
end

function IB.Tip(ids, values)
    local lines = {}
    values = type(values) == "table" and values or {}
    for _, id in ipairs(ids or {}) do lines[#lines + 1] = IB.Detail(id, values[id]) end
    lines[#lines + 1] = IB.CLICK
    return lines
end

-- A saved point { p1, p2, x, y }, or nil.
local function point(p)
    if type(p) ~= "table" or type(p[1]) ~= "string" or type(p[2]) ~= "string" then return nil end
    if not finite(p[3]) or not finite(p[4]) then return nil end
    return { p[1], p[2], p[3], p[4] }
end

local function size(s)
    if type(s) ~= "table" or not finite(s[1]) or not finite(s[2]) or s[1] <= 0 or s[2] <= 0 then return nil end
    return { s[1], s[2] }
end

local SYNONYMS = { "info", "bar", "data", "broker", "gold", "bags", "durability", "experience", "xp",
    "reputation", "clock", "fps", "latency", "hearthstone" }

function IB.Declare(k)
    local ctx, bar, broker
    local values, ids = {}, {}
    local cancels = {}
    local listening, timing = false, false
    local api = {}

    local function fail(where, err)
        k.problems:add(IB.NAME, where, tostring(err))
    end

    local function get(key) return ctx.settings:get(key) end

    -- One read through the client, by metric. A read that errors is
    -- unknown (nil) and recorded.
    local READ = {
        gold = function(c) return c.money() end,
        bags = function(c) return c.bags() end,
        durability = function(c) return c.durability() end,
        xp = function(c) return c.xp() end,
        rep = function(c) return c.watchedFaction() end,
        clock = function(c) return c.gameTime() end,
        hearth = function(c) return c.hearthCooldown() end,
        fps = function(c) return c.framerate() end,
        latency = function(c) return c.latency() end,
    }

    local function read(id)
        local fn = READ[id]
        local c = ctx and ctx.client
        if not fn or type(c) ~= "table" then return end
        local ok, v = pcall(fn, c)
        if ok then values[id] = v else values[id] = nil; fail("read " .. id, v) end
    end

    local function render()
        if not bar then return end
        local ok, err = pcall(bar.setText, IB.Text(ids, values, get("infoBar.layout")))
        if not ok then fail("text", err) end
        if broker then
            local okB, errB = pcall(function() broker.text = IB.Text(ids, values, "strip") end)
            if not okB then fail("broker", errB) end
        end
    end

    local function chosen(id)
        for _, x in ipairs(ids) do if x == id then return true end end
        return false
    end

    local function letGo()
        if listening then ctx.bus:off(IB.NAME); listening = false end
        if timing then ctx.sched:off(IB.NAME); timing = false end
    end

    local function listen()
        letGo()
        local wanted = {}
        for _, id in ipairs(ids) do
            for _, ev in ipairs(IB.EVENTS[id] or {}) do
                wanted[ev] = wanted[ev] or {}
                wanted[ev][#wanted[ev] + 1] = id
            end
        end
        for ev, list in pairs(wanted) do
            ctx.bus:on(IB.NAME, ev, function()
                for _, id in ipairs(list) do read(id) end
                render()
            end)
            listening = true
        end
        local timed = false
        for _, id in ipairs(ids) do if IB.TIMED[id] then timed = true end end
        if timed then
            ctx.sched:every(IB.NAME, IB.TICK, function()
                for _, id in ipairs(ids) do if IB.TIMED[id] then read(id) end end
                render()
            end)
            timing = true
        end
    end

    local function savePlace(change)
        local was = get("infoBar.place")
        local to = {}
        if type(was) == "table" then
            to.point, to.size = point(was.point), size(was.size)
        end
        for key, v in pairs(change) do to[key] = v end
        local ok, err = ctx.settings:set("infoBar.place", to)
        if not ok and err then fail("place", err) end
    end

    local function look()
        if not bar then return end
        local box = get("infoBar.layout") == "box"
        local place = get("infoBar.place")
        place = type(place) == "table" and place or {}
        local p = point(place.point) or { "TOP", "TOP", 0, -20 }
        local s = size(place.size) or (box and { IB.BOX_WIDTH, IB.BOX_HEIGHT } or { IB.WIDTH, IB.HEIGHT })
        bar.font(get("infoBar.fontSize"))
        bar.alpha(get("infoBar.opacity") / 100)
        bar.size(s[1], s[2])
        bar.place(p)
        bar.lock(get("infoBar.locked") == true)
    end

    local function make()
        if bar then return bar end
        local id = k.id or ns.id
        bar = ctx.client.infoBar({ name = id.framePrefix .. "InfoBar", width = IB.WIDTH, height = IB.HEIGHT })
        if not bar then return nil end
        bar.onMoved(function(p)
            local to = point(p)
            if to then savePlace({ point = to }) end
        end)
        bar.onResized(function(w, h)
            local to = size({ w, h })
            if to then savePlace({ size = to }) end
        end)
        bar.onHover(function(on)
            if on then bar.tip(IB.Tip(ids, values)) else bar.tip(nil) end
        end)
        bar.onClick(function()
            local sp = k.use and ns.SettingsPanel and k.use(ns.SettingsPanel.NAME)
            if type(sp) == "table" and type(sp.Show) == "function" then
                local ok, err = pcall(sp.Show, "general")
                if not ok then fail("click", err) end
            end
        end)
        -- The data broker feed only where the library is already loaded.
        if type(ctx.client.broker) == "function" then
            local ok, made = pcall(ctx.client.broker, (k.id or ns.id).framePrefix .. "InfoBar",
                { type = "data source", text = "", OnTooltipShow = function(tip)
                    for _, line in ipairs(IB.Tip(ids, values)) do
                        pcall(function() tip:AddLine(line) end)
                    end
                end })
            if ok and type(made) == "table" then broker = made end
        end
        return bar
    end

    -- Everything follows the settings: shown or not, which metrics, the look.
    local function refresh()
        if not ctx then return end
        if get("infoBar.shown") ~= true then
            letGo()
            values = {}
            if bar then
                bar.tip(nil)
                bar.show(false)
            end
            return
        end
        ids = IB.Parse(get("infoBar.metrics"))
        values = {}
        if not make() then return end
        listen()
        for _, id in ipairs(ids) do read(id) end
        look()
        render()
        bar.show(true)
    end

    local function safeRefresh()
        local ok, err = pcall(refresh)
        if not ok then fail("refresh", err) end
    end

    local function watch(key)
        local row = ctx.settings:row(key)
        if type(row) ~= "table" then return end
        local cancel = ctx.store:watch(row.scope, row.path or ("settings." .. key), function()
            if key == "infoBar.place" then
                local ok, err = pcall(look)
                if not ok then fail("look", err) end
            else
                safeRefresh()
            end
        end)
        if type(cancel) == "function" then cancels[#cancels + 1] = cancel end
    end

    function api.shown() return bar ~= nil and get("infoBar.shown") == true end
    function api.chosen(id) return chosen(id) end

    local function row(t)
        t.scope = "account"
        t.group = "general.windows"
        t.synonyms = SYNONYMS
        return t
    end

    k:Module({
        name = IB.NAME,
        needs = { "client", "store", "bus", "settings", "sched" },
        settings = {
            row({ key = "infoBar.shown", type = "bool", default = true, label = "Info bar",
                help = "A small bar with gold, free bag slots, durability and experience. "
                    .. "Shown until you turn it off. Hover for the details; a click opens these settings." }),
            row({ key = "infoBar.metrics", type = "string", default = IB.DEFAULT, label = "Info bar metrics",
                help = "The metrics shown, in order: gold, bags, durability, xp, rep, clock, hearth, fps, latency." }),
            row({ key = "infoBar.layout", type = "choice", choices = { "strip", "box" }, default = "strip",
                label = "Info bar layout", help = "A strip on one line, or a box with one metric a line." }),
            row({ key = "infoBar.locked", type = "bool", default = false, label = "Lock the info bar",
                help = "Locked, the bar is neither moved nor resized." }),
            row({ key = "infoBar.fontSize", type = "number", min = 8, max = 24, default = 12,
                label = "Info bar text size" }),
            row({ key = "infoBar.opacity", type = "number", min = 0, max = 100, default = 60,
                label = "Info bar background opacity", help = "0 is clear, 100 is solid." }),
            row({ key = "infoBar.place", type = "table", path = IB.PLACE, keepOnResetAll = true,
                label = "Info bar place and size" }),
        },
        provides = { Shown = api.shown },
        start = function(c)
            ctx = c
            for _, key in ipairs({ "infoBar.shown", "infoBar.metrics", "infoBar.layout", "infoBar.locked",
                "infoBar.fontSize", "infoBar.opacity", "infoBar.place" }) do
                watch(key)
            end
            safeRefresh()
        end,
        stop = function()
            for i = 1, #cancels do pcall(cancels[i]) end
            cancels = {}
            if ctx then pcall(letGo) end
            if bar then pcall(bar.show, false) end
            ctx = nil
        end,
    })
    return api
end

ns.infoBar = IB.Declare(ns)
