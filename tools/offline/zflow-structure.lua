-- Z-Flow structure check. Lua 5.1 only (it reads Lua 5.1 bytecode).
--   lua5.1 zflow-structure.lua <repo root> <file list>
-- The list file names every .lua file under ZFlow/, one per line, relative
-- to ZFlow/. Fails (exit 1) when:
--   1. a manifest entry has no file, or differs from it in case;
--   2. a file outside Tests/ is not in the manifest, or a Tests/ file is;
--   3. an identity string appears as a string constant outside
--      Core/Identity.lua (Tests/ and manifest.lua excepted);
--   4. a file reads or writes a global that is not plain Lua 5.1, outside
--      Core/Client.lua. Client names, print, _G, getfenv and the like all
--      count: everything from the client goes through the client boundary.
-- Globals and constants are read from the compiled chunk (string.dump), so
-- comments, locals and field names never count.
local here = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
local L = dofile(here .. "/zflow-lib.lua")

local root, listFile = arg[1], arg[2]
if not root or not listFile then
    print("usage: zflow-structure.lua <repo root> <file list>")
    os.exit(2)
end

local IDENTITY = { "ZFlow", "Z-Flow", "/zflow", "ZFLOW" }
local IDENTITY_FILE = "Core/Identity.lua"
local CLIENT_FILE = "Core/Client.lua"
local PLAIN = {}
for name in ([[assert error ipairs next pairs pcall select tonumber tostring type unpack xpcall
    setmetatable getmetatable rawget rawset rawequal string table math]]):gmatch("%S+") do
    PLAIN[name] = true
end

local fail = 0
local function bad(text)
    fail = fail + 1
    print(text)
end

-- Lua 5.1 bytecode: every global access and string constant of a chunk,
-- nested functions included.
local function scan(dump)
    local pos = 1
    local function byte()
        local b = dump:byte(pos)
        pos = pos + 1
        return b
    end
    assert(dump:sub(1, 4) == "\27Lua" and dump:byte(5) == 0x51, "not Lua 5.1 bytecode")
    local little = dump:byte(7) == 1
    local sizeInt, sizeT, sizeIns, sizeNum = dump:byte(8), dump:byte(9), dump:byte(10), dump:byte(11)
    pos = 13
    local function int(size)
        local bytes = { dump:byte(pos, pos + size - 1) }
        pos = pos + size
        local n = 0
        if little then
            for i = size, 1, -1 do n = n * 256 + bytes[i] end
        else
            for i = 1, size do n = n * 256 + bytes[i] end
        end
        return n
    end
    local function str()
        local len = int(sizeT)
        if len == 0 then return nil end
        local s = dump:sub(pos, pos + len - 2)
        pos = pos + len
        return s
    end
    local globals, strings = {}, {}
    local function fn()
        str()                       -- source name
        int(sizeInt); int(sizeInt)  -- line defined, last line
        byte(); byte(); byte(); byte()
        local code = {}
        for i = 1, int(sizeInt) do code[i] = int(sizeIns) end
        local consts = {}
        for i = 1, int(sizeInt) do
            local kind = byte()
            if kind == 1 then byte()
            elseif kind == 3 then pos = pos + sizeNum
            elseif kind == 4 then
                consts[i] = str()
                if consts[i] then strings[#strings + 1] = consts[i] end
            end
        end
        local accesses = {}
        for pc, ins in ipairs(code) do
            local op = ins % 64
            if op == 5 or op == 7 then      -- GETGLOBAL, SETGLOBAL
                local bx = math.floor(ins / 16384)
                accesses[#accesses + 1] = { name = consts[bx + 1], set = op == 7, pc = pc }
            end
        end
        for _ = 1, int(sizeInt) do fn() end
        local lines = {}
        for i = 1, int(sizeInt) do lines[i] = int(sizeInt) end
        for _ = 1, int(sizeInt) do str(); int(sizeInt); int(sizeInt) end
        for _ = 1, int(sizeInt) do str() end
        for _, a in ipairs(accesses) do
            a.line = lines[a.pc] or 0
            globals[#globals + 1] = a
        end
    end
    fn()
    return globals, strings
end

local manifest, merr = L.manifest(root)
if not manifest then
    print("zflow-structure: " .. tostring(merr))
    os.exit(2)
end
local onDisk = L.readLines(listFile)
if not onDisk then
    print("zflow-structure: cannot read the file list " .. listFile)
    os.exit(2)
end
for i, rel in ipairs(onDisk) do onDisk[i] = rel:gsub("\\", "/") end
table.sort(onDisk)

-- 1 and 2: manifest against the folder
local exact, lower = {}, {}
for _, rel in ipairs(onDisk) do
    exact[rel] = true
    lower[rel:lower()] = rel
end
local listed = {}
for _, f in ipairs(manifest.files) do
    listed[f.path] = true
    if f.path:find("^Tests/") then
        bad("manifest.lua: " .. f.path .. " is a test file; tests are never listed")
    elseif not exact[f.path] then
        if lower[f.path:lower()] then
            bad("manifest.lua: " .. f.path .. " differs in case from the file on disk (" .. lower[f.path:lower()] .. ")")
        else
            bad("manifest.lua: " .. f.path .. " is listed but the file does not exist")
        end
    end
end
local shipped = 0
for _, rel in ipairs(onDisk) do
    if rel ~= "manifest.lua" and not rel:find("^Tests/") then
        shipped = shipped + 1
        if not listed[rel] then bad(rel .. ": not listed in manifest.lua, so it never loads") end
    end
end
if fail == 0 then print("manifest: " .. #manifest.files .. " files listed, all present; none missing from it") end

-- 3 and 4: identity strings and globals
local before = fail
for _, rel in ipairs(onDisk) do
    local chunk, err = loadfile(L.join(root, L.ADDON .. "/" .. rel))
    if not chunk then
        bad(rel .. ": does not compile: " .. tostring(err))
    else
        local globals, strings = scan(string.dump(chunk))
        if rel ~= CLIENT_FILE then
            for _, g in ipairs(globals) do
                if g.set then
                    bad(rel .. ":" .. g.line .. ": sets the global " .. tostring(g.name))
                elseif not PLAIN[g.name] then
                    bad(rel .. ":" .. g.line .. ": reads the global " .. tostring(g.name) .. " (only " .. CLIENT_FILE .. " may touch the client)")
                end
            end
        end
        if rel ~= IDENTITY_FILE and rel ~= "manifest.lua" and not rel:find("^Tests/") then
            for _, s in ipairs(strings) do
                for _, word in ipairs(IDENTITY) do
                    if s:find(word, 1, true) then
                        bad(rel .. ": the identity string \"" .. word .. "\" appears in " .. string.format("%q", s) .. " (read it from ns.id)")
                        break
                    end
                end
            end
        end
    end
end
if fail == before then
    print("identity strings only in " .. IDENTITY_FILE .. "; client globals only in " .. CLIENT_FILE .. " (" .. #onDisk .. " files, " .. shipped .. " outside Tests)")
end

if fail > 0 then
    print("ZFLOW STRUCTURE FAILED: " .. fail .. " problem(s) above.")
    os.exit(1)
end
print("zflow structure OK")
os.exit(0)
