-- Colours used across Flow. Swap the values here to re-theme everything.

local _, ns = ...

local function rgb(hex)
    return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255,
             tonumber(hex:sub(5, 6), 16) / 255, hex = hex }
end

-- Route colours (map lines, pins, the nav arrow, the minimap dot). The route
-- and the arrow share one colour, and it tells you the route's state:
--   Most XP first       epic purple   optimised
--   Shortest path       rare blue     optimised
--   Custom route        legendary orange: you picked the next stop (a ^);
--                       stays until you choose Most XP or Shortest again
-- Your own waypoint is green (uncommon green), its own colour so it never
-- reads as a Custom route: the arrow and a line on the map to it. Hovering a
-- ^ previews that route in orange. The stop under your mouse is red.
-- Colour-blind palette (/flow settings): Okabe-Ito equivalents that stay
-- apart for the common kinds of colour blindness.
local PALETTES = {
    standard = {
        modes    = { xp = rgb("A335EE"), distance = rgb("0070DD"), custom = rgb("FF8000"), selected = rgb("FF8000") },
        proposed = rgb("FF8000"),  -- legendary orange: the route you'd follow if you pick the hovered stop
        waypoint = rgb("1EFF00"),  -- uncommon green: your own waypoint (arrow, map line, Router line)
        changed  = rgb("9A9A9A"),  -- grey: your route while previewing another
        hover    = rgb("FF4A4A"),  -- red: the stop under your mouse
        -- The modern arrow's colour by how close you are (Nav.lua, N.ArrowColor):
        -- grey while the stop is in another zone, then red (far) through
        -- yellow to green (close), and blue once you're in its area.
        arrowAway = rgb("9EA0A8"),
        arrowFar  = rgb("FF2E1F"),
        arrowMid  = rgb("FFD91A"),
        arrowNear = rgb("33F24D"),
        arrowHere = rgb("4DA6FF"),
    },
    colorblind = {
        modes    = { xp = rgb("CC79A7"), distance = rgb("0072B2"), custom = rgb("E69F00"), selected = rgb("E69F00") },
        proposed = rgb("E69F00"),
        waypoint = rgb("009E73"),  -- bluish green
        changed  = rgb("9A9A9A"),
        hover    = rgb("D55E00"),
        arrowAway = rgb("9EA0A8"),
        arrowFar  = rgb("D55E00"),  -- vermillion
        arrowMid  = rgb("F0E442"),  -- yellow
        arrowNear = rgb("009E73"),  -- bluish green
        arrowHere = rgb("56B4E9"),  -- sky blue
    },
}

ns.theme = {
    arrow    = rgb("E69F00"),  -- orange: Flow's accent colour on panels and buttons
    user     = rgb("56B4E9"),  -- sky blue: your own waypoint
    muted    = rgb("BBBBBB"),
    profPointer = rgb("6B6E76"),  -- dark grey: the faint profession needle under the main arrow
}

-- Flow's panel title bar, the brand on every Flow panel (Flow Tracker, Flow
-- Router, Flow Seller): a dark bar with the orange accent down its left edge,
-- an icon and the title in gold. One recipe, so the panels can't drift apart.
-- frameType "Button" when the bar is clickable. Returns the bar with
-- .bg, .accent, .icon and .text (the title).
ns.theme.TITLE_H = 24
function ns.theme:TitleBar(parent, title, icon, frameType)
    local h = CreateFrame(frameType or "Frame", nil, parent)
    h.flowTitleBar = true
    h:SetHeight(self.TITLE_H)
    h:SetPoint("TOPLEFT"); h:SetPoint("TOPRIGHT")
    h.bg = h:CreateTexture(nil, "BACKGROUND"); h.bg:SetAllPoints()
    h.bg:SetColorTexture(0.11, 0.09, 0.06, 0.92)
    local o = self.arrow
    h.accent = h:CreateTexture(nil, "BORDER")
    h.accent:SetPoint("TOPLEFT"); h.accent:SetPoint("BOTTOMLEFT"); h.accent:SetWidth(4)
    h.accent:SetColorTexture(o[1], o[2], o[3], 1)
    h.icon = h:CreateTexture(nil, "ARTWORK")
    h.icon:SetSize(16, 16); h.icon:SetPoint("LEFT", 9, 0)
    if icon then h.icon:SetTexture(icon) end
    h.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h.text:SetPoint("LEFT", h.icon, "RIGHT", 6, 0)
    h.text:SetText(title or "")
    return h
end

local function set(self, k, c)
    if self[k] then
        self[k][1], self[k][2], self[k][3], self[k].hex = c[1], c[2], c[3], c.hex
    else
        self[k] = { c[1], c[2], c[3], hex = c.hex }
    end
