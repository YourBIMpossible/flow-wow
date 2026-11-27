local _, ns = ...
-- The Cooldowns display (button spec Step 2, lead section 624): one
-- small face for each spell or item the rotation is offering that is
-- on its own cooldown, so the wait is drawn where the player looks —
-- the dark sweep over the picture and the seconds in the middle —
-- instead of living only in the rotation icon's caption, which fades
-- exactly while the Flow button holds that spell.
--
-- The tracked set is the rotation's own plan (the Flow button's spell
-- and the modifier slots) plus the self button's buff pick, read from
-- the driver's view; a spell shows only while c.spellCooldown reads
-- true (its own cooldown, the global cooldown told apart by that
-- read), an item while c.itemCooldown reads above zero. A cooldown
-- that cannot be read shows nothing: the display never guesses, and
-- in a fight, where the time is hidden, the reads answer nil and the
-- face stays away.
--
-- Two layouts, by the flowButton.layout choice (Step 1's row, another
-- lane's file; until it lands the read answers nil and the display
-- stands Separate, the default): Separate — the faces stand in a row
-- at their own saved place (cooldowns.place), first face always shown
-- so the group can be found and dragged by its grip when nothing is
-- cooling down. Combined — one face at the Flow button's size,
-- anchored to its right, showing the soonest spell only.
--
-- Seconds are bare numbers, the predecessor's way: whole seconds at
-- ten and above, one decimal under ten, minutes rounded up at sixty;
-- under CD.MIN_LEFT seconds nothing is written, so the global
-- cooldown after a cast never flashes a number. Items get the sweep
-- and no seconds.
--
-- The drawing is the client's c.cooldownFace (Step 4); the faces are
-- look-only: no mouse, no action, never secure, nothing cast.
-- Not seen in game.
local CD = {}
ns.Cooldowns = CD

local D = ns.RotationDriver

CD.NAME = "cooldowns"
CD.SETTING = "cooldowns.place"
CD.PATH = "layout.cooldowns.frame"
CD.DEFAULT_POINT = { "CENTER", "CENTER", 380, 220 }
CD.SIZE = 38          -- a face in the Separate group
CD.COMBINED_SIZE = 58 -- the Combined face: the Flow button's size
CD.GAP = 4
CD.MIN_LEFT = 1.5
CD.MAX_FACES = 7
CD.FACE_NAME = "ZFlowCooldownFace1"
CD.COMBINED_NAME = "ZFlowCooldownFaceBig"
CD.MODE_SETTING = "flowButton.layout"

-- The seconds as they are written on a face: nil when the time is
-- not a number or is at the threshold (the global cooldown is not
-- worth a number); else the bare count.
function CD.Text(left)
    if type(left) ~= "number" or left ~= left then return nil end
    if left <= CD.MIN_LEFT then return nil end
    if left >= 60 then return string.format("%dm", math.ceil(left / 60)) end
    if left >= 10 then return string.format("%d", math.floor(left + 0.5)) end
    return string.format("%.1f", left)
end

-- The layout mode from the setting's value: only "combined" combines.
function CD.ModeOf(value)
    if value == "combined" then return "combined" end
    return "separate"
end

