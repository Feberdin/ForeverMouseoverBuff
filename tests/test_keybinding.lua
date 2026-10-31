-- Purpose: verify deliberate key assignment at the native binding API boundary.
-- Input: real Keybinding module and synthetic account/character key maps.
-- Output: deterministic PASS/FAIL, without a game, private data or spell casts.
-- Invariants: unrelated actions survive; failures restore only touched keys.
-- Debug: lua tests/test_keybinding.lua [test-name-substring].
local tests = {}
local function test(name, run) tests[#tests + 1] = {name = name, run = run} end
local function eq(got, expected, label)
    assert(got == expected, (label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(got))
end
local binding = "CLICK ForeverMouseoverBuffButton:LeftButton"
local unpackValues = unpack or table.unpack
local function setup(initial)
    local state = {keys = {}, writes = {}, saves = {}, locked = false, set = 2, modifiers = {}}
    for key, action in pairs(initial or {}) do state.keys[key] = action end
    local ns = {API = {Locked = function() return state.locked end}}
    _G.issecretvalue = function() return false end
    _G.GetBindingKey = function(action)
        local keys = {}
        for key, value in pairs(state.keys) do
            if value == action then keys[#keys + 1] = key end
        end
        table.sort(keys)
        return unpackValues(keys)
    end
    _G.GetBindingAction = function(key, checkOverride)
        if checkOverride and state.override then return state.override end
        return state.keys[key] or ""
    end
    _G.SetBinding = function(key, action)
        state.writes[#state.writes + 1] = {key = key, action = action}
        if state.rejectWrite == #state.writes then return false end
        state.keys[key] = action
        if state.throwWrite == #state.writes then error("synthetic native failure") end
        return true
    end
    _G.SaveBindings = function(set)
        state.saves[#state.saves + 1] = set
        if state.throwSave == #state.saves then error("synthetic native save failure") end
        if state.rejectSave == #state.saves then return false end
        -- Modern native SaveBindings has no success return; nil is not failure.
    end
    _G.GetCurrentBindingSet = function() return state.set end
    _G.IsAltKeyDown = function() return state.modifiers.alt or false end
    _G.IsControlKeyDown = function() return state.modifiers.ctrl or false end
    _G.IsShiftKeyDown = function() return state.modifiers.shift or false end
    _G.IsMetaKeyDown = function() return state.modifiers.meta or false end
    assert(loadfile("src/ForeverMouseoverBuff/Keybinding.lua"))("ForeverMouseoverBuff", ns)
    return ns.Keybinding, state
end

test("new key targets native click and saves the current character set", function()
    local keys, state = setup({W = "MOVEFORWARD"})
    local success, message = keys.Assign("F6")
    eq(success, true, message)
    eq(state.keys.F6, binding)
    eq(state.keys.W, "MOVEFORWARD")
    eq(state.saves[1], 2)
    eq(#state.saves, 1)
end)
test("changing the buff key replaces owned keys and preserves other actions", function()
    local keys, state = setup({F6 = binding, F7 = binding, W = "MOVEFORWARD"})
    state.set = 1
    eq(keys.Assign("CTRL-BUTTON5"), true)
    eq(state.keys.F6, nil); eq(state.keys.F7, nil)
    eq(state.keys["CTRL-BUTTON5"], binding)
    eq(state.keys.W, "MOVEFORWARD")
    eq(state.saves[1], 1)
end)
test("existing buff key is accepted without removing secondary keys", function()
    local keys, state = setup({F6 = binding, F7 = binding})
    eq(keys.Assign("F6"), true)
    eq(state.keys.F7, binding)
    eq(#state.writes, 0)
    eq(#state.saves, 0)
end)
test("occupied key cannot replace another action", function()
    local keys, state = setup({F6 = binding, W = "MOVEFORWARD"})
    local success, message = keys.Assign("W")
    eq(success, false)
    assert(message:find("belegt", 1, true), message)
    eq(state.keys.W, "MOVEFORWARD"); eq(state.keys.F6, binding)
    eq(#state.writes, 0); eq(#state.saves, 0)
end)
test("active override is reported before saving an ineffective binding", function()
    local keys, state = setup({F6 = binding})
    state.override = "ACTIONBUTTON1"
    local success, message = keys.Assign("F7")
    eq(success, false)
    assert(message:find("belegt", 1, true), message)
    eq(#state.writes, 0); eq(#state.saves, 0)
end)
test("combat refuses assignment and clearing without writing", function()
    local keys, state = setup({F6 = binding})
    state.locked = true
    local success, message = keys.Assign("F7")
    eq(success, false); assert(message:find("Kampf", 1, true), message)
    eq(keys.Clear(), false)
    eq(state.keys.F6, binding)
    eq(#state.writes, 0); eq(#state.saves, 0)
end)
test("malformed reserved and modifier-only inputs cannot alter keys", function()
    local keys, state = setup({F6 = binding})
    for _, invalid in ipairs({"", "ESCAPE", "BUTTON1", "CTRL-BUTTON2", "LSHIFT", "SHIFT-", "UNKNOWN", "a b", "F6\n", "|cff00ff00X", 12, {}}) do
        eq(keys.Assign(invalid), false, "invalid input")
    end
    eq(keys.Assign(nil), false)
    eq(#state.writes, 0); eq(#state.saves, 0)
end)
test("native API availability and binding set are checked before changes", function()
    local keys, state = setup({F6 = binding})
    state.set = 0
    eq(keys.Assign("F7"), false)
    state.set = 2
    _G.SaveBindings = nil
    eq(keys.Assign("F7"), false)
    eq(keys.Clear(), false)
    eq(#state.writes, 0)
end)
test("rejected assignment preserves old bindings without saving", function()
    local keys, state = setup({F6 = binding, W = "MOVEFORWARD"})
    state.rejectWrite = 1
    eq(keys.Assign("F7"), false)
    eq(state.keys.F6, binding); eq(state.keys.F7, nil)
    eq(state.keys.W, "MOVEFORWARD")
    eq(#state.saves, 0)
end)
test("partially failed replacement restores every original owned key", function()
    local keys, state = setup({F6 = binding, F7 = binding, W = "MOVEFORWARD"})
    state.throwWrite = 3
    local success, message = keys.Assign("F8")
    eq(success, false)
    eq(state.keys.F6, binding); eq(state.keys.F7, binding); eq(state.keys.F8, nil)
    eq(state.keys.W, "MOVEFORWARD")
    assert(not message:find("synthetic", 1, true), "native errors stay out of messages")
end)
test("save failure restores original keys and attempts to persist restoration", function()
    local keys, state = setup({F6 = binding, W = "MOVEFORWARD"})
    state.throwSave = 1
    local success, message = keys.Assign("F7")
    eq(success, false)
    eq(state.keys.F6, binding); eq(state.keys.F7, nil)
    eq(state.keys.W, "MOVEFORWARD")
    eq(#state.saves, 2)
    assert(message:find("gespeichert", 1, true), message)
end)
test("explicit native save rejection also restores original keys", function()
    local keys, state = setup({F6 = binding})
    state.rejectSave = 1
    eq(keys.Assign("F7"), false)
    eq(state.keys.F6, binding); eq(state.keys.F7, nil)
end)
test("clear removes only buff bindings and persists once", function()
    local keys, state = setup({F6 = binding, F7 = binding, W = "MOVEFORWARD"})
    eq(keys.Clear(), true)
    eq(state.keys.F6, nil); eq(state.keys.F7, nil)
    eq(state.keys.W, "MOVEFORWARD")
    eq(#state.saves, 1)
    eq(keys.Clear(), true)
    eq(#state.saves, 1, "empty clear does not save again")
end)
test("clear failure restores owned keys", function()
    local keys, state = setup({F6 = binding, F7 = binding})
    state.rejectWrite = 2
    eq(keys.Clear(), false)
    eq(state.keys.F6, binding); eq(state.keys.F7, binding)
end)
test("input capture normalizes mouse wheel and modifier chords", function()
    local keys, state = setup()
    eq(keys.FromInput("Button5"), "BUTTON5")
    eq(keys.FromInput("MiddleButton"), "BUTTON3")
    state.modifiers = {alt = true, ctrl = true, shift = true, meta = true}
    eq(keys.FromInput("F6"), "ALT-CTRL-SHIFT-META-F6")
    eq(keys.FromInput("MOUSEWHEELDOWN"), "ALT-CTRL-SHIFT-META-MOUSEWHEELDOWN")
    eq(keys.FromInput("LeftButton"), nil)
    eq(keys.FromInput("RightButton"), nil)
    eq(keys.FromInput("ESCAPE"), nil)
    eq(keys.FromInput("LSHIFT"), nil)
    eq(keys.FromInput("LMETA"), nil)
end)
test("input capture accepts a localized keyboard character", function()
    local keys, state = setup()
    state.modifiers.ctrl = true
    eq(keys.FromInput("Ö"), "CTRL-Ö", "German keyboard character")
    eq(keys.Assign("CTRL-Ö"), true)
    eq(state.keys["CTRL-Ö"], binding)
end)
test("unreadable native results stop before any binding changes", function()
    local keys, state = setup({F6 = binding})
    _G.GetBindingAction = function() error("private native detail") end
    local success, message = keys.Assign("F7")
    eq(success, false)
    assert(not message:find("private", 1, true))
    eq(#state.writes, 0)
end)
test("failed restoration is distinguished from a successful rollback", function()
    local keys, state = setup({F6 = binding})
    state.throwSave = 1
    state.rejectWrite = 3
    local success, message = keys.Assign("F7")
    eq(success, false)
    assert(message:find("nicht sicher wiederhergestellt", 1, true), message)
    assert(message:find("prüfen", 1, true), message)
end)
test("current keys are detached and module initialization never assigns defaults", function()
    local keys, state = setup({F6 = binding, F7 = binding})
    local current = keys.CurrentKeys()
    eq(#current, 2); eq(current[1], "F6")
    current[1] = "W"
    eq(keys.CurrentKeys()[1], "F6")
    eq(#state.writes, 0); eq(#state.saves, 0)
end)

local count = 0
for _, entry in ipairs(tests) do
    if not arg[1] or entry.name:find(arg[1], 1, true) then
        local ok, message = pcall(entry.run)
        if not ok then io.stderr:write("FAIL " .. entry.name .. ": " .. tostring(message) .. "\n"); os.exit(1) end
        print("PASS " .. entry.name)
        count = count + 1
    end
end
assert(count > 0, "No matching tests executed")
print("PASS: " .. count .. " keybinding tests")
