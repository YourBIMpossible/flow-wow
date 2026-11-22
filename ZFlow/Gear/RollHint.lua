local _, ns = ...

-- The hint on a loot roll (S21): when the game offers you a roll on an item,
-- say whether it is an upgrade, by the same verdict the item tooltip gives.
-- It only shows a word. It never rolls, passes or confirms anything.
--
--   hint = GearRollHint.Hint(client, packs, link)
--   api  = GearRollHint.Declare(k[, packs])
--     api.hooked()   true once the client's loot rolls are being followed
--     api.errors()   how many rolls could not be worked out
--   ns.use(GearRollHint.NAME) -> { Hooked = api.hooked, Errors = api.errors }
--
-- Hint: { text, tone, lines }, or nil for what is not gear.
--   text   "Upgrade"      at least one role's line is an upgrade
--          "Unknown"      no upgrade line, and at least one line is a "No
--                         verdict" (or a note that something was not known)
--          "No upgrade"   every line is a known no: the same, worse, or
--                         "Can't use"
--   tone   "good" for an upgrade, else "none"
--   lines  the tooltip lines behind the word, as text: the upgrade lines for
--          "Upgrade", all of them otherwise
--   Unknown is never shown as an upgrade and never as a no.
--
-- The module: one setting row, account wide, on by default:
--   gear.rollHint   "Upgrade hint on loot rolls"
-- At start it asks the client to be told about loot rolls:
--   client.onLootRoll(fn) -> cancel;  fn(rollId, link, show);  show(text, r, g, b)
-- A client without that hook (see Core/Client.lua, F4) leaves the
-- module started and quiet. With the setting off nothing is worked out. An
-- error while working a hint out shows nothing for that roll, is counted,
-- and is kept as one "gear" problem per distinct error.

local R = {}
ns.GearRollHint = R

R.NAME = "gearRollHint"
R.SETTING = "gear.rollHint"

function R.Hint(client, packs, link)
    if type(client) ~= "table" or type(link) ~= "string" or link == "" then return nil end
    local lines = ns.GearTooltipModule.Lines(client, packs, link)
    if type(lines) ~= "table" or #lines == 0 then return nil end
    local good, all, unknown = {}, {}, false
    for i = 1, #lines do
        all[i] = lines[i].text
        if lines[i].tone == "good" then
            good[#good + 1] = lines[i].text
        elseif lines[i].tone == "none" then
            unknown = true
        end
    end
    if #good > 0 then return { text = "Upgrade", tone = "good", lines = good } end
    if unknown then return { text = "Unknown", tone = "none", lines = all } end
    return { text = "No upgrade", tone = "none", lines = all }
end

function R.Declare(k, packs)
    local api = {}
    local hooked, errors, cancel = false, 0, nil
    local seen = {}
    function api.hooked() return hooked end
    function api.errors() return errors end

    k:Module({
        name = R.NAME,
        needs = { "client", "store", "bus" },
        settings = { {
            key = R.SETTING, scope = "account", type = "bool", default = true,
            label = "Upgrade hint on loot rolls",
            help = "When the game offers you a roll on gear, say whether it is an upgrade. It never rolls for you.",
            group = "Gear",
        } },
        provides = { Hooked = api.hooked, Errors = api.errors },
        start = function(ctx)
            if type(ctx.client.onLootRoll) ~= "function" then return end
            local got = ctx.client.onLootRoll(function(_, link, show)
                if ctx.settings:get(R.SETTING) ~= true or type(show) ~= "function" then return end
                local ok, hint = pcall(R.Hint, ctx.client, packs or ns.Packs, link)
                if not ok then
                    errors = errors + 1
                    local text = tostring(hint)
                    if not seen[text] then
                        seen[text] = true
                        k.problems:add("gear", "roll hint", text)
                    end
                    return
                end
                if not hint then return end
                local colours = ns.GearTooltipModule.COLOUR
                local colour = colours[hint.tone] or colours.none
                show(hint.text, colour[1], colour[2], colour[3])
            end)
            if type(got) == "function" then
                cancel, hooked = got, true
            end
        end,
        stop = function()
            if cancel then cancel() end
            cancel, hooked = nil, false
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.gearRollHint = R.Declare(ns)
