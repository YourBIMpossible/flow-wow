-- Hearthstone, as part of the levelling route (no pop-ups). When you're in a
-- zone with a known inn and your hearthstone is set somewhere else, the route
-- gets a stop: "Set hearthstone: Innkeeper Farley (Goldshire)". Hide it like
-- any stop (right-click it on the map) if you don't want it.
-- Innkeepers are data (registry kind "innkeeper"); more zones can be added
-- without touching this file. The NPC ID is checked against the name.

local _, ns = ...
local H = {}
ns.hearth = H

-- Alliance levelling towns (classic IDs).
for key, inn in pairs({
    goldshire  = { name = "Innkeeper Farley", id = 295, town = "Goldshire", inn = "Lion's Pride Inn", zone = "Elwynn Forest" },
    sentinel   = { name = "Innkeeper Heather", id = 8931, town = "Sentinel Hill", inn = "Sentinel Hill Inn", zone = "Westfall" },
    thelsamar  = { name = "Innkeeper Hearthstove", id = 6734, town = "Thelsamar", inn = "Stoutlager Inn", zone = "Loch Modan" },
    lakeshire  = { name = "Innkeeper Brianna", id = 6727, town = "Lakeshire", inn = "Lakeshire Inn", zone = "Redridge Mountains" },
    darkshire  = { name = "Innkeeper Trelayne", id = 6790, town = "Darkshire", inn = "Scarlet Raven Tavern", zone = "Duskwood" },
}) do ns:Register("innkeeper", key, inn) end

ns:Register("npcIds", "innkeepers", {
    ["Innkeeper Farley"] = 295, ["Innkeeper Heather"] = 8931, ["Innkeeper Hearthstove"] = 6734,
    ["Innkeeper Brianna"] = 6727, ["Innkeeper Trelayne"] = 6790,
})

-- Is the hearthstone already set at this inn? The game may report the town
-- ("Goldshire") or the inn ("Lion's Pride Inn"); either counts.
function H:BoundTo(inn, bind)
    if not bind then return false end
    local b = bind:lower()
    for _, name in ipairs({ inn.town, inn.inn }) do
        if name then
            local n = name:lower()
            if b == n or b:find(n, 1, true) or n:find(b, 1, true) then return true end
        end
    end
    return false
end

-- Would the hearthstone get you there sooner? An estimate, never an action:
-- Flow does not use the hearthstone for you.
--   straight: the distance at your speed
--   hearthstone: what's left of its cooldown + the cast + the loading screen
--                + the run from your inn to the same place
-- Anything unknown (which inn, where it is, the cooldown) means no estimate.
H.ITEM = 6948
H.CAST, H.LOAD = 10, 10          -- seconds: the cast, and a guess at the loading screen
H.MIN_SAVE, H.MIN_SHARE = 120, 0.25   -- say it only when it saves 2 minutes and a quarter of the trip

function H.Compare(directYd, bindYd, cooldownLeft, speed)
    if not (type(directYd) == "number" and type(bindYd) == "number" and type(cooldownLeft) == "number"
        and type(speed) == "number" and speed > 0) then return nil end
    local direct = directYd / speed
    local hearth = cooldownLeft + H.CAST + H.LOAD + bindYd / speed
    local saving = direct - hearth
    return { direct = direct, hearth = hearth, saving = saving, wait = cooldownLeft,
             better = saving >= H.MIN_SAVE and saving >= direct * H.MIN_SHARE }
end

local function span(s)
    if s >= 90 then return string.format("%d min", math.floor(s / 60 + 0.5)) end
    return string.format("%d s", math.floor(s + 0.5))
end

-- The line to show, or nil when the hearthstone isn't clearly quicker.
function H.AdviceText(c, bind)
    if not (c and c.better) then return nil end
    return string.format("Estimate: hearthstone to %s, then run, is about %s quicker (%s against %s%s). Your call: Flow never uses it for you.",
        bind or "your inn", span(c.saving), span(c.hearth), span(c.direct),
        c.wait > 0 and (", counting " .. span(c.wait) .. " left on its cooldown") or "")
end

-- Where your hearthstone goes, as a point: only when it's an inn Flow knows.
function H:BindPoint()
    local bind = GetBindLocation and GetBindLocation()
    if not bind then return nil end
    for _, inn in ns:Each("innkeeper") do
        if H:BoundTo(inn, bind) then
            local p = ns.places and ns.places:Points(inn.name)[1]
            if p and p.map then return p, bind end
        end
    end
    return nil
end

-- Seconds left on the hearthstone's cooldown; nil when you carry none or the game won't say.
function H:CooldownLeft()
    if not (GetItemCount and (GetItemCount(H.ITEM) or 0) > 0) then return nil end
    local get = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if not get then return nil end
    local ok, start, duration = pcall(get, H.ITEM)
    local A = ns.api
    start, duration = ok and A.Safe(start) or nil, ok and A.Safe(duration) or nil
    if type(start) ~= "number" or type(duration) ~= "number" then return nil end
    if start == 0 or duration == 0 then return 0 end
    return math.max(0, start + duration - GetTime())
end

-- The estimate line for a place directYd away, or nil.
function H:Advice(map, x, y, directYd)
    local ok, text = pcall(function()
        local nav = ns.nav
        local p, bind = H:BindPoint()
        if not (nav and p) then return nil end
        local c1, ax, ay = nav:ToWorld(p.map, p.x, p.y)
        local c2, bx, by = nav:ToWorld(map, x, y)
        if not (c1 and c2 and c1 == c2 and ax and bx) then return nil end
        local bindYd = math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
        return H.AdviceText(H.Compare(directYd, bindYd, H:CooldownLeft(), nav.RUN_SPEED or 7), bind)
    end)
    return ok and text or nil
end

ns:Register("navGoal", "hearth", {
    collect = function()
        if ns.db.hearth and ns.db.hearth.off then return nil end
        local zone = GetZoneText and GetZoneText()
        local bind = GetBindLocation and GetBindLocation()
        if not zone or not bind then return nil end
        for key, inn in ns:Each("innkeeper") do
            if inn.zone == zone and not H:BoundTo(inn, bind) then
                local points = ns.places:Points(inn.name)
                if #points > 0 then
                    return { {
                        key = "hearth:" .. key, weight = 1.1, points = points,
                        title = "Set hearthstone",
                        text = string.format("Set hearthstone: %s (%s)", inn.name, inn.town),
                        details = { string.format("Your hearthstone is set to %s. Questing around %s? Set it here:", bind, inn.town),
                                    "talk to the innkeeper and choose \"Make this inn your home\".",
                                    "Right-click this stop on the map to hide it." },
                    } }
                end
            end
        end
    end,
})

ns:OnLoad(function(saved) saved.hearth = saved.hearth or {} end)

-- Setting it removes the stop.
ns:On("HEARTHSTONE_BOUND", function()
    ns:Print("hearthstone set to " .. tostring(GetBindLocation()))
    if ns.nav then ns.nav:Collect() end
end)

ns.commands.hearth = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns.db.hearth.off = (arg == "off")
        if ns.nav then ns.nav:Collect() end
        ns:Print("hearthstone stops on the route " .. arg)
    else
        ns:Print("hearthstone: " .. tostring(GetBindLocation()) .. ". Route stops "
            .. (ns.db.hearth.off and "off" or "on") .. ". /flow hearth on|off")
    end
end
