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
local _, ns = ...

local Lite = {}
ns.Lite = Lite

Lite.NAME = "lite"
Lite.WORD = "lite"
Lite.SETTING = "perf.lite"
Lite.REASON = "lite mode is on"
Lite.RELOAD = "Saved. Type /reload to apply it."
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
        } },
        provides = { Off = api.off },
    })

    k:BeforeWire(Lite.NAME, function()
        if k.settings:get(Lite.SETTING) ~= true then return end
        for i = 1, #Lite.OFF do
            if k:SwitchOff(Lite.OFF[i], Lite.REASON) then switched[#switched + 1] = Lite.OFF[i] end
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
