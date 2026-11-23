-- Capture loader (lead sections 187, 188): a diag capture, what the client
-- itself wrote to the saved file, put into the fake client, so the whole
-- add-on (ns.offline.addon(c)) starts from the client's real answers.
-- Offline only: listed as `dev` in manifest.lua, never in the TOC.
--
-- CAPTURE FORMAT, version 1. One Lua table; every field is plain saved data.
--   {
--     format  = 1,
--     account = the account saved table (ns.id.accountDB, "ZFlowDB") as the
--               client wrote it, every key kept. Its `diag` (Core/Diag.lua):
--         snaps  = { snap, ... }   oldest first, newest KEEP (20); each snap:
--             why, at, clock, timing, kernel   (timing.character, timing.realm:
--                                               names, see NAMES below)
--             reads  = { money, combatLockdown, inCombat, bags = { row },
--                        bagStacks, bankOpen, bankStacks,
--                        position = { map, x, y }, zone = { cont, zone },
--                        mapSize = { w, h } (of position.map), recipes,
--                        predecessorLoaded, predecessorData, selfLoaded }
--             known  = { [read name] = true | false }
--             shapes = { [key] = { ok, n, types = { type, ... },
--                                  values = { v1 = plain | { [key] = plain | type name } } } }
--                      type "secret": the client hid the value; no value kept
--         names  = { build = "1.16.1 (7777)", names = { ["C_Map.GetBestMapForUnit"] = "function", ... } }
--         reads  = { { at, build, reads = Diag.Reads(client) }, ... }  oldest first; types only
--         api    = { namespaces = { [ns] = { [member] = type } | false }, globals }
--         starts, count
--     char    = the character saved table (ns.id.charDB, "ZFlowCharDB"), or nil
--   }
-- A saved-variables file gives one with Capture.FromSaved(vars), vars being
-- what running the file assigned: { ZFlowDB = ..., ZFlowCharDB = ... } (the
-- account file and the character file are two files; merge their globals).
--
-- NAMES. A capture from the game holds character, realm and account names
-- (diag timing.character, timing.realm; shapes realm, realmNormalized,
-- fullName; saved per-character keys) and may hold chat or mail text.
-- Real captures never enter the repo, a branch, RESULTS or Drive (lead
-- section 188, 3): tests here use made-up captures in this format.
local _, ns = ...

local Capture = {}
ns.Capture = Capture

Capture.FORMAT = 1
