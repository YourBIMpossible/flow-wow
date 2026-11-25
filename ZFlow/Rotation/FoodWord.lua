local _, ns = ...

-- FoodWord (parity row D-13; lead section 668): `<slash> food` lists the
-- Well Fed foods you carry, best first, what each gives and its score for
-- your role, which one is suggested, and when. As Flow's /flow rot why food
-- list (Modules/Rotation/BuffItems.lua FoodWhy / FoodWhyText).
--
-- LOOK ONLY. It reads your bags, their tooltips and your buffs, and prints.
-- Nothing is eaten, and the rotation key is not touched: the suggestion
-- itself is the food step's (Rotation/Choose.lua steps.food), unchanged.
--
-- The foods and their scores are the driver's own (RotationDriver.Foods):
-- the same tooltip read, stat weights and role as the suggestion.
-- Not tested in game.

local FW = {}
ns.FoodWord = FW

FW.NAME = "foodWord"
FW.WORD = "food"
FW.HELP = "list the Well Fed foods you carry, which one is suggested, and when"
FW.UNREAD = "your bags could not be read, so the foods are not known."
FW.WELL_FED = ns.BuffFood.WELL_FED
FW.OFF = "Well Fed food is switched off, so none is suggested."

function FW.Declare(k, diag)
    local api = {}

    local function ask(name, ...)
        local c = k.client
        if type(c) ~= "table" or type(c[name]) ~= "function" then return nil end
        local ok, v = pcall(c[name], ...)
        if ok then return v end
        return nil
    end

    -- The lines to print, the first one without the add-on's title.
    function api.Lines()
        local D = ns.RotationDriver
        if type(D) ~= "table" or type(D.Foods) ~= "function" then return { FW.UNREAD } end
        local class = ask("class")
        local packs = ns.Packs
        local pack
        if type(class) == "string" and type(packs) == "table" then pack = packs[class] end
        local role
        if type(k.settings) == "table" and type(k.settings.get) == "function" and type(D.ROLE) == "string" then
            local ok, v = pcall(k.settings.get, k.settings, D.ROLE)
            if ok then role = v end
        end
        local ok, foods, as, pole = pcall(D.Foods, k.client, pack, role)
        if not ok or type(foods) ~= "table" then return { FW.UNREAD } end
        local buffs = ask("playerBuffs")
        local fed = type(buffs) == "table" and buffs[FW.WELL_FED] ~= nil
        local lines = ns.BuffFood.WhyText(foods, as, fed, pole)
        -- Zen-3's note: the food setting off is said (Driver's D.FOOD).
        local off = false
        if type(k.settings) == "table" and type(k.settings.get) == "function" and type(D.FOOD) == "string" then
            local okF, v = pcall(k.settings.get, k.settings, D.FOOD)
            off = okF and v == false
        end
        if off then lines[#lines + 1] = FW.OFF end
        return lines
    end

    if type(diag) == "table" and type(diag.commands) == "table" then
        diag.commands[FW.WORD] = function()
            local c = k.client
            if type(c) ~= "table" or type(c.print) ~= "function" then return end
            local id = k.id
            if type(id) ~= "table" then id = ns.id end
            local title
            if type(id) == "table" and type(id.title) == "string" and id.title ~= "" then title = id.title end
            for i, line in ipairs(api.Lines()) do
                if i == 1 and title then line = title .. ": " .. line end
                c.print(line)
            end
        end
        if type(diag.help) == "table" then diag.help[FW.WORD] = FW.HELP end
    end

    k:Module({
        name = FW.NAME,
        needs = { "client", "settings" },
        provides = { Lines = api.Lines },
    })
    return api
end

-- The addon's own: declared when this file loads.
ns.foodWord = FW.Declare(ns, ns.diag)
