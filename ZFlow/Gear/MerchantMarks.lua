local _, ns = ...

-- Which of a merchant's items are upgrades (S20). It asks the same question
-- the item tooltip asks (Gear/TooltipModule.lua's Lines) of every item the
-- open merchant has on sale, and keeps the ones with an upgrade line. Look
-- only: nothing is bought, picked up or equipped, and nothing here touches
-- the merchant window.
--
--   marks, info = GearMerchantMarks.Marks(client, packs, role)
--     role: spec.role; none chosen, GearRole.Active's "dps" (one role)
--   text        = GearMerchantMarks.Text(marks, info[, opts])
--   badges      = GearMerchantMarks.Specs(client, packs, role)
--
--   client  the injected client. Used: merchantItems() (the rows on sale;
--           nil when no merchant window is open or it cannot be read), and
--           whatever the tooltip lines read (gear, class, level).
--   packs   the class packs (ns.Packs)
--   marks   the upgrades, in the window's order:
--             { { index, link, lines = { "Upgrade for ...", ... } } ... }
--           lines holds the upgrade line of each role it is an upgrade for.
--           price: the row's price in copper, when the client gave one.
--           nil when the merchant could not be read; {} when nothing on
--           sale is an upgrade.
--   info    { why } with no marks; else the counts
--             rows       items on sale
--             unread     rows whose item the client did not give
--             gear       rows that are gear and were looked at
--             cannotUse  gear the game (or the class table) says you cannot use
--             noVerdict  gear with no verdict: something needed was not read
--   text    lines to show: how many upgrades, then one line for each; or
--           that there are none, when gear was looked at; {} otherwise.
--           With opts (the advisor's lines): each item line also gives its
--           price, and ", more than you have" when opts.money (the player's
--           copper, a read) is a count below it. No money read: no claim.
--   badges  { [the merchant's item number] = { { role, state } ... } }:
--           per role the pack has weights for, the chosen role (spec.role)
--           first, then the others in name order; state "up" (an upgrade),
--           "down" (not an upgrade) or "same". A role whose verdict is
--           can't use or no verdict gets no entry; an item with none is
--           left out. nil when the merchant could not be read.
--
-- An item is marked only on an "Upgrade" line. "Can't use", "No verdict",
-- "Same" and "Not an upgrade" never mark it, so nothing unknown becomes a
-- mark.

local M = {}
ns.GearMerchantMarks = M

M.REASON = {
    merchant = "the merchant's items could not be read",
}

local function plural(n, one, many)
    return n .. " " .. (n == 1 and one or many)
end

function M.Marks(client, packs, role)
    local rows = nil
    if type(client) == "table" and type(client.merchantItems) == "function" then
        rows = client.merchantItems()
    end
    if type(rows) ~= "table" then return nil, { why = M.REASON.merchant } end

    local marks = {}
    local info = { rows = #rows, unread = 0, gear = 0, cannotUse = 0, noVerdict = 0 }
    for i = 1, #rows do
        local row = type(rows[i]) == "table" and rows[i] or {}
        local link = row.item
        if type(link) ~= "string" or link == "" then
            info.unread = info.unread + 1
        else
            local lines = ns.GearTooltipModule.Lines(client, packs, link,
                { role = (ns.GearRole.Active(role)) })
            if type(lines) == "table" and #lines > 0 then
                info.gear = info.gear + 1
                local good = {}
                for j = 1, #lines do
                    if lines[j].tone == "good" then good[#good + 1] = lines[j].text end
                end
                if #good > 0 then
                    marks[#marks + 1] = { index = type(row.index) == "number" and row.index or i,
                                          link = link, lines = good, price = row.price }
                elseif lines[1].text:find("^Can't use") then
                    info.cannotUse = info.cannotUse + 1
                elseif lines[1].tone == "none" then
                    info.noVerdict = info.noVerdict + 1
                end
            end
        end
    end
    return marks, info
end

local function count(v)
    return type(v) == "number" and v >= 0 and v == math.floor(v)
end

-- "; 25s 40c" and, when the money read is below it, ", more than you have".
local function priceTail(price, money)
    if not count(price) then return "" end
    local text = "; " .. ns.Prices.Coin(price)
    if count(money) and money < price then text = text .. ", more than you have" end
    return text
end

function M.Text(marks, info, opts)
    if type(marks) ~= "table" or type(info) ~= "table" then return {} end
    local out = {}
    if #marks == 0 then
        if (info.gear or 0) == 0 then return out end
        local text = "No upgrades on sale here"
        if (info.noVerdict or 0) > 0 then
            text = text .. "; " .. plural(info.noVerdict, "item", "items") .. " with no verdict"
        end
        out[1] = text
        return out
    end
    out[1] = plural(#marks, "upgrade", "upgrades") .. " on sale here"
    for i = 1, #marks do
        local line = tostring(marks[i].link) .. ": " .. table.concat(marks[i].lines, "; ")
        if type(opts) == "table" then line = line .. priceTail(marks[i].price, opts.money) end
        out[#out + 1] = line
    end
    return out
end

-- The per-role badge states (S20): the tooltip verdict's tone, role by role.
M.STATE = { good = "up", bad = "down", same = "same" }

local function ask(client, read, ...)
    if type(client) ~= "table" or type(client[read]) ~= "function" then return nil end
    return client[read](...)
end

-- The chosen role first when the pack has weights for it, then the rest
-- in name order.
local function rolesFor(pack, chosen)
    local weights = type(pack) == "table" and type(pack.weights) == "table" and pack.weights or {}
    local rest = {}
    for r, w in pairs(weights) do
        if type(r) == "string" and type(w) == "table" and r ~= chosen then rest[#rest + 1] = r end
    end
    table.sort(rest)
    local out = {}
    if type(chosen) == "string" and chosen ~= "" and type(weights[chosen]) == "table" then out[1] = chosen end
    for i = 1, #rest do out[#out + 1] = rest[i] end
    return out
end

function M.Specs(client, packs, role)
    local rows = ask(client, "merchantItems")
    if type(rows) ~= "table" then return nil end
    local class = ask(client, "class")
    local pack = nil
    if type(packs) == "table" and class ~= nil then pack = packs[class] end
    local level = ask(client, "level")
    local skills = nil
    local okSkills, readSkills = pcall(ask, client, "weaponSkills")
    if okSkills and type(readSkills) == "table" then skills = readSkills end
    local roles = rolesFor(pack, role)
    local out = {}
    for i = 1, #rows do
        local row = type(rows[i]) == "table" and rows[i] or {}
        local link = row.item
        local gear = nil
        if type(link) == "string" and link ~= "" then gear = ask(client, "gear", link) end
        if type(gear) == "table" then
            local list = {}
            for j = 1, #roles do
                local lines, detail = ns.GearVerdict.Lines(gear, { pack = pack, role = roles[j], level = level,
                                                                    skills = skills })
                if lines == nil then break end
                local use = nil
                if type(detail) == "table" then use = detail.use end
                local first = lines[1]
                if type(use) == "table" and use.can == true and type(first) == "table" then
                    local state = M.STATE[first.tone]
                    if state ~= nil then list[#list + 1] = { role = roles[j], state = state } end
                end
            end
            if #list > 0 then out[type(row.index) == "number" and row.index or i] = list end
        end
    end
    return out
end
