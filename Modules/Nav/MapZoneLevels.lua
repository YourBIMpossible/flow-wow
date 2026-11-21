-- Zone info when you hover a zone on the continent world map.
--
-- "I would just like to highlight the zone and see the name of the zone,
-- the level range, and the fishing level range."
-- On Kalimdor or the Eastern Kingdoms map, the zone under the cursor gets a
-- small card in the map's top left corner (by the cursor it covered too much:
-- "The card ends up blocking too many things"):
--   Westfall
--   Level 10-20        (coloured against your level)
--   Fishing 1
-- The game's own zone highlight shows which zone it is. With nothing
-- hovered, the card shows the zone you're in, in the same corner ("Can we
-- have it still show when you're in the zone by default?"). Settings: "Zone info when hovering the world map",
-- "World map: your zone's info without hovering". Both on by default.
--
-- Level ranges: warcraft.wiki.gg "Zones by level (Classic)". Fishing: the
-- skill to fish the zone's waters without the catch getting away, as the
-- Classic fishing tables give it; "130 (205)" means most waters need 130 and
-- some need 205. Keyed by the map's own zone ID (locale-proof).
--
-- Holding Shift adds what the zone's waters give and how often ("I think
-- your shift idea's probably the best"); a grey "Shift" after the fishing
-- line says so. Flow ships no catch records (ZL.FISH is empty), so the list
-- says the catches are unknown. ZL.FISH's shape, for records Flow gets from
-- the game: [uiMapID] = { records, { itemID, percent, "English name" }, ... }.
--
-- Flow's own frames only. It reads the cursor and C_Map; it never changes
-- the game's map, its labels or its highlight, and its card takes no mouse.

local _, ns = ...
local ZL = {}
ns.mapZoneLevels = ZL

ZL.FONT_SIZE = 14
ZL.FISH_SIZE = 12
ZL.FISH_COLOR = { 0.36, 0.88, 0.95 }   -- light tropical-water blue
ZL.LIST_SIZE = 11
ZL.FEW = 300                            -- fewer records than this: "few catches recorded"
ZL.FISH = ZL.FISH or {}                 -- no catch records shipped: unknown
ZL.FISH_UNKNOWN = "catches unknown"

-- [uiMapID] = { name, min, max, fish, fishTop }. A city has no range; a zone
-- with no water no fishing.
ZL.ZONES = {
    -- Eastern Kingdoms
    [1426] = { "Dun Morogh", 1, 10, 1 },           [1429] = { "Elwynn Forest", 1, 10, 1 },
    [1420] = { "Tirisfal Glades", 1, 10, 1 },       [1436] = { "Westfall", 10, 20, 1 },
    [1432] = { "Loch Modan", 10, 20, 1 },           [1421] = { "Silverpine Forest", 10, 20, 1 },
    [1433] = { "Redridge Mountains", 15, 25, 55 },  [1431] = { "Duskwood", 18, 30, 55 },
    [1437] = { "Wetlands", 20, 30, 55 },            [1424] = { "Hillsbrad Foothills", 20, 35, 55 },
    [1416] = { "Alterac Mountains", 30, 40, 130 },  [1417] = { "Arathi Highlands", 30, 40, 130 },
    [1434] = { "Stranglethorn Vale", 30, 45, 130, 205 },
    [1418] = { "Badlands", 35, 45 },                [1435] = { "Swamp of Sorrows", 35, 45, 130 },
    [1425] = { "The Hinterlands", 40, 50, 205 },    [1427] = { "Searing Gorge", 45, 50 },
    [1419] = { "Blasted Lands", 45, 55 },           [1428] = { "Burning Steppes", 50, 58, 330 },
    [1422] = { "Western Plaguelands", 51, 58, 205 },
    [1423] = { "Eastern Plaguelands", 53, 60, 330 },
    [1430] = { "Deadwind Pass", 55, 60, 330 },
    [1453] = { "Stormwind City", nil, nil, 1 },     [1455] = { "Ironforge", nil, nil, 1 },
    [1458] = { "Undercity", nil, nil, 1 },
    -- Kalimdor
    [1438] = { "Teldrassil", 1, 10, 1 },            [1411] = { "Durotar", 1, 10, 1 },
    [1412] = { "Mulgore", 1, 10, 1 },               [1439] = { "Darkshore", 10, 20, 1 },
    [1413] = { "The Barrens", 10, 25, 1 },          [1442] = { "Stonetalon Mountains", 15, 27, 55 },
    [1440] = { "Ashenvale", 18, 30, 55 },           [1441] = { "Thousand Needles", 25, 35, 130 },
    [1443] = { "Desolace", 30, 40, 130 },           [1445] = { "Dustwallow Marsh", 35, 45, 130 },
    [1444] = { "Feralas", 40, 50, 205, 330 },       [1446] = { "Tanaris", 40, 50, 205 },
    [1447] = { "Azshara", 45, 55, 205, 330 },       [1449] = { "Un'Goro Crater", 48, 55, 205 },
    [1448] = { "Felwood", 48, 55, 205 },            [1452] = { "Winterspring", 53, 60, 330 },
    [1450] = { "Moonglade", 55, 60, 205 },          [1451] = { "Silithus", 55, 60, 330 },
    [1454] = { "Orgrimmar", nil, nil, 1 },          [1456] = { "Thunder Bluff", nil, nil, 1 },
    [1457] = { "Darnassus", nil, nil, 1 },
}

