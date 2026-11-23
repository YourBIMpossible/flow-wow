local _, ns = ...
-- The Flow button and the self button (lead section 285 item 2b, sections
-- 294 and 295), as legacy Flow had them (Modules/Rotation/BuffButton.lua and
-- the main cast button): two buttons on the screen the player clicks.
--
--   Flow button  holds what the rotation suggests now (the plain key part of
--                the driver's attributes: type, spell, unit, item). On with
--                "Keep the rotation on one button" (rotation.keyFrame), which
--                is on by default; with the rotation off it shows a question
--                mark and holds nothing.
--   Self button  holds the first self buff the class pack wants that is not
--                on you (unit "player"). N15: seals, shouts, shields, Hunter's
--                Mark and the forms stay on the Flow button, never here. On
--                with buffButton.enabled, on by default (section 294); with
--                nothing to cast it still shows, holding nothing.
--
-- Each button casts only on the player's own click, or a key the player
-- binds to it on the settings page (UI/SettingsKeys.lua). Nothing here
-- clicks, binds or casts. Attributes are type "spell" or "item" only, never
-- a macro. Everything is set through ns.KeyFrame, only while the lock reads
-- a plain false; a change in a fight waits and is set after
-- PLAYER_REGEN_ENABLED. The hover tooltip says in one line what the button
-- holds, or what is missing. Section 297 item 5: no art path is named here;
-- the face is the spell or item icon the client reads, or, with nothing to
-- cast or no icon read, a plain panel drawn with colour only
-- (client.buttonFace), so a missing part never stops the button showing.
--
-- Size and place come from the Flow import (Import/Stored.lua): the Flow
-- button at layout.rotation.frame and scale, the self button docked under
-- it (buffButton.dock, on by default) at the dock scale, or at
-- layout.buffButton.frame and scale. The grip beside either one (the S29
-- move handle, UI/MoveHandle.lua) moves it, out of a fight; the place is
-- kept at those same paths. Moving a docked self button undocks it.
-- Lead section 305 item 1: nothing drags the secure button itself. It acts
-- on the press down (Core/Client.lua clickRow registers AnyUp and
-- AnyDown), so a drag that starts on it would also cast.
--
-- Client needs (Core/Client.lua): clickRow, buttonFace, moveHandle,
-- hoverTip, screen.
-- Not tested in game.
local FB = {}
ns.FlowButton = FB

local D = ns.RotationDriver
local K = ns.KeyFrame

FB.NAME = "flowButton"
FB.SETTING = K.SETTING               -- rotation.keyFrame: the Flow button
FB.LABEL = K.LABEL
FB.SELF_SETTING = "buffButton.enabled"
-- Lead section 305 item 4: the imported legacy buffButton.key, key2 and
-- always (Import/FromFlow.lua, kept under settings.buffButton) are not
-- applied. The add-on binds a key only when the player presses Set key on
-- the settings page (keys.flow, keys.self); binding an imported key at
-- load would be the add-on binding by itself. The player sets them again
-- on that page. always is not mapped: section 294 keeps the self button
-- shown even when it holds nothing, which is what always=true did, so
-- always=false (hide when empty) is not offered. Pinned in
-- Tests/E2E/FlowButton.lua.
FB.DOCK = "buffButton.dock"
FB.LAYOUT = "flowButton.place"
FB.PATH = "layout.rotation.frame"
FB.SELF_LAYOUT = "selfButton.place"
FB.SELF_PATH = "layout.buffButton.frame"
FB.FRAME = "FlowButton"
FB.SELF_FRAME = "SelfButton"
FB.SIZE = 52                         -- legacy BuffButton.lua BB.SIZE
FB.DOCK_GAP = 17                     -- legacy DOCK_GAP
FB.DEFAULT_POINT = { "CENTER", "CENTER", 0, -215 } -- authored: under the rotation icon
FB.SELF_LABEL = "Show the self buff button"
FB.DOCK_LABEL = "Keep the self button under the Flow button"
FB.PARTS = { "type", "spell", "unit", "item" }

-- N15: what stays on the Flow button (legacy BuffButton.lua:45-60).
FB.ON_ACTION = { "^Seal of ", " Shout$", " Shield$", "^Hunter's Mark$", "^Bear Form$",
                 "^Dire Bear Form$", "^Cat Form$", "^Moonkin Form$" }

function FB.OnAction(name)
    if type(name) ~= "string" then return false end
    for _, pat in ipairs(FB.ON_ACTION) do
        if name:find(pat) then return true end
    end
    return false
end

-- The self button's pick: the first buff rule of the list for this fight
-- that is not N15, wanted (its own when), known and ready. nil: nothing.
-- s: the driver's snapshot; pack: the class pack. skip: what the Flow
-- button holds ({ spell } or nil): lead section 305 item 2, the two
-- buttons never show the same buff, and the Flow button keeps the
-- rotation's suggestion, so the self button passes it by.
function FB.SelfPick(s, pack, skip)
    if type(s) ~= "table" or type(pack) ~= "table" then return nil end
    if s.dead ~= false then return nil end
    local R = ns.Rotation
    if type(R) ~= "table" then return nil end
    if R.OutOfFight(s) and s.resting == true then return nil end
    local lists = type(pack.lists) == "table" and pack.lists or {}
    local list = lists.default
    if s.fightType and type(lists[s.fightType]) == "table" then list = lists[s.fightType] end
    if type(list) ~= "table" then return nil end
    local skipSpell = nil
    if type(skip) == "table" and type(skip.spell) == "string" then skipSpell = skip.spell end
    for _, rule in ipairs(list) do
        if type(rule) == "table" and rule.kind == "buff" and type(rule.spell) == "string"
            and rule.spell ~= skipSpell and not FB.OnAction(rule.spell) and R.Knows(s, rule.spell) then
            local wants = true
            if type(rule.when) == "function" then
                local ok, got = pcall(rule.when, s)
                wants = ok and got ~= nil and got ~= false
            end
            if wants and R.Ready(s, rule.spell) == true then
                return { spell = rule.spell, unit = "player" }
            end
        end
    end
    return nil
end

-- The Flow button's pick: the plain key part of the driver's attributes.
function FB.FlowPick(view)
    if type(view) ~= "table" or type(view.attrs) ~= "table" or view.attrs.ok ~= true then return nil end
    local plan = ns.ClickSlots.Plan(view.attrs.button, nil)
    return plan.key
end

-- The rows for one button. e: { spell [, unit] } or { item } or nil (shown,
-- holding nothing).
function FB.Rows(e)
    local kind, spell, unit, item
    if type(e) == "table" then
        if type(e.item) == "string" then
            kind, item = "item", e.item
        elseif type(e.spell) == "string" then
            kind, spell = "spell", e.spell
            if type(e.unit) == "string" then unit = e.unit end
        end
    end
    return {
        { attr = "1:type", value = kind },
        { attr = "1:spell", value = spell },
        { attr = "1:unit", value = unit },
        { attr = "1:item", value = item },
        { attr = "1:shown", value = true },
        { attr = "0:shown", value = true },
    }
end

function FB.Signature(e)
    if e == nil then return "clear" end
    local out = {}
    for _, row in ipairs(FB.Rows(e.hold)) do out[#out + 1] = row.attr .. "=" .. tostring(row.value) end
    return table.concat(out, "|")
end

local function roundSize(scale)
    return math.floor(FB.SIZE * scale + 0.5)
end

-- Where the docked self button stands: under the Flow button at point,
-- centred, DOCK_GAP below its bottom edge, in the same anchor.
function FB.DockPoint(point, flowSize, selfSize)
    if type(point) ~= "table" or type(point[1]) ~= "string" then return nil end
    local x, y = point[3], point[4]
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    local a = point[1]
    if a:find("TOP", 1, true) then
        y = y - flowSize - FB.DOCK_GAP
    elseif a:find("BOTTOM", 1, true) then
        y = y - FB.DOCK_GAP - selfSize
    else
        y = y - flowSize / 2 - FB.DOCK_GAP - selfSize / 2
    end
    if a:find("LEFT", 1, true) then
        x = x + (flowSize - selfSize) / 2
    elseif a:find("RIGHT", 1, true) then
        x = x - (flowSize - selfSize) / 2
    end
    return { point[1], point[2], x, y }
end

-- The hover line.
function FB.Tip(which, why, hold)
    if type(hold) == "table" then
        local what = hold.spell or hold.item
        if which == "self" then return "Casts " .. tostring(what) .. " on you when you click it." end
        return "Casts " .. tostring(what) .. " when you click it."
    end
    return tostring(why)
end

local function texture(client, e)
    if type(e) ~= "table" then return nil end
    if type(e.spell) == "string" then
        if type(client.spellId) ~= "function" or type(client.spellTexture) ~= "function" then return nil end
        local okId, id = pcall(client.spellId, e.spell)
        if not okId or id == nil then return nil end
        local okTex, tex = pcall(client.spellTexture, id)
        if okTex then return tex end
        return nil
    end
    if type(e.item) == "string" and type(client.itemTexture) == "function" then
        local id = tonumber(e.item:match("^item:(%d+)$"))
        if id == nil then return nil end
        local okTex, tex = pcall(client.itemTexture, id)
        if okTex then return tex end
    end
    return nil
end

function FB.Declare(k)
    local api = {}
    local client, store
    local lastView = nil
    local units = {}

    local function lockdown()
        if not client then return nil end
        local ok, v = pcall(function() return client.combatLockdown() end)
        if not ok then return nil end
        return v
    end

    local function raw(name)
        if not store then return nil end
        local ok, v = pcall(store.get, store, "account", name)
        if ok and type(v) == "table" then return v end
        return nil
    end

    local function screen()
        if not client or type(client.screen) ~= "function" then return nil end
        local ok, w, h = pcall(client.screen)
        if not ok then return nil end
        return w, h
    end

    local function setting(key)
        local ok, v = pcall(k.settings.get, k.settings, key)
        if ok then return v end
        return nil
    end

    local St = ns.Import.Stored

    local function flowSize()
        return roundSize(St.RotationScale(raw("layout")))
    end

    local function docked()
        return setting(FB.DOCK) ~= false
    end

    local function selfSize()
        local layout = raw("layout")
        if docked() then return roundSize(St.DockScale(layout, St.RotationScale(layout))) end
        return roundSize(St.BuffButtonLayout(layout).scale)
    end

    local function flowPoint()
        local saved = St.Point(setting(FB.LAYOUT))
        if saved then return saved end
        return { FB.DEFAULT_POINT[1], FB.DEFAULT_POINT[2], FB.DEFAULT_POINT[3], FB.DEFAULT_POINT[4] }
    end

    local function clamp(point, size)
        local w, h = screen()
        return ns.Nav.ClampPoint(point, size, w, h, size) or point
    end

    -- Docked: under where the Flow button stands on the screen.
    local function selfPoint()
        local saved = St.Point(setting(FB.SELF_LAYOUT))
        if saved and not docked() then return saved end
        local fs = flowSize()
        return FB.DockPoint(clamp(flowPoint(), fs), fs, selfSize())
    end

    -- One button: made once, out of a fight; set through a KeyFrame.
    local function unit(which, frame, sizeOf, pointOf, layoutKey)
        local u = { which = which, why = "", hold = nil, wanted = nil }
        local row, kf, face, iconSig
        local name = ns.id.framePrefix .. frame
        local madeSaid = false

        function u.made() return row ~= nil end
        function u.status()
            if kf then return kf:status() end
            return nil
        end

        local function plain(on)
            if face then pcall(face.empty, on) end
        end

        -- The icon of what it holds; the plain face with nothing held, or
        -- no icon read.
        local function icon(e)
            if not row then return end
            local tex = nil
            if e ~= nil then tex = texture(client, e) end
            if tex == nil or type(row.icon) ~= "function" then
                plain(true)
                return
            end
            if tostring(tex) ~= iconSig then
                local ok, given = pcall(row.icon, 1, tex)
                if not ok or given == false then
                    plain(true)
                    return
                end
                iconSig = tostring(tex)
            end
            plain(false)
        end

        local function after(st)
            if type(st) ~= "table" then return end
            if st.state == "set" then
                u.hold = nil
                if u.wanted then u.hold = u.wanted.hold end
                icon(u.hold)
            elseif st.state == "cleared" then
                u.hold = nil
            elseif st.state == "failed" and not u.failSaid then
                u.failSaid = true
                k.problems:add(FB.NAME, which, "the " .. which .. " button could not be set")
            end
        end

        function u.place()
            if not row then return end
            local size = sizeOf()
            pcall(row.place, clamp(pointOf(), size))
        end

        local function moved(point)
            local p = St.Point(point)
            if not p then return end
            local ok = k.settings:set(layoutKey, p)
            if which == "self" and docked() then k.settings:set(FB.DOCK, false) end
            if ok then u.place() end
            if which == "flow" and units.self then units.self.place() end
        end

        local function ensure()
            if row then return true end
            if not client or type(client.clickRow) ~= "function" then return false end
            if lockdown() ~= false then return false end
            local ok, made = pcall(client.clickRow, { name = name, count = 1, size = sizeOf(), gap = 0 })
            if not ok or type(made) ~= "table" or type(made.set) ~= "function" then
                if not madeSaid then
                    madeSaid = true
                    k.problems:add(FB.NAME, which, "the client made no secure button; the " .. which .. " button is not shown")
                end
                return false
            end
            row = made
            u.place()
            if type(client.buttonFace) == "function" then
                local okFace, got = pcall(client.buttonFace, { button = name .. "1" })
                if okFace and type(got) == "table" and type(got.empty) == "function" then face = got end
            end
            plain(true)
            local size = sizeOf()
            ns.MoveHandle.Attach(k, client, { target = name, width = size, height = size, save = moved })
            if type(client.hoverTip) == "function" then
                pcall(client.hoverTip, { frame = name .. "1", text = function() return FB.Tip(which, u.why, u.hold) end })
            end
            kf = K.New({ button = ns.ClickSlots.Button(row), lockdown = lockdown,
                         rows = function(plan) return FB.Rows(plan.hold) end, signature = FB.Signature })
            return true
        end

        -- on: the setting; hold: what to hold or nil; why: the line when
        -- nothing is held.
        function u.want(on, hold, why)
            u.why = why
            if not on then
                u.wanted = nil
                if kf then after(kf:want(nil)) end
                return
            end
            if not ensure() then return end
            u.wanted = { hold = hold }
            after(kf:want(u.wanted))
        end

        function u.try()
            if kf then after(kf:try(true)) end
        end

        return u
    end

    units.flow = unit("flow", FB.FRAME, flowSize, flowPoint, FB.LAYOUT)
    units.self = unit("self", FB.SELF_FRAME, selfSize, selfPoint, FB.SELF_LAYOUT)

    function api.made() return units.flow.made() end
    function api.selfMade() return units.self.made() end
    function api.status() return { flow = units.flow.status(), self = units.self.status() } end

    local function pack()
        if not client or type(client.class) ~= "function" then return nil end
        local ok, class = pcall(client.class)
        if not ok or type(ns.Packs) ~= "table" then return nil end
        return ns.Packs[class]
    end

    local function refresh()
        if not client then return end
        local view = lastView
        local rotationOn = setting(D.SETTING) == true
        local live = rotationOn and type(view) == "table" and view.pack == true
        if lockdown() ~= false then
            units.flow.try()
            units.self.try()
            return
        end
        local flowWhy = "The rotation is off: switch it on in the settings (Combat) and this button holds what it suggests."
        local selfWhy = "The rotation is off: switch it on in the settings (Combat) and this button holds a buff you are missing."
        local flowHold, selfHold = nil, nil
        if live then
            flowHold = FB.FlowPick(view)
            flowWhy = "Nothing to cast now: the rotation has no suggestion yet."
            local shown = nil
            if setting(FB.SETTING) == true then shown = flowHold end
            local okPick, pick = pcall(FB.SelfPick, view.snapshot, pack(), shown)
            if okPick then selfHold = pick end
            selfWhy = "Nothing to cast now: every self buff you know is up or on the Flow button (seals, shouts and forms stay there)."
        end
        units.flow.want(setting(FB.SETTING) == true, flowHold, flowWhy)
        units.self.want(setting(FB.SELF_SETTING) == true, selfHold, selfWhy)
    end

    local function onView(view)
        lastView = view
        refresh()
    end

    k:Module({
        name = FB.NAME,
        needs = { "client", "store", "bus", D.NAME },
        settings = { {
            key = FB.SELF_SETTING, scope = "account", type = "bool", default = true,
            label = FB.SELF_LABEL, group = "combat",
            synonyms = { "buff", "self", "button", "buff button", "self buff" },
            help = "A button that holds a buff you are missing, cast on you when you click it. Seals, shouts and forms stay on the Flow button. Set outside fights only. It binds no key and presses nothing for you.",
        }, {
            key = FB.DOCK, scope = "account", type = "bool", default = true,
            label = FB.DOCK_LABEL, group = "combat",
            synonyms = { "dock", "buff button", "self", "under" },
            help = "On, the self button stands under the Flow button. Moving the self button with its grip turns this off.",
        }, {
            key = FB.LAYOUT, scope = "account", type = "table", path = FB.PATH,
            label = "Flow button position", group = "combat", synonyms = { "flow", "button", "position", "move" },
            keepOnResetAll = true,
            help = "Where the Flow button stands. Drag the grip on its left to move it, outside fights. Resetting puts it back.",
        }, {
            key = FB.SELF_LAYOUT, scope = "account", type = "table", path = FB.SELF_PATH,
            label = "Self button position", group = "combat", synonyms = { "self", "buff button", "position", "move" },
            keepOnResetAll = true,
            help = "Where the self button stands when it is not under the Flow button. Resetting puts it back.",
        } },
        start = function(ctx)
            client, store = ctx.client, ctx.store
            ctx.bus:on(FB.NAME, D.EVENT, onView)
            client.listen("PLAYER_REGEN_ENABLED", function()
                units.flow.try()
                units.self.try()
                refresh()
            end)
            ctx.sched:every(FB.NAME, 1, refresh)
            refresh()
        end,
    })

    return api
end

ns.flowButton = FB.Declare(ns)
