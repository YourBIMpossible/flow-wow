local _, ns = ...
-- S15 click slots (P-KEYS slice C): a row of secure buttons on the screen,
-- each holding one suggestion: the rotation key's, the care key's, and the
-- rotation plan's Ctrl, Shift, Alt and Ctrl+Shift parts. Each slot casts
-- what it holds only when the player clicks it; the add-on never clicks,
-- binds or casts. Slots are set only while InCombatLockdown answers a plain
-- false: in a fight they keep what they had (frozen) and are set again
-- when it ends. Off by default (char setting S.SETTING); needs the rotation
-- on. No macro type and no macro text, ever (section 246).
--
-- S29: the row has a grip (UI/MoveHandle.lua) that moves it out of a fight;
-- its place is kept in the account layout (S.LAYOUT), nothing else.
--
-- Not tested in game: the buttons, the click and the grip.
local S = {}
ns.ClickSlots = S

local D = ns.RotationDriver
local K = ns.KeyFrame
local C = ns.cast

S.NAME = "clickSlots"
S.SETTING = "rotation.clickSlots"
S.LAYOUT = "clickSlots.layout"
S.PATH = "layout.clickSlots"
S.WORD = "slots"
S.FRAME = "ClickSlots"
S.LABEL = "Click slots for your suggestions"
S.HELP = "show what your click slots hold; slots apply tries again what could not be set"
S.SLOTS = { "key", "care", "ctrl", "shift", "alt", "more" }
S.SIZE = 32
S.GAP = 4
S.DEFAULT_POINT = { "CENTER", "CENTER", 0, -220 } -- authored: below the rotation icon
S.PARTS = { "type", "spell", "unit", "item" }

local SUBJECT = "your click slots"
local PART = {}
for _, p in ipairs(S.PARTS) do PART[p] = true end

function S.Width()
    return #S.SLOTS * S.SIZE + (#S.SLOTS - 1) * S.GAP
end

-- One slot from a kind, a spell, a unit and an item text; nil when none.
local function entry(kind, spell, unit, item)
    if kind == "spell" and type(spell) == "string" and spell ~= "" then
        local out = { spell = spell }
        if type(unit) == "string" then out.unit = unit end
        return out
    end
    if kind == "item" and type(item) == "string" and item ~= "" then return { item = item } end
    return nil
end

-- S.Plan(rows, care) -> { key, care, ctrl, shift, alt, more }: each
-- { spell, unit } or { item = "item:ID" }, an empty slot left out. rows are
-- the rotation button's attribute rows (Rotation/Cast.lua C.Attributes);
-- care is the care key's plan (Rotation/CareKeys.lua CK.Plan), whose key
-- fills the care slot.
function S.Plan(rows, care)
    local m = {}
    if type(rows) == "table" then
        for _, r in ipairs(rows) do
            if type(r) == "table" and r.attr ~= nil then m[r.attr] = r.value end
        end
    end
    local plan = {}
    plan.key = entry(m.type, m.spell, m.unit, m.item)
    for _, slot in ipairs(C.MODIFIERS) do
        local suffix = "-" .. slot
        plan[slot] = entry(m["*type" .. suffix], m["*spell" .. suffix], m["*unit" .. suffix], m["*item" .. suffix])
    end
    if type(care) == "table" and type(care.key) == "table" then
        local ck = care.key
        if type(ck.item) == "number" then
            plan.care = { item = "item:" .. tostring(ck.item) }
        else
            plan.care = entry("spell", ck.spell, ck.unit, nil)
        end
    end
    return plan
end

