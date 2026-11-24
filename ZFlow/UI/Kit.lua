-- The shared window kit (lead sections 287 and 291 item 1): one description
-- of a window and its parts, checked here and drawn by the client
-- (client.kitWindow, Core/Client.lua). Every player window is built from
-- these parts, so every window looks the same and is changed in one place.
--
-- LOOK ONLY. Nothing here sells, buys, moves, casts or clicks anything. A
-- part carries the caller's own function (onClick, onToggle ...); the kit
-- only hands it to the client's widget.
--
-- Pure: no client and no kernel. The only other file it asks is
-- Items/Prices.lua, for coin text (the one place that builds it).
--
--   Kit.Window(spec) -> tree | nil, reason
--     spec: id (a word: letters, digits, _), title, children (a list of
--     parts); optional width, height, point, movable, closable, escape,
--     resizable. A tree is a checked copy with every default filled in and
--     a `path` on every part ("3", "5.1" for a row's control, "8.2" for the
--     second part in a scroll). A window that lists things (a scroll, a
--     topic list or an item line) can be resized unless told otherwise.
--   Kit.Check(part)  -> true | nil, reason      one part on its own
--   Kit.Money(copper) -> { text, coins = { { coin, amount, icon } } } | nil
--   Kit.Quality(q)   -> { r, g, b, hex, known }  the stock item colours
--   Kit.Place(saved, tree) -> point, width, height
--   Kit.BindText(key) -> the key's name, or "Not Bound"
--   Kit.Each(tree, fn)   fn(part) for every part, in drawing order
--   Kit.TextOf(part) -> the words a part shows first, or nil
--   Kit.look             every size, colour, font and stock art name
--
-- The parts (kind =):
--   header     title; search = { onText(text), placeholder, text }
--   tabs       items = { text ... }, selected, onSelect(i)
--   topicList  items = { text ... }, selected, onSelect(i). Stands at the
--              left, the full height of the window; every part after it is
--              drawn in the pane at its right.
--   section    text; folded (true | false) with onFold(folded) when it folds
--              big (true): the pane's page heading (lead section 340)
--   line       text, icon, sub (a second line), right (a short text at the
--              right), tone, tooltip, enabled, onClick()
--   row        label, description, tooltip, enabled, reason, control (one
--              of: checkbox, bind, button, choice, number, text)
--   button     text, onClick(), enabled, tooltip
--   checkbox   checked, onToggle(checked), label, enabled
--   bind       key (the bound key's name, or nil), onClick(), waiting
--   choice     items = { text ... }, selected, onSelect(i)        (a control)
--              drop = true: one box that opens the list (a dropdown)
--   number     value, min, max, step, onChange(value)             (a control)
--              with both min and max it is drawn as a slider
--   text       text, onText(text)                                 (a control)
--   scroll     children, height. No scroll, header, tabs, topic list or
--              footer stands in a scroll.
--   itemLine   name, quality (0..5), count, money (whole copper), icon,
--              item, note, tone ("good" | "warn" | "bad")
--   empty      text (what is missing), how (how to get it): both needed
--   footer     text, money (whole copper), slot (a name another lane's
--              button is put in), buttons = { button ... }
-- Any part but a bind may carry `key`, a name for tests and for the caller
-- to find it by; a key may be given once in a window.
local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit

Kit.WIDTH, Kit.HEIGHT = 420, 480
Kit.MIN_WIDTH, Kit.MIN_HEIGHT = 320, 240
Kit.POINT = { "CENTER", "CENTER", 0, 0 }
Kit.SEARCH = "Search"
Kit.NOT_BOUND = "Not Bound"
Kit.BIND_WAITING = "Press a key..."
Kit.SCROLL_HEIGHT = 240

-- Every size, colour, font and Blizzard part name: the one theme file,
-- UI/Kit/Theme.lua (loaded before this file).
Kit.look = ns.KitTheme

-- The stock item colours, by quality 0 (poor) to 5 (legendary).
local QUALITY = {
    [0] = { 0.62, 0.62, 0.62, "9d9d9d" },
    [1] = { 1, 1, 1, "ffffff" },
    [2] = { 0.12, 1, 0, "1eff00" },
    [3] = { 0, 0.44, 0.87, "0070dd" },
    [4] = { 0.64, 0.21, 0.93, "a335ee" },
    [5] = { 1, 0.5, 0, "ff8000" },
}
local TONES = { good = true, warn = true, bad = true }
local CONTROLS = { checkbox = true, bind = true, button = true, choice = true, number = true, text = true }
-- What may not stand in a scroll.
local NOT_IN_SCROLL = { scroll = true, header = true, tabs = true, topicList = true, footer = true }

local function isText(v) return type(v) == "string" and v ~= "" end
local function isFlag(v) return v == true or v == false end
local function isAmount(v) return type(v) == "number" and v == v and v > -math.huge and v < math.huge end
local function isWhole(v) return isAmount(v) and v >= 0 and v == math.floor(v) end
local function isPoint(p)
    return type(p) == "table" and type(p[1]) == "string" and type(p[2]) == "string"
        and isAmount(p[3]) and isAmount(p[4])
end

-- The colour of an item of that quality: { r, g, b, hex, known }. Anything
-- that is not a quality 0 to 5 is common white, and known = false.
function Kit.Quality(q)
    local row = QUALITY[q]
    local known = row ~= nil
    if not known then row = QUALITY[1] end
    return { r = row[1], g = row[2], b = row[3], hex = row[4], known = known }
end

-- Whole copper as coin parts, largest first, each with its stock coin icon,
-- and the same amount as text. A part that is zero is left out, as
-- Prices.Coin leaves it out; nothing at all is "0c". nil for anything that
-- is not whole copper, 0 or more. The text is Prices.Coin's (nil when that
-- file is not loaded).
function Kit.Money(copper)
    if not isWhole(copper) then return nil end
    local art = Kit.look.art
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local rest = copper % 100
    local coins = {}
    if gold > 0 then coins[#coins + 1] = { coin = "gold", amount = gold, icon = art.gold } end
    if silver > 0 then coins[#coins + 1] = { coin = "silver", amount = silver, icon = art.silver } end
    if rest > 0 or #coins == 0 then coins[#coins + 1] = { coin = "copper", amount = rest, icon = art.copper } end
    local text
    local prices = ns.Prices
    if type(prices) == "table" and type(prices.Coin) == "function" then text = prices.Coin(copper) end
    return { text = text, coins = coins }
end

function Kit.BindText(key)
    if isText(key) then return key end
    return Kit.NOT_BOUND
end

---------------------------------------------------------------------------
-- Checking. Each kind has one function: it reads the given part `p`, fills
-- the copy `out`, and answers true, or nil and a reason naming the field.
---------------------------------------------------------------------------

local function needText(p, out, field, what)
    if not isText(p[field]) then return nil, what .. " needs " .. field .. ": text that is not empty" end
    out[field] = p[field]
    return true
end

local function someText(p, out, field, what)
    local v = p[field]
    if v == nil then return true end
    if type(v) ~= "string" then return nil, what .. ": " .. field .. " must be text" end
    out[field] = v
    return true
end

-- An icon: a texture path, or the file number the game gives for one.
local function someIcon(p, out, what)
    local v = p.icon
    if v == nil then return true end
    if type(v) ~= "string" and not (isAmount(v) and v > 0) then
        return nil, what .. ": icon must be a texture path or a file number"
    end
    out.icon = v
    return true
end

local function needFn(p, out, field, what)
    if type(p[field]) ~= "function" then return nil, what .. " needs " .. field .. ": a function" end
    out[field] = p[field]
    return true
end

local function flag(p, out, field, default, what)
    local v = p[field]
    if v == nil then v = default end
    if not isFlag(v) then return nil, what .. ": " .. field .. " must be true or false" end
    out[field] = v
    return true
end

-- A list of texts, none empty. `least` is how many it needs.
local function texts(p, out, field, least, what)
    local list = p[field]
    if type(list) ~= "table" or #list < least then
        return nil, what .. " needs " .. field .. ": a list of at least " .. least .. " text"
    end
    local copy = {}
    for i = 1, #list do
        if not isText(list[i]) then return nil, what .. ": " .. field .. " " .. i .. " must be text that is not empty" end
        copy[i] = list[i]
    end
    out[field] = copy
    return true
end

-- Which of `n` is chosen: the first unless told.
local function chosen(p, out, n, what)
    local sel = p.selected
    if sel == nil then
        if n > 0 then out.selected = 1 end
        return true
    end
    if not isWhole(sel) or sel < 1 or sel > n then
        return nil, what .. ": selected must be a place in its " .. n .. " items"
    end
    out.selected = sel
    return true
end

local PARTS = {}
local norm

-- The checked copies of a list of parts. `prefix` is "" at the top of a
-- window and "8." inside the part at 8.
local function parts(list, prefix, ctx, what)
    if type(list) ~= "table" then return nil, what .. ": children must be a list of parts" end
    local out = {}
    for i = 1, #list do
        local child, why = norm(list[i], prefix .. i, ctx)
        if not child then return nil, why end
        out[i] = child
    end
    return out
end

function PARTS.header(p, out)
    local ok, why = needText(p, out, "title", "a header")
    if not ok then return nil, why end
    if p.search == nil then return true end
    if type(p.search) ~= "table" then return nil, "a header: search must be a table with onText" end
    local search = {}
    ok, why = needFn(p.search, search, "onText", "a header's search")
    if not ok then return nil, why end
    ok, why = someText(p.search, search, "placeholder", "a header's search")
    if not ok then return nil, why end
    ok, why = someText(p.search, search, "text", "a header's search")
    if not ok then return nil, why end
    if not isText(search.placeholder) then search.placeholder = Kit.SEARCH end
    if search.text == nil then search.text = "" end
    out.search = search
    return true
end

local function picker(what, least)
    return function(p, out)
        local ok, why = texts(p, out, "items", least, what)
        if not ok then return nil, why end
        ok, why = chosen(p, out, #out.items, what)
        if not ok then return nil, why end
        return needFn(p, out, "onSelect", what)
    end
end
PARTS.tabs = picker("tabs", 1)
do
    local plainChoice = picker("a choice", 1)
    -- drop = true: drawn as one box showing the item in use, which opens
    -- the list of items under it (the game's dropdown), not a row of buttons.
    function PARTS.choice(p, out)
        if p.drop ~= nil and type(p.drop) ~= "boolean" then return nil, "a choice: drop must be true or false" end
        if p.drop == true then out.drop = true end
        return plainChoice(p, out)
    end
end

do
    local topics = picker("a topic list", 0)
    function PARTS.topicList(p, out, _, ctx)
        ctx.lists = true
        return topics(p, out)
    end
end

function PARTS.section(p, out)
    local ok, why = needText(p, out, "text", "a section")
    if not ok then return nil, why end
    -- Lead section 340: big = true draws it as the pane's page heading.
    if p.big ~= nil then
        if not isFlag(p.big) then return nil, "a section: big must be true or false" end
        out.big = p.big
    end
    -- A section that folds says which way it is and whom to tell.
    if p.folded == nil then return true end
    if not isFlag(p.folded) then return nil, "a section: folded must be true or false" end
    out.folded = p.folded
    return needFn(p, out, "onFold", "a section that folds")
end

-- A list row: a name, and optionally an icon, a second line under the
-- name, a short text at the right (in a tone) and a click.
function PARTS.line(p, out)
    local ok, why = needText(p, out, "text", "a line")
    if not ok then return nil, why end
    ok, why = someIcon(p, out, "a line")
    if not ok then return nil, why end
    for _, field in ipairs({ "sub", "right", "tooltip" }) do
        ok, why = someText(p, out, field, "a line")
        if not ok then return nil, why end
    end
    if p.tone ~= nil then
        if not TONES[p.tone] then return nil, "a line: tone must be good, warn or bad" end
        out.tone = p.tone
    end
    ok, why = flag(p, out, "enabled", true, "a line")
    if not ok then return nil, why end
    if p.onClick ~= nil then
        if type(p.onClick) ~= "function" then return nil, "a line: onClick must be a function" end
        out.onClick = p.onClick
    end
    return true
end

function PARTS.button(p, out)
    local ok, why = needText(p, out, "text", "a button")
    if not ok then return nil, why end
    ok, why = needFn(p, out, "onClick", "a button")
    if not ok then return nil, why end
    ok, why = flag(p, out, "enabled", true, "a button")
    if not ok then return nil, why end
    return someText(p, out, "tooltip", "a button")
end

function PARTS.checkbox(p, out)
    local ok, why = flag(p, out, "checked", false, "a checkbox")
    if not ok then return nil, why end
    ok, why = needFn(p, out, "onToggle", "a checkbox")
    if not ok then return nil, why end
    ok, why = flag(p, out, "enabled", true, "a checkbox")
    if not ok then return nil, why end
    return someText(p, out, "label", "a checkbox")
end

-- A bind button's `key` is the bound key's name, not a name for the part.
function PARTS.bind(p, out)
    if p.key ~= nil and type(p.key) ~= "string" then return nil, "a bind button: key must be text or nil" end
    local ok, why = needFn(p, out, "onClick", "a bind button")
    if not ok then return nil, why end
    ok, why = flag(p, out, "waiting", false, "a bind button")
    if not ok then return nil, why end
    ok, why = flag(p, out, "enabled", true, "a bind button")
    if not ok then return nil, why end
    if isText(p.key) then out.bound = p.key end
    if out.waiting then
        out.text = Kit.BIND_WAITING
    else
        out.text = Kit.BindText(p.key)
    end
    return true
end

function PARTS.number(p, out)
    if not isAmount(p.value) then return nil, "a number needs value: a number" end
    out.value = p.value
    for _, field in ipairs({ "min", "max", "step" }) do
        local v = p[field]
        if v ~= nil then
            if not isAmount(v) then return nil, "a number: " .. field .. " must be a number" end
            out[field] = v
        end
    end
    if out.step == nil then out.step = 1 end
    if out.step <= 0 then return nil, "a number: step must be above 0" end
    if out.min ~= nil and out.max ~= nil and out.min > out.max then return nil, "a number: min must not be above max" end
    return needFn(p, out, "onChange", "a number")
end

function PARTS.text(p, out)
    local ok, why = someText(p, out, "text", "a text box")
    if not ok then return nil, why end
    if out.text == nil then out.text = "" end
    return needFn(p, out, "onText", "a text box")
end

function PARTS.row(p, out, path, ctx)
    local ok, why = needText(p, out, "label", "a row")
    if not ok then return nil, why end
    for _, field in ipairs({ "description", "tooltip", "reason" }) do
        ok, why = someText(p, out, field, "a row")
        if not ok then return nil, why end
    end
    ok, why = flag(p, out, "enabled", true, "a row")
    if not ok then return nil, why end
    if p.control == nil then return true end
    if type(p.control) ~= "table" or not CONTROLS[p.control.kind] then
        return nil, "a row: control must be a checkbox, bind, button, choice, number or text"
    end
    local control, whyControl = norm(p.control, path .. ".1", ctx)
    if not control then return nil, whyControl end
    out.control = control
    return true
end

function PARTS.scroll(p, out, path, ctx)
    local height = p.height
    if height == nil then height = Kit.SCROLL_HEIGHT end
    if not isAmount(height) or height <= 0 then return nil, "a scroll: height must be a number above 0" end
    out.height = height
    ctx.lists = true
    ctx.inScroll = true
    local children, why = parts(p.children, path .. ".", ctx, "a scroll")
    ctx.inScroll = false
    if not children then return nil, why end
    out.children = children
    return true
end

function PARTS.itemLine(p, out, _, ctx)
    ctx.lists = true
    local ok, why = needText(p, out, "name", "an item line")
    if not ok then return nil, why end
    if p.quality ~= nil then
        if not isWhole(p.quality) or p.quality > 5 then return nil, "an item line: quality must be 0 to 5" end
        out.quality = p.quality
    end
    out.color = Kit.Quality(p.quality)
    if p.count ~= nil then
        if not isWhole(p.count) then return nil, "an item line: count must be a whole number, 0 or more" end
        out.count = p.count
    end
    if p.money ~= nil then
        local coins = Kit.Money(p.money)
        if not coins then return nil, "an item line: money must be whole copper, 0 or more" end
        out.money = p.money
        out.coins = coins
    end
    if p.item ~= nil then
        if type(p.item) ~= "number" and type(p.item) ~= "string" then
            return nil, "an item line: item must be an item number or a link"
        end
        out.item = p.item
    end
    ok, why = someIcon(p, out, "an item line")
    if not ok then return nil, why end
    ok, why = someText(p, out, "note", "an item line")
    if not ok then return nil, why end
    if p.tone ~= nil then
        if not TONES[p.tone] then return nil, "an item line: tone must be good, warn or bad" end
        out.tone = p.tone
    end
    return true
end

-- The line a list shows in place of nothing: what is missing, and how to
-- get it. Both are needed, so no window is ever blank or a dead end.
function PARTS.empty(p, out)
    local ok, why = needText(p, out, "text", "an empty-state line")
    if not ok then return nil, why end
    return needText(p, out, "how", "an empty-state line")
end

function PARTS.footer(p, out, path, ctx)
    local ok, why = someText(p, out, "text", "a footer")
    if not ok then return nil, why end
    if p.money ~= nil then
        local coins = Kit.Money(p.money)
        if not coins then return nil, "a footer: money must be whole copper, 0 or more" end
        out.money = p.money
        out.coins = coins
    end
    if p.slot ~= nil then
        if not isText(p.slot) then return nil, "a footer: slot must be a name" end
        out.slot = p.slot
    end
    out.buttons = {}
    if p.buttons == nil then return true end
    if type(p.buttons) ~= "table" then return nil, "a footer: buttons must be a list of buttons" end
    for i = 1, #p.buttons do
        local b = p.buttons[i]
        if type(b) ~= "table" or b.kind ~= "button" then return nil, "a footer: buttons must be a list of buttons" end
        local button, whyButton = norm(b, path .. "." .. i, ctx)
        if not button then return nil, whyButton end
        out.buttons[i] = button
    end
    return true
end

norm = function(p, path, ctx)
    if type(p) ~= "table" then return nil, "a part must be a table with a kind" end
    local check = PARTS[p.kind]
    if check == nil then return nil, "kind " .. tostring(p.kind) .. " is not a part of the kit" end
    if ctx.inScroll and NOT_IN_SCROLL[p.kind] then
        return nil, "a " .. p.kind .. " may not stand in a scroll"
    end
    local out = { kind = p.kind, path = path }
    if p.kind ~= "bind" and p.key ~= nil then
        if not isText(p.key) then return nil, "a part's key must be text that is not empty" end
        if ctx.keys[p.key] then return nil, "the key " .. p.key .. " is given twice in one window" end
        ctx.keys[p.key] = true
        out.key = p.key
    end
    local ok, why = check(p, out, path, ctx)
    if not ok then return nil, why end
    return out
end

local function newCtx() return { keys = {}, lists = false, inScroll = false } end

function Kit.Check(part)
    local out, why = norm(part, "1", newCtx())
    if not out then return nil, why end
    return true
end

local function size(v, default, field)
    if v == nil then return default end
    if not isAmount(v) or v <= 0 then return nil, "a window: " .. field .. " must be a number above 0" end
    return v
end

function Kit.Window(spec)
    if type(spec) ~= "table" then return nil, "a window must be a table with id, title and children" end
    if type(spec.id) ~= "string" or not spec.id:match("^%a[%w_]*$") then
        return nil, "a window needs id: one word of letters, digits and _"
    end
    local tree = { kind = "window", id = spec.id }
    local ok, why = needText(spec, tree, "title", "a window")
    if not ok then return nil, why end
    if type(spec.children) ~= "table" then return nil, "a window: children must be a list of parts" end
    local width, whyW = size(spec.width, Kit.WIDTH, "width")
    if not width then return nil, whyW end
    local height, whyH = size(spec.height, Kit.HEIGHT, "height")
    if not height then return nil, whyH end
    tree.width, tree.height = width, height
    tree.minWidth, tree.minHeight = math.min(width, Kit.MIN_WIDTH), math.min(height, Kit.MIN_HEIGHT)
    for _, field in ipairs({ "movable", "closable", "escape" }) do
        ok, why = flag(spec, tree, field, true, "a window")
        if not ok then return nil, why end
    end
    local point = spec.point
    if point == nil then point = Kit.POINT end
    if not isPoint(point) then return nil, "a window: point must be anchor, screen anchor, x, y" end
    tree.point = { point[1], point[2], point[3], point[4] }
    local ctx = newCtx()
    local children, whyKids = parts(spec.children, "", ctx, "a window")
    if not children then return nil, whyKids end
    tree.children = children
    ok, why = flag(spec, tree, "resizable", ctx.lists, "a window")
    if not ok then return nil, why end
    return tree
end

-- Where a window stands and how big it is: what was saved when that is
-- whole, else the window's own. The place and the size are judged apart. A
-- window that cannot be resized keeps its own size whatever was saved.
function Kit.Place(saved, tree)
    tree = type(tree) == "table" and tree or {}
    local own = isPoint(tree.point) and tree.point or Kit.POINT
    local point = { own[1], own[2], own[3], own[4] }
    local width, height = tree.width or Kit.WIDTH, tree.height or Kit.HEIGHT
    if type(saved) ~= "table" then return point, width, height end
    if isPoint(saved.point) then
        point = { saved.point[1], saved.point[2], saved.point[3], saved.point[4] }
    end
    if tree.resizable == true and isAmount(saved.width) and isAmount(saved.height) then
        local least = tree.minWidth or Kit.MIN_WIDTH
        local leastH = tree.minHeight or Kit.MIN_HEIGHT
        if saved.width >= least and saved.height >= leastH then
            width, height = saved.width, saved.height
        end
    end
    return point, width, height
end

-- fn(part) for every part of a tree, in the order it is drawn: a part,
-- then its control, its children or its buttons.
function Kit.Each(tree, fn)
    if type(tree) ~= "table" or type(fn) ~= "function" then return end
    local function walk(list)
        for i = 1, #(list or {}) do
            local part = list[i]
            fn(part)
            if part.control then fn(part.control) end
            if part.children then walk(part.children) end
            if part.buttons then walk(part.buttons) end
        end
    end
    walk(tree.children)
end

-- The words a part shows first: a header's title, a row's label, an item
-- line's name; nil for a part with no words of its own.
function Kit.TextOf(part)
    if type(part) ~= "table" then return nil end
    return part.title or part.label or part.name or part.text
end