function ZL.On() return not (ns.db and ns.db.nav and ns.db.nav.mapZoneLevels == false) end

-- The colour of a zone's range for someone of `level`.
function ZL.Color(min, max, level)
    if level < min - 3 then return 1, 0.1, 0.1, "red" end
    if level < min then return 1, 0.5, 0.25, "orange" end
    if level <= max then return 1, 0.82, 0, "yellow" end
    if level <= max + 5 then return 0.25, 0.75, 0.25, "green" end
    return 0.62, 0.62, 0.62, "grey"
end

-- The card for the zone `zoneID` (named `name` by the map) for someone of
-- `level`: { name, level = "Level 10-20" or nil, r, g, b, fish = "Fishing
-- 130 (205)" or nil }, or nil when Flow knows nothing about it.
function ZL.Card(zoneID, name, level)
    local z = ZL.ZONES[zoneID]
    if not z then return nil end
    local card = { name = name or z[1] }
    if z[2] then
        card.level = z[2] == z[3] and ("Level " .. z[2]) or string.format("Level %d-%d", z[2], z[3])
        card.r, card.g, card.b = ZL.Color(z[2], z[3], level)
    end
    if z[4] then
        card.fish = "Fishing " .. z[4] .. (z[5] and string.format(" (%d)", z[5]) or "")
    end
    return card
end

-- What the zone's waters give: { { name, pct }, ... }, few (true when only a
-- handful of catches were recorded), or nil when Flow has no records.
-- `nameOf(itemID)` gives the local name (the game's item cache); the English
-- one stands in until it loads.
function ZL.FishList(zoneID, nameOf)
    local f = ZL.FISH[zoneID]
    if not (f and f[2]) then return nil end
    nameOf = nameOf or function(id) return ns.api.ItemInfo and (ns.api.ItemInfo(id)) end   -- (not the bare GetItemInfo: gone on Forever)
    local rows = {}
    for i = 2, #f do
        rows[#rows + 1] = { name = nameOf(f[i][1]) or f[i][3], pct = f[i][2] }
    end
    return rows, f[1] < ZL.FEW
end

function ZL.FishOpen() return IsShiftKeyDown and IsShiftKeyDown() or false end

-------------------------------------------------------------------------------
-- The card.
-------------------------------------------------------------------------------

local card
local function makeCard()
    local f = CreateFrame("Frame", nil, WorldMapFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetFrameStrata("TOOLTIP")
    f:EnableMouse(false)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                        tile = true, tileSize = 16, edgeSize = 14,
                        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0.04, 0.04, 0.06, 0.92)
        f:SetBackdropBorderColor(0.55, 0.55, 0.6, 1)
    end
    f.name = f:CreateFontString(nil, "ARTWORK")
    f.name:SetPoint("TOPLEFT", 10, -9)
    f.level = f:CreateFontString(nil, "ARTWORK")
    f.level:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -4)
    f.fish = f:CreateFontString(nil, "ARTWORK")
    for _, fs in ipairs({ f.name, f.level, f.fish }) do
        fs:SetFont(STANDARD_TEXT_FONT, fs == f.fish and ZL.FISH_SIZE or ZL.FONT_SIZE, "OUTLINE")
        fs:SetShadowOffset(1, -1)
        fs:SetJustifyH("LEFT")
    end
    f.fish:SetTextColor(unpack(ZL.FISH_COLOR))
    f.name:SetTextColor(1, 1, 1)
    -- "Shift" after the fishing line, when there's a list to show.
    f.hint = f:CreateFontString(nil, "ARTWORK")
    f.hint:SetFont(STANDARD_TEXT_FONT, ZL.LIST_SIZE - 1, "OUTLINE")
    f.hint:SetShadowOffset(1, -1)
    f.hint:SetTextColor(0.5, 0.5, 0.5)
    f.hint:SetText("Shift")
    f.hint:SetPoint("BOTTOMLEFT", f.fish, "BOTTOMRIGHT", 6, 0)
    f.rows = {}
    f.few = f:CreateFontString(nil, "ARTWORK")
    f.few:SetFont(STANDARD_TEXT_FONT, ZL.LIST_SIZE, "OUTLINE")
    f.few:SetShadowOffset(1, -1)
    f.few:SetTextColor(0.6, 0.6, 0.6)
    f.few:SetText("few catches recorded")
    f.unknown = f:CreateFontString(nil, "ARTWORK")
    f.unknown:SetFont(STANDARD_TEXT_FONT, ZL.LIST_SIZE, "OUTLINE")
    f.unknown:SetShadowOffset(1, -1)
    f.unknown:SetTextColor(0.6, 0.6, 0.6)
    f.unknown:SetText(ZL.FISH_UNKNOWN)
    f:Hide()
    return f
end

local function row(f, i)
    local r = f.rows[i]
    if r then return r end
    r = { n = f:CreateFontString(nil, "ARTWORK"), p = f:CreateFontString(nil, "ARTWORK") }
    for _, fs in ipairs({ r.n, r.p }) do
        fs:SetFont(STANDARD_TEXT_FONT, ZL.LIST_SIZE, "OUTLINE")
        fs:SetShadowOffset(1, -1)
    end
    r.n:SetJustifyH("LEFT")
    r.n:SetTextColor(0.9, 0.9, 0.9)
    r.p:SetJustifyH("RIGHT")
    r.p:SetTextColor(unpack(ZL.FISH_COLOR))
    f.rows[i] = r
    return r
end

local shownFor
local function hideCard()
    if card then card:Hide(); card.key = nil end
    shownFor = nil
end

local function cardKey(zoneID) return zoneID .. (ZL.FishOpen() and "+" or "-") end

-- Lay out the card's text for `c`, with the fish list under the fishing
-- line when it's open.
local function layout(c, zoneID)
    card.name:SetText(c.name)
    local below = card.name
    card.level:SetShown(c.level ~= nil)
    if c.level then
        card.level:SetText(c.level)
        card.level:SetTextColor(c.r, c.g, c.b)
        below = card.level
    end
    local w = math.max(card.name:GetStringWidth(), c.level and card.level:GetStringWidth() or 0)
    local h = 9 + card.name:GetStringHeight() + (c.level and 4 + card.level:GetStringHeight() or 0)
    card.fish:ClearAllPoints()
    card.fish:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -3)
    card.fish:SetShown(c.fish ~= nil)
    local list, few
    if c.fish then
        card.fish:SetText(c.fish)
        list, few = ZL.FishList(zoneID)
    end
    local open = c.fish ~= nil and ZL.FishOpen()
    -- The hint while the list (or the word that it's unknown) isn't showing.
    card.hint:SetShown(c.fish ~= nil and not open)
    for _, r in ipairs(card.rows) do r.n:Hide(); r.p:Hide() end
    card.few:Hide()
    card.unknown:Hide()
    if c.fish then
        w = math.max(w, card.fish:GetStringWidth() + 6 + card.hint:GetStringWidth())
        h = h + 3 + card.fish:GetStringHeight()
    end
    if open and not list then
        card.unknown:ClearAllPoints()
        card.unknown:SetPoint("TOPLEFT", card.fish, "BOTTOMLEFT", 0, -5)
        card.unknown:Show()
        w = math.max(w, card.unknown:GetStringWidth())
        h = h + 5 + card.unknown:GetStringHeight()
    elseif open then
        local nameW, pctW = 0, 0
        for i, f in ipairs(list) do
            local r = row(card, i)
            r.n:SetText(f.name)
            r.p:SetText(f.pct .. "%")
            nameW = math.max(nameW, r.n:GetStringWidth())
            pctW = math.max(pctW, r.p:GetStringWidth())
        end
        local prev = card.fish
        for i = 1, #list do
            local r = card.rows[i]
            local gap = i == 1 and 5 or 2
            r.n:ClearAllPoints()
            r.n:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -gap)
            r.p:ClearAllPoints()
            r.p:SetPoint("TOPLEFT", r.n, "TOPLEFT", nameW + 12, 0)
            r.p:SetWidth(pctW + 2)
            r.n:Show(); r.p:Show()
            h = h + gap + r.n:GetStringHeight()
            prev = r.n
        end
        w = math.max(w, nameW + 12 + pctW + 2)
        if few then
            card.few:ClearAllPoints()
            card.few:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -4)
            card.few:Show()
            w = math.max(w, card.few:GetStringWidth())
            h = h + 4 + card.few:GetStringHeight()
        end
    end
    card:SetSize(math.ceil(w) + 20, math.ceil(h + 9))
