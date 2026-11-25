-- Lite mode (G57): one row, perf.lite (account, off by default). When it
-- is on at load, the extra modules in Lite.OFF are switched off before they
-- are wired (Core/Module.lua k:BeforeWire), so they never listen, tick or
-- draw this session; what needs one of them goes off with it. It changes
-- no game setting and acts on nothing: it only leaves add-on features off.
-- A change takes effect at the next load (/reload).
--
--   <slash> lite        say whether it is on and what it leaves off
--   <slash> lite on     turn it on (after /reload)
--   <slash> lite off    turn it off (after /reload)
--
--   Lite.Lines(on, off, slash) -> lines   (pure)
--   Lite.Start(k, diag) -> { run = fn, off = fn }  off(): the names it switched off
--
-- F-08, ease off by place (lead section 693; legacy Flow Perf.lua:159-183,
-- LiteWhy): a second row, perf.litePlace (account, ON by default as in
-- Flow). Inside a dungeon, raid, battleground or arena, as the game says
-- (client.instance: IsInInstance's kind), the add-on eases off:
--   * a load inside one (a /reload there) leaves the Lite.OFF extras off,
--     as manual lite does;
--   * module "lite" gives Place(): the reason now, or nil; it is read again
--     on PLAYER_ENTERING_WORLD and ZONE_CHANGED_NEW_AREA, and Lite.EVENT is
--     sent on the bus when it changes, for a module that eases off live.
-- The player's own perf.lite is never changed by it: on stays on. Not from
-- Flow here: its raid-group and boss-fight triggers (no encounter read).
--   Lite.PlaceWhy(instance, on) -> reason | nil   (pure)
local _, ns = ...

local Lite = {}
ns.Lite = Lite

Lite.NAME = "lite"
Lite.WORD = "lite"
Lite.SETTING = "perf.lite"
Lite.REASON = "lite mode is on"
Lite.RELOAD = "Saved. Type /reload to apply it."
Lite.PLACE_SETTING = "perf.litePlace"
Lite.EVENT = "lite.place"
Lite.WHY = { party = "in a dungeon", raid = "in a raid", pvp = "in a battleground" }
Lite.KIND = { party = "party", raid = "raid", pvp = "pvp", arena = "pvp" }

function Lite.PlaceWhy(instance, on)
    if on ~= true or type(instance) ~= "table" or instance.inside ~= true then return nil end
    local kind = Lite.KIND[instance.kind]
    if not kind then return nil end
    return Lite.WHY[kind]
end
-- The extras: name plates, the press pulse, the info bar, the gear tooltip
-- lines and the quest speech. Nothing the arrow, quests or selling need.
Lite.OFF = { "plateCombo", "plateThreat", "plateQuests", "pulse", "infoBar", "gearTooltip", "npcSpeech" }

function Lite.Lines(on, off, slash)
    off = type(off) == "table" and off or {}
    local cmd = tostring(slash or ns.id.slash) .. " " .. Lite.WORD
    if on then
        local n = #off
        return {
            "Lite mode is on: " .. n .. (n == 1 and " extra feature is off" or " extra features are off")
                .. (n > 0 and (" (" .. table.concat(off, ", ") .. ")") or "") .. ".",
            "Type " .. cmd .. " off, then /reload, to turn them back on.",
        }
    end
    return {
        "Lite mode is off: every feature runs.",
        "Type " .. cmd .. " on, then /reload, to turn off the extras when the game feels slow.",
    }
end

function Lite.Start(k, diag)
    local switched = {}
    local api = {}
    function api.off()
        local out = {}
        for i = 1, #switched do out[i] = switched[i] end
        return out
    end

    k:Module({
        name = Lite.NAME,
        needs = { "settings" },
        settings = { {
            key = Lite.SETTING, scope = "account", type = "bool", default = false,
            label = "Lite mode: leave the extras off",
            help = "When the game feels slow, leave the extra features off (name plate marks, the press pulse, "
                .. "the info bar, gear tooltip lines, quest speech). Takes effect after /reload. Changes no game setting.",
            group = "advanced", synonyms = { "lite", "perf", "performance", "slow", "fps", "lag" },
        }, {
            key = Lite.PLACE_SETTING, scope = "account", type = "bool", default = true,
            label = "Ease off in raids, dungeons and battlegrounds",
            help = "Inside a dungeon, raid or battleground the add-on does less, so it never adds to lag there:"
                .. " a reload inside one leaves the extra features off. Your own lite mode setting is kept as you set it.",
            group = "party", synonyms = { "lite", "perf", "lag", "raid", "dungeon", "battleground", "instance" },
        } },
        provides = { Off = api.off, Place = function() return api.place() end },
        start = function()
            local function read()
                local was = api.now
                local okI, inst = pcall(k.client.instance)
                if not okI then inst = nil end
                api.now = Lite.PlaceWhy(inst, k.settings:get(Lite.PLACE_SETTING) == true)
                if api.now ~= was and type(k.bus) == "table" and type(k.bus.emit) == "function" then
                    pcall(k.bus.emit, k.bus, Lite.EVENT, api.now)
                end
            end
            if type(k.client.listen) == "function" then
                for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
                    pcall(k.client.listen, event, function() pcall(read) end)
                end
            end
            pcall(read)
        end,
    })
    function api.place() return api.now end

    k:BeforeWire(Lite.NAME, function()
        local why = Lite.REASON
        if k.settings:get(Lite.SETTING) ~= true then
            -- F-08: a load inside a dungeon, raid or battleground.
            local okI, inst = pcall(k.client.instance)
            if not okI then inst = nil end
            why = Lite.PlaceWhy(inst, k.settings:get(Lite.PLACE_SETTING) == true)
            if not why then return end
        end
        for i = 1, #Lite.OFF do
            if k:SwitchOff(Lite.OFF[i], why) then switched[#switched + 1] = Lite.OFF[i] end
        end
    end)

    local function say(text) k.client.print(k.id.title .. ": " .. text) end
    function api.run(rest)
        rest = (tostring(rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
        local slash = type(k.id) == "table" and k.id.slash or ns.id.slash
        if rest == "on" or rest == "off" then
            local ok, why = k.settings:set(Lite.SETTING, rest == "on")
            say(ok and Lite.RELOAD or ("couldn't save it (" .. tostring(why) .. ")."))
            return
        end
        if rest ~= "" then
            say("Type " .. slash .. " " .. Lite.WORD .. ", " .. slash .. " " .. Lite.WORD .. " on, or "
                .. slash .. " " .. Lite.WORD .. " off.")
            return
        end
        local lines = Lite.Lines(k.settings:get(Lite.SETTING) == true, switched, slash)
        for i = 1, #lines do say(lines[i]) end
    end
    if diag and type(diag.commands) == "table" then
        diag.commands[Lite.WORD] = api.run
        if type(diag.help) == "table" then
            diag.help[Lite.WORD] = "lite on / lite off: leave the extra features off when the game feels slow (after /reload)"
        end
    end
    return api
end

-- The addon's own.
ns.lite = Lite.Start(ns, ns.diag)