-- S.Rows(plan) -> { { attr = "i:part", value } }: for each slot i its
-- type, spell, unit, item and shown (true, or nil: hidden), then "0:shown"
-- (the row itself) last.
function S.Rows(plan)
    plan = type(plan) == "table" and plan or {}
    local rows = {}
    for i, slot in ipairs(S.SLOTS) do
        local e = plan[slot]
        local kind, spell, unit, item, shown
        if type(e) == "table" then
            if type(e.item) == "string" then
                kind, item, shown = "item", e.item, true
            elseif type(e.spell) == "string" then
                kind, spell, shown = "spell", e.spell, true
                if type(e.unit) == "string" then unit = e.unit end
            end
        end
        rows[#rows + 1] = { attr = i .. ":type", value = kind }
        rows[#rows + 1] = { attr = i .. ":spell", value = spell }
        rows[#rows + 1] = { attr = i .. ":unit", value = unit }
        rows[#rows + 1] = { attr = i .. ":item", value = item }
        rows[#rows + 1] = { attr = i .. ":shown", value = shown }
    end
    rows[#rows + 1] = { attr = "0:shown", value = true }
    return rows
end

function S.Signature(plan)
    if plan == nil then return "clear" end
    local out = {}
    for _, row in ipairs(S.Rows(plan)) do out[#out + 1] = row.attr .. "=" .. tostring(row.value) end
    return table.concat(out, "|")
end

-- The key frame (Rotation/KeyFrame.lua) sets one attribute at a time; the
-- row has slots. "i:part" goes to slot i; "i:shown" shows or hides it.
local function parse(attr)
    if type(attr) ~= "string" then return nil end
    local i, part = attr:match("^(%d+):(%a+)$")
    if not i then return nil end
    return tonumber(i), part
end

function S.Button(row)
    local b = {}
    function b.set(attr, value)
        local i, part = parse(attr)
        if i == nil then return false, "refused" end
        if part == "shown" then return row.show(i, value == true) end
        if i == 0 or not PART[part] then return false, "refused" end
        return row.set(i, part, value)
    end
    function b.get(attr)
        local i, part = parse(attr)
        if i == nil then return nil end
        if part == "shown" then
            if row.isShown(i) == true then return true end
            return nil
        end
        if i == 0 or not PART[part] then return nil end
        return row.get(i, part)
    end
    return b
end

local function holds(held)
    held = type(held) == "table" and held or {}
    local out = {}
    for i, slot in ipairs(S.SLOTS) do
        local v = held[i .. ":spell"]
        if v == nil then v = held[i .. ":item"] end
        if v ~= nil then out[#out + 1] = slot .. ": " .. tostring(v) end
    end
    return table.concat(out, "; ")
end

function S.FailLine(st)
    if type(st) ~= "table" or st.state ~= "failed" then return nil end
    if type(st.failed) ~= "table" or #st.failed == 0 then
        return SUBJECT .. " could not be set: " .. tostring(st.text or st.reason) .. "."
    end
    return string.format("%s could not be set (%d of %d parts). They keep what they had;"
        .. " they are tried again after your next fight.", SUBJECT, #st.failed, st.parts or 0)
end

function S.Lines(st)
    if type(st) ~= "table" then
        return { SUBJECT .. " are off. Switch on \"" .. S.LABEL .. "\" and the rotation in the settings to use them." }
    end
    local lines = {}
    if st.state == "noFrame" then
        lines[1] = SUBJECT .. ": this client build makes no secure buttons, so nothing is set."
    elseif st.state == "idle" then
        lines[1] = SUBJECT .. ": nothing to set yet."
    elseif st.state == "waiting" and st.reason == "lockdown" then
        lines[1] = SUBJECT .. " are waiting for the fight to end. Nothing changes in a fight."
    elseif st.state == "waiting" then
        lines[1] = SUBJECT .. " are waiting: the client did not say whether you are in a fight."
    elseif st.state == "cleared" then
        lines[1] = SUBJECT .. " hold nothing."
    elseif st.state == "set" then
        local what = holds(st.held)
        if what == "" then what = "nothing yet" end
        lines[1] = SUBJECT .. " are set: " .. what .. "."
        lines[2] = "Each casts only when you click it; nothing is bound or pressed for you. Drag the grip to move them, out of a fight."
    elseif st.state == "failed" then
        lines[1] = S.FailLine(st)
    else
        lines[1] = SUBJECT .. ": state not known."
    end
    return lines
end

-- A texture for a slot: the spell icon by its id, or the item icon.
local function texture(client, e)
    if type(e) ~= "table" then return nil end
    if type(e.spell) == "string" then
        if type(client.spellId) ~= "function" or type(client.spellTexture) ~= "function" then return nil end
        local okId, id = pcall(client.spellId, e.spell)
        if not okId or id == nil then return nil end
        local okTex, tex = pcall(client.spellTexture, id)
        if okTex then return tex end
        return nil
    end
    if type(e.item) == "string" and type(client.itemTexture) == "function" then
        local id = tonumber(e.item:match("^item:(%d+)$"))
        if id == nil then return nil end
        local okTex, tex = pcall(client.itemTexture, id)
        if okTex then return tex end
    end
    return nil
end

function S.Declare(k, diag)
    local api = {}
    local kf, client, row
    local noFrame, failSaid, saveSaid = false, false, false
    -- SC-2: the last try to make the row gave nothing (tried again on the
    -- next ensure once the lock is a plain false); the problem said once.
    local rowMissed, rowSaid = false, false
    local wantedPlan, iconSig = nil, nil

    function api.status()
        if kf then return kf:status() end
        if noFrame or rowMissed then return { state = "noFrame", failed = {}, parts = 0 } end
        return nil
    end

    local function say(text)
        if client then client.print(ns.id.title .. ": " .. text) end
    end

    local function icons()
        if not row or type(row.icon) ~= "function" then return end
        local sig = S.Signature(wantedPlan)
        if sig == iconSig then return end
        iconSig = sig
        if type(wantedPlan) ~= "table" then return end
        for i, slot in ipairs(S.SLOTS) do
            local tex = texture(client, wantedPlan[slot])
            if tex ~= nil then pcall(row.icon, i, tex) end
        end
    end

    local function after(st)
        if st.state == "failed" then
            if not failSaid then
                failSaid = true
                local line = S.FailLine(st)
                say(line)
                k.problems:add(S.NAME, "apply", line)
            end
        elseif st.state == "set" then
            failSaid = false
            icons()
        elseif st.state == "cleared" then
            failSaid = false
            iconSig = nil
        end
    end

    local function screen()
        if type(client.screen) ~= "function" then return nil end
        local ok, w, h = pcall(client.screen)
        if not ok then return nil end
        return w, h
    end

    local function place(point)
        if row then pcall(row.place, point) end
    end

    local function save(point)
        local ok, reason = k.settings:set(S.LAYOUT, { point = point })
        if not ok and not saveSaid then
            saveSaid = true
            k.problems:add(S.NAME, "save", "the place of " .. SUBJECT .. " was not kept (" .. tostring(reason) .. ")")
        end
    end

    local function ensure()
        if kf then return kf end
        if noFrame or not client or type(client.clickRow) ~= "function" then
            noFrame = true
            return nil
        end
        -- SC-2: a row is asked for only while the lock is a plain false; one
        -- that is not made (a lock race included) is asked for again on the
        -- next ensure, not given up for the session.
        local okLock, lock = pcall(client.combatLockdown)
        if not okLock or lock ~= false then return nil end
        local name = ns.id.framePrefix .. S.FRAME
        local ok, made = pcall(client.clickRow, { name = name, count = #S.SLOTS, size = S.SIZE, gap = S.GAP })
        if not ok or type(made) ~= "table" or type(made.set) ~= "function" then
            rowMissed = true
            if not rowSaid then
                rowSaid = true
                k.problems:add(S.NAME, "frame", "the client made no secure buttons; " .. SUBJECT .. " are not set")
            end
            return nil
        end
        rowMissed = false
        row = made
        local saved = k.settings:get(S.LAYOUT)
        local savedPoint = nil
        if type(saved) == "table" then savedPoint = saved.point end
        local w, h = screen()
        place(ns.Nav.ClampPoint(savedPoint, S.Width(), w, h, S.SIZE)
            or ns.Nav.ClampPoint(S.DEFAULT_POINT, S.Width(), w, h, S.SIZE)
            or S.DEFAULT_POINT)
        ns.MoveHandle.Attach(k, client, { target = name, width = S.Width(), height = S.SIZE,
            place = place, save = save })
        kf = K.New({ button = S.Button(row), lockdown = client.combatLockdown, rows = S.Rows, signature = S.Signature })
        return kf
    end

    local function switchedOn()
        return k.settings:get(S.SETTING) == true and k.settings:get(D.SETTING) == true
    end

    local function clear()
        wantedPlan = nil
        if kf then after(kf:want(nil)) end
    end

    local function onView(view)
        if not (switchedOn() and type(view) == "table" and view.pack == true) then
            clear()
            return
        end
        -- Frozen in a fight: anything but a plain false is the lock.
        local okLock, lock = pcall(client.combatLockdown)
        if not okLock or lock ~= false then
            if kf then after(kf:try()) end
            return
        end
        local attrs = view.attrs
        local rows = nil
        if type(attrs) == "table" and attrs.ok == true then rows = attrs.button end
        local care = nil
        if type(ns.CareKeys) == "table" and type(ns.CareKeys.FromView) == "function" then
            local okCare, got = pcall(ns.CareKeys.FromView, client, view)
            if okCare then care = got end
        end
        local plan = S.Plan(rows, care)
        if next(plan) == nil then
            clear()
            return
        end
        if not ensure() then return end
        wantedPlan = plan
        after(kf:want(plan))
    end

    local function run(rest)
        if kf and tostring(rest):find("apply", 1, true) then after(kf:try(true)) end
        local st = api.status()
        local on = k.settings:get(S.SETTING) == true
        if not on and (st == nil or st.state == "cleared") then st = nil end
        if st == nil and on then st = { state = "idle" } end
        local lines = S.Lines(st)
        for i = 1, #lines do say(lines[i]) end
    end

    k:Module({
        name = S.NAME,
        needs = { "client", "store", "bus", D.NAME },
        settings = { {
            key = S.SETTING, scope = "char", type = "bool", default = false,
            label = S.LABEL,
            help = "With the rotation on, shows a row of buttons holding the suggested spell, the care key's heal or cure, and what Ctrl, Shift, Alt and Ctrl+Shift would cast. Each casts only when you click it. Set outside fights only; in a fight they keep what they had. Drag the grip on its left to move the row, outside fights. It binds no key and presses nothing for you.",
            group = "combat", synonyms = { "click", "slots", "buttons", "bar", "click to cast", "action bar" },
        }, {
            key = S.LAYOUT, scope = "account", type = "table", path = S.PATH,
            label = "Click slots position", group = "combat", synonyms = { "click", "slots", "position", "move" },
            keepOnResetAll = true,
            help = "Where the click slots stand. Resetting puts them back.",
        } },
        start = function(ctx)
            client = ctx.client
            ctx.bus:on(S.NAME, D.EVENT, onView)
            client.listen("PLAYER_REGEN_ENABLED", function()
                if kf then after(kf:try(true)) end
            end)
        end,
    })

    if diag and type(diag.commands) == "table" then
        diag.commands[S.WORD] = run
        if type(diag.help) == "table" then diag.help[S.WORD] = S.HELP end
    end

    return api
end

-- The add-on own: declared when this file loads, off until the setting is
-- switched on.
ns.clickSlots = S.Declare(ns, ns.diag)
