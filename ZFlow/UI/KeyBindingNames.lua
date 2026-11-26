local _, ns = ...

-- The Key Bindings screen entry (FLOW-PARITY F-19; lead sections 580 item
-- 10, 850), as Flow's Bindings.xml: ZFlow/Bindings.xml declares one CLICK
-- binding on the rotation key button (Rotation/KeyFrame.lua makes it, named
-- ns.id.framePrefix .. "RotationKey") under the ns.id.bindingHeader heading. The game
-- reads Bindings.xml from the add-on's folder by itself; nothing here binds
-- a key or changes a secure attribute. A key the player picks in the game's
-- screen is the game's own binding.
--
-- The game shows the heading and the entry by two global names. Setting
-- globals is Core/Client.lua's (a lead patch); this file only says them:
--   KeyBindingNames.Globals() -> { [global name] = text }

local KB = {}
ns.KeyBindingNames = KB

-- Every name is read from ns.id (Core/Identity.lua; zflow-structure rule 3).
-- Bindings.xml is static XML and can't read ns.id, so its header and button
-- name are written out there; this file and that one must agree (the test).
KB.HEADER = ns.id.bindingHeader
KB.ACTION = "CLICK " .. ns.id.framePrefix .. "RotationKey:LeftButton"
KB.HEADER_TEXT = ns.id.title
KB.NAME_TEXT = ns.id.title .. " key: cast the suggested spell"

function KB.Globals()
    return {
        ["BINDING_HEADER_" .. KB.HEADER] = KB.HEADER_TEXT,
        ["BINDING_NAME_" .. KB.ACTION] = KB.NAME_TEXT,
    }
end
