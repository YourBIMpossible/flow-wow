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
-- button at layout.rotation.frame and scale, the self button at
-- layout.buffButton.frame and scale, else beside the Flow button at
-- FB.SELF_DEFAULT_POINT, or docked under it (buffButton.dock) at the dock
-- scale. Recovery R1 (lead section 564): docked by default, as legacy Flow
-- (BB.DockWanted: docked unless taken off) and as Settings/Model.lua and
-- Import/Stored.lua already read it. A saved choice wins; with none saved,
-- a self button the player has given a place of its own stays there.
--
-- Lead section 340: three things on screen, each saying what it is in its
-- tooltip. The rotation icon (UI/RotationIcon.lua) shows the next spell and
-- casts nothing; the Flow button casts on a click; the self button is the
-- buff button, for your self buffs. In a fight the Flow button cannot
-- change: its tooltip says what the click casts and, when the rotation now
-- suggests something else, that it changes after the fight. As the fight
-- starts, a Flow button holding the swing takes the fight spell
-- (RotationDriver view.fight). The grip beside either one (the S29
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
-- D-12 (lead section 704): the self button also holds a buff item (a stone
-- or oil on your weapon, an elixir, scroll or flask) when no self buff
-- spell is due: Rotation/BuffItemPick.lua. On as made, as legacy Flow.
FB.ITEMS = "buffButton.items"
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
FB.DEFAULT_POINT = { "CENTER", "CENTER", 0, -270 } -- authored: well under the rotation icon, not beside it
-- Lead section 340: the buff button apart from the Flow button by default,
-- to its right, one button and a gap clear of it (authored).
FB.SELF_DEFAULT_POINT = { "CENTER", "CENTER", 100, -270 }
FB.FLOW_NAME = "Flow button"
FB.ITEM_PENDING = "Item not loaded yet."
FB.SELF_NAME = "Buff button, for your self buffs"
-- Lead section 409 item 4: the word under each button, so the two are told
-- apart without hovering.
FB.FLOW_WORD = "Flow"
FB.SELF_WORD = "Buffs"
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

-- The rows for one button. e: { spell [, unit] } or { item [, targetSlot] }
-- or nil (shown, holding nothing). targetSlot (D-12): 16 or 17, the weapon
-- hand a stone or oil goes on (the secure item type's target-slot).
function FB.Rows(e)
    local kind, spell, unit, item, slot
    if type(e) == "table" then
        if type(e.item) == "string" then
            kind, item = "item", e.item
            if e.targetSlot == 16 or e.targetSlot == 17 then slot = e.targetSlot end
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
        { attr = "1:target-slot", value = slot },
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

-- The hover line: which button it is, then what a click casts, or what is
-- missing. now: in a fight, the spell the rotation suggests now (nil out of
-- a fight); when the Flow button holds something else, the line says the
-- button changes after the fight.
function FB.Tip(which, why, hold, now)
    local name = FB.FLOW_NAME
    if which == "self" then name = FB.SELF_NAME end
    if type(hold) ~= "table" then return name .. ". " .. tostring(why) end
    if hold.pending then return name .. ". " .. FB.ITEM_PENDING end
    local what = hold.spell or hold.item
    if which == "self" then return name .. ". Casts " .. tostring(what) .. " on you when you click it." end
    local line = name .. ". Casts " .. tostring(what) .. " when you click it."
    if type(now) == "string" and now ~= what and not (ns.cast.ATTACK[now] and ns.cast.ATTACK[what]) then
        line = line .. " The rotation now suggests " .. now .. "; this button changes after the fight."
    end
    return line
end

-- Lead section 340: the Flow button's pick as the fight starts, from the
-- driver's view.fight; nil when the view has none.
function FB.FightPick(view)
    if type(view) ~= "table" or type(view.fight) ~= "table" or view.fight.ok ~= true then return nil end
    local plan = ns.ClickSlots.Plan(view.fight.button, nil)
    return plan.key
end

-- Section 448 (F5): the tooltip's own copy of what the button holds, its
-- item resolved to the display name client.itemInfo gives (a link or an ID
-- in, { name = } out) so the line reads a name, never the raw secure-
-- attribute token ("item:28653") the button is actually set with; FB.Tip
-- stays pure and unaware of the client. Unresolved (not yet loaded, or no
-- client): the hold is marked pending and FB.Tip says FB.ITEM_PENDING,
-- never the raw token (section 454).
local function tipHold(client, hold)
    if type(hold) ~= "table" or type(hold.item) ~= "string" then return hold end
    local pending = { item = hold.item, pending = true }
    if type(client) ~= "table" or type(client.itemInfo) ~= "function" then return pending end
    local ok, info = pcall(client.itemInfo, hold.item)
    if not ok or type(info) ~= "table" or type(info.name) ~= "string" or info.name == "" then return pending end
    return { item = info.name }
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

    -- The saved choice when there is one. With none: docked (the
    -- default), unless the self button has a saved place of its own: the
    -- player put it there while "apart" was the default, and moving an
    -- undocked button wrote no dock value. Nothing is written here.
    local function docked()
        local saved = nil
        if store then
            local ok, v = pcall(store.get, store, "account", "settings." .. FB.DOCK)
            if ok and type(v) == "boolean" then saved = v end
        end
        if saved ~= nil then return saved end
        if St.Point(setting(FB.SELF_LAYOUT)) then return false end
        return setting(FB.DOCK) == true
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

    -- Docked: under where the Flow button stands on the screen. Not
    -- docked: its own place, else FB.SELF_DEFAULT_POINT.
    local function selfPoint()
        if not docked() then
            local saved = St.Point(setting(FB.SELF_LAYOUT))
            if saved then return saved end
            local p = FB.SELF_DEFAULT_POINT
            return { p[1], p[2], p[3], p[4] }
        end
        local fs = flowSize()
        return FB.DockPoint(clamp(flowPoint(), fs), fs, selfSize())
    end

    -- In a fight (the lock not a plain false), the spell the rotation
    -- suggests now; nil out of a fight or with no suggestion.
    local function suggestedNow()
        if lockdown() == false then return nil end
        local v = lastView
        if type(v) ~= "table" or type(v.suggestion) ~= "table" then return nil end
        local spell = v.suggestion.spell
        if type(spell) ~= "string" then return nil end
        return spell
    end

    -- One button: made once, out of a fight; set through a KeyFrame.
    local function unit(which, frame, sizeOf, pointOf, layoutKey)
        local u = { which = which, why = "", hold = nil, wanted = nil, lastTex = nil }
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

        -- Lead section 409 item 1: the look of a face set after plain.
        -- nil: the plain face; "picture": dimmed, no "?"; "gone": nothing.
        local function dim(mode)
            if face and type(face.dim) == "function" then pcall(face.dim, mode) end
        end

        -- Recovery R1 (lead section 564): the buff button takes the mouse
        -- whether or not it holds a buff, so its tooltip shows on an empty
        -- one too (legacy BuffButton.lua). Set only while the lock reads a
        -- plain false. The Flow button always takes the mouse.
        local function mouse(on)
            if which ~= "self" or not face or type(face.mouse) ~= "function" then return end
            if lockdown() ~= false then return end
            pcall(face.mouse, on)
        end

        -- The icon of what it holds; the plain face with nothing held, or
        -- no icon read.
        -- Lead section 409 item 1: the self button holding nothing shows
        -- the last buff it held, dimmed, never a "?". Recovery R1 (lead
        -- section 564): having held none it still shows, its plain dark
        -- face and its word. Look only: the click still casts nothing.
        local function icon(e)
            if not row then return end
            local tex = nil
            if e ~= nil then tex = texture(client, e) end
            local mode = nil
            -- Lead section 415: the Flow button too: the last spell dimmed,
            -- or, never having held one, its plain word "Flow"; a held
            -- spell with no icon read shows the word. Never a "?".
            local none = "word"
            if e == nil then
                tex = u.lastTex
                mode = "picture"
                if tex == nil then mode = none end
            end
            mouse(true)
            if tex == nil or type(row.icon) ~= "function" then
                if mode == nil then mode = "word" end
                plain(true)
                dim(mode)
                return
            end
            if tostring(tex) ~= iconSig then
                local ok, given = pcall(row.icon, 1, tex)
                if not ok or given == false then
                    plain(true)
                    if mode ~= nil then mode = none else mode = "word" end
                    dim(mode)
                    return
                end
                iconSig = tostring(tex)
            end
            if e ~= nil then u.lastTex = tex end
            plain(false)
            dim(mode)
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
                local word = FB.FLOW_WORD
                if which == "self" then word = FB.SELF_WORD end
                local okFace, got = pcall(client.buttonFace, { button = name .. "1", label = word })
                if okFace and type(got) == "table" and type(got.empty) == "function" then face = got end
            end
            plain(true)
            dim("word")
            mouse(true)
            local size = sizeOf()
            -- Lead section 409 item 3: the grip's yellow bar is drawn only
            -- while the mouse is over it or the button (quiet).
            ns.MoveHandle.Attach(k, client, { target = name, width = size, height = size, save = moved, quiet = true })
            if type(client.hoverTip) == "function" then
                local function line()
                    local hold = tipHold(client, u.hold)
                    if which == "flow" then return FB.Tip(which, u.why, hold, suggestedNow()) end
                    return FB.Tip(which, u.why, hold)
                end
                pcall(client.hoverTip, { frame = name .. "1", text = line })
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
    -- Lead section 340: the spell or item the Flow button holds now (set on
    -- the button), or nil: off, not made, or holding nothing.
    -- Lead section 409 item 2: the spell or item whose picture the Flow
    -- button shows after this driver view: out of a fight what it is about
    -- to hold, in one what it holds. nil: off, not made, or nothing.
    function api.picture(view)
        if setting(FB.SETTING) ~= true or not units.flow.made() then return nil end
        local h = units.flow.hold
        if lockdown() == false then h = FB.FlowPick(view) end
        if type(h) ~= "table" then return nil end
        return h.spell or h.item
    end
    function api.held()
        if setting(FB.SETTING) ~= true or not units.flow.made() then return nil end
        local h = units.flow.hold
        if type(h) ~= "table" then return nil end
        return h.spell or h.item
    end

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
            -- Recovery R2: no self buff to cast, so the gathering tracking
            -- that is off (Rotation/Gather.lua G.Self; its guards hold).
            if selfHold == nil and type(ns.Gather) == "table" then
                local okTrack, track = pcall(ns.Gather.Self, view.snapshot, shown)
                if okTrack then selfHold = track end
            end
            -- D-12: no self buff spell and no tracking: a buff item from the
            -- bags (Rotation/BuffItemPick.lua), with the setting not off.
            if selfHold == nil and setting(FB.ITEMS) ~= false and type(ns.BuffItemPick) == "table" then
                local okRead, items, ctx = pcall(ns.BuffItemPick.Read, client)
                if okRead and type(items) == "table" then
                    local okItem, item = pcall(ns.BuffItemPick.Pick, items, ctx)
                    if okItem and type(item) == "table" then selfHold = item end
                end
            end
            selfWhy = "Nothing to cast now: every self buff you know is up or on the Flow button (seals, shouts and forms stay there)."
        end
        units.flow.want(setting(FB.SETTING) == true, flowHold, flowWhy)
        units.self.want(setting(FB.SELF_SETTING) == true, selfHold, selfWhy)
    end

    local function onView(view)
        lastView = view
        refresh()
    end

    -- Lead section 340: the fight starts. Handled while the lock is still a
    -- plain false (a first guess, not seen in game): a Flow button holding
    -- Attack takes the fight spell now, as a second click on Attack would
    -- toggle the swing off and the lock keeps the button from changing.
    local function fightStarts()
        if not client or lockdown() ~= false or setting(FB.SETTING) ~= true then return end
        local h = units.flow.hold
        if type(h) ~= "table" or type(h.spell) ~= "string" or ns.cast.ATTACK[h.spell] ~= true then return end
        local pick = FB.FightPick(lastView)
        if pick == nil then return end
        units.flow.want(true, pick, units.flow.why)
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
            key = FB.ITEMS, scope = "account", type = "bool", default = true,
            label = "Buff items on the self button", group = "combat",
            synonyms = { "stone", "oil", "elixir", "scroll", "flask", "buff button", "self" },
            help = "When no buff spell is due, the self button holds a sharpening stone, weightstone or oil for your weapon, or an elixir, scroll or flask whose buff is not on you, from your bags. Out of fights only; you click it. Nothing is bought.",
        }, {
            key = FB.DOCK, scope = "account", type = "bool", default = true,
            label = FB.DOCK_LABEL, group = "combat",
            synonyms = { "dock", "buff button", "self", "under" },
            help = "On (the default), the self button stands under the Flow button. Off, it stands apart, to the right of it. Moving the self button with its grip turns this off.",
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
            client.listen("PLAYER_REGEN_DISABLED", fightStarts)
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
