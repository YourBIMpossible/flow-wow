local _, ns = ...

-- N64 (lead section 243): a reminder when the enchant on your weapon (a
-- rogue's poison, a shaman's imbue, an oil or a sharpening stone) runs low
-- or is gone. It says a line in your chat, out of a fight only; it casts,
-- uses and binds nothing.
--
-- It reminds only for a hand that had an enchant on it while the add-on
-- was running: a shield, an empty hand or a weapon you never enchant is
-- never asked about. What it saw is kept in memory only; after a reload a
-- hand is watched again from the first read that finds an enchant on it.
--
-- The read is c.weaponEnchant() as Plexy's P-READS note (item 5) names it:
--   { main = { has, left, charges }, off = ... } or nil
-- has true or false, left the seconds left (nil: not known). It is not in
-- Core/Client.lua yet (P-READS, Plexy's code); until it is, this client
-- build gives no answer and the reminder says nothing, and the diag word
-- says so. Built against the fake only; not tested in game. The row stays
-- PARTLY.
--
--   E.Read(client) -> { [hand] = { has, left, charges } } | nil
--       every answer checked: has a boolean or left out, left a number of
--       seconds or nil. nil: no read, the read raised or gave no table.
--   E.Judge(row, seen) -> "gone" | "low" | "on" | nil
--       nil: not known, or a hand never seen with an enchant.
--   E.Lines(view) -> lines              what the word says, plain words
--   E.Declare(k[, diag]) -> { view = fn }
local E = {}
ns.Enchant = E

E.NAME = "weaponEnchant"
E.SETTING = "buffs.weaponEnchant"
E.WORD = "enchant"
E.EVERY = 5
-- First guess: five minutes left is "running out".
E.WARN = 300
E.HANDS = { "main", "off" }
E.HAND_WORDS = { main = "main-hand", off = "off-hand" }
E.LABEL = "Remind me when my weapon enchant runs out"
E.HELP = "show the enchant on your weapons"

local function number(v)
    return type(v) == "number" and v == v
end

function E.Read(client)
    if type(client) ~= "table" or type(client.weaponEnchant) ~= "function" then return nil end
    local ok, got = pcall(client.weaponEnchant)
    if not ok or type(got) ~= "table" then return nil end
    local out = {}
    for _, hand in ipairs(E.HANDS) do
        local row = got[hand]
        if type(row) == "table" then
            local clean = {}
            if type(row.has) == "boolean" then clean.has = row.has end
            if number(row.left) and row.left >= 0 then clean.left = row.left end
            if number(row.charges) then clean.charges = row.charges end
            out[hand] = clean
        end
    end
    return out
end

function E.Judge(row, seen)
    if type(row) ~= "table" then return nil end
    if row.has == true then
        if number(row.left) and row.left <= E.WARN then return "low" end
        return "on"
    end
    if row.has == false and seen == true then return "gone" end
    return nil
end

local function minutes(secs)
    local m = math.ceil(secs / 60)
    if m < 1 then m = 1 end
    if m == 1 then return "1 minute" end
    return m .. " minutes"
end

-- The line said for a hand that went low or bare.
local function saying(hand, state, row)
    local what = "your " .. E.HAND_WORDS[hand] .. " weapon enchant"
    if state == "gone" then return what .. " is gone. Put it on again." end
    if number(row.left) then return what .. " runs out in " .. minutes(row.left) .. "." end
    return what .. " is running out."
end

function E.Lines(view)
    if type(view) ~= "table" or view.on ~= true then
        return { "the weapon enchant reminder is off. Switch on \"" .. E.LABEL .. "\" in the settings to use it." }
    end
    if type(view.read) ~= "table" then
        return { "this client build gives no weapon enchant read yet, so the reminder says nothing." }
    end
    local out = {}
    for _, hand in ipairs(E.HANDS) do
        local row = view.read[hand]
        local word = E.HAND_WORDS[hand]
        if type(row) ~= "table" or row.has == nil then
            out[#out + 1] = word .. ": not known."
        elseif row.has == false then
            local watched = view.seen and view.seen[hand] == true
            out[#out + 1] = word .. ": no enchant" .. (watched and " (it had one: you are reminded)." or ".")
        elseif number(row.left) then
            out[#out + 1] = word .. ": enchant on, " .. minutes(row.left) .. " left."
        else
            out[#out + 1] = word .. ": enchant on, the time left not known."
        end
    end
    return out
end

function E.Declare(k, diag)
    local api = {}
    local client, live
    local seen, said = {}, {}
    local noReadSaid = false

    local function say(text)
        local out = client or k.client
        if type(out) == "table" and type(out.print) == "function" then pcall(out.print, k.id.title .. ": " .. text) end
    end

    local function outOfFight()
        if type(client.inCombat) ~= "function" then return false end
        local ok, v = pcall(client.inCombat)
        return ok and v == false
    end

    local function look(ctx)
        if not client then return end
        if ctx.settings:get(E.SETTING) ~= true then
            said = {}
            return
        end
        local read = E.Read(client)
        if read == nil then
            if type(client.weaponEnchant) ~= "function" and not noReadSaid then
                noReadSaid = true
                k.problems:add(E.NAME, "read", "this client build gives no weapon enchant read; the reminder says nothing")
            end
            return
        end
        for _, hand in ipairs(E.HANDS) do
            local row = read[hand]
            if type(row) == "table" and row.has == true then seen[hand] = true end
            local state = E.Judge(row, seen[hand])
            if state == "on" then
                said[hand] = nil
            elseif (state == "low" or state == "gone") and said[hand] ~= state and outOfFight() then
                said[hand] = state
                say(saying(hand, state, row))
            end
        end
    end

    function api.view()
        local seenCopy = {}
        for hand, v in pairs(seen) do seenCopy[hand] = v end
        local on = live ~= nil and live.settings:get(E.SETTING) == true
        return { on = on, read = E.Read(client), seen = seenCopy }
    end

    k:Module({
        name = E.NAME,
        needs = { "client", "settings", "bus" },
        settings = { {
            key = E.SETTING, scope = "char", type = "bool", default = false,
            label = E.LABEL,
            help = "Says a line in your chat, out of fights, when the poison, imbue, oil or stone on a weapon "
                .. "runs low or is gone. Only a hand that had one is watched. It puts nothing on for you.",
            group = "buffs",
            -- "weapon" and "reminder" are words of the gear and spells topics.
            synonyms = { "enchant", "poison", "imbue", "oil", "sharpening stone", "windfury",
                         "flametongue", "rockbiter", "frostbrand" },
        } },
        ticks = { { every = E.EVERY, run = function(ctx) look(ctx) end } },
        -- Plexy's note: the read is fresh on UNIT_INVENTORY_CHANGED for
        -- you; a line held back by a fight is said when it ends.
        events = {
            UNIT_INVENTORY_CHANGED = function(ctx, unit)
                if unit == nil or unit == "player" then look(ctx) end
            end,
            PLAYER_REGEN_ENABLED = function(ctx) look(ctx) end,
        },
        start = function(ctx)
            client, live = ctx.client, ctx
            seen, said, noReadSaid = {}, {}, false
        end,
        stop = function()
            client, live = nil, nil
            seen, said, noReadSaid = {}, {}, false
        end,
    })

    if diag and type(diag.commands) == "table" then
        diag.commands[E.WORD] = function()
            local lines = E.Lines(api.view())
            for i = 1, #lines do say(lines[i]) end
        end
        if type(diag.help) == "table" then diag.help[E.WORD] = E.HELP end
    end

    return api
end

-- The addon's own: declared when this file loads, off until the setting is
-- switched on.
ns.weaponEnchant = E.Declare(ns, ns.diag)
