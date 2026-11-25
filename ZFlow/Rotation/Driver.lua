local _, ns = ...

-- Rotation driver: each tick it reads the client, asks the chooser, and
-- holds the answer as a view for whoever shows it. It suggests; it presses
-- nothing: no attribute, binding, cast or frame is touched here, and the
-- key plan is only worked out, never applied.
--
--   D.Read(client, pack, ids[, role, extra]) -> read(field)
--     extra (section 232): one options table with named fields; no further
--     positional arguments. extra.food: the module's food table (below).
--     extra.heal: the module's heal table (N8, below).
--     extra.chosen: the seals and blessings from the ownCasts module (below).
--     extra.combo: the combo module's counted combo points (below).
--     extra.controls: the key controls (N41, Rotation/KeyControls.lua).
--     extra.keyActions: the key actions' input (N1, N2, N20, N5,
--     Rotation/KeyActions.lua).
--     extra.counts: the driver's counts table (SE-4, SD-3), added to by a
--     read or a step: targetNameUnread, keyActionsRaised.
--     the reader ns.Snapshot takes. dead, inCombat, stealthed, hostile,
--     spells, buffs, targetDebuffs, form, current and pet are asked of the
--     client; role is the
--     one handed in; every other field answers nil (not known), never a
--     guess.
--       role       the role you chose (the setting D.ROLE), when it is
--                  "dps", "heal" or "tank" and the pack has a part for it;
--                  anything else: nil. No talent is read: the rotation
--                  plays the role you say, or none.
--       stealthed  client.stealthed() as it answered; nil when the client
--                  has no such read
--       hostile    from client.target() -> { exists, hostile, dead } or nil:
--                  true for a target that is there, hostile and alive; false
--                  when any of the three was read the other way; nil for
--                  anything else, or when the client has no such read
--       buffs      client.playerBuffs() as it answered: { [name] = seconds
--                  left or true }, {} for read and none, nil when not known
--                  or the client has no such read
--       targetDebuffs  client.targetDebuffs(): your own debuffs on the
--                  target, the same shape and the same not known (187)
--       form       client.formName(): the form name, or nil for no form
--                  and for not known alike
--       formKnown  true when client.formName() said its answer is known
--                  (a form name, or no form); nil otherwise, never false.
--                  form nil with formKnown true is no form (section 186)
--       current    { [spell name] = true or false } over the pack's spell
--                  ids, from client.currentSpell(id); a spell whose answer
--                  was not read is left out; nil when the client has no
--                  such read or no spell was read
--       pet        client.pet() as it answered (lead section 197): nil when
--                  not known or the client has no such read; { exists =
--                  false } for no pet; else exists, dead, inCombat, family,
--                  happiness, powerKind, each nil when not known
--       spells     each row also gets inRange = client.inRange(spell id)
--                  when the client has that read and the answer is true or
--                  false; otherwise range stays not known
--       buffFood   the best Well Fed food in your bags (section 226). With
--                  food (a table the module keeps, section 229 F-1): the
--                  bags are read only out of a fight (inCombat false), and
--                  a food read is kept in food until the module clears it
--                  on BAG_UPDATE_DELAYED, or the pack or role changes. In a
--                  fight, or a fight not known, the kept food answers, or
--                  nil. Not known (nil) is not kept: the next read asks
--                  again. A pick made while some food in the bags was not
--                  read yet (section 236: data arriving in parts) answers
--                  but is not kept either: the next read asks again, so a
--                  better food read late is not missed until the bags
--                  change. Without food: read each time, as before.
--                  food.on false (the D.FOOD setting off, section 230
--                  BF-3): nil, and the bags are not read
--       foodOn     food.on (true or false); nil without food
--       mounted, onTaxi  client.mounted(), client.onTaxi(): true or false,
--                  nil when the client has no such read or does not say
--       chosen     extra.chosen (CF-32, N12): the seals and blessings
--                  you cast or chose, by key, from the ownCasts module
--                  (Rotation/OwnCasts.lua); nil when it is not a table
--                  (none, or the module is not there)
--       finisherReady  ROGUE-2 (section 236): the client's combo read when
--                  a plain whole number, else extra.combo (the combo
--                  module's counted estimate, Rotation/Combo.lua), against
--                  the pack's options.combo.need; nil without options.combo
--                  or when neither answers
--       ownBuffs   client.ownBuffs() as it answered (N13): the buffs on you
--                  that you put up yourself; nil when not known or the
--                  client has no such read; a read that raises is nil
--       lowHealth  N8 (lead section 238): client.lowHealth(), the game's
--                  low-health warning: true or false, nil when not known or
--                  the client has no such read
--       loc        G25: client.heldBy(), the kind of hold on you ("ROOT",
--                  ...); nil when not held, not known or not read
--       hurt       G26: extra.hurt, the driver's estimate of seconds of
--                  hits (D.HURT, D.StepHurt) as a whole number; nil when
--                  none is given
--       healItem   N8: your healthstone and healing potion
--                  (Rotation/HealItems.lua): { stone, stoneName, potion,
--                  potionName } kept in extra.heal until the bags change
--                  or item data arrives (only a read with every item's
--                  info is kept), plus stoneWait and potionWait (client.
--                  itemCooldown, read each time; nil: not known) and alt,
--                  the item on Alt + your rotation key: set out of a fight
--                  only, with heal.keys true (the key frame on), and kept
--                  through the fight. heal.on false (the D.HEAL setting
--                  off): nil, and the bags are not read
--       grouped    client.grouped() when it answers true or false (PC-3);
--                  nil otherwise
--       debuffTypes  client.unitDebuffTypes("player") (P-PARTY flag (a)):
--                  { [type] = debuff name } on you; nil when not known, the
--                  read raised, or the client has no such read
--       party, groupOn  your group and the "suggest buffs for your group"
--                  setting, from Rotation/Group.lua (ns.PartyGroup.Read,
--                  handed the pack and ids already here: no new argument)
--       tree       N50 (lead sections 227, 228, 232): the pack's
--                  options.trees rows { spell, tree } in order; the first
--                  whose spell client.spell reads as known names the tree
--                  (id from ids, else client.spellId). nil when the pack has
--                  no rows, none is known, or a read raised
--       weaponEnchant  P-SELFBUFF: client.weaponEnchant() by hand: the
--                  seconds left, true (on, time not shown) or false (bare);
--                  a hand with nothing known, or with no weapon worn in
--                  its slot (client.wornLinks 16/17), is left out. nil when not
--                  known, the read raised, or the client has no such read
--       debuffs    PRIEST-3: client.playerDebuffs(): your own debuffs by
--                  name, as playerBuffs; nil when not known, the read
--                  raised, or the client has no such read
--       enemies, plateCasts  client.plateEnemies() and client.plateCasts()
--                  (lead section 242; the real reads are P-READS, Plexy):
--                  the list as it answered; nil when not known, the read
--                  raised or answered no list, or the client has no such read
--   D.Step(client, pack[, prefs, bias, applied, role, extra]) -> view
--     extra is handed to D.Read as it is (section 232).
--     one read and one choice. A read that fails is an error (not caught
--     here; the tick catches it).
--   D.Why(snapshot, trace, keys, lockdown) -> why
--   D.Declare(k[, packs]) -> api           declares the module on kernel k
--     packs: { [class token] = pack }, ns.Packs when left out.
--     api.view()       the view held, nil when off or before the first
--     api.errors()     how many ticks failed
--     api.lastError()  the last failure as text, or nil
--   ns.use(D.NAME) -> { View = api.view, Errors = api.errors }
--
--   view = {
--     pack        true; false when there is no pack for this class, and then
--                 the view holds only pack, trace = {} and why = { pack = false }:
--                 nothing was read and the chooser was not called
--     snapshot    ns.Snapshot of the read
--     suggestion  what ns.Choose picked, or nil. suggestion.passed (below)
--                 is added when it is not empty
--     trace       ns.Choose's trace
--     lockdown    client.combatLockdown() as it answered (nil: not known)
--     keys        ns.cast.Apply(plan, applied, lockdown)
--     attrs       ns.cast.Attributes(suggestion, plan, applied, lockdown)
--     unread      the pack's spells that could not be read (sorted)
--     notRead     the reads the pack names in options.reads (formKnown,
--                 buffs, targetDebuffs, pet) that came back not known, in the
--                 pack's order; {} when every one was read (section 187)
--     missing     the pack's spells with no id (sorted)
--     passed      the spells the chooser's steps passed by only because
--                 nobody read their cooldown (sorted, each once): the trace
--                 rows' own passed lists put together. A spell no step came
--                 to is not in it
--     why         the plain reasons, see below
--     stale       true on a view kept from an earlier tick because this
--                 tick's read failed; absent on a fresh view
--     fight       lead section 340: with a swing suggested (Attack or Auto
--                 Attack), the attributes, as attrs, of what the chooser
--                 gives in a fight with the swing left out (D.FightAttrs);
--                 absent otherwise. The Flow button takes it as the fight
--                 starts (Rotation/FlowButton.lua)
--   }
--   why = { dead, inCombat, lockdown    as read (nil: not known),
--           refused, reason             from keys, when the keys are refused,
--           step, result, note, spell   the last row of the trace }
--
-- The module is declared on (lead section 293, as legacy Flow): char setting D.SETTING. While off nothing is
-- read and no view is held. Switched on, each tick publishes its view on
-- the bus as D.EVENT; switched off, one D.EVENT with no view, then nothing.
-- A tick whose read fails keeps the last good view (a copy marked stale),
-- counts the error and never counts against the module.
--
-- Not tested in game: every client read used here is a first guess.

local D = ns.RotationDriver or {}
ns.RotationDriver = D

D.NAME = "rotationDriver"
D.EVENT = "rotation.suggested"
D.SETTING = "rotation.enabled"
-- Section 230 (BF-3): suggest Well Fed food. The key Flow's import writes
-- (Import/FromFlow.lua, rotation.recoverBuffFood).
D.FOOD = "rotation.recoverBuffFood"
-- N8 (lead section 238): healthstone, then healing potion, in a fight.
D.HEAL = "rotation.emergencyItems"
-- The role you chose (Rotation/Role.lua declares the row).
D.ROLE = "spec.role"
D.EVERY = 0.2

-- G26: Flow's estimate of being hurt, in seconds of hits since you last
-- healed (Flow's Modules/Rotation/Engine.lua E.HURT and E.StepHurt), kept
-- by the driver and handed to the snapshot as hurt (a whole number). Up in
-- a fight by how much an enemy is on you: the client has no threat read,
-- so Flow's own rate for "the game won't say" (unknownHit). Down out of a
-- fight (no eating read here, so the slower rate). At least low while the
-- game's low-health warning is on; 0 when dead; kept within 0 and max. A
-- tick with combat not known makes no step. gap: a longer pause between
-- ticks counts as this many seconds at most. Suggest only.
D.HURT = { low = 40, regen = 1 / 3, eat = 3, max = 60, unknownHit = 0.5, gap = 1 }

function D.StepHurt(hurt, dt, inCombat, hit, eat, low)
    local H = D.HURT
    if inCombat then hurt = hurt + dt * hit
    else hurt = hurt - dt * (eat and H.eat or H.regen) end
    if low then hurt = math.max(hurt, H.low) end
    return math.max(0, math.min(H.max, hurt))
end
-- SE-4, SD-3: each count (D.Declare's counts) and the diag timing mark
-- added the first time it rises.
D.MARKS = {
    targetNameUnread = "ROTATION_TARGET_NAME_UNREAD",
    keyActionsRaised = "ROTATION_KEY_ACTIONS_RAISED",
}

local RR = ns.RotationReader

-- Is an enemy targeted? Yes or no only from what the target read gave.
local function hostileOf(client)
    if type(client.target) ~= "function" then return nil end
    local target = client.target()
    if type(target) ~= "table" then return nil end
    if target.exists == false or target.hostile == false or target.dead == true then return false end
    if target.exists == true and target.hostile == true and target.dead == false then return true end
    return nil
end

-- What is queued or toggled on, by spell name: only answers read as yes
-- or no are kept; nil when nothing could be read (section 183).
local function currentOf(client, ids)
    if type(client.currentSpell) ~= "function" or type(ids) ~= "table" then return nil end
    local out, any = {}, false
    for name, id in pairs(ids) do
        local asked, on = pcall(client.currentSpell, id)
        if asked and type(on) == "boolean" then
            out[name] = on
            any = true
        end
    end
    return any and out or nil
end

-- N39 (P-KEYS slice E): whether you are swinging, read as the current spell
-- of Auto Attack or Attack; nil when neither could be read. SE-3: the id
-- is the pack's when it has the row (Druid, Paladin), else asked of the
-- client by name (client.spellId), so every class reads its swing.
local function attackingOf(client, ids)
    if type(client.currentSpell) ~= "function" or type(ids) ~= "table" then return nil end
    local seen = nil
    for _, name in ipairs({ "Auto Attack", "Attack" }) do
        local id = ids[name]
        if type(id) ~= "number" and type(client.spellId) == "function" then
            local okId, got = pcall(client.spellId, name)
            if okId and type(got) == "number" then id = got end
        end
        if type(id) == "number" then
            local asked, on = pcall(client.currentSpell, id)
            if asked and on == true then return true end
            if asked and on == false then seen = false end
        end
    end
    return seen
end

-- N39: the key can start the swing only with the key frame on, out of
-- combat lockdown (its attributes cannot change in it) and not swinging.
local function canStartOf(client, ids, sk)
    if sk.keyOn ~= true then return false end
    if type(client.combatLockdown) ~= "function" then return nil end
    local asked, locked = pcall(client.combatLockdown)
    if not asked or type(locked) ~= "boolean" then return nil end
    if locked then return false end
    local swinging = attackingOf(client, ids)
    if swinging == nil then return nil end
    return not swinging
end

-- N39: your target is on the no-auto-attack list (Rotation/SpellKeys.lua).
-- An empty list is false. SE-4: a name not read with a list kept is nil
-- (not known), never "gave up": giving up on every target for one unread
-- name left no trace. Each such read adds 1 to counts.targetNameUnread
-- (the driver's counts, D.Declare), which the driver turns into a diag mark.
local function gaveUpOf(client, sk, counts)
    if type(sk.noAttack) ~= "table" or next(sk.noAttack) == nil then return false end
    local name = nil
    if type(client.targetName) == "function" then
        local asked, got = pcall(client.targetName)
        if asked and type(got) == "string" then name = got end
    end
    if name == nil then
        if type(counts) == "table" then counts.targetNameUnread = (counts.targetNameUnread or 0) + 1 end
        return nil
    end
    return sk.noAttack[name] == true
end

-- Conjured food and water (lead section 197): for each row of the pack's
-- options.conjure ({ spell, items = { item name, ... } }), how many of its
-- items are in the bags, added up. A row none of whose items could be
-- counted is left out; nil when nothing could be counted (not read).
local function conjuredOf(client, pack)
    local options = type(pack) == "table" and pack.options or nil
    local rows = type(options) == "table" and options.conjure or nil
    if type(rows) ~= "table" or type(client.itemCount) ~= "function" then return nil end
    local out, any = {}, false
    for _, row in ipairs(rows) do
        local total = nil
        if type(row) == "table" and type(row.spell) == "string" and type(row.items) == "table" then
            for _, item in ipairs(row.items) do
                local asked, n = pcall(client.itemCount, item)
                if asked and type(n) == "number" then total = (total or 0) + n end
            end
        end
        if total then
            out[row.spell] = total
            any = true
        end
    end
    return any and out or nil
end

-- The pack's spell rows, each with its range when the client can tell.
local function spellRows(client, pack, ids)
    local rows = RR.SpellRows(pack, ids, client.spell, client.spellCooldown).rows
    if type(client.inRange) ~= "function" then return rows end
    for name, row in pairs(rows) do
        local asked, near = pcall(client.inRange, ids[name])
        if asked and type(near) == "boolean" then row.inRange = near end
    end
    return rows
end

-- N50 / GAP DRUID-2: the known-spell tree (see the header). A read that
-- raises gives nil for the whole field: nothing is said about the tree.
local function treeOf(client, pack, ids)
    local options = type(pack) == "table" and pack.options or nil
    local rows = type(options) == "table" and options.trees or nil
    if type(rows) ~= "table" or type(client.spell) ~= "function" then return nil end
    for _, row in ipairs(rows) do
        if type(row) == "table" and type(row.spell) == "string" and type(row.tree) == "string" then
            local id
            if type(ids) == "table" then id = ids[row.spell] end
            if type(id) ~= "number" and type(client.spellId) == "function" then
                local ok, got = pcall(client.spellId, row.spell)
                if not ok then return nil end
                id = got
            end
            if type(id) == "number" then
                local ok, got = pcall(client.spell, id)
                if not ok then return nil end
                if type(got) == "table" and got.known == true then return row.tree end
            end
        end
    end
    return nil
end

-- P-SELFBUFF: the enchant on your weapons (see the header). A read that
-- raises, or answers no table, gives nil: not known. A hand counts only
-- with a weapon worn in its slot (client.wornLinks: 16 main, 17 off): an
-- empty slot, a slot not read, or a worn read that raises leaves it out,
-- so an unarmed player is never asked for an enchant.
local ENCHANT_SLOTS = { main = 16, off = 17 }
local function enchantOf(client)
    if type(client.weaponEnchant) ~= "function" then return nil end
    local ok, got = pcall(client.weaponEnchant)
    if not ok or type(got) ~= "table" then return nil end
    local worn
    if type(client.wornLinks) == "function" then
        local wornOk, links = pcall(client.wornLinks)
        if wornOk and type(links) == "table" then worn = links end
    end
    local out = {}
    for _, hand in ipairs({ "main", "off" }) do
        local row = got[hand]
        local link
        if worn then link = worn[ENCHANT_SLOTS[hand]] end
        if type(row) == "table" and type(link) == "string" and link ~= "" then
            if row.has == false then
                out[hand] = false
            elseif row.has == true then
                local secs = row.left
                if type(secs) == "number" and secs == secs and secs >= 0 then
                    out[hand] = secs
                else
                    out[hand] = true
                end
            end
        end
    end
    return out
end

local ROLES = { dps = true, heal = true, tank = true }
local function roleIn(pack, role)
    if type(role) ~= "string" or not ROLES[role] then return nil end
    if type(pack) ~= "table" or type(pack.roles) ~= "table" or type(pack.roles[role]) ~= "table" then return nil end
    return role
end

-- Section 226 (CF-30): the best Well Fed food in your bags for your role
-- (Rotation/BuffFood.lua), { name, item, score }; {} when the bags were read
-- and hold none; nil when the bags, or the facts or tooltip of a food in
-- them, could not be read. Food is consumable class 0, subclass 5; Well Fed
-- food is food whose tooltip says well fed.
-- Section 235 item 4: scored with pack.weights[role].values (the fixed role
-- tables only when the pack has none for the role). A food for a profession
-- (BuffFood.Activity) is never a fight food. pole: client.fishingPole().
-- With a pole (true) only a Fishing food is picked, and no fight food; with
-- no pole or not known, never a Fishing food.
local function weightsOf(pack, role)
    local w = type(pack) == "table" and type(pack.weights) == "table" and pack.weights[role] or nil
    if type(w) == "table" and type(w.values) == "table" then return w.values end
    return nil
end

local function buffFoodOf(client, pack, role, pole)
    local BF = ns.BuffFood
    if type(BF) ~= "table" or type(client.bagItems) ~= "function" or type(client.itemInfo) ~= "function"
        or type(client.itemLines) ~= "function" then return nil end
    local ok, stacks = pcall(client.bagItems)
    if not ok or type(stacks) ~= "table" then return nil end
    local mana, as = BF.UsesMana(pack), roleIn(pack, role) or "dps"
    local values = weightsOf(pack, as)
    local foods, fishing, seen, unread = {}, {}, {}, false
    for _, st in ipairs(stacks) do
        local id = type(st) == "table" and ns.Items.Id(st.item) or nil
        if id and not seen[id] and (st.count == nil or (type(st.count) == "number" and st.count > 0)) then
            seen[id] = true
            local okI, info = pcall(client.itemInfo, id)
            if not okI or type(info) ~= "table" then
                unread = true
            elseif info.classID == BF.CLASS and info.subclassID == BF.SUBCLASS then
                local okL, lines = pcall(client.itemLines, id)
                if not okL or type(lines) ~= "table" then
                    unread = true
                elseif BF.IsBuffFood(lines) and type(info.name) == "string" and info.name ~= "" then
                    local act = BF.Activity(lines)
                    if next(act) ~= nil then
                        local n = act.Fishing
                        if pole == true and type(n) == "number" then
                            fishing[#fishing + 1] = { id = id, name = info.name, score = n }
                        end
                    elseif pole ~= true then
                        local gain = BF.Gain(lines)
                        local score
                        if values then score = BF.Score(gain, values) else score = BF.ScoreByRole(gain, as, mana) end
                        foods[#foods + 1] = { id = id, name = info.name, score = score, gain = gain }
                    end
                end
            end
        end
    end
    -- The second answer: true when some item could not be read, so the
    -- answer may change when it arrives (section 236).
    -- The third answer (D-13): every fight food read, with what it gives.
    local best = BF.Best(pole == true and fishing or foods)
    if best then return { name = best.name, item = best.id, score = best.score }, unread, foods end
    if unread then return nil, true, foods end
    return {}, false, foods
end

-- Parity row D-13 (lead section 668): every Well Fed fight food in your
-- bags, { { id, name, score, gain } } in bag order, scored as the
-- suggestion is; nil when the bags could not be read. The role used is the
-- second answer. For Rotation/FoodWord.lua; the suggestion is unchanged.
function D.Foods(client, pack, role)
    if type(client) ~= "table" then return nil end
    local _, _, foods = buffFoodOf(client, pack, role, false)
    return foods, roleIn(pack, role) or "dps"
end

-- Section 229 (F-1): the food read, kept between bag changes and skipped in
-- a fight. food: the module's table { kept, value, pack, role }; nil reads
-- each time.
-- Section 235 item 4: a fishing pole in your main hand: true, false, nil
-- when the client has no such read or does not say.
-- Section 401: the snapshot fields read from client.targetClose, and how
-- long a hit on you counts as "just now" (a first guess, Needs game test).
local CLOSE = { targetNear = "near", targetMelee = "noMana", targetOnYou = "onYou" }
D.HIT_WINDOW = 3

local function poleOf(client)
    if type(client.fishingPole) ~= "function" then return nil end
    local ok, v = pcall(client.fishingPole)
    if ok and type(v) == "boolean" then return v end
    return nil
end

-- pole: the step's one pole read (section 237 FB3-1), asked when needed.
local function buffFoodKept(client, pack, role, food, pole)
    if type(food) ~= "table" then return (buffFoodOf(client, pack, role, pole())) end
    if food.on == false then return nil end
    -- The pole changes with no bag change: a kept pick is for one pole answer.
    pole = pole()
    local fresh = food.kept == true and food.pack == pack and food.role == role and food.pole == pole
    if fresh then return food.value end
    if client.inCombat() ~= false then return nil end
    local got, partial = buffFoodOf(client, pack, role, pole)
    if got ~= nil and not partial then
        food.kept, food.value, food.pack, food.role, food.pole = true, got, pack, role, pole
    else
        food.kept, food.value = false, nil
    end
    return got
end

-- N8 (lead section 238): an item's cooldown, seconds (0: ready), or nil.
local function cooldownOf(client, id)
    if type(id) ~= "number" or type(client.itemCooldown) ~= "function" then return nil end
    local ok, left = pcall(client.itemCooldown, id)
    if ok and type(left) == "number" and left == left and left >= 0 then return left end
    return nil
end

-- N8: the healing items, kept as the food is (above). Without heal: read
-- each time, no alt.
local function healItemKept(client, heal)
    if type(ns.HealItems) ~= "table" then return nil end
    if type(heal) == "table" and heal.on == false then return nil end
    local pick
    if type(heal) == "table" and heal.kept == true then
        pick = heal.value
    else
        local got, partial = ns.HealItems.Read(client)
        pick = got
        if type(heal) == "table" then
            if got ~= nil and not partial then
                heal.kept, heal.value = true, got
            else
                heal.kept, heal.value = false, nil
            end
        end
    end
    if type(pick) ~= "table" then return nil end
    local out = { stone = pick.stone, stoneName = pick.stoneName,
                  potion = pick.potion, potionName = pick.potionName }
    out.stoneWait = cooldownOf(client, pick.stone)
    out.potionWait = cooldownOf(client, pick.potion)
    if type(heal) == "table" and heal.keys == true then
        -- The key may change only out of a fight; in one, what is on it stays.
        if type(client.inCombat) == "function" and client.inCombat() == false then
            heal.alt = pick.stone or pick.potion
        end
        out.alt = heal.alt
    end
    return out
end

-- ROGUE-2 (section 236): is a finisher due. The client's combo read when it
-- gives a plain whole number, else the combo module's counted estimate
-- (Rotation/Combo.lua), against the pack's options.combo.need. nil for a
-- pack without options.combo, or when neither answers.
local function finisherOf(client, pack, counted)
    local options = type(pack) == "table" and pack.options or nil
    local rules = type(options) == "table" and options.combo or nil
    if type(rules) ~= "table" or type(ns.Combo) ~= "table" then return nil end
    local points
    if type(client.combo) == "function" then
        local ok, got = pcall(client.combo)
        if ok and type(got) == "table" then points = got.points end
    end
    local due = ns.Combo.Ready(points, counted, rules.need)
    return due
end

function D.Read(client, pack, ids, role, extra)
    local food = type(extra) == "table" and extra.food or nil
    local heal = type(extra) == "table" and extra.heal or nil
    local chosen = type(extra) == "table" and extra.chosen or nil
    local combo = type(extra) == "table" and extra.combo or nil
    local spellKeys = nil
    if type(extra) == "table" then spellKeys = extra.spellKeys end
    -- SE-4, SD-3: the driver's counts (D.Declare), added to by a read.
    local counts = nil
    if type(extra) == "table" then counts = extra.counts end
    -- Lead section 187: the form is asked of the client once for a read,
    -- and both fields (form, formKnown) come from that one answer.
    -- The answer is kept only for the other field of the pair, and used
    -- once: a field asked again asks the client again.
    local kept
    local function form(field)
        if kept ~= nil and kept.field ~= field then
            local name, known = kept.name, kept.known
            kept = nil
            return name, known
        end
        local name, known = client.formName()
        kept = { field = field, name = name, known = known }
        return name, known
    end
    -- Section 237 FB3-1: the pole is asked of the client once for a read,
    -- on first need, and the food pick and the fishingPole field share the
    -- answer (nil, not known, kept too).
    local poleRead, poleValue = false, nil
    local function pole()
        if not poleRead then poleRead, poleValue = true, poleOf(client) end
        return poleValue
    end
    -- Section 401: one read of the close-enemy answers for the three fields.
    local closeRead, closeValue = false, nil
    local function close()
        if not closeRead then
            closeRead = true
            if type(client.targetClose) == "function" then
                local ok, v = pcall(client.targetClose)
                if ok and type(v) == "table" then closeValue = v end
            end
        end
        return closeValue
    end
    return function(field)
        if field == "role" then return roleIn(pack, role) end
        if field == "tree" then return treeOf(client, pack, ids) end
        -- PRIEST-3: your own debuffs by name; a read that raises is not known.
        if field == "debuffs" then
            if type(client.playerDebuffs) ~= "function" then return nil end
            local ok, v = pcall(client.playerDebuffs)
            if ok and type(v) == "table" then return v end
            return nil
        end
        if field == "weaponEnchant" then return enchantOf(client) end
        if field == "dead" then return client.dead() end
        if field == "inCombat" then return client.inCombat() end
        if field == "stealthed" then
            if type(client.stealthed) ~= "function" then return nil end
            return client.stealthed()
        end
        if field == "hostile" then return hostileOf(client) end
        if field == "spells" then return spellRows(client, pack, ids) end
        if field == "buffs" then
            if type(client.playerBuffs) ~= "function" then return nil end
            -- A read that raises is not known (as ownBuffs below): the
            -- rules that need your buffs then wait, and the icon does
            -- not keep asking for what was up before the failure.
            local ok, v = pcall(client.playerBuffs)
            if ok and type(v) == "table" then return v end
            return nil
        end
        if field == "targetDebuffs" then
            if type(client.targetDebuffs) ~= "function" then return nil end
            return client.targetDebuffs()
        end
        if field == "form" then
            if type(client.formName) ~= "function" then return nil end
            local name = form("form")
            return type(name) == "string" and name or nil
        end
        if field == "formKnown" then
            if type(client.formName) ~= "function" then return nil end
            local name, known = form("formKnown")
            if known ~= true then return nil end
            if name == nil or type(name) == "string" then return true end
            return nil
        end
        if field == "current" then return currentOf(client, ids) end
        if field == "pet" then
            if type(client.pet) ~= "function" then return nil end
            return client.pet()
        end
        if field == "conjured" then return conjuredOf(client, pack) end
        if field == "chosen" then return type(chosen) == "table" and chosen or nil end
        if field == "finisherReady" then return finisherOf(client, pack, combo) end
        if field == "ownBuffs" then
            if type(client.ownBuffs) ~= "function" then return nil end
            -- Section 236 (c): a read that raises is not known, and the
            -- tick goes on (the aura rule then waits).
            local ok, v = pcall(client.ownBuffs)
            if ok and type(v) == "table" then return v end
            return nil
        end
        -- PC-3: in a group, read as yes or no (Classes/Paladin.lua's seal).
        -- N39 (P-KEYS slice E): the swing, whether the key may start it and
        -- whether your target is on the no-auto-attack list. N40: the spell
        -- your target is casting; false when it casts none. Asked only with
        -- the spell keys' input (Rotation/SpellKeys.lua): not known without.
        if field == "attacking" or field == "canStartAttack" or field == "engageGaveUp"
            or field == "targetCasting" then
            if type(spellKeys) ~= "table" then return nil end
        end
        if field == "attacking" then return attackingOf(client, ids) end
        if field == "canStartAttack" then return canStartOf(client, ids, spellKeys) end
        if field == "engageGaveUp" then return gaveUpOf(client, spellKeys, counts) end
        if field == "targetCasting" then
            if type(client.targetCast) ~= "function" then return nil end
            local ok, v = pcall(client.targetCast)
            if ok and (type(v) == "string" or v == false) then return v end
            return nil
        end
        -- Section 401: the enemy next to you (client.targetClose) and an
        -- enemy that hit you just now (client.hitOnYouAge, HIT_WINDOW
        -- seconds). Each true or false as read; nil when not known.
        if CLOSE[field] then
            local r = close()
            local v = nil
            if type(r) == "table" then v = r[CLOSE[field]] end
            if type(v) == "boolean" then return v end
            return nil
        end
        if field == "hittingYou" then
            if type(client.hitOnYouAge) ~= "function" then return nil end
            local ok, age = pcall(client.hitOnYouAge)
            if not ok then return nil end
            if age == false then return false end
            if type(age) == "number" then return age >= 0 and age <= D.HIT_WINDOW end
            return nil
        end
        if field == "grouped" then
            if type(client.grouped) ~= "function" then return nil end
            local ok, v = pcall(client.grouped)
            if ok and type(v) == "boolean" then return v end
            return nil
        end
        -- Lead section 242: the enemies on nameplates and the casts on them
        -- (client.plateEnemies, client.plateCasts; P-READS, Plexy). A read
        -- that raises, or answers anything but a list, is not known.
        if field == "enemies" or field == "plateCasts" then
            local fn = client[field == "enemies" and "plateEnemies" or "plateCasts"]
            if type(fn) ~= "function" then return nil end
            local ok, v = pcall(fn)
            if ok and type(v) == "table" then return v end
            return nil
        end
        if field == "buffFood" then return buffFoodKept(client, pack, role, food, pole) end
        -- Section 230: no "and ... or nil" here; false must stay false.
        if field == "foodOn" then
            if type(food) ~= "table" or type(food.on) ~= "boolean" then return nil end
            return food.on
        end
        -- Section 230 (BF-2) and GT-2: one read of each for both the food and the gather guards.
        if field == "fishingPole" then return pole() end
        -- N8: the game's low-health warning, and the healing items.
        if field == "lowHealth" then
            if type(client.lowHealth) ~= "function" then return nil end
            local ok, v = pcall(client.lowHealth)
            if ok and type(v) == "boolean" then return v end
            return nil
        end
        if field == "healItem" then return healItemKept(client, heal) end
        -- G25: what holds you (client.heldBy), for the break-free rule. Not
        -- held, not known and a failed read are all nil: the rule then
        -- reads no hold and suggests nothing.
        if field == "loc" then
            if type(client.heldBy) ~= "function" then return nil end
            local ok, v = pcall(client.heldBy)
            if ok and type(v) == "string" then return v end
            return nil
        end
        -- G26: the driver's estimate (D.HURT), nil when none was given.
        if field == "hurt" then
            if type(extra) == "table" and type(extra.hurt) == "number" then return extra.hurt end
            return nil
        end
        if field == "mounted" or field == "onTaxi" then
            if type(client[field]) ~= "function" then return nil end
            local ok, v = pcall(client[field])
            if ok and type(v) == "boolean" then return v end
            return nil
        end
        -- P-PARTY flag (a): what is on you that you could remove, by type.
        if field == "debuffTypes" then
            if type(client.unitDebuffTypes) ~= "function" then return nil end
            local ok, got = pcall(client.unitDebuffTypes, "player")
            if ok and type(got) == "table" then return got end
            return nil
        end
        -- P-PARTY: your group and its setting (Rotation/Group.lua).
        if field == "party" or field == "groupOn" then
            if type(ns.PartyGroup) ~= "table" then return nil end
            return ns.PartyGroup.Read(client, field, { pack = pack, ids = ids })
        end
        -- GT-1: is any tracking on (Rotation/Gather.lua).
        if field == "trackingAny" then
            if type(ns.Gather) ~= "table" then return nil end
            return ns.Gather.Read(client, field)
        end
        -- P-GATHER: the gathering tracking reads (Rotation/Gather.lua).
        if field == "tracking" or field == "trackKnown" or field == "professions" or field == "gatherOn" then
            -- Lead: no "and ... or nil" here; a false answer (the setting off) must stay false.
            if type(ns.Gather) ~= "table" then return nil end
            return ns.Gather.Read(client, field)
        end
        return nil
    end
end

-- The spells the steps passed by for a cooldown nobody read: the trace
-- rows' passed lists as one (sorted, each once).
local function passedIn(trace)
    local seen, out = {}, {}
    for _, row in ipairs(trace) do
        for _, name in ipairs(row.passed or {}) do
            if not seen[name] then
                seen[name] = true
                out[#out + 1] = name
            end
        end
    end
    table.sort(out)
    return out
end

function D.Why(snapshot, trace, keys, lockdown)
    local why = {}
    if type(snapshot) == "table" then
        why.dead, why.inCombat = snapshot.dead, snapshot.inCombat
    end
    why.lockdown = lockdown
    if type(keys) == "table" and keys.ok ~= true then
        why.refused, why.reason = keys.refused, keys.reason
    end
    local n = type(trace) == "table" and #trace or 0
    -- Section 226 (CF-30): food is the step after the rotation. Skipped, its
    -- row is not the rotation's reason; the row before it is.
    -- Lead (merge of P-FOOD and P-GATHER): the same holds for "track".
    -- P-PARTY: and for "group", the step after "track".
    while n > 1 and type(trace[n]) == "table"
        and (trace[n].step == "food" or trace[n].step == "track" or trace[n].step == "group")
        and trace[n].result ~= "pick" do
        n = n - 1
    end
    local last = n > 0 and trace[n] or nil
    -- Lead section 187: with nothing picked, the reason shown is the last
    -- step that was stopped by a read nobody gave ("not known ..."), not
    -- the step after it. A list that had rules ready but could not read
    -- their range was followed by "nothing out of range", and that was
    -- what the player was told.
    if type(last) == "table" and last.result ~= "pick" then
        for i = n, 1, -1 do
            local row = trace[i]
            if type(row) == "table" and type(row.note) == "string" and row.note:find("not known", 1, true) then
                last = row
                break
            end
        end
    end
    if type(last) == "table" then
        why.step, why.result, why.note, why.spell = last.step, last.result, last.note, last.spell
    end
    return why
end

-- Lead section 340: what to hold once the fight is on, for a button that
-- cannot change in combat lockdown and holds the swing now. A second press
-- of Attack toggles the swing off (first guess, not seen in game), so the
-- swing is left out: the chooser asked again on a copy of the snapshot read
-- as in a fight, with Attack and Auto Attack skipped and the engage step
-- off, the plan without its key action. nil when it gives nothing.
-- zflow-btn-pull-spell: the chooser's pick for the fight, as above (the
-- snapshot read as in a fight, Attack and Auto Attack skipped, the engage
-- step off). Flow's class pull spell (Flow Modules/Rotation/Cast.lua, the
-- PLAYER_REGEN_DISABLED handler: def.pullLock) comes from the class file;
-- Z-Flow's packs have no pull row, so their fight list gives it. nil when
-- it gives nothing.
function D.PullPick(snapshot, pack, prefs, bias)
    if type(snapshot) ~= "table" or type(pack) ~= "table" then return nil end
    local s = {}
    for key, value in pairs(snapshot) do s[key] = value end
    s.inCombat = true
    local p, skip = {}, {}
    if type(prefs) == "table" then
        for key, value in pairs(prefs) do p[key] = value end
        if type(prefs.skip) == "table" then
            for key, value in pairs(prefs.skip) do skip[key] = value end
        end
    end
    for name in pairs(ns.cast.ATTACK) do skip[name] = true end
    p.skip, p.autoAttack = skip, false
    local pick = ns.Choose(s, pack, p, bias)
    if type(pick) ~= "table" then return nil end
    return pick
end

function D.FightAttrs(snapshot, pack, prefs, bias, plan, applied, lockdown)
    local pick = D.PullPick(snapshot, pack, prefs, bias)
    if pick == nil then return nil end
    local fightPlan = plan
    if type(plan) == "table" and plan.action ~= nil then
        fightPlan = {}
        for key, value in pairs(plan) do fightPlan[key] = value end
        fightPlan.action = nil
    end
    return ns.cast.Attributes(pick, fightPlan, applied, lockdown, nil)
end

function D.Step(client, pack, prefs, bias, applied, role, extra)
    if type(pack) ~= "table" then
        return { pack = false, trace = {}, why = { pack = false } }
    end
    local ids, missing = RR.SpellIds(pack, client.spellId)
    local snapshot = ns.Snapshot(D.Read(client, pack, ids, role, extra))
    -- N39 and N27 (P-KEYS slice E): with no prefs passed, the spells list
    -- and the auto attack row (Rotation/SpellKeys.lua), extra.spellKeys,
    -- give them: the chooser's, and the key plan's (Skip and Bar off it).
    local planPrefs = prefs
    local sk = nil
    if type(extra) == "table" then sk = extra.spellKeys end
    if prefs == nil and type(sk) == "table" and type(ns.SpellKeys) == "table" then
        prefs, planPrefs = ns.SpellKeys.Prefs(sk)
    end
    local suggestion, trace = ns.Choose(snapshot, pack, prefs, bias)
    local passed = passedIn(trace)
    if suggestion and #passed > 0 then suggestion.passed = passed end

    local lockdown = client.combatLockdown()
    local plan = ns.KeyPlan(pack, planPrefs)
    -- N8: the healing item on Alt + the key (KeyPlan gives a fresh table).
    local hi = snapshot.healItem
    if type(plan) == "table" and type(hi) == "table" and type(hi.alt) == "number" then
        plan.altItem = hi.alt
    end
    -- N41 (P-KEYS slice B): the key controls (Rotation/KeyControls.lua),
    -- extra.controls, shape the plan; a gathering step with the key's
    -- actions off is shown but kept off the key.
    local KC = ns.KeyControls
    local controls = nil
    if type(extra) == "table" then controls = extra.controls end
    -- N1, N2, N20, N5 (P-KEYS slice D): out of a fight, the key actions
    -- (Rotation/KeyActions.lua), extra.keyActions, may take the key's place
    -- of a weak suggestion; never with the key's actions row off.
    local KA = ns.KeyActions
    local actions = nil
    if type(extra) == "table" then actions = extra.keyActions end
    if type(KA) == "table" and type(actions) == "table"
        and not (type(controls) == "table" and controls.actions == false) then
        local okA, act = pcall(function() return KA.Pick(KA.Read(client, actions, pack, role, lockdown), suggestion) end)
        -- SD-3: a read that raises leaves the suggestion as it is, and is
        -- counted (extra.counts.keyActionsRaised), which the driver turns
        -- into a diag mark (D.Declare).
        if not okA and type(extra) == "table" and type(extra.counts) == "table" then
            extra.counts.keyActionsRaised = (extra.counts.keyActionsRaised or 0) + 1
        end
        if okA and type(act) == "table" then
            suggestion = act
            -- The key frame holds the plan, not the suggestion: an action
            -- the key may hold goes on the plan (a spell or an item, never
            -- a look). The fresh plan from ns.KeyPlan, out of a fight only.
            if act.look ~= true and type(plan) == "table" and lockdown == false then
                if type(act.itemId) == "number" then
                    plan.action = { itemId = act.itemId }
                elseif type(act.spell) == "string" then
                    plan.action = { spell = act.spell, unit = act.unit }
                end
            end
        end
    end
    -- N39 (P-KEYS slice E): the engage step's Attack goes on the plan, a
    -- spell (never a macro), out of combat lockdown only. SE-1: the key
    -- frame takes it off again as the fight starts (Rotation/KeyFrame.lua).
    if type(suggestion) == "table" and suggestion.engage == true and type(suggestion.spell) == "string"
        and type(plan) == "table" and plan.action == nil and lockdown == false then
        plan.action = { spell = suggestion.spell }
    end
    local onKey = suggestion
    if type(KC) == "table" and type(controls) == "table" then
        KC.Shape(plan, controls, snapshot, pack, KC.FriendUnit(client))
        suggestion = KC.Gate(suggestion, controls)
        if type(suggestion) == "table" and suggestion.keyOff == true then onKey = nil end
    end
    -- N27: a Bar spell is shown but kept off the key.
    if type(onKey) == "table" and type(prefs) == "table" and type(prefs.bar) == "table"
        and type(onKey.spell) == "string" and prefs.bar[onKey.spell] then
        onKey = nil
    end
    -- zflow-btn-pull-spell (lead section 430 item 1): Flow's way (Flow
    -- Modules/Rotation/Cast.lua C.FightLock and its PLAYER_REGEN_DISABLED
    -- handler). The Attack spell toggles: a second press turns the swing
    -- off (first guess, not seen in game), and the key and the Flow button
    -- cannot change once the lock is on. Flow keeps Attack on its key only
    -- through the game's Start Attack binding, which Z-Flow does not make;
    -- so neither the key nor the Flow button holds Attack. They hold the
    -- spell for the fight (D.PullPick) now, before the pull, so the lock
    -- coming on early changes nothing; with no pick, nothing is added (as
    -- Flow's setAction(nil)). The suggestion, and so the icon, still says
    -- to start the attack.
    if type(onKey) == "table" and ns.cast.ATTACK[onKey.spell] then
        local pull = D.PullPick(snapshot, pack, prefs, bias)
        if type(pull) == "table" and pull.look == true then pull = nil end
        onKey = pull
        if type(plan) == "table" and type(plan.action) == "table" and ns.cast.ATTACK[plan.action.spell] then
            plan.action = nil
            if type(pull) == "table" and lockdown == false then
                if type(pull.itemId) == "number" then
                    plan.action = { itemId = pull.itemId }
                elseif type(pull.spell) == "string" then
                    plan.action = { spell = pull.spell, unit = pull.unit }
                end
            end
        end
    end
    local keys = ns.cast.Apply(plan, applied, lockdown)
    local attrs = ns.cast.Attributes(onKey, plan, applied, lockdown, nil)
    -- Lead section 340: the swing on the key now: what it takes as the
    -- fight starts (D.FightAttrs).
    local fight = nil
    if type(onKey) == "table" and ns.cast.ATTACK[onKey.spell] then
        fight = D.FightAttrs(snapshot, pack, prefs, bias, plan, applied, lockdown)
    end

    -- Not read: no id, or no row came back for it.
    local notRead = {}
    for _, name in ipairs(RR.SpellNames(pack)) do
        if type(snapshot.spells) ~= "table" or snapshot.spells[name] == nil then notRead[#notRead + 1] = name end
    end
    table.sort(notRead)

    -- The reads the pack leans on that came back not known (section 187).
    local readsMissing = {}
    local options = type(pack.options) == "table" and pack.options or {}
    for _, field in ipairs(type(options.reads) == "table" and options.reads or {}) do
        if snapshot[field] == nil then readsMissing[#readsMissing + 1] = field end
    end

    return {
        pack = true,
        snapshot = snapshot,
        suggestion = suggestion,
        trace = trace,
        lockdown = lockdown,
        keys = keys,
        attrs = attrs,
        unread = notRead,
        notRead = readsMissing,
        missing = missing,
        passed = passed,
        why = D.Why(snapshot, trace, keys, lockdown),
        fight = fight,
    }
end

-- One tick's work: the class's pack, then a step.
local function work(client, packs, role, extra)
    local class = type(client.class) == "function" and client.class() or nil
    local pack = type(class) == "string" and type(packs) == "table" and packs[class] or nil
    return D.Step(client, pack, nil, nil, nil, role, extra)
end

-- CF-32: what the ownCasts module keeps (Rotation/OwnCasts.lua), asked
-- each tick; nil when the kernel has no such module, it is off, or it
-- keeps nothing. Resolved when called, so file order does not matter.
local function chosenOf(k)
    if type(k) ~= "table" or type(k.use) ~= "function" then return nil end
    local ok, own = pcall(k.use, "ownCasts")
    if not ok or type(own) ~= "table" or type(own.Chosen) ~= "function" then return nil end
    local asked, got = pcall(own.Chosen)
    if asked and type(got) == "table" then return got end
    return nil
end

-- ROGUE-2: the combo module's counted combo points (Rotation/Combo.lua),
-- asked each tick; nil when there is no such module or it counts nothing
-- for your class. Resolved when called, as chosenOf.
local function comboOf(k)
    if type(k) ~= "table" or type(k.use) ~= "function" then return nil end
    local ok, mod = pcall(k.use, "combo")
    if not ok or type(mod) ~= "table" or type(mod.Count) ~= "function" then return nil end
    local asked, got = pcall(mod.Count)
    if asked and type(got) == "number" then return got end
    return nil
end

-- P-KEYS slice D: the key actions' input (Rotation/KeyActions.lua), asked
-- each tick; nil when the kernel has no such module or it is off. Resolved
-- when called, as chosenOf.
local function keyActionsOf(k, settings)
    if type(k) ~= "table" or type(k.use) ~= "function" then return nil end
    local ok, mod = pcall(k.use, "keyActions")
    if not ok or type(mod) ~= "table" or type(mod.Input) ~= "function" then return nil end
    local asked, got = pcall(mod.Input, settings)
    if asked and type(got) == "table" then return got end
    return nil
end

-- P-KEYS slice E: the spells list's and auto attack's input
-- (Rotation/SpellKeys.lua), asked each tick; nil when the kernel has no
-- such module or it is off. Resolved when called, as chosenOf.
local function spellKeysOf(k, settings)
    if type(k) ~= "table" or type(k.use) ~= "function" then return nil end
    local ok, mod = pcall(k.use, "spellKeys")
    if not ok or type(mod) ~= "table" or type(mod.Input) ~= "function" then return nil end
    local asked, got = pcall(mod.Input, settings)
    if asked and type(got) == "table" then return got end
    return nil
end

function D.Declare(k, packs)
    local api = {}
    local view, errors, lastError = nil, 0, nil
    -- Section 229 (F-1): the Well Fed food read, kept until the bags change.
    local food = {}
    -- N8: the healing items read, kept until the bags change or item data
    -- arrives; alt (what is on Alt + the key) is kept through both.
    local heal = {}
    -- G26: the hurt estimate (D.StepHurt) and the time of its last step.
    local hurt, hurtAt = 0, nil
    local function ask(client, name)
        if type(client[name]) ~= "function" then return nil end
        local ok, v = pcall(client[name])
        if ok then return v end
        return nil
    end
    local function stepHurt(client)
        local now = ask(client, "now")
        if type(now) ~= "number" then return end
        local dt = hurtAt and math.max(0, math.min(D.HURT.gap, now - hurtAt)) or 0
        hurtAt = now
        if ask(client, "dead") == true then hurt = 0 return end
        local inCombat = ask(client, "inCombat")
        if type(inCombat) ~= "boolean" then return end
        hurt = D.StepHurt(hurt, dt, inCombat, D.HURT.unknownHit, false, ask(client, "lowHealth") == true)
    end
    function api.view() return view end
    function api.errors() return errors end
    function api.lastError() return lastError end
    -- SE-4, SD-3: reads that could not be made, counted for this session.
    -- A count that rises adds its diag timing mark (D.MARKS) once.
    local counts = { targetNameUnread = 0, keyActionsRaised = 0 }
    function api.counts()
        local out = {}
        for key, value in pairs(counts) do out[key] = value end
        return out
    end

    local function tick(ctx)
        if ctx.settings:get(D.SETTING) ~= true then
            hurt, hurtAt = 0, nil
            if view ~= nil then
                view = nil
                ctx.bus:emit(D.EVENT, nil)
            end
            return
        end
        stepHurt(ctx.client)
        food.on = ctx.settings:get(D.FOOD) ~= false
        heal.on = ctx.settings:get(D.HEAL) ~= false
        local K = ns.KeyFrame
        heal.keys = type(K) == "table" and ctx.settings:get(K.SETTING) == true
        -- N41: the key controls' rows, read each tick.
        local controls = nil
        if type(ns.KeyControls) == "table" then controls = ns.KeyControls.Read(ctx.settings) end
        -- N1, N2, N20, N5: the key actions' rows and what they keep.
        local keyActions = keyActionsOf(k, ctx.settings)
        -- N39, N40, N27 (P-KEYS slice E): the spell keys' input, and whether
        -- the key frame is on (only the key can start the swing).
        local spellKeys = spellKeysOf(k, ctx.settings)
        if type(spellKeys) == "table" then spellKeys.keyOn = heal.keys == true end
        local before = api.counts()
        local ok, got = pcall(work, ctx.client, packs or ns.Packs, ctx.settings:get(D.ROLE),
            { food = food, heal = heal, chosen = chosenOf(k), combo = comboOf(k), controls = controls,
              keyActions = keyActions, spellKeys = spellKeys, counts = counts,
              hurt = math.floor(hurt) })
        local Dg = ns.Diag
        if type(Dg) == "table" and type(Dg.MARK_EVENT) == "string" then
            for key, name in pairs(D.MARKS) do
                if (counts[key] or 0) > (before[key] or 0) then ctx.bus:emit(Dg.MARK_EVENT, name) end
            end
        end
        if ok then
            view = got
        else
            errors, lastError = errors + 1, tostring(got)
            if view == nil then return end
            if view.stale ~= true then
                local kept = {}
                for key, value in pairs(view) do kept[key] = value end
                kept.stale = true
                view = kept
            end
        end
        ctx.bus:emit(D.EVENT, view)
    end

    k:Module({
        name = D.NAME,
        needs = { "client", "store", "bus" },
        settings = { {
            key = D.SETTING, scope = "char", type = "bool", default = true,
            label = "Suggest the next spell",
            help = "Works out which spell to press next. It presses nothing for you.",
            group = "combat.rotation", synonyms = { "rotation", "next spell", "suggest", "icon", "combat" },
        }, {
            key = D.FOOD, scope = "account", type = "bool", default = true,
            label = "Suggest Well Fed food",
            help = "Out of a fight, with no Well Fed on you, suggests the best Well Fed food in your bags. It eats nothing for you.",
            group = "buffs", synonyms = { "food", "buffs", "well fed", "eat", "recovery" },
        }, {
            key = D.HEAL, scope = "account", type = "bool", default = true,
            label = "In a fight: healthstone, then healing potion",
            help = "With the game's low-health warning on in a fight, suggests your healthstone, else a healing potion, and puts it on Alt + your rotation key. It uses nothing for you.",
            group = "buffs", synonyms = { "healthstone", "potion", "heal", "low health", "recovery" },
        } },
        provides = { View = api.view, Errors = api.errors, Counts = api.counts },
        ticks = { { every = D.EVERY, run = tick } },
        start = function(c)
            food, heal = {}, {}
            hurt, hurtAt = 0, nil
            -- The bags changed: the food kept may be gone, or a better one there.
            c.bus:on(D.NAME, "BAG_UPDATE_DELAYED", function() food, heal = {}, { alt = heal.alt } end)
            -- Item data arrived (lead section 238): a read made without it
            -- may change.
            c.bus:on(D.NAME, "GET_ITEM_INFO_RECEIVED", function() food, heal = {}, { alt = heal.alt } end)
        end,
        stop = function()
            food, heal = {}, {}
            hurt, hurtAt = 0, nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login, off
-- until the setting is switched on.
ns.rotationDriver = D.Declare(ns)
