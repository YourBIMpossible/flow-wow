-- Z-Flow bootstrap test loader (shared; used until the kernel's runner,
-- tools/zflow-tests.ps1, lands on branch zflow; then that runner replaces it).
--
-- Usage, from the repository root, with Lua 5.1:
--   lua5.1 tools/zflow-boot.lua ZFlow/Items/Resources.lua ZFlow/Items/Prices.lua -- ZFlow/Tests/Items
-- Arguments before "--" are module files, loaded in the order given.
-- Arguments after "--" are test files or folders (every *.lua below a folder).
--
-- Each file is loaded as the game loads an addon file: loadfile(path)("ZFlow", ns),
-- with one shared ns table. A test file returns { ["test name"] = function(t) ... end }.
-- t.ok(value, msg) and t.eq(got, want, msg) are the only checks.
-- A test with no checks counts as a failure. Exit code 1 on any fail or error.

local ns = {}
local modules, tests, afterSep = {}, {}, false
for _, a in ipairs(arg) do
  if a == "--" then afterSep = true
  elseif afterSep then tests[#tests + 1] = a
  else modules[#modules + 1] = a end
end

local function luaFilesUnder(path)
  if path:match("%.lua$") then return { path } end
  local out = {}
  local sep = package.config:sub(1, 1)
  local cmd = sep == "\\" and ('dir /b /s /a-d "' .. path:gsub("/", "\\") .. '\\*.lua" 2>nul')
                           or ('find "' .. path .. '" -name "*.lua" -type f 2>/dev/null | sort')
  local p = io.popen(cmd)
  if p then
    for line in p:lines() do out[#out + 1] = line end
    p:close()
  end
  table.sort(out)
  return out
end

local function load(path)
  local chunk, err = loadfile(path)
  if not chunk then return nil, err end
  local ok, res = pcall(chunk, "ZFlow", ns)
  if not ok then return nil, res end
  return true, res
end

local loadFailed = 0
for _, m in ipairs(modules) do
  local ok, err = load(m)
  if not ok then loadFailed = loadFailed + 1; print("LOAD ERROR " .. m .. ": " .. tostring(err)) end
end

local function deepEq(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do if not deepEq(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local run, pass, fail, errors = 0, 0, 0, 0
for _, target in ipairs(tests) do
  for _, file in ipairs(luaFilesUnder(target)) do
    local ok, suite = load(file)
    if not ok then
      errors = errors + 1; print("LOAD ERROR " .. file .. ": " .. tostring(suite))
    elseif type(suite) ~= "table" then
      errors = errors + 1; print("LOAD ERROR " .. file .. ": did not return a table of tests")
    else
      local names = {}
      for name in pairs(suite) do names[#names + 1] = name end
      table.sort(names)
      for _, name in ipairs(names) do
        run = run + 1
        local checks, failed = 0, {}
        local t = {
          ok = function(v, msg) checks = checks + 1; if not v then failed[#failed + 1] = msg or "ok failed" end end,
          eq = function(got, want, msg)
            checks = checks + 1
            if not deepEq(got, want) then
              failed[#failed + 1] = (msg or "eq failed") .. ": got " .. tostring(got) .. ", want " .. tostring(want)
            end
          end,
        }
        local okRun, err = pcall(suite[name], t)
        if not okRun then
          errors = errors + 1; print("ERROR " .. name .. ": " .. tostring(err))
        elseif checks == 0 then
          fail = fail + 1; print("FAIL  " .. name .. ": no checks")
        elseif #failed > 0 then
          fail = fail + 1; print("FAIL  " .. name .. ": " .. table.concat(failed, "; "))
        else
          pass = pass + 1
        end
      end
    end
  end
end

print(string.format("zflow boot: %d run: %d pass, %d fail, %d error; %d module load error(s)",
  run, pass, fail, errors, loadFailed))
os.exit((fail + errors + loadFailed) == 0 and 0 or 1)