end

-- Always in the map's top left corner, clear of the zones you're looking at.
local function showCard(c, zoneID)
    card = card or makeCard()
    if card.key ~= cardKey(zoneID) then
        layout(c, zoneID)
        card.key = cardKey(zoneID)
    end
    shownFor = zoneID
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", WorldMapFrame.ScrollContainer, "TOPLEFT", 12, -12)
    card:Show()
end

-- The zone you're in (one Flow knows), or nil: from a sub-zone, cave or
-- town map up to its zone.
function ZL.PlayerZone(best, parentOf)
    parentOf = parentOf or function(id)
        local info = C_Map.GetMapInfo(id)
        return info and info.parentMapID
    end
    local id = best
    for _ = 1, 6 do
        if not id or id == 0 then return nil end
        if ZL.ZONES[id] then return id end
        id = parentOf(id)
    end
    return nil
end

function ZL.Here() return not (ns.db and ns.db.nav and ns.db.nav.mapZoneHere == false) end

-- The continent zone under the cursor, or nil.
local function zoneUnderCursor()
    local sc = WorldMapFrame.ScrollContainer
    if not (sc and sc.GetNormalizedCursorPosition and sc:IsMouseOver()) then return nil end
    local mapID = WorldMapFrame:GetMapID()
    local info = mapID and C_Map.GetMapInfo(mapID)
    if not (info and Enum.UIMapType and info.mapType == Enum.UIMapType.Continent) then return nil end
    local x, y = sc:GetNormalizedCursorPosition()
    if not (x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1) then return nil end
    local at = C_Map.GetMapInfoAtPosition(mapID, x, y)
    if not at or at.mapID == mapID then return nil end
    return at.mapID, at.name
