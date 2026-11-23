local _, ns = ...
-- S12 care key (P-KEYS slice A): a second secure button, beside the
-- rotation key. The rotation key carries damage; this one carries the heal,
-- cure or revive. Off by default ("Heals and cures on your care key"); it
-- works with the rotation switched on, from the driver's view
-- (D.EVENT), as the rotation button does (Rotation/KeyFrame.lua).
--
-- The parts (spell type on a unit, never a macro, section 246):
--   key          a friend's heal, cure or revive (CHOOSE-2, R.FriendHeal in
--                Rotation/Choose.lua: your friendly target or a party
--                member), else your quick heal on you
--   Ctrl         your heal over time, on you
--   Shift        another heal (not the quick one), on you
--   Alt          your healthstone or healing potion (N8), the item type
--   Ctrl+Shift   your first cure, on you ("more"). No bandage: the button
--                holds an item on Alt only, and no read says how hurt you
--                are (R.FROM_AMOUNT)
-- Unknown spells are left out. Attributes are set out of a fight only (the
-- lock asked before every set, nil is not "no fight"); a change in a fight
-- waits for its end. The add-on binds no key: the player binds the button
-- on the settings page (UI/SettingsKeys.lua, the "Care key" row). Nothing
-- here presses anything.
--
-- The unit under your mouse is the N63 button's (Rotation/Mouseover.lua),
-- not this one's. Not tested in game; every client read it leans on
-- (c.unitCare) is a first guess.
local CK = {}
ns.CareKeys = CK

local D = ns.RotationDriver
local R = ns.Rotation
local K = ns.KeyFrame

CK.NAME = "careKey"
CK.SETTING = "rotation.careKey"
CK.WORD = "care"
CK.BUTTON = "CareKey"
CK.LABEL = "Heals and cures on your care key"
CK.HELP = "show what your care key holds; care apply tries again what could not be set"
CK.SLOTS = { "ctrl", "shift", "alt", "more" }

local SUBJECT = "your care key"

local function known(s, name)
    return type(name) == "string" and R.Knows(s, name)
end

local function castMs(s, name)
    local r = type(s.spells) == "table" and s.spells[name] or nil
    return type(r) == "table" and type(r.castMs) == "number" and r.castMs or 0
end

-- CK.Plan(pack, s, friend, altItem) -> plan or nil
--   pack the class's pack; s a snapshot; friend what R.FriendHeal gave (or
--   nil); altItem an item id (or nil). nil without a pack or a snapshot.
--   A plan: { key, ctrl, shift, more = { spell, unit } , alt = { item } },
--   each part left out when nothing known fills it.
function CK.Plan(pack, s, friend, altItem)
    if type(pack) ~= "table" or type(s) ~= "table" then return nil end
    local plan = {}
    local heals = type(pack.heals) == "table" and pack.heals or {}
    local own = type(heals.self) == "table" and heals.self or {}
    local hots = type(heals.hots) == "table" and heals.hots or {}
    local isHot = {}
    for _, name in ipairs(hots) do isHot[name] = true end
    local quick = R.DirectHeal(own, hots, function(name) return known(s, name) end,
        function(name) return castMs(s, name) end)

    if type(friend) == "table" and type(friend.spell) == "string" and type(friend.unit) == "string" then
        plan.key = { spell = friend.spell, unit = friend.unit }
    elseif quick then
        plan.key = { spell = quick, unit = "player" }
    end
    local onKey = plan.key and plan.key.spell
    for _, name in ipairs(hots) do
        if name ~= onKey and known(s, name) then
            plan.ctrl = { spell = name, unit = "player" }
            break
        end
    end
    for _, name in ipairs(own) do
        if not isHot[name] and name ~= quick and known(s, name) then
            plan.shift = { spell = name, unit = "player" }
            break
        end
    end
    if type(altItem) == "number" then plan.alt = { item = altItem } end
    for _, rule in ipairs(type(pack.dispels) == "table" and pack.dispels or {}) do
        if type(rule) == "table" and known(s, rule.spell) then
            plan.more = { spell = rule.spell, unit = "player" }
            break
        end
    end
    return plan
