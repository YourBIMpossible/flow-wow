-- Load guard. This addon and the one it replaces would both claim the same
-- keys, both act at a vendor and both hook the same client functions, so
-- they never run together: if the predecessor is loaded this addon pauses.
--
-- Decide is a pure function over the client boundary. It builds no frame:
-- `panel` is plain data for whoever draws it.
local _, ns = ...

ns.Guard = {}

function ns.Guard.Decide(client, id)
    local old = id.predecessor
    -- Two signs, because neither is confirmed on this client: the addon-loaded
    -- query, and the presence of the predecessor's account table.
    local loaded = client.addonLoaded(old) or client.savedExists(id.predecessorDB)
    if not loaded then return { paused = false } end
    return {
        paused = true,
        reason = old .. " is loaded",
        panel = {
            text = old .. " is also enabled. " .. id.title .. " is paused.",
            actions = {
                { id = "import", label = "Import from " .. old },
                { id = "disable-flow-and-reload", label = "Turn " .. old .. " off and reload" },
            },
        },
    }
end