end

-- With nothing hovered: the zone you're in, on the continent map or its own.
local function yourZone()
    if not ZL.Here() then return nil end
    local here = ZL.PlayerZone(C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
    if not here then return nil end
    local mapID = WorldMapFrame:GetMapID()
    if mapID == here then return here end
    local info = mapID and C_Map.GetMapInfo(mapID)
    if not (info and Enum.UIMapType and info.mapType == Enum.UIMapType.Continent) then return nil end
    return here
end

function ZL.Tick()
    if not (ZL.On() and WorldMapFrame and WorldMapFrame:IsShown()) then hideCard() return end
    -- A pin's own tooltip wins: no card on top of it.
    if GameTooltip:IsShown() then hideCard() return end
    local level = UnitLevel("player") or 1
    local zoneID, name = zoneUnderCursor()
    local c = zoneID and ZL.Card(zoneID, name, level)
    if c then showCard(c, zoneID) return end
    local here = yourZone()
    c = here and ZL.Card(here, C_Map.GetMapInfo(here) and C_Map.GetMapInfo(here).name, level)
    if c then showCard(c, here) else hideCard() end
end
ZL.Tick = ns.perf.Wrap("world map (zone info)", ZL.Tick)

function ZL.Set(on)
    ns.db.nav.mapZoneLevels = on and true or false
    if not on then hideCard() end
end

ns:OnLoad(function()
    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function()
        if WorldMapFrame and WorldMapFrame:IsShown() then pcall(ZL.Tick)
        elseif shownFor then hideCard() end
    end)
end)

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck{ group = "route", label = "Zone info when hovering the world map",
        tip = "On the continent map, the zone under the cursor shows, in the map's top left corner, its name, level range (coloured against "
            .. "your level) and the fishing skill its waters need. Hold Shift for the fish its waters give: Flow has no record of them, so it says they're unknown.",
        get = ZL.On, set = ZL.Set }
    ns.settings:AddCheck{ group = "route", label = "World map: your zone's info without hovering",
        tip = "With nothing hovered, the card shows the zone you're in, on the continent map "
            .. "and on your zone's own map.",
        get = ZL.Here, set = function(on) ns.db.nav.mapZoneHere = on and true or false; hideCard() end }
end
