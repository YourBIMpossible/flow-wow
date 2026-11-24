local _, ns = ...

-- Vendor recipes (lead section 422 item 1): the recipes this player saw for
-- sale at a vendor they opened, for the profession plan
-- (Items/ProfPlan.lua) to name "buy it there" between trainer ranks.
-- Learned at run time only: no recipe table is shipped, nothing is
-- authored, nothing is bought.
--
-- On MERCHANT_SHOW (through the bus, after client.watchMerchant()), each
-- item of client.merchantItems() whose tooltip (client.itemLines) has a
-- line "Requires <profession> (<skill>)" is kept under account
--   "learned.vendorRecipes"[item key] =
--     { item, name, recipe, prof, skill, vendor, map, x, y, seen }
-- name is client.itemInfo(item).name (else the tooltip's first line);
-- recipe is the name with a leading "<word>: " taken off (the name the
-- recipe book saves once learned); vendor is client.serviceNpc().name;
-- map, x, y are client.position() at the show (where the player stood);
-- seen is client.clock() when known. An item whose tooltip gives no
-- profession line is not kept: its profession and skill are never
-- guessed. No vendor name, no position, or a merchant that cannot be read:
-- nothing is written. The newest sighting of an item replaces the old one.
--
--   VendorRecipes.Line(lines) -> prof, skill   or nil
--   VendorRecipes.Seen(client, store) -> report { ok, reason, kept }
--   VendorRecipes.Rows(store) -> { row, ... } sorted by item key
--   VendorRecipes.Declare(k) -> api { last() }
--
-- First guesses, not seen in game: the "Requires X (n)" wording (the
-- English client's), and that the recipe book saves a recipe under its
-- item's name past the colon.

local VR = {}
ns.VendorRecipes = VR

VR.NAME = "vendorRecipes"
VR.PATH = "learned.vendorRecipes"
VR.MAX = 400
VR.REQUIRES = "^Requires (.-) %((%d+)%)$"

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function text(v)
    return type(v) == "string" and v ~= ""
end

local function ask(client, read, ...)
    if type(client) ~= "table" or type(client[read]) ~= "function" then return nil end
    local ok, v = pcall(client[read], ...)
    if not ok then return nil end
    return v
end

-- The profession and skill a tooltip names, or nil.
function VR.Line(lines)
    if type(lines) ~= "table" then return nil end
    for _, line in ipairs(lines) do
        if type(line) == "string" then
            local prof, skill = line:match(VR.REQUIRES)
            if text(prof) and skill then return prof, tonumber(skill) end
        end
    end
    return nil
end

-- The recipe's own name: the item name past a leading "<word>: ".
function VR.RecipeName(name)
    if not text(name) then return nil end
    local rest = name:match("^[^:]+: (.+)$")
    if text(rest) then return rest end
    return name
end

function VR.Seen(client, store)
    local report = { ok = false, kept = 0 }
    local items = ask(client, "merchantItems")
    if type(items) ~= "table" then report.reason = "the merchant cannot be read" return report end
    local npc = ask(client, "serviceNpc")
    local vendor = type(npc) == "table" and npc.name or nil
    if not text(vendor) then report.reason = "the vendor is not named" return report end
    local pos = ask(client, "position")
    if type(pos) ~= "table" or pos.map == nil or not (finite(pos.x) and finite(pos.y)) then
        report.reason = "the position is not known"
        return report
    end
    if type(store) ~= "table" or type(store.get) ~= "function" or type(store.set) ~= "function" then
        report.reason = "the recipes cannot be saved"
        return report
    end
    local now = ask(client, "clock")
    local keyOf = ns.Items and ns.Items.Key or function(v) return v end
    local found = {}
    for _, row in pairs(items) do
        local key = type(row) == "table" and row.item ~= nil and keyOf(row.item) or nil
        if key ~= nil then
            local lines = ask(client, "itemLines", row.item)
            local prof, skill = VR.Line(lines)
            if prof then
                local info = ask(client, "itemInfo", row.item)
                local name = type(info) == "table" and info.name or nil
                if not text(name) and type(lines) == "table" then name = lines[1] end
                if text(name) then
                    found[key] = { item = key, name = name, recipe = VR.RecipeName(name), prof = prof,
                        skill = finite(skill) and skill or nil, vendor = vendor,
                        map = pos.map, x = pos.x, y = pos.y, seen = finite(now) and now or nil }
                end
            end
        end
    end
    if next(found) == nil then report.ok = true return report end
    local okGet, cur = pcall(store.get, store, "account", VR.PATH)
    if not okGet or (cur ~= nil and type(cur) ~= "table") then
        report.reason = "the recipes cannot be saved"
        return report
    end
    local out, n = {}, 0
    for k, v in pairs(cur or {}) do out[k] = v; n = n + 1 end
    for k, v in pairs(found) do
        if out[k] == nil then n = n + 1 end
        if out[k] ~= nil or n <= VR.MAX then
            out[k] = v
            report.kept = report.kept + 1
        end
    end
    local okSet, set = pcall(store.set, store, "account", VR.PATH, out)
    if not okSet or set ~= true then
        report.kept = 0
        report.reason = "the recipes cannot be saved"
        return report
    end
    report.ok = true
    return report
end

function VR.Rows(store)
    if type(store) ~= "table" or type(store.get) ~= "function" then return {} end
    local ok, cur = pcall(store.get, store, "account", VR.PATH)
    if not ok or type(cur) ~= "table" then return {} end
    local keys = {}
    for k in pairs(cur) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = {}
    for _, k in ipairs(keys) do
        if type(cur[k]) == "table" then out[#out + 1] = cur[k] end
    end
    return out
end

function VR.Declare(k)
    local api = {}
    local last
    function api.last() return last end
    k:Module({
        name = VR.NAME,
        needs = { "client", "store", "bus" },
        provides = { Last = api.last },
        -- After watchMerchant(), so the client knows the window is open.
        start = function(ctx)
            if type(ctx.client.watchMerchant) == "function" then ctx.client.watchMerchant() end
            ctx.bus:on(VR.NAME, "MERCHANT_SHOW", function()
                last = VR.Seen(ctx.client, ctx.store)
            end)
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.vendorRecipes = VR.Declare(ns)
