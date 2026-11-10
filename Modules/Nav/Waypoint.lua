-- Your own waypoint. It is NOT a stop on the route: while it's set the arrow
-- points there (Nav.lua, N.WaypointChoice; green with the route colours), the map draws a green
-- line to it and the Flow Router a green line above the route, and the
-- route itself carries on unchanged. It clears itself when you arrive.
--   Set:   paste coordinates (/flow way or /way, or right-click the arrow: Set a
--          waypoint), Ctrl-click the world map (the game's own map pin, on clients that
--          have it), Alt-click the world map, /flow way <x> <y> [note], or
--          "Point the arrow here" on any stop
--   Clear: /flow way clear, the X in the Flow Router, the arrow or map menu, or arrive
-- PLACEHOLDER: a custom multi-point path (ticketed).

local _, ns = ...
local W = {}
ns.waypoint = W

local function blizzard() return C_Map and C_Map.HasUserWaypoint and C_Map.GetUserWaypoint end

-- { map, x, y, note } or nil
function W:Get()
    if blizzard() and C_Map.HasUserWaypoint() then
        local pt = C_Map.GetUserWaypoint()
        local pos = pt and pt.position
        if pos then
            -- A vector on most clients; a plain { x, y } table on Forever (calling
            -- :GetXY on that broke the arrow's menu once a waypoint was set).
            local x, y
            if type(pos.GetXY) == "function" then x, y = pos:GetXY() else x, y = pos.x, pos.y end
            if x and y then return { map = pt.uiMapID, x = x, y = y, note = ns.db.nav.waypointNote } end
        end
    end
    return ns.db.nav.waypoint
end

function W:Set(map, x, y, note)
    -- On a shared party route, a waypoint becomes a shared stop at the front.
    if ns.party and ns.party:Following() then
        ns.party:AddFront(map, x, y, note or "Waypoint", nil, "waypoint")
        ns:Print(string.format("added %.1f, %.1f to the front of the shared route", x * 100, y * 100))
        return
    end
    ns.db.nav.waypointNote = note
    if blizzard() and C_Map.SetUserWaypoint and UiMapPoint then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x, y))
        ns.db.nav.waypoint = nil
    else
        ns.db.nav.waypoint = { map = map, x = x, y = y, note = note }
    end
    W.Changed()
    ns:Print(string.format("waypoint set at %.1f, %.1f%s: the arrow points there (your route waits)",
        x * 100, y * 100, note and (" (" .. note .. ")") or ""))
end

function W:Clear()
    if blizzard() and C_Map.ClearUserWaypoint then C_Map.ClearUserWaypoint() end
    ns.db.nav.waypoint, ns.db.nav.waypointNote = nil, nil
    W.Changed()
end

-- The waypoint isn't part of the route, so nothing is re-planned: the arrow
-- picks it up on its next update; the map and its list redraw now.
function W.Changed()
    if ns.mapOverlay and WorldMapFrame and WorldMapFrame:IsShown() then pcall(ns.mapOverlay.Redraw, ns.mapOverlay) end
end

-- Alt-click on the world map.
local function hookMap()
    local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
    if not (sc and sc.GetNormalizedCursorPosition) then return end
    sc:HookScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" or not IsAltKeyDown() then return end
        local x, y = self:GetNormalizedCursorPosition()
        local map = WorldMapFrame:GetMapID()
        if map and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then W:Set(map, x, y) end
    end)
end

ns:On("PLAYER_LOGIN", function() pcall(hookMap) end)
ns:On("USER_WAYPOINT_UPDATED", function() W.Changed() end)

-------------------------------------------------------------------------------
-- Coordinates as people paste them. All of these work:
--   45.2 63.1                    (your current zone)
--   45.2, 63.1  /  (45.2, 63.1)  /  45.2 63.1 Hogger
--   /way 45.2 63.1 Hogger        (a TomTom-style line pasted whole)
--   /way Elwynn Forest 45.2 63.1 Hogger
--   /way #1429 45.2 63.1         (a map ID)
--   0.452 0.631                  (0-1 map fractions)
-------------------------------------------------------------------------------

-- Zone name -> map ID (zones and continents the client knows).
local zoneIds
local function zoneByName(name)
    if not (C_Map and C_Map.GetMapInfo) then return nil end
    if not zoneIds then
        zoneIds = {}
        for id = 1, 2500 do
            local ok, info = pcall(C_Map.GetMapInfo, id)
            if ok and info and info.name and info.mapType and info.mapType <= 3 then  -- cosmic/world/continent/zone
                local key = info.name:lower()
                if not zoneIds[key] or info.mapType == 3 then zoneIds[key] = id end
            end
        end
    end
    return zoneIds[name:lower()]
end