-- Soonest ready first; on a tie the Flow button's own spell (first)
-- stands ahead, then the order the rows came in.
function CD.Order(rows)
    local out = {}
    if type(rows) == "table" then
        for i = 1, #rows do
            local r = rows[i]
            if type(r) == "table" then out[#out + 1] = { row = r, at = i } end
        end
    end
    table.sort(out, function(a, b)
        local la, lb = a.row.left, b.row.left
        if type(la) ~= "number" then la = math.huge end
        if type(lb) ~= "number" then lb = math.huge end
        if la ~= lb then return la < lb end
        if (a.row.first == true) ~= (b.row.first == true) then return a.row.first == true end
        return a.at < b.at
    end)
    local sorted = {}
    for i = 1, #out do sorted[i] = out[i].row end
    return sorted
end

local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, got = pcall(client[name], ...)
    if not ok then return nil end
    return got
end

-- One plan entry -> a tracked row { kind, id }, or nil: a spell name
-- the client cannot number, or an item that carries no number, is
-- left out rather than guessed at.
local function resolve(client, entry, first)
    if type(entry) ~= "table" then return nil end
    if type(entry.spell) == "string" then
        local id = ask(client, "spellId", entry.spell)
        if type(id) ~= "number" then return nil end
        local row = { kind = "spell", id = id }
        if first then row.first = true end
        return row
    end
    local item = entry.item
    local id = nil
    if type(item) == "number" then
        id = item
    elseif type(item) == "string" then
        local digits = string.match(item, "^item:(%d+)$")
        if digits ~= nil then id = tonumber(digits) end
    end
    if id == nil then return nil end
    local row = { kind = "item", id = id }
    if first then row.first = true end
    return row
end

local function packOf(client)
    local class = ask(client, "class")
    if type(class) ~= "string" or type(ns.Packs) ~= "table" then return nil end
    return ns.Packs[class]
end

-- The tracked set for one driver view, in plan order (the Flow
-- button's slot first, marked first), each spell or item once, the
-- self button's buff pick last. Not a plan view: nothing.
function CD.Tracked(client, view)
    local rows = {}
    if type(view) ~= "table" or type(view.attrs) ~= "table" or view.attrs.ok ~= true then return rows end
    if type(ns.ClickSlots) ~= "table" or type(ns.ClickSlots.Plan) ~= "function" then return rows end
    local ok, plan = pcall(ns.ClickSlots.Plan, view.attrs.button, nil)
    if not ok or type(plan) ~= "table" then return rows end
    local seen = {}
    local slots = ns.ClickSlots.SLOTS
    if type(slots) ~= "table" then slots = { "key" } end
    for i = 1, #slots do
        local entry = plan[slots[i]]
        local row = resolve(client, entry, slots[i] == "key")
        if row ~= nil then
            local mark = row.kind .. ":" .. tostring(row.id)
            if seen[mark] ~= true then
                seen[mark] = true
                rows[#rows + 1] = row
            end
        end
    end
    local FB = ns.FlowButton
    if type(FB) == "table" and type(FB.SelfPick) == "function" then
        local okPick, pick = pcall(FB.SelfPick, view.snapshot, packOf(client), plan.key)
        if okPick then
            local row = resolve(client, pick, false)
            if row ~= nil then
                local mark = row.kind .. ":" .. tostring(row.id)
                if seen[mark] ~= true then rows[#rows + 1] = row end
            end
        end
    end
    return rows
end

-- The rows that are on cooldown now, with the seconds left where the
-- client tells them (items: the seconds order the faces but are
-- never written on them).
local function cooling(client, view)
    local out = {}
    local rows = CD.Tracked(client, view)
    for i = 1, #rows do
        local row = rows[i]
        if row.kind == "spell" then
            if ask(client, "spellCooldown", row.id) == true then
                row.left = ask(client, "spellCooldownLeft", row.id)
                out[#out + 1] = row
            end
        else
            local left = ask(client, "itemCooldown", row.id)
            if type(left) == "number" and left > 0 then
                row.left = left
                out[#out + 1] = row
            end
        end
    end
    return CD.Order(out)
end

local function isPoint(p)
    return type(p) == "table" and type(p[1]) == "string" and type(p[2]) == "string"
        and type(p[3]) == "number" and type(p[4]) == "number"
end

function CD.Declare(k)
    local client, settings = nil, nil
    local lastView = nil
    local faces, bigFace, grip = {}, nil, nil
    local pendingPoint = nil

    local function setting(key)
        if settings == nil then return nil end
        local ok, got = pcall(settings.get, settings, key)
        if not ok then return nil end
        return got
    end

    local function groupPoint()
        if isPoint(pendingPoint) then return pendingPoint end
        local saved = setting(CD.SETTING)
        if isPoint(saved) then return saved end
        return CD.DEFAULT_POINT
    end

    local function faceAt(i)
        if faces[i] == nil then
            local spec = { size = CD.SIZE }
            if i == 1 then spec.name = CD.FACE_NAME end
            faces[i] = ask(client, "cooldownFace", spec)
        end
        return faces[i]
    end

    local function big()
        if bigFace == nil then
            bigFace = ask(client, "cooldownFace", { name = CD.COMBINED_NAME, size = CD.COMBINED_SIZE })
        end
        return bigFace
    end

    local function flowName()
        local FB = ns.FlowButton
        local base = "FlowButton"
        if type(FB) == "table" and type(FB.FRAME) == "string" then base = FB.FRAME end
        local prefix = nil
        if type(ns.id) == "table" then prefix = ns.id.framePrefix end
        if type(prefix) == "string" then return prefix .. base end
        return base
    end

    -- Draw one tracked row on one face: the picture, the sweep, the
    -- seconds (spells only). False when the client will not draw the
    -- sweep — the caller hides the face rather than show a guess.
    local function draw(h, row)
        local texture = nil
        if row.kind == "spell" then texture = ask(client, "spellTexture", row.id) end
        if row.kind == "item" then texture = ask(client, "itemTexture", row.id) end
        h.icon(texture)
        local swept = nil
        if row.kind == "spell" then swept = h.spell(row.id) end
        if row.kind == "item" then swept = h.item(row.id) end
        if swept ~= "sweep" then return false end
        if row.kind == "spell" then h.seconds(CD.Text(row.left)) end
        if row.kind == "item" then h.seconds(nil) end
        h.show(true)
        return true
    end

    local function hideFrom(i)
        for j = i, CD.MAX_FACES do
            if faces[j] ~= nil then faces[j].show(false) end
        end
    end

    local function drawGroup(ordered)
        local p = groupPoint()
        if #ordered == 0 then
            local h = faceAt(1)
            if h ~= nil then
                h.icon(nil)
                h.clear()
                h.place({ p[1], p[2], p[3], p[4] })
                h.show(true)
            end
            hideFrom(2)
            return
        end
        for i = 1, #ordered do
            local h = faceAt(i)
            if h ~= nil then
                h.place({ p[1], p[2], p[3] + (i - 1) * (CD.SIZE + CD.GAP), p[4] })
                if not draw(h, ordered[i]) then h.show(false) end
            end
        end
        hideFrom(#ordered + 1)
    end

    local function drawCombined(ordered)
        hideFrom(1)
        local h = big()
        if h == nil then return end
        local okAnchor = h.anchor("LEFT", flowName(), "RIGHT", 6, 0)
        if okAnchor ~= true then
            h.show(false)
            return
        end
        local row = ordered[1]
        if row == nil then
            h.icon(nil)
            h.clear()
            h.show(true)
            return
        end
        if not draw(h, row) then h.show(false) end
    end

    local function attachGrip()
        if grip ~= nil or faces[1] == nil then return end
        if type(ns.MoveHandle) ~= "table" or type(ns.MoveHandle.Attach) ~= "function" then return end
        local ok, handle = pcall(ns.MoveHandle.Attach, k, client, {
            target = CD.FACE_NAME,
            width = CD.MAX_FACES * (CD.SIZE + CD.GAP),
            height = CD.SIZE,
            quiet = true,
            place = function(point)
                pendingPoint = point
                drawGroup(cooling(client, lastView))
            end,
            save = function(point)
                pendingPoint = nil
                if settings ~= nil then pcall(settings.set, settings, CD.SETTING, point) end
            end,
        })
        if ok and type(handle) == "table" then grip = handle end
    end

    local function refresh()
        if client == nil then return end
        local live = setting(D.SETTING) == true and type(lastView) == "table" and lastView.pack == true
        local ordered = {}
        if live then ordered = cooling(client, lastView) end
        if CD.ModeOf(setting(CD.MODE_SETTING)) == "combined" then
            drawCombined(ordered)
        else
            if bigFace ~= nil then bigFace.show(false) end
            drawGroup(ordered)
            attachGrip()
        end
    end

    local function onView(view)
        lastView = view
        refresh()
    end

    local api = { Refresh = refresh }

    k:Module({
        name = CD.NAME,
        needs = { "client", "store", "bus", D.NAME },
        settings = { {
            key = CD.SETTING, scope = "account", type = "table", path = CD.PATH,
            label = "Cooldowns position", group = "combat",
            synonyms = { "cooldowns", "position", "move" },
            keepOnResetAll = true,
            help = "Where the cooldowns stand in the Separate button layout. Drag the grip on the group's left to move it, outside fights. Resetting puts it back.",
        } },
        start = function(ctx)
            client, settings = ctx.client, ctx.settings
            ctx.bus:on(CD.NAME, D.EVENT, onView)
            client.listen("PLAYER_REGEN_ENABLED", refresh)
            ctx.sched:every(CD.NAME, 1, refresh)
            refresh()
        end,
    })

    return api
end

ns.cooldowns = CD.Declare(ns)
