-- Flow's settings: a page in the game's Options > AddOns > Flow (the
-- Settings API; older clients: Interface Options). /flow settings opens it.
--
--   Cast key       Click "Set key", press the key (modifiers and mouse
--                  buttons 3-5 work). If the key already does something,
--                  Flow says what and you choose: use it anyway (your own
--                  binding is untouched and comes back if you clear Flow's
--                  key) or pick another. Movement keys get an extra warning.
--   Flow           Flow's own options (route colours, the arrow, minimap).
--   Suggested WoW settings
--                  The game settings Flow recommends (Setup.lua rows: auto
--                  loot, nameplates, target of target, ...), each with what
--                  Flow suggests and why; "Use Flow's suggestions" sets all.
--
-- Nothing here calls Blizzard's panel functions (ShowUIPanel/HideUIPanel on
-- their frames): doing that from add-on code taints the game menu.

local _, ns = ...
local S = {}
ns.settings = S

local frame

-- S:AddCheck{ label, note, tip, get, set }: one more tick box under "Flow".
-- Add it before the page first opens (at file load).
S.extraChecks = {}
function S:AddCheck(def)
    self.extraChecks[#self.extraChecks + 1] = def
end

local MODIFIER_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LALT = true, RALT = true, LMETA = true, RMETA = true,
}
local MOUSE = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

local function withModifiers(key)
    local s = ""
    if IsAltKeyDown() then s = s .. "ALT-" end
    if IsControlKeyDown() then s = s .. "CTRL-" end
    if IsShiftKeyDown() then s = s .. "SHIFT-" end
    return s .. key
end

local function label(key)
    if not key then return "not set" end
    return (GetBindingText and GetBindingText(key, "KEY_", true)) or key
end

local function button(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 110, 24)
    b:SetText(text)
    return b
end

-- Every tick box and value on the page shows the current state.
local function refresh()
    if not frame then return end
    frame.keyValue:SetText(label(ns.db.cast.key))
    frame.clear:SetEnabled(ns.db.cast.key ~= nil)
    frame.key2Value:SetText(label(ns.db.cast.key2))
    frame.clear2:SetEnabled(ns.db.cast.key2 ~= nil)
    for _, c in ipairs(frame.checks or {}) do
        local ok, on = pcall(c.get)
        c:SetChecked(ok and on and true or false)
        if c.now then local ok2, t = pcall(c.nowText); c.now:SetText(ok2 and t or "") end
    end
    -- Button rows: the choice in use is lit.
    for _, row in ipairs(frame.choices or {}) do
        local ok, v = pcall(row.get)
        for _, b in ipairs(row.buttons) do
            if ok and v == b.value then b:LockHighlight() else b:UnlockHighlight() end
        end
    end
end

local function stopCapture(msg)
    frame.capturing = false
    frame.capture:Hide()
    frame.status:SetText(msg or "")
end

-- A key was pressed while capturing: check it, then set it or ask.
local function choose(key)
    stopCapture()
    local what, action = ns.cast:Conflict(key)
    if not what then
        ns.cast:SetKey(key, frame.slot)
        frame.status:SetText("|cff66ff66" .. label(key) .. " now casts Flow's suggestion.|r")
        refresh()
        return
    end
    frame.pendingKey = key
    local warn = ns.cast:IsMovement(action) and "|cffff9933That's a movement key, so this isn't recommended.|r\n" or ""
    frame.status:SetText(string.format(
        "%s%s already does: |cffffd200%s|r.\nUse it for Flow anyway? Your own binding isn't changed; it comes back if you clear Flow's key.",
        warn, label(key), what))
    frame.confirm:Show()
    frame.another:Show()
end


local WIDTH = 580

local function heading(f, y, text)
    local h = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    h:SetPoint("TOPLEFT", 16, y)
    h:SetText(text)
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -4)
    line:SetSize(WIDTH - 40, 1)
    line:SetColorTexture(1, 0.82, 0.25, 0.5)
    return y - 34
end