-- Text -> { map (or nil = your zone), mapName, x, y (0-1), note }, or nil + why.
-- `lookup(name)` finds a zone's map ID (defaults to the game's map list).
function W.Parse(text, lookup)
    lookup = lookup or zoneByName
    local s = (text or ""):gsub("^%s*/%a+%s*", ""):gsub("^[Ww]ay%s+", "")   -- a pasted "/way", "/flow way" or "/tomtom"
    s = s:gsub("[%(%)%[%]]", " "):gsub("^%s+", ""):gsub("%s+$", "")
    local map, mapName
    local id, rest = s:match("^#(%d+)%s+(.*)$")
    if id then map, s = tonumber(id), rest end
    -- The first number pair; anything before it is a zone name, after it a note.
    local before, x, y, after = s:match("^(.-)%s*(%d+%.?%d*)%s*[,%s]%s*(%d+%.?%d*)%s*(.-)$")
    x, y = tonumber(x), tonumber(y)
    if not (x and y) then return nil, "no coordinates found" end
    if before and before ~= "" then
        mapName = before:gsub("[,%s]+$", "")
        map = lookup(mapName)
        if not map then return nil, "unknown zone \"" .. mapName .. "\"" end
    end
    if x > 1 or y > 1 then x, y = x / 100, y / 100 end   -- 45.2 -> 0.452
    if x < 0 or x > 1 or y < 0 or y > 1 then return nil, "coordinates must be 0-100" end
    return { map = map, mapName = mapName, x = x, y = y, note = (after and after ~= "") and after or nil }
end

-- Set from pasted text; returns true if it worked (prints why not).
function W:SetFromText(text)
    -- A party member's name: follow them (Follow.lua), the arrow keeps
    -- pointing at them as they move.
    local who = (text or ""):gsub("^%s*/%a+%s*", ""):gsub("^[Ww]ay%s+", ""):match("^%s*(%S+)%s*$")
    if who and not who:find("%d") and ns.follow then
        local name = ns.follow.MemberNamed(who)
        if name then ns.follow:Start(name) return true end
    end
    local p, why = W.Parse(text)
    if not p then
        ns:Print("couldn't read that: " .. why .. ". Try: 45.2 63.1, or Elwynn Forest 45.2 63.1 Hogger")
        return false
    end
    local map = p.map or (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
    if not map then ns:Print("can't tell which zone you're in") return false end
    W:Set(map, p.x, p.y, p.note)
    return true
end

-- A box to paste coordinates into (arrow menu: "Set a waypoint...").
-- (Only our own key in the game's popup table: replacing the table itself taints
-- every popup in the game.)
StaticPopupDialogs["FLOW_WAYPOINT"] = {
    text = "Paste or type coordinates, or a party member's name to follow them:\n|cff999999e.g. 45.2 63.1  or  Elwynn Forest 45.2 63.1 Hogger  or  Zed|r",
    button1 = ACCEPT or "Accept", button2 = CANCEL or "Cancel",
    hasEditBox = true, editBoxWidth = 260,
    OnAccept = function(self)
        local box = self.editBox or self.EditBox
        W:SetFromText(box and box:GetText())
    end,
    EditBoxOnEnterPressed = function(self)
        if W:SetFromText(self:GetText()) then self:GetParent():Hide() end
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
function W:Prompt() StaticPopup_Show("FLOW_WAYPOINT") end

ns.commands.way = function(arg)
    arg = arg or ""
    if arg:lower():match("^%s*clear") then
        W:Clear()
        ns:Print("waypoint cleared")
        return
    end
    -- A service: nearest repair, vendor, flight master, innkeeper, banker,
    -- auctioneer or mailbox (Services.lua). A few other words for them too.
    local ALIAS = { sell = "vendor", taxi = "flight", fly = "flight", flightmaster = "flight", innkeeper = "inn",
                    hearth = "inn", banker = "bank", ah = "auction", auctioneer = "auction", mailbox = "mail" }
    local svc = arg:lower():match("^%s*(%a+)%s*$")
    svc = svc and (ALIAS[svc] or svc)
    if svc and ns.services and ns.services.LABEL and ns.services.LABEL[svc] then
        ns.services:GoTo(svc)
        return
    end
    if arg:match("^%s*$") then
        ns:Print("/flow way <x> <y> [note], /flow way <zone> <x> <y> [note], /flow way <party member> (follow them), /flow way repair | vendor | flight | inn | bank | auction | mail, /flow way clear. Or Alt-click the world map, or right-click the arrow.")
        return
    end
    W:SetFromText(arg)
end

-- "/way ..." too, the format most guides and sites give, unless another
-- addon (TomTom) already owns it.
ns:On("PLAYER_LOGIN", function()
    local taken = (SlashCmdList and SlashCmdList.TOMTOM_WAY) or (hash_SlashCmdList and hash_SlashCmdList["/WAY"])
    if not taken and SlashCmdList then
        SLASH_FLOWWAY1 = "/way"
        SlashCmdList.FLOWWAY = ns.commands.way
    end
end)