end

-- Colour of a route state ("xp", "distance", "custom") in the current palette:
-- menus and the map list colour their labels with it.
function ns.theme:ModeColor(mode)
    local p = PALETTES[self.palette or "standard"]
    return p.modes[mode] or p.modes.xp
end
function ns.theme:ModeText(mode, text) return "|cff" .. self:ModeColor(mode).hex .. text .. "|r" end

-- Route colour from the order mode (call after the mode changes).
function ns.theme:UpdateRoute()
    local p = PALETTES[self.palette or "standard"]
    local mode = ns.db and ns.db.nav and ns.db.nav.sorter or "xp"
    if mode == "selected" then mode = "custom" end   -- (its older name)
    local obj = ns.Get and ns:Get("routeObjective", mode)
    set(self, "route", p.modes[mode] or (obj and obj.color) or p.modes.xp)
    self.current = self.route  -- older name
end

-- Copies a palette's colours into ns.theme (the tables are shared, so code
-- that kept a reference sees the change too).
function ns.theme:UsePalette(name)
    local p = PALETTES[name] or PALETTES.standard
    self.palette = PALETTES[name] and name or "standard"
    for k, c in pairs(p) do if k ~= "modes" then set(self, k, c) end end
    self:UpdateRoute()
end
ns.theme:UsePalette("standard")

function ns.theme:ColorBlind() return self.palette == "colorblind" end
function ns.theme:SetColorBlind(on)
    ns.db.colorblind = on and true or false
    self:UsePalette(on and "colorblind" or "standard")
    if ns.mapOverlay and ns.mapOverlay.Redraw then pcall(ns.mapOverlay.Redraw, ns.mapOverlay) end
end

ns:OnLoad(function(saved)
    ns.theme:UsePalette(saved.colorblind and "colorblind" or "standard")
end)

-- Stop types on the route: a colour AND an icon each, so colour is never
-- the only cue. (Quests yellow, dailies blue, kills red were chosen by the
-- player; the rest are picked to stay apart from those.)
local R = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
ns.theme.kinds = {
    accept       = { color = rgb("F0E442"), icon = "Interface\\GossipFrame\\AvailableQuestIcon", label = "Accept quest" },
    turnin       = { color = rgb("FFD100"), icon = "Interface\\GossipFrame\\ActiveQuestIcon", label = "Turn in" },
    daily        = { color = rgb("4DA6FF"), icon = "Interface\\GossipFrame\\AvailableQuestIcon", label = "Daily quest" },
    kill         = { color = rgb("E8443A"), icon = R .. "8", label = "Kill" },
    collect      = { color = rgb("E69F00"), icon = R .. "3", label = "Collect (drops)" },
    use          = { color = rgb("C8A165"), icon = "Interface\\Icons\\INV_Misc_Gear_01", label = "Use / click" },
    talk         = { color = rgb("8FD694"), icon = "Interface\\GossipFrame\\GossipGossipIcon", label = "Talk to" },
    proftrainer  = { color = rgb("B07CFF"), icon = "Interface\\GossipFrame\\TrainerGossipIcon", label = "Profession trainer" },
    classtrainer = { color = rgb("2EC4B6"), icon = "Interface\\GossipFrame\\TrainerGossipIcon", label = "Class trainer" },
    merchant     = { color = rgb("D4AF37"), icon = "Interface\\GossipFrame\\VendorGossipIcon", label = "Merchant" },
    hearth       = { color = rgb("E0E0E0"), icon = "Interface\\Icons\\INV_Misc_Rune_01", label = "Hearthstone" },
    skill        = { color = rgb("57C785"), icon = "Interface\\Icons\\Trade_Fishing", label = "Skill-up" },
    gather       = { color = rgb("B5651D"), icon = "Interface\\Icons\\Trade_Mining", label = "Gather (mine, herbs)" },
    craft        = { color = rgb("CFCFCF"), icon = "Interface\\Icons\\Trade_BlackSmithing", label = "Craft / smelt" },
    waypoint     = { color = rgb("56B4E9"), icon = "Interface\\Minimap\\MinimapArrow", label = "Your waypoint" },
    party        = { color = rgb("56B4E9"), icon = "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon", label = "Party route" },
}

-- Progress reads as a path, where you are -> where you're going: "9 -> 66",
-- never "9/66". ProgressText rewrites the game's "0/7 Murloc slain".
function ns.Progress(have, need) return tostring(have) .. " -> " .. tostring(need) end
function ns.ProgressText(text)
    if type(text) ~= "string" then return text end
    return (text:gsub("(%d+)%s*/%s*(%d+)", "%1 -> %2"))
end
