local _, ns = ...

-- F-new-4: putting right what was learned wrongly. A place learned from
-- the wrong NPC, or a quest spot learned where the objective did not
-- really move on, keeps sending the player to the wrong spot; these words
-- forget the one entry the player names, so the next real visit learns it
-- again. Saved data only: nothing in the game is touched.
--
--   places                     how many places are learned; how to forget one
--   places forget <name|key>   forgets that NPC: this character's
--                              char "learned.places.services" entries whose
--                              key or name matches (any case), and the
--                              account "learned.places.npcs" entry of that
--                              name (the places brought over from Flow)
--   spots                      how many quests have learned spots; how to forget
--   spots forget <quest> [n|done]
--                              account "learned.places.questSpots": the whole
--                              quest, objective n, or where it was handed in
--
-- Neither word wipes everything: without a name it only counts and explains.
-- Resetting the first levels learned from class trainers is the facts word
-- (Core/Facts.lua), next to what it resets.
--
--   LF.ForgetPlace(services, npcs, what) -> { names removed }   (pure, edits both)
--   LF.ForgetSpot(book, quest, which) -> how many lists removed (pure, edits book)
ns.Nav = ns.Nav or {}
local LF = {}
ns.Nav.LearnedForget = LF

LF.NAME = "learnedForget"
LF.PLACES_WORD = "places"
LF.SPOTS_WORD = "spots"
LF.SERVICES = "learned.places.services"
LF.NPCS = "learned.places.npcs"
LF.SPOTS = "learned.places.questSpots"
LF.TURN_IN = 0

local function count(t)
    local n = 0
    if type(t) ~= "table" then return n end
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- " 2" or " done" after a quest number, or nothing when none was given.
local function tail(which)
    if which == nil or which == "" then return "" end
    return " " .. which
end

local function entries(n)
    if n == 1 then return "1 entry" end
    return n .. " entries"
end

local function copy(t)
    local out = {}
    if type(t) ~= "table" then return out end
    for k, v in pairs(t) do out[k] = v end
    return out
end

function LF.ForgetPlace(services, npcs, what)
    local gone = {}
    if type(what) ~= "string" or what == "" then return gone end
    local low = what:lower()
    if type(services) == "table" then
        local drop = {}
        for key, e in pairs(services) do
            local name = nil
            if type(e) == "table" and type(e.name) == "string" then name = e.name end
            if key == what or (name and name:lower() == low) then drop[#drop + 1] = key end
        end
        for _, key in ipairs(drop) do
            local e = services[key]
            local label = tostring(key)
            if type(e) == "table" and type(e.name) == "string" then label = e.name end
            services[key] = nil
            gone[#gone + 1] = label
        end
    end
    if type(npcs) == "table" then
        local drop = {}
        for name in pairs(npcs) do
            if type(name) == "string" and name:lower() == low then drop[#drop + 1] = name end
        end
        for _, name in ipairs(drop) do
            npcs[name] = nil
            gone[#gone + 1] = name
        end
    end
    return gone
end

function LF.ForgetSpot(book, quest, which)
    if type(book) ~= "table" then return 0 end
    local entry = book[quest]
    if type(entry) ~= "table" then return 0 end
    if which == nil or which == "" then
        book[quest] = nil
        return 1
    end
    local index
    if which == "done" then
        index = LF.TURN_IN
    else
        index = tonumber(which)
    end
    if index == nil or entry[index] == nil then return 0 end
    entry[index] = nil
    if next(entry) == nil then book[quest] = nil end
    return 1
end

function LF.Declare(k, diag)
    local ctx
    local id = k.id or ns.id

    local function say(line)
        if ctx then ctx.client.print(id.title .. ": " .. line) end
    end

    local function places(rest)
        local store = ctx.store
        local services = store:get("char", LF.SERVICES)
        local npcs = store:get("account", LF.NPCS)
        local what = (rest or ""):match("^[Ff][Oo][Rr][Gg][Ee][Tt]%s+(.-)%s*$")
        if what == nil or what == "" then
            say(("%d place(s) learned by this character, %d brought over from Flow."):format(count(services), count(npcs)))
            say(("  one wrong? %s %s forget <name>: it is learned again at your next real visit."):format(id.slash, LF.PLACES_WORD))
            return
        end
        local s, a = copy(services), copy(npcs)
        local gone = LF.ForgetPlace(s, a, what)
        if #gone == 0 then
            say(("no learned place called %s; nothing changed."):format(what))
            return
        end
        if count(s) ~= count(services) and store:set("char", LF.SERVICES, s) ~= true then
            say("could not save the change; nothing was forgotten.")
            return
        end
        if count(a) ~= count(npcs) then store:set("account", LF.NPCS, a) end
        say(("forgot %s (%s); your next visit learns it again."):format(gone[1], entries(#gone)))
    end

    local function spots(rest)
        local store = ctx.store
        local book = store:get("account", LF.SPOTS)
        local quest, which = (rest or ""):match("^[Ff][Oo][Rr][Gg][Ee][Tt]%s+(%d+)%s*(%S*)%s*$")
        if quest == nil then
            say(("%d quest(s) with spots learned from your play."):format(count(book)))
            say(("  one wrong? %s %s forget <quest id> [objective number|done]"):format(id.slash, LF.SPOTS_WORD))
            return
        end
        local b = copy(book)
        local q = tonumber(quest)
        if type(b[q]) == "table" then b[q] = copy(b[q]) end
        local n = LF.ForgetSpot(b, q, which)
        if n == 0 then
            say(("no learned spot for quest %s%s; nothing changed."):format(quest, tail(which)))
            return
        end
        if store:set("account", LF.SPOTS, b) ~= true then
            say("could not save the change; nothing was forgotten.")
            return
        end
        say(("forgot the learned spot for quest %s%s; doing it again learns it again."):format(quest, tail(which)))
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[LF.PLACES_WORD] = function(rest)
            if ctx then places(rest) end
        end
        diag.commands[LF.SPOTS_WORD] = function(rest)
            if ctx then spots(rest) end
        end
        if type(diag.help) == "table" then
            diag.help[LF.PLACES_WORD] = "count the NPC places learned; 'forget <name>' drops one learned wrongly"
            diag.help[LF.SPOTS_WORD] = "count the quest spots learned; 'forget <quest id> [objective|done]' drops one learned wrongly"
        end
    end

    k:Module({
        name = LF.NAME,
        needs = { "client", "store" },
        start = function(c) ctx = c end,
        stop = function() ctx = nil end,
    })
end

LF.Declare(ns, ns.diag)
