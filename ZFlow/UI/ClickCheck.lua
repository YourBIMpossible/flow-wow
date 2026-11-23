local _, ns = ...
-- S23 click-casting check (P-KEYS slice B): one line on the settings page,
-- where the key rows and their lines show (UI/SettingsKeys.lua), when a
-- click-cast add-on or another binding would take a Z-Flow key over. A read
-- only: it binds nothing, clears nothing, and touches no other add-on.
-- Click casting itself (Z-Flow casting from unit frames) is an owner
-- decision (lead section 243) and is not built here.
--
--   CC.Read(client, slots) -> { addons, taken, unknown }
--     slots: { { label, action, override }, ... }: each key slot's label,
--            its binding action ("CLICK <button>:LeftButton") and the key
--            held for the session only (or nil)
--     addons: the click-cast add-ons loaded (CC.ADDONS order)
--     taken:  { { label, key, by }, ... }: a slot's key whose winning
--             binding (client.bindingOverride) is something else
--     unknown: true when a read failed or gave nothing; a key not known is
--             never counted as taken
--   CC.Line(read, title) -> the one line, or nil when there is nothing to say
--
-- First guess: the add-on names below are click-cast add-ons known from
-- other clients, not checked on this one; c.bindingOverride is not seen in
-- game either. Fake client only; not tested in game.
local CC = {}
ns.ClickCheck = CC

-- First guess: Clique first, then other click-cast and unit frame healing
-- add-ons that take mouse buttons and keys over unit frames.
CC.ADDONS = { "Clique", "Clicked", "HealBot", "VuhDo" }

local function add(list, seen, key)
    if type(key) == "string" and key ~= "" and not seen[key] then
        seen[key] = true
        list[#list + 1] = key
    end
end

function CC.Read(client, slots)
    local out = { addons = {}, taken = {}, unknown = false }
    if type(client) ~= "table" then
        out.unknown = true
        return out
    end
    if type(client.addonLoaded) == "function" then
        for _, name in ipairs(CC.ADDONS) do
            local ok, loaded = pcall(client.addonLoaded, name)
            if ok and loaded == true then out.addons[#out.addons + 1] = name end
        end
    end
    local checked = {}
    for _, slot in ipairs(type(slots) == "table" and slots or {}) do
        if type(slot) == "table" and type(slot.action) == "string" then
            local keys, seen = {}, {}
            add(keys, seen, slot.override)
            if type(client.bindingKeys) == "function" then
                local ok, got = pcall(client.bindingKeys, slot.action)
                if ok and type(got) == "table" then
                    for _, key in ipairs(got) do add(keys, seen, key) end
                else
                    out.unknown = true
                end
            else
                out.unknown = true
            end
            for _, key in ipairs(keys) do
                if not checked[key] then
                    checked[key] = true
                    local ok, by = false, nil
                    if type(client.bindingOverride) == "function" then
                        ok, by = pcall(client.bindingOverride, key, slot.action)
                    end
                    if not ok or type(by) ~= "string" then
                        out.unknown = true
                    elseif by ~= "" and by ~= slot.action then
                        out.taken[#out.taken + 1] = { label = tostring(slot.label), key = key, by = by }
                    end
                end
            end
        end
    end
    return out
end

local function named(addons)
    if #addons == 1 then return addons[1] .. " is" end
    return table.concat(addons, ", ") .. " are"
end

function CC.Line(read, title)
    if type(read) ~= "table" then return nil end
    local addons = type(read.addons) == "table" and read.addons or {}
    local taken = type(read.taken) == "table" and read.taken or {}
    local who = "this add-on"
    if type(title) == "string" and title ~= "" then who = title end
    if #taken > 0 then
        local first = taken[1]
        local line = "Click casting: your " .. tostring(first.label) .. " " .. tostring(first.key)
            .. " does " .. tostring(first.by) .. ", not " .. who .. "'s key"
        if #addons > 0 then line = line .. " (" .. named(addons) .. " loaded)" end
        if #taken > 1 then line = line .. "; " .. (#taken - 1) .. " more taken" end
        return line .. "."
    end
    if #addons > 0 then
        return "Click casting: " .. named(addons) .. " loaded; it may take your keys over unit frames. Check its bindings."
    end
    return nil
end