end

-- CK.Rows(plan) -> { { attr, value }, ... }: every part, a nil value
-- clearing it. 16 rows: type, spell, unit for the key and each modifier,
-- then the item on Alt. Never a macro.
function CK.Rows(plan)
    plan = type(plan) == "table" and plan or {}
    local rows = {}
    local function part(prefix, suffix, slot)
        local kind, spell, unit
        if type(slot) == "table" then
            if type(slot.item) == "number" then
                kind = "item"
            elseif type(slot.spell) == "string" then
                kind, spell = "spell", slot.spell
                if type(slot.unit) == "string" then unit = slot.unit end
            end
        end
        rows[#rows + 1] = { attr = prefix .. "type" .. suffix, value = kind }
        rows[#rows + 1] = { attr = prefix .. "spell" .. suffix, value = spell }
        rows[#rows + 1] = { attr = prefix .. "unit" .. suffix, value = unit }
    end
    part("", "", plan.key)
    for _, slot in ipairs(CK.SLOTS) do part("*", "-" .. slot, plan[slot]) end
    local alt = plan.alt
    local itemText
    if type(alt) == "table" and type(alt.item) == "number" then itemText = "item:" .. tostring(alt.item) end
    rows[#rows + 1] = { attr = "*item-alt", value = itemText }
    return rows
end

-- A plan as one text, to tell a changed plan from the same one again.
function CK.Signature(plan)
    if plan == nil then return "clear" end
    local out = {}
    for _, row in ipairs(CK.Rows(plan)) do out[#out + 1] = row.attr .. "=" .. tostring(row.value) end
    return table.concat(out, "|")
end

-- CK.TargetUnit(client) -> "party1".."party4" | "raid1".."raid40" | nil
--   The stable group token of the unit you target: the party row whose
--   guid is your target's (client.guid("target")). PK-1: a secure unit
--   attribute of "target" re-resolves at the press, after the target may
--   have changed in a fight; a group token does not. nil when the target
--   is not in your group or either read raised or gave nothing. Read only.
local function partyRows(client)
    if type(client) ~= "table" or type(client.party) ~= "function" then return nil end
    local ok, rows = pcall(client.party)
    if not ok or type(rows) ~= "table" then return nil end
    return rows
end

local function targetIn(client, rows)
    if type(rows) ~= "table" or type(client.guid) ~= "function" then return nil end
    local ok, id = pcall(client.guid, "target")
    if not ok or type(id) ~= "string" or id == "" then return nil end
    for _, m in ipairs(rows) do
        if type(m) == "table" and m.guid == id and type(m.unit) == "string" and m.unit ~= "target" then
            return m.unit
        end
    end
    return nil
end

function CK.TargetUnit(client)
    if type(client) ~= "table" then return nil end
    return targetIn(client, partyRows(client))
end

-- CK.Friends(client) -> { { unit, dead, hurt, debuffTypes }, ... } or nil
--   Each party member when the client says it is there, friendly and not
--   you; the one you target first (CK.TargetUnit), by its group token. A
--   friendly target not in your group is left out: never "target" (PK-1).
--   A unit whose read raised or gave nothing is left out; nil when no unit
--   was read at all. Read only.
function CK.Friends(client)
    if type(client) ~= "table" or type(client.unitCare) ~= "function" then return nil end
    local list, read = {}, false
    local function add(unit)
        local ok, row = pcall(client.unitCare, unit)
        if not ok or type(row) ~= "table" then return end
        read = true
        if row.exists ~= true or row.friend ~= true or row.isSelf == true then return end
        local entry = { unit = unit, dead = row.dead, hurt = row.hurt }
        if type(client.unitDebuffTypes) == "function" then
            local okTypes, types = pcall(client.unitDebuffTypes, unit)
            if okTypes and type(types) == "table" then entry.debuffTypes = types end
        end
        list[#list + 1] = entry
    end
    local rows = partyRows(client)
    if rows then
        local first = targetIn(client, rows)
        if first then add(first) end
        for _, m in ipairs(rows) do
            if type(m) == "table" and type(m.unit) == "string" and m.unit ~= "target" and m.unit ~= first then
                add(m.unit)
            end
        end
    end
    if not read then return nil end
    return list
end

-- CK.FromView(client, view) -> the care plan for a driver view, or nil:
-- the same plan the care key is given (S15 click slots, P-KEYS slice C,
-- show it on a slot of their own). Reads only.
function CK.FromView(client, view)
    if type(client) ~= "table" or type(view) ~= "table" or view.pack ~= true then return nil end
    if type(client.class) ~= "function" or type(ns.Packs) ~= "table" then return nil end
    local okClass, class = pcall(client.class)
    if not okClass or type(class) ~= "string" then return nil end
    local pack = ns.Packs[class]
    local snap = view.snapshot
    if type(pack) ~= "table" or type(snap) ~= "table" then return nil end
    local s = setmetatable({ friends = CK.Friends(client) }, { __index = snap })
    local friend = R.FriendHeal(s, pack)
    local altItem = nil
    local hi = snap.healItem
    if type(hi) == "table" then
        altItem = hi.alt
        if altItem == nil then altItem = hi.stone end
        if altItem == nil then altItem = hi.potion end
    end
    if type(altItem) ~= "number" then altItem = nil end
    return CK.Plan(pack, s, friend, altItem)
end

-- What the button holds, as text.
local function holds(held)
    held = type(held) == "table" and held or {}
    local out = {}
    if held.spell then out[#out + 1] = "key: " .. tostring(held.spell) .. " (" .. tostring(held.unit) .. ")" end
    for _, slot in ipairs(CK.SLOTS) do
        local v = held["*spell-" .. slot] or held["*item-" .. slot]
        if v then out[#out + 1] = slot .. ": " .. tostring(v) end
    end
    return table.concat(out, "; ")
end

function CK.FailLine(st)
    if type(st) ~= "table" or st.state ~= "failed" then return nil end
    if type(st.failed) ~= "table" or #st.failed == 0 then
        return SUBJECT .. " could not be set: " .. tostring(st.text or st.reason) .. "."
    end
    return string.format("%s could not be set (%d of %d parts). It keeps what it had;"
        .. " it is tried again after your next fight.", SUBJECT, #st.failed, st.parts or 0)
end

function CK.Lines(st)
    if type(st) ~= "table" then
        return { SUBJECT .. " is off. Switch on \"" .. CK.LABEL .. "\" and the rotation in the settings to use it." }
    end
    local lines = {}
    if st.state == "noFrame" then
        lines[1] = SUBJECT .. ": this client build makes no secure button yet, so nothing is set."
    elseif st.state == "idle" then
        lines[1] = SUBJECT .. ": nothing to set yet."
    elseif st.state == "waiting" and st.reason == "lockdown" then
        lines[1] = SUBJECT .. " is waiting for the fight to end. Nothing changes in a fight."
    elseif st.state == "waiting" then
        lines[1] = SUBJECT .. " is waiting: the client did not say whether you are in a fight."
    elseif st.state == "cleared" then
        lines[1] = SUBJECT .. " holds nothing."
    elseif st.state == "set" then
        local what = holds(st.held)
        lines[1] = SUBJECT .. " is set" .. (what ~= "" and (". " .. what .. ".") or ", and you know no heal or cure for it.")
        lines[2] = "It has no key: bind one on the settings page; nothing is bound for you."
    elseif st.state == "failed" then
        lines[1] = CK.FailLine(st)
    else
        lines[1] = SUBJECT .. ": state not known."
    end
    return lines
end

-- The module on kernel k. diag (optional) is what Diag.Start returned.
function CK.Declare(k, diag)
    local api = {}
    local kf, client
    local noFrame, failSaid = false, false

    -- True once the secure button is made, so the settings page binds a key
    -- only to a frame that is there (UI/SettingsKeys.lua).
    function api.made() return kf ~= nil end

    function api.status()
        if kf then return kf:status() end
        if noFrame then return { state = "noFrame", failed = {}, parts = 0 } end
        return nil
    end

    local function say(text)
        if client then client.print(ns.id.title .. ": " .. text) end
    end

    -- A failure is said once; again only after an apply went through.
    local function after(st)
        if st.state == "failed" then
            if not failSaid then
                failSaid = true
                local line = CK.FailLine(st)
                say(line)
                k.problems:add(CK.NAME, "apply", line)
            end
        elseif st.state == "set" or st.state == "cleared" then
            failSaid = false
        end
    end

    local function ensure()
        if kf then return kf end
        if noFrame or not client or type(client.secureButton) ~= "function" then
            noFrame = true
            return nil
        end
        local ok, button = pcall(client.secureButton, { name = ns.id.framePrefix .. CK.BUTTON })
        if not ok or type(button) ~= "table" or type(button.set) ~= "function" then
            noFrame = true
            k.problems:add(CK.NAME, "frame", "the client made no secure button; " .. SUBJECT .. " is not set")
            return nil
        end
        kf = K.New({ button = button, lockdown = client.combatLockdown, rows = CK.Rows, signature = CK.Signature })
        return kf
    end

    local function switchedOn()
        return k.settings:get(CK.SETTING) == true and k.settings:get(D.SETTING) == true
    end

    local function onView(view)
        if not (switchedOn() and type(view) == "table" and view.pack == true) then
            if kf then after(kf:want(nil)) end
            return
        end
        -- In a fight, or the lock not read: what is wanted stays and waits.
        local okLock, lock = pcall(client.combatLockdown)
        if not okLock or lock ~= false then
            if kf then after(kf:try()) end
            return
        end
        local okClass, class = pcall(client.class)
        local pack = okClass and type(class) == "string" and type(ns.Packs) == "table" and ns.Packs[class] or nil
        local snap = view.snapshot
        if type(pack) ~= "table" or type(snap) ~= "table" then return end
        local s = setmetatable({ friends = CK.Friends(client) }, { __index = snap })
        local friend = R.FriendHeal(s, pack)
        local hi = snap.healItem
        local altItem = type(hi) == "table" and (hi.alt or hi.stone or hi.potion) or nil
        if type(altItem) ~= "number" then altItem = nil end
        local plan = CK.Plan(pack, s, friend, altItem)
        if plan == nil or next(plan) == nil then
            if kf then after(kf:want(nil)) end
            return
        end
        if not ensure() then return end
        after(kf:want(plan))
    end

    local function run(rest)
        if kf and tostring(rest):find("apply", 1, true) then after(kf:try(true)) end
        local st = api.status()
        local on = k.settings:get(CK.SETTING) == true
        if not on and (st == nil or st.state == "cleared") then st = nil end
        local lines = CK.Lines(st or (on and { state = "idle" }) or nil)
        for i = 1, #lines do say(lines[i]) end
    end

    k:Module({
        name = CK.NAME,
        needs = { "client", "store", "bus", D.NAME },
        settings = { {
            key = CK.SETTING, scope = "char", type = "bool", default = false,
            label = CK.LABEL,
            help = "With the rotation on, puts a heal, cure or revive for a hurt or dead friend (else your own quick heal) on a second hidden button, with your heal over time, another heal, your healthstone and a cure on Ctrl, Shift, Alt and Ctrl+Shift. Outside fights only. It binds no key and presses nothing for you.",
            group = "combat", synonyms = { "care", "heal", "cure", "cleanse", "resurrect", "shield", "second key" },
        } },
        start = function(ctx)
            client = ctx.client
            ctx.bus:on(CK.NAME, D.EVENT, onView)
            client.listen("PLAYER_REGEN_ENABLED", function()
                if kf then after(kf:try(true)) end
            end)
        end,
    })

    if diag and type(diag.commands) == "table" then
        diag.commands[CK.WORD] = run
        if type(diag.help) == "table" then diag.help[CK.WORD] = CK.HELP end
    end

    return api
end

-- The addon's own: declared when this file loads, off until the setting is
-- switched on.
ns.careKey = CK.Declare(ns, ns.diag)
