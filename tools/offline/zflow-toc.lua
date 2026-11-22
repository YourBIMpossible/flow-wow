-- Writes ZFlow/ZFlow.toc from ZFlow/manifest.lua and Core/Identity.lua.
--   lua5.1 zflow-toc.lua <repo root> [--check]
-- --check writes nothing and exits 1 when the TOC on disk is out of date.
local here = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
local L = dofile(here .. "/zflow-lib.lua")

local root, check = arg[1], arg[2] == "--check"
if not root then
    print("usage: zflow-toc.lua <repo root> [--check]")
    os.exit(2)
end

local m, merr = L.manifest(root)
if not m then print("zflow-toc: " .. tostring(merr)); os.exit(2) end
local id, ierr = L.identity(root)
if not id then print("zflow-toc: " .. tostring(ierr)); os.exit(2) end

local path = L.join(root, L.ADDON .. "/" .. id.addon .. ".toc")
local want = L.tocText(m, id)
local listed = 0
for _, f in ipairs(m.files) do
    if not f.dev then listed = listed + 1 end
end

if check then
    local have = L.readAll(path)
    if have and have:gsub("\r\n", "\n") == want then
        print("zflow-toc: " .. id.addon .. ".toc is current (" .. listed .. " files)")
        os.exit(0)
    end
    print("zflow-toc: " .. id.addon .. ".toc is " .. (have and "out of date" or "missing") .. ": run tools/zflow-toc.ps1")
    os.exit(1)
end

local f, err = io.open(path, "w")   -- text mode: the platform's line ends
if not f then print("zflow-toc: " .. tostring(err)); os.exit(2) end
f:write(want)
f:close()
print("zflow-toc: wrote " .. path .. " (" .. listed .. " files)")
os.exit(0)
