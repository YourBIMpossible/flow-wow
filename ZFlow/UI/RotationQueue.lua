local _, ns = ...

-- The modifier queue display (S13): beside the rotation icon, one small
-- icon for each modifier + the key (Shift, Ctrl, Alt, Ctrl + Shift) with
-- the spell that press casts in the form you are in. The one whose
-- modifier is down is edged green; the one that casts what is suggested is
-- edged gold: hold that modifier.
--
-- It shows; it presses nothing. No secure action, no binding, no click. It
-- is on screen in a fight, with an enemy targeted, or while a modifier is
-- held, and only while "Suggest the next spell" and its own setting are on.
-- A slot whose spell the client gives no texture for is not drawn.
--
-- The key plan comes from the view the driver emits. In a fight the keys
-- in that view are a refusal with no plan, so the last plan seen is kept.
--
-- Not tested in game: client.slotIcon and client.modifiers are first guesses.
local U = {}
ns.RotationQueue = U

local Q = ns.Queue
local D = ns.RotationDriver
local I = ns.RotationIcon

U.NAME = "rotationQueue"
U.SETTING = "rotationQueue.enabled"
U.MOD_EVENT = "MODIFIER_STATE_CHANGED"
U.COLOR = { advised = { 1, 0.82, 0 }, held = { 0.4, 1, 0.4 } }

-- true only when the client has this read and it answers true.
local function says(client, name)
    local fn = client[name]
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn)
    return ok and v == true
end

-- The texture the client gives for a spell by name, or nil.
local function texture(client, spell)
    if type(client.spellId) ~= "function" or type(client.spellTexture) ~= "function" then return nil end
    local okId, id = pcall(client.spellId, spell)
    if not okId or type(id) ~= "number" then return nil end
    local ok, tex = pcall(client.spellTexture, id)
    if not ok then return nil end
    if type(tex) == "number" and tex > 0 then return tex end
    if type(tex) == "string" and tex ~= "" then return tex end
    return nil
end

function U.Declare(k)
    local slots
    local api = {}
    function api.handles() return slots end

    local function hideAll()
        if not slots then return end
        for _, h in ipairs(slots) do
            h.setTexture(nil)
            h.mark(nil)
            h.show(false)
        end
    end

    k:Module({
        name = U.NAME,
        needs = { "client", "store", "bus", D.NAME, I.NAME },
        settings = { {
            key = U.SETTING, scope = "account", type = "bool", default = true,
            label = "Show what each modifier casts",
            help = "Small icons beside the suggested spell: what Shift, Ctrl, Alt and Ctrl + Shift with your key cast. It presses nothing.",
            group = "Rotation",
        } },
        start = function(ctx)
            local client = ctx.client
            local plan, stealthForm, lastView, placed, side

            if type(client.slotIcon) ~= "function" then
                k.problems:add(U.NAME, "frame", "the client has no slot icon; the modifier queue is not shown")
                return
            end
            local made = {}
            for i, slot in ipairs(Q.ORDER) do
                local h = client.slotIcon({
                    name = ns.id.framePrefix .. "RotationQueue" .. i, size = Q.SIZES[i], label = Q.LABEL[slot],
                })
                if not h then
                    k.problems:add(U.NAME, "frame", "the client made no slot icon; the modifier queue is not shown")
                    return
                end
                made[i] = h
            end
            slots = made
            hideAll()
            if type(client.modifiers) ~= "function" then
                k.problems:add(U.NAME, "modifiers",
                    "the client has no modifier read; the held modifier is not marked")
            end

            local function held()
                if type(client.modifiers) ~= "function" then return nil end
                local ok, ctrl, shift, alt = pcall(client.modifiers)
                if not ok then return nil end
                return Q.HeldMod(ctrl, shift, alt)
            end
            local function form(snapshot)
                if type(snapshot.form) == "number" then return snapshot.form end
                if type(client.form) ~= "function" then return nil end
                local ok, n = pcall(client.form)
                return ok and type(n) == "number" and n or nil
            end
            -- Where the big icon stands: where the player left it, else its
            -- default. Also the screen width, or nil when not known.
            local function mainPoint()
                local w, h
                if type(client.screen) == "function" then
                    local ok, sw, sh = pcall(client.screen)
                    if ok then w, h = sw, sh end
                end
                local saved = I.Row(k) and k.settings:get(I.SETTING) or nil
                local point = ns.Nav.ClampPoint(type(saved) == "table" and saved.point or nil, I.SIZE, w, h)
                    or ns.Nav.ClampPoint(I.DEFAULT_POINT, I.SIZE, w, h)
                    or I.DEFAULT_POINT
                return point, w, h
            end
            -- Puts the slots beside the big icon; only when it has moved.
            -- In a fight the side they run to stays the one they had (as
            -- Flow froze it): they do not jump across the icon mid-fight.
            -- A run that would leave the screen goes to the other side,
            -- and each slot is kept on the screen.
            local function place(inCombat)
                local point, w, h = mainPoint()
                if not (inCombat == true and side) then side = Q.Side(point, I.SIZE, w) end
                side = Q.FitSide(point, I.SIZE, side, w)
                local mark = table.concat({ tostring(point[1]), tostring(point[2]),
                    tostring(point[3]), tostring(point[4]), side, tostring(w), tostring(h) }, "|")
                if mark == placed then return true end
                local points = Q.Clamp(Q.Place(point, I.SIZE, side), w, h)
                if not points then return false end
                for i, h in ipairs(slots) do h.place(points[i]) end
                placed = mark
                return true
            end

            local function draw(view)
                lastView = view
                if type(view) ~= "table" then
                    plan, stealthForm = nil, nil
                    hideAll()
                    return
                end
                if type(view.keys) == "table" and type(view.keys.plan) == "table" then
                    plan, stealthForm = view.keys.plan, view.keys.stealthForm
                end
                if k.settings:get(D.SETTING) ~= true or k.settings:get(U.SETTING) ~= true
                    or says(client, "petBattle") or says(client, "vehicle") then
                    hideAll()
                    return
                end
                local snapshot = type(view.snapshot) == "table" and view.snapshot or {}
                local row = Q.Row(plan, form(snapshot), snapshot.stealthed, stealthForm)
                local mod = held()
                if not row or not Q.Shows(snapshot.inCombat, snapshot.hostile, mod) or not place(snapshot.inCombat) then
                    hideAll()
                    return
                end
                for i, e in ipairs(Q.Slots(row, I.Spell(view), mod)) do
                    local h = slots[i]
                    local tex = e.spell and texture(client, e.spell) or nil
                    if tex and h.setTexture(tex) then
                        local colour = e.state and U.COLOR[e.state] or nil
                        if colour then h.mark(colour[1], colour[2], colour[3]) else h.mark(nil) end
                        h.show(true)
                    else
                        h.setTexture(nil)
                        h.mark(nil)
                        h.show(false)
                    end
                end
            end

            ctx.bus:on(U.NAME, D.EVENT, draw)
            -- A modifier pressed or let go between two ticks of the driver:
            -- draw the last view again so the green edge follows the hand.
            client.listen(U.MOD_EVENT, function()
                if not slots then return end
                local ok, err = pcall(draw, lastView)
                if not ok then k.fault(U.NAME, err) end
            end)
        end,
        stop = function()
            hideAll()
        end,
    })
    return api
end

-- The queue of the addon itself: declared when this file loads, made at login.
ns.rotationQueue = U.Declare(ns)