-- A tick box: label, grey note, tooltip; get() -> on, set(on).
local function check(f, y, text, note, tip, get, set)
    local c = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    c:SetSize(24, 24)
    c:SetPoint("TOPLEFT", 14, y)
    c.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    c.label:SetPoint("LEFT", c, "RIGHT", 4, 0)
    c.label:SetText(text .. (note and ("  |cff888888" .. note .. "|r") or ""))
    c.get = get
    c:SetScript("OnClick", function(self)
        if InCombatLockdown() then
            refresh()
            frame.status:SetText("Settings can't change in combat.")
            return
        end
        local ok, err = pcall(set, self:GetChecked() and true or false)
        if not ok then ns:Log("settings", text .. ": " .. tostring(err)) end
        refresh()
    end)
    if tip then
        c:SetScript("OnEnter", function(self)
            ns.Tip(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(text)
            GameTooltip:AddLine(tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    frame.checks[#frame.checks + 1] = c
    return c, y - 28
end

-- A row of buttons, one per choice; the one in use is lit.
-- options = { { label, value, width }, ... }; get() -> value, set(value).
local function choices(f, y, text, tip, options, get, set)
    local l = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    l:SetPoint("TOPLEFT", 18, y - 5)
    l:SetText(text)
    local row = { get = get, buttons = {}, label = l }
    local prev
    for _, o in ipairs(options) do
        local b = button(f, o[1], o[3] or 40)
        b:SetHeight(22)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 250, y) end
        b.value = o[2]
        b:SetScript("OnClick", function(self)
            local ok, err = pcall(set, self.value)
            if not ok then ns:Log("settings", text .. ": " .. tostring(err)) end
            refresh()
        end)
        if tip then
            b:SetScript("OnEnter", function(self)
                ns.Tip(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(text)
                GameTooltip:AddLine(tip, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        row.buttons[#row.buttons + 1] = b
        prev = b
    end
    frame.choices[#frame.choices + 1] = row
    return row, y - 30
end

local function build(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -28, 4)
    local f = CreateFrame("Frame", "FlowSettings", scroll)
    f:SetSize(WIDTH, 900)
    scroll:SetScrollChild(f)
    f.scroll = scroll
    frame = f
    f.checks = {}
    f.choices = {}

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    f.title:SetPoint("TOPLEFT", 16, -12)
    f.title:SetText("Flow Settings  |cff888888v" .. (ns.Version and ns.Version() or "?") .. "|r")

    -- Cast key
    local y = heading(f, -52, "Cast key")
    local name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    name:SetPoint("TOPLEFT", 16, y - 4)
    name:SetText("Your key:")
    f.keyValue = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.keyValue:SetPoint("LEFT", name, "RIGHT", 12, 0)
    local set = button(f, "Set key", 90)
    set:SetPoint("TOPLEFT", 250, y)
    f.clear = button(f, "Clear", 80)
    f.clear:SetPoint("LEFT", set, "RIGHT", 8, 0)
    -- A second key for the same button (e.g. one under each hand).
    local name2 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    name2:SetPoint("TOPLEFT", 16, y - 32)
    name2:SetText("Second key:")
    f.key2Value = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.key2Value:SetPoint("LEFT", name2, "RIGHT", 12, 0)
    local set2 = button(f, "Set key", 90)
    set2:SetPoint("TOPLEFT", 250, y - 28)
    f.clear2 = button(f, "Clear", 80)
    f.clear2:SetPoint("LEFT", set2, "RIGHT", 8, 0)
    y = y - 28
    local help = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", 16, y - 32)
    help:SetWidth(WIDTH - 40)
    help:SetJustifyH("LEFT")
    help:SetText("Press either key (or click the suggestion icon) to cast what Flow suggests. "
        .. "In combat WoW doesn't let add-ons change what a key casts, so it keeps the spell it "
        .. "had when the fight started; a small \"key:\" icon shows it.")
    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.status:SetPoint("TOPLEFT", 16, y - 66)
    f.status:SetWidth(WIDTH - 40)
    f.status:SetJustifyH("LEFT")
    f.confirm = button(f, "Use it anyway", 120)
    f.confirm:SetPoint("TOPLEFT", 16, y - 96)
    f.another = button(f, "Pick another", 110)
    f.another:SetPoint("LEFT", f.confirm, "RIGHT", 8, 0)
    f.confirm:Hide(); f.another:Hide()
    y = y - 126

    -- Every other key: hover-to-bind mode (Modules/BindMode.lua), here so
    -- it's easy to find (also in the arrow's menu and /flow bind).
    local hover = button(f, "Hover to bind keys...", 170)
    hover:SetPoint("TOPLEFT", 16, y)
    hover:SetScript("OnClick", function() if ns.bind then ns.bind:Start() end end)
    local hoverHelp = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hoverHelp:SetPoint("LEFT", hover, "RIGHT", 10, 0)
    hoverHelp:SetWidth(WIDTH - 220)
    hoverHelp:SetJustifyH("LEFT")
    hoverHelp:SetText("Hover any action button and press a key. Nothing changes until you click Save.")
    y = y - 32
    -- Heals land on you when nobody friendly is targeted (the game's Auto
    -- Self Cast, in the setup suggestions); this key forces it on you anyway.
    f.selfCastRow, y = choices(f, y, "Heal yourself: hold",
        "Hold this while casting a heal to put it on yourself even with someone else targeted. With nobody friendly targeted, heals land on you with no key at all (Auto Self Cast, in Flow's suggestions below).",
        { { "Alt", "ALT", 46 }, { "Ctrl", "CTRL", 46 }, { "Shift", "SHIFT", 50 }, { "None", "NONE", 50 } },
        function() return GetModifiedClick and GetModifiedClick("SELFCAST") or "ALT" end,
        function(v)
            if InCombatLockdown() then ns:Print("can't change that in combat") return end
            if SetModifiedClick then SetModifiedClick("SELFCAST", v) end
            if SaveBindings and GetCurrentBindingSet then SaveBindings(GetCurrentBindingSet()) end
        end)

    -- Flow's own options
    y = heading(f, y, "Flow")
    local _
    _, y = check(f, y, "Colour-blind route colours", "(safer colours)",
        "The route and arrow colour shows the route's state: purple = Most XP first, blue = Shortest path, orange = Custom route (you picked the next stop), green = your own waypoint. On: the same roles in colours that stay apart for the common kinds of colour blindness.",
        function() return ns.theme:ColorBlind() end, function(on) ns.theme:SetColorBlind(on) end)
    f.arrowRow, y = choices(f, y, "Arrow",
        "Modern (default): a glossy chevron floating over its shadow; when you arrive, a glowing ring with ripples and a beam of light. 3D: the chevron of lines over a ring of pillars. Flat: the plain line arrow. All turn left and right; WoW: Forever gives no heights, so none can point up or down. Also in the arrow's right-click menu and /flow nav arrow.",
        { { "Modern", "modern", 64 }, { "3D", "3d", 40 }, { "Flat", "flat", 44 } },
        function() return ns.nav:ArrowStyle() end,
        function(v) ns.nav:SetArrowStyle(v) end)
    _, y = check(f, y, "Arrow colour by distance", "(off = the route's colour)",
        "Grey while the stop is in another zone, red when it's far away turning yellow then green as you close in, blue once you're in its area. Off: the route's colour (purple / blue / orange), green for your own waypoint.",
        function() return ns.nav:ArrowColorMode() == "distance" end,
        function(on) ns.nav:SetArrowColorMode(on and "distance" or "route") end)
    _, y = check(f, y, "Stop areas on the minimap", nil,
        "The area of the stop the arrow points at, on the minimap (and the stop you hover in the Flow Tracker).",
        function() return ns.db.nav.minimapAreas ~= false end,
        function(on) ns.db.nav.minimapAreas = on; if ns.minimapPin then ns.minimapPin:Hide() end end)
    _, y = check(f, y, "Profession nodes near you", "(minimap clouds, Flow Tracker line)",
        "Where ore and herbs your professions can gather spawn around you and your next stop: tan (ore) and green (herb) clouds on the minimap, and \"Nearby: Iron Deposit x3\" under the Flow Tracker's stops (+skill when it still raises your skill).",
        function() return ns.db.nav.nearbyNodes ~= false end,
        function(on) ns.db.nav.nearbyNodes = on; if ns.minimapPin then ns.minimapPin:Hide() end end)
    _, y = check(f, y, "Show the route on the world map", nil, nil,
        function() return ns.db.nav.mapLines ~= false end,
        function(on) ns.db.nav.mapLines = on end)
    _, y = check(f, y, "Arrow follows paths you've walked", "(off = straight at the stop)",
        "Off (default): the arrow points straight at your stop, except into caves and buildings, where it follows the way you walked in. On: outdoors too it follows a path you've walked when that's at most half again as long as the straight line (around a cliff, along a road).",
        function() return ns.db.nav.arrowPaths == true end,
        function(on) ns.db.nav.arrowPaths = on end)
    _, y = check(f, y, "Finish a zone before leaving it", "(quests too low or high don't count)",
        "The route does this zone's quests before heading to the next zone. Quests too low (less XP) or 3+ levels above you don't hold you here, and a stop just over the border or your class trainer can come any time. Waiting stops say \"(Westfall, after this zone)\".",
        function() return ns.db.nav.zoneFirst ~= false end,
        function(on) ns.db.nav.zoneFirst = on; if ns.nav then ns.nav:Collect(); ns.nav.planDirty = true end end)
    -- 0 = all (nil can't sit in the options list).
    f.stopsRow, y = choices(f, y, "Stops on the map",
        "How many of your next stops the world map and the Flow Tracker show. The Flow Router always lists the whole route. Also in the arrow's right-click menu and /flow nav stops.",
        { { "Next only", 1, 76 }, { "3", 3 }, { "5", 5 }, { "10", 10 }, { "All", 0, 48 } },
        function() return ns.nav:StopsShown() or 0 end,
        function(v) ns.nav:SetStopsShown(v) end)
    _, y = check(f, y, "Tooltips where WoW shows them", "(and the stop card)",
        "Flow's tooltips and its stop card open where WoW shows its own tooltips (the spot you set in Edit Mode or the interface options). Off: next to what you hover or click. A stop card you dragged somewhere stays there. (The arrow's drawer opens beside the arrow, or where you Shift-dragged it.)",
        function() return ns.TipsAtGameSpot() end,
        function(on) ns.db.settings.tipsBeside = not on end)
    _, y = check(f, y, "Intro on the arrow when you log in", "(/flow splash replays it)",
        "After logging in or /reload the arrow spins, shows FLOW in its ring, and the version and status underneath.",
        function() return ns.db.splash.enabled ~= false end,
        function(on) ns.db.splash.enabled = on end)
    _, y = check(f, y, "Flow key does fishing and gathering steps", "(/flow action)",
        "Out of combat at a fishing or gathering stop, the key equips your pole, puts on a lure, casts and reels in; at veins and herbs it gathers.",
        function() return ns.db.actions.enabled ~= false end,
        function(on) ns.db.actions.enabled = on end)
    _, y = check(f, y, "Flow Seller: auto-sell at vendors", "(also on the Flow Seller drawer)",
        "When you open a vendor, sell everything Flow marks to sell: up to 12 a visit, so you can buy any back (Flow then never sells it again).",
        function() return ns.db.sell.autoAll == true end,
        function(on) ns.db.sell.autoAll = on end)
    _, y = check(f, y, "Flow Seller: auto-sell grey junk", nil,
        "Sells every grey item as soon as you open a vendor.",
        function() return ns.db.sell.autoJunk == true end,
        function(on) ns.db.sell.autoJunk = on end)
    _, y = check(f, y, "Flow Seller: auto-cleanup after selling", "(also on the Flow Seller)",
        "After the Flow Seller sells something, your bags are tidied with the game's Clean Up Bags (the broom on your bags).",
        function() return ns.db.sell.autoCleanup ~= false end,
        function(on) ns.db.sell.autoCleanup = on end)
    _, y = check(f, y, "Leave junk behind when looting", "(Flow auto-loots the rest)",
        "Grey items stay in the corpse; everything else (money, quest items, gear, materials) is looted for you. The game's own Auto Loot can't skip junk, so Flow does the looting while this is on and gives it back when you turn this off. Hold Shift to loot by hand.",
        function() return ns.db.loot.skipJunk == true end,
        function(on) ns.lootFilter:SetEnabled(on) end)
    _, y = check(f, y, "Turn in finished quests for you", "(hold Shift at the NPC to skip)",
        "Talk to the NPC and Flow picks the finished quest, completes it and takes the reward. With several rewards to choose from, you pick (the green arrow is Flow's pick). Quests that take gold are left to you.",
        function() return ns.db.quests.autoTurnIn ~= false end,
        function(on) ns.db.quests.autoTurnIn = on end)
    _, y = check(f, y, "Accept new quests for you", "(hold Shift at the NPC to skip)",
        "Talk to a quest giver and Flow opens their new quest and accepts it (after turning in any finished ones). Grey and repeatable quests are left to you, and nothing is accepted with your quest log full.",
        function() return ns.db.quests.autoAccept ~= false end,
        function(on) ns.db.quests.autoAccept = on end)
    _, y = check(f, y, "Share quests with your party", "(share yours, accept theirs; /flow share)",
        "In a group: a quest you pick up is shared when a party member doesn't have it, and Flow players get your quests they're missing, one every few seconds. Quests your party shares with you are accepted (unless your log is full). Each quest is offered to each person once.",
        function() return ns.db.quests.share ~= false end,
        function(on) ns.db.quests.share = on end)
    _, y = check(f, y, "New spells: offer to place or bind them", "(/flow newspell)",
        "When you learn a spell, a small card shows it for 10 s: put it on your bar, drag it where you want it, bind a key to it (you confirm first), or say you don't want it on your bars (Flow then stops asking).",
        function() return ns.db.spellbar.offer ~= false end,
        function(on) ns.db.spellbar.offer = on end)
    _, y = check(f, y, "Shift + easy key heals you", "(works in fights too)",
        "Your easy key can't change what it casts during a fight (WoW's rule), so a heal Flow shows mid-fight can't be cast with it. Shift + your key always casts your fastest heal on you, fights included.",
        function() return ns.db.cast.shiftHeal ~= false end,
        function(on) ns.db.cast.shiftHeal = on end)
    _, y = check(f, y, "Ctrl + easy key: on your target", "(heals and buffs)",
        "Your buffs and heals always go on you, even with a friend targeted. Hold Ctrl with your easy key to cast the shown heal or buff on your target instead.",
        function() return ns.db.cast.ctrlTarget ~= false end,
        function(on) ns.db.cast.ctrlTarget = on; if ns.cast then ns.cast:ApplyKey() end end)
    _, y = check(f, y, "Easy button buffs your group", "(party and raid)",
        "Out of combat, with nothing else to press, the easy button casts your buffs on the people in your group who are missing them, the right one for each: a druid's Mark of the Wild for everyone and Thorns for tanks; a paladin's Might for melee, Wisdom for casters, healers and hunters, Kings for tanks.",
        function() return ns.db.rotation.groupBuffs ~= false end,
        function(on) ns.db.rotation.groupBuffs = on end)
    _, y = check(f, y, "Profession reminders", "(/flow prof remind)",
        "Now and then (after you log in, when you level up, when a skill reaches its cap, in a town with a trainer you need) a small card says what to learn or train next for your professions, and can point the arrow at the trainer. It closes by itself after 8 s.",
        function() return ns.db.prof.remind ~= false end,
        function(on) ns.db.prof.remind = on end)
    _, y = check(f, y, "Upgrade spell ranks on your bars", "(when you learn a rank)",
        "When you learn a higher rank of a spell, every action bar slot with an older rank of it gets the new one (after the fight, if you're in one). A lower rank you put back on purpose stays until you learn the next rank.",
        function() return ns.db.spellbar.upgradeRanks ~= false end,
        function(on) ns.db.spellbar.upgradeRanks = on end)
    _, y = check(f, y, "Accept group invites from friends", "(/flow invites)",
        "Invites from your friends list and Battle.net friends are accepted for you. Anyone else gets the usual popup.",
        function() return ns.db.invites.friends ~= false end,
        function(on) ns.db.invites.friends = on end)
    -- Bonus mode (Bonus.lua: new in 0.35.84, so only after a WoW restart).
    if ns.bonus then
        _, y = check(f, y, "Bonus mode: extras just for fun", "(off by default; /flow bonus)",
            "Turns on Flow's fun extras, listed below (each has its own switch).",
            function() return ns.bonus:On() end,
            function(on) ns.bonus:Set(on) end)
        for _, x in ipairs(ns.bonus.EXTRAS) do
            _, y = check(f, y, "   " .. x.label, "(needs Bonus mode)", x.why,
                function() return ns.db.bonus[x.key] ~= false end,
                function(on) ns.db.bonus[x.key] = on end)
        end
    end
    -- Tick boxes other files add with S:AddCheck (after the built-in ones).
    for _, x in ipairs(S.extraChecks) do
        _, y = check(f, y, x.label, x.note, x.tip, x.get, x.set)
    end
    y = y - 10

    -- Suggested WoW settings (Setup.lua rows)
    f.suggestTop = y
    y = heading(f, y, "Suggested WoW settings")
    local intro = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", 16, y + 4)
    intro:SetWidth(WIDTH - 40)
    intro:SetJustifyH("LEFT")
    intro:SetText("Game settings that help while levelling. Each row says what Flow suggests; hover it for why.")
    y = y - 20
    local suggestions = {}
    for _, r in ipairs(ns.setup and ns.setup:Rows() or {}) do
        local item = r.item
        if item.isOn then
            _, y = check(f, y, item.label,
                item.suggested and "|cff66ff66Flow suggests on|r" or "Flow suggests off",
                item.why, item.isOn, item.set)
            suggestions[#suggestions + 1] = item
        elseif item.now and not item.action then
            local t = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            t:SetPoint("TOPLEFT", 42, y - 4)
            t:SetWidth(WIDTH - 70)
            t:SetJustifyH("LEFT")
            local ok, now = pcall(item.now)
            t:SetText(item.label .. ":  |cffffd200" .. tostring(ok and now or "?") .. "|r  |cff888888" .. (item.why or "") .. "|r")
            y = y - math.max(24, t:GetStringHeight() + 8)
        end
    end
    local all = button(f, "Use Flow's suggestions", 190)
    all:SetPoint("TOPLEFT", 16, y - 6)
    all:SetScript("OnClick", function()
        if InCombatLockdown() then f.status:SetText("Settings can't change in combat.") return end
        local n = 0
        for _, item in ipairs(suggestions) do
            local want = item.suggested and true or false
            if want ~= (item.isOn() and true or false) then pcall(item.set, want); n = n + 1 end
        end
        ns.db.setup.done = true
        ns:Print(n .. " setting(s) changed to Flow's suggestions.")
        refresh()
    end)
    y = y - 44
    f:SetHeight(-y + 20)

    -- Key capture overlay (over the visible page).
    local cap = CreateFrame("Button", nil, parent)
    cap:SetAllPoints(parent)
    cap:SetFrameLevel(parent:GetFrameLevel() + 50)
    cap.bg = cap:CreateTexture(nil, "BACKGROUND")
    cap.bg:SetAllPoints()
    cap.bg:SetColorTexture(0, 0, 0, 0.85)
    cap.text = cap:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    cap.text:SetPoint("CENTER")
    cap.text:SetText("Press a key for Flow (Escape cancels)")
    cap:EnableKeyboard(true)
    if cap.SetPropagateKeyboardInput then cap:SetPropagateKeyboardInput(false) end
    cap:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then stopCapture("Cancelled.") return end
        if MODIFIER_KEYS[key] then return end
        choose(withModifiers(key))
    end)
    cap:RegisterForClicks("AnyUp")
    cap:SetScript("OnMouseDown", function(_, mb)
        if MOUSE[mb] then choose(withModifiers(MOUSE[mb])) end
    end)
    cap:Hide()
    f.capture = cap

    -- (f.slot: which key is being set, 1 or 2.)
    local function startCapture(slot)
        if InCombatLockdown() then f.status:SetText("Key bindings can't change in combat.") return end
        f.slot = slot
        f.confirm:Hide(); f.another:Hide()
        f.capturing = true
        cap:Show()
    end
    set:SetScript("OnClick", function() startCapture(1) end)
    set2:SetScript("OnClick", function() startCapture(2) end)
    f.clear:SetScript("OnClick", function()
        ns.cast:SetKey(nil, 1)
        f.status:SetText("Flow's key cleared; that key does what it did before.")
        refresh()
    end)
    f.clear2:SetScript("OnClick", function()
        ns.cast:SetKey(nil, 2)
        f.status:SetText("Second key cleared; that key does what it did before.")
        refresh()
    end)
    f.confirm:SetScript("OnClick", function()
        ns.cast:SetKey(f.pendingKey, f.slot)
        f.status:SetText("|cff66ff66" .. label(f.pendingKey) .. " now casts Flow's suggestion.|r")
        f.confirm:Hide(); f.another:Hide()
        refresh()
    end)
    f.another:SetScript("OnClick", function()
        f.confirm:Hide(); f.another:Hide()
        f.capturing = true
        cap:Show()
    end)
    return f
end

-------------------------------------------------------------------------------
-- The page in Options > AddOns.
-------------------------------------------------------------------------------

local canvas, category

local function register()
    canvas = CreateFrame("Frame")
    canvas.name = "Flow"
    canvas:SetSize(WIDTH + 40, 600)
    canvas:SetScript("OnShow", function(self)
        if not frame then build(self) end
        refresh()
    end)
    if Settings and Settings.RegisterCanvasLayoutCategory then
        category = Settings.RegisterCanvasLayoutCategory(canvas, "Flow")
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(canvas)
    end
end

-- Opens Flow's page in the game's Options. `section` "suggest" scrolls to
-- the suggested WoW settings. Returns false if this client has no page.
function S:Open(section)
    if InCombatLockdown() then ns:Print("Options can't open in combat.") return true end
    local opened = false
    if category and Settings and Settings.OpenToCategory then
        opened = pcall(Settings.OpenToCategory, (category.GetID and category:GetID()) or category)
    elseif canvas and InterfaceOptionsFrame_OpenToCategory then
        opened = pcall(InterfaceOptionsFrame_OpenToCategory, canvas)
        pcall(InterfaceOptionsFrame_OpenToCategory, canvas)  -- (older clients need it twice)
    end
    if not opened then return false end
    if not frame and canvas then build(canvas) end
    refresh()
    if section == "suggest" and frame and frame.scroll and frame.suggestTop then
        C_Timer.After(0, function() frame.scroll:SetVerticalScroll(math.max(0, -frame.suggestTop - 10)) end)
    end
    return true
end

-- (Tests) the page's rows: Flow options and suggested WoW settings.
function S:Checks()
    return frame and frame.checks or {}
end
function S:Choices()
    return frame and frame.choices or {}
end

ns:OnLoad(function(saved)
    saved.settings = saved.settings or {}
    pcall(register)
end)

-- First run: open the page once so the key can be set.
ns:On("PLAYER_ENTERING_WORLD", function()
    if ns.db.cast.key or ns.db.settings.prompted then return end
    ns.db.settings.prompted = true
    C_Timer.After(7, function()
        if not InCombatLockdown() and S:Open() and frame then
            frame.status:SetText("First setting: pick the key that casts Flow's suggestion.")
        end
    end)
end)

ns.commands.settings = function() if not S:Open() then ns:Print("this client has no add-on options page") end end
ns.commands.key = function(arg)
    if (arg or ""):lower():match("^%s*test") then ns.cast:Test() else ns.commands.settings() end
end
ns:Register("help", "settings", { order = 5, title = "Settings", lines = {
    "/flow settings (or Game Menu > Options > AddOns > Flow) - cast key, Flow options, suggested WoW settings",
    "/flow key test - check the cast key",
    "/flow zoom on|off - max camera zoom",
} })
