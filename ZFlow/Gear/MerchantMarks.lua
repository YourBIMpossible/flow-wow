local _, ns = ...

-- Which of a merchant's items are upgrades (S20). It asks the same question
-- the item tooltip asks (Gear/TooltipModule.lua's Lines) of every item the
-- open merchant has on sale, and keeps the ones with an upgrade line. Look
-- only: nothing is bought, picked up or equipped, and nothing here touches
-- the merchant window.
--
--   marks, info = GearMerchantMarks.Marks(client, packs)
--   text        = GearMerchantMarks.Text(marks, info)
--
--   client  the injected client. Used: merchantItems() (the rows on sale;
--           nil when no merchant window is open or it cannot be read), and
--           whatever the tooltip lines read (gear, class, level).
--   packs   the class packs (ns.Packs)
--   marks   the upgrades, in the window's order:
--             { { index, link, lines = { "Upgrade for ...", ... } } ... }
--           lines holds the upgrade line of each role it is an upgrade for.
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

function M.Marks(client, packs)
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
            local lines = ns.GearTooltipModule.Lines(client, packs, link)
            if type(lines) == "table" and #lines > 0 then
                info.gear = info.gear + 1
                local good = {}
                for j = 1, #lines do
                    if lines[j].tone == "good" then good[#good + 1] = lines[j].text end
                end
                if #good > 0 then
                    marks[#marks + 1] = { index = type(row.index) == "number" and row.index or i,
                                          link = link, lines = good }
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

function M.Text(marks, info)
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
        out[#out + 1] = tostring(marks[i].link) .. ": " .. table.concat(marks[i].lines, "; ")
    end
    return out
end
