-- Purpose: protect Sanctum navigation, live settings, real counters and safe actions.
-- Input: real Menu/App entry point plus synthetic native UI frames; output: PASS/FAIL.
-- Invariants: no game, personal data, HTTP or native cast engine is used here.
-- Debug: lua tests/test_menu.lua [name-substring]; menu_frames records all nodes.
local tests = {}
local function test(name, fn) tests[#tests + 1] = {name = name, fn = fn} end
local function eq(got, expected, label)
    assert(got == expected, (label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(got))
end
local function setup()
    local state = assert(loadfile("tests/menu_frames.lua"))().install()
    local ns = {db = {enabled = true, mode = "auto", sound = true, whisper = true,
        receiveWhispers = false, showOutgoingWhispers = false, sealSound = true, rankingEnabled = false},
        VERSION = "0.7.4", initialized = true,
        decision = {ready = false, text = "Fahre mit der Maus über einen anderen befreundeten Spieler."},
        API = {Locked = function() return false end}}
    -- Load the actual visual controls as an integration boundary: hit areas,
    -- selected state and child geometry must not depend on a second theme fake.
    assert(loadfile("src/ForeverMouseoverBuff/Theme.lua"))("ForeverMouseoverBuff", ns)
    -- Loading the real old App preserves a meaningful preimplementation failure:
    -- the opening panel is 460 pixels wide rather than the approved 840-pixel menu.
    assert(loadfile("src/ForeverMouseoverBuff/App.lua"))("ForeverMouseoverBuff", ns)
    ns.Refresh = function() if ns.Menu then ns.Menu.Refresh() end end
    ns.BindingLabel = function() return "BUTTON5" end
    ns.DiagnosticSnapshot = function()
        state.diagnosticReads = (state.diagnosticReads or 0) + 1
        return {attempts = 7, confirmed = 5, failed = 2, storageAvailable = true,
            status = {clientVersion = "1.60.1", clientBuild = "70338"},
            events = {{sequence = 10, severity = "WARN", origin = "API", code = "NO_TARGET"}}, codes = {"NO_TARGET"}}
    end
    ns.Stats = {Summary = function()
        state.statsReads = (state.statsReads or 0) + 1
        return state.summary or {available = true, total = 11, families = {might = 6, wisdom = 4, kings = 1}}
    end}
    state.commands = {}
    ns.Command = function(_, command)
        state.commands[#state.commands + 1] = command
        local key, value = command:match("^(%a+) (%a+)$")
        local keys = {receive = "receiveWhispers", outgoing = "showOutgoingWhispers", ranking = "rankingEnabled",
            whisper = "whisper", sound = "sound", seal = "sealSound", debug = "debug"}
        if keys[key] then ns.db[keys[key]] = value == "on" end
        if command == "off" or command == "on" then ns.db.enabled = command == "on" end
        if command == "auto" or command == "might" or command == "wisdom" or command == "kings" then ns.db.mode = command end
        if ns.Menu then ns.Menu.Refresh() end
    end
    ns.ShowFeedbackPanel = function() state.feedbackOpened = true end
    local file = io.open("src/ForeverMouseoverBuff/Menu.lua", "rb")
    if file then file:close(); assert(loadfile("src/ForeverMouseoverBuff/Menu.lua"))("ForeverMouseoverBuff", ns) end
    if ns.Menu then ns.Menu.Show() else ns:ShowPanel() end
    return ns, state
end
local function textContains(state, part)
    for _, node in ipairs(state.nodes) do
        if type(node.text) == "string" and node.text:find(part, 1, true) then return true end
    end
    return false
end

test("approved spacious menu replaces the old narrow button stack", function()
    local ns = setup()
    eq(ns.panel.width, 840, "main menu width")
    eq(ns.panel.height, 620, "main menu height")
    eq(ns.Menu.current, "buffs")
end)
test("six pages switch exclusively and invalid navigation preserves selection", function()
    local ns = setup()
    local count = 0
    for _ in pairs(ns.Menu.pages) do count = count + 1 end
    eq(count, 6)
    ns.Menu.Select("messages")
    for name, page in pairs(ns.Menu.pages) do eq(page:IsShown(), name == "messages", name) end
    eq(ns.Menu.Select("unknown"), false)
    eq(ns.Menu.current, "messages")
end)
test("receive outgoing and export keep independent existing command paths", function()
    local ns, state = setup()
    ns.receiveButton:Click(); eq(state.commands[1], "receive on")
    eq(ns.db.whisper, true); eq(ns.db.showOutgoingWhispers, false)
    ns.outgoingButton:Click(); eq(state.commands[2], "outgoing on")
    ns.rankingButton:Click(); eq(state.commands[3], "ranking on")
    eq(ns.receiveButton.value, true)
    eq(ns.outgoingButton.value, true)
    eq(ns.rankingButton.value, true)
end)
test("stats use live local totals and never invent a rank", function()
    local ns, state = setup()
    eq(state.statsReads, nil)
    ns.Menu.Select("stats")
    eq(state.statsReads, 1)
    assert(textContains(state, "11"), "live total should be visible")
    assert(textContains(state, "unbestätigt"), "local counters must be identified honestly")
    state.summary = {available = false}
    ns.Menu.Refresh()
    assert(textContains(state, "nicht verfügbar"), "damaged counters need an actionable message")
end)
test("diagnostics read live snapshot only while their page is visible", function()
    local ns, state = setup()
    eq(state.diagnosticReads, nil)
    ns.Menu.Select("diagnostics")
    eq(state.diagnosticReads, 1)
    assert(textContains(state, "NO_TARGET"))
    assert(textContains(state, "70338"))
    ns.panel:Hide(); ns.Menu.Refresh()
    eq(state.diagnosticReads, 1)
end)
test("both original logos and current binding are included", function()
    local _, state = setup()
    local icons = {}
    for _, node in ipairs(state.nodes) do if node.texture then icons[node.texture] = true end end
    assert(icons["Interface\\AddOns\\ForeverMouseoverBuff\\Media\\ProjectIcon.tga"])
    assert(icons["Interface\\AddOns\\ForeverMouseoverBuff\\Media\\FeberdinKnight.tga"])
    assert(textContains(state, "BUTTON5"))
end)
test("help and feedback actions need deliberate clicks", function()
    local ns, state = setup()
    eq(#state.commands, 0)
    ns.Menu.Select("help")
    eq(state.feedbackOpened, nil)
    ns.feedbackButton:Click()
    eq(state.feedbackOpened, true)
    ns.uploadHelpButton:Click()
    eq(state.commands[1], "ranking help")
end)
test("all page content fits above the footer", function()
    local ns = setup()
    for pageName, page in pairs(ns.Menu.pages) do
        for _, child in ipairs(page.children) do
            local point = child.points[1]
            if point and point[1] == "TOPLEFT" then
                local bottom = -point[5] + child.height
                assert(bottom <= 438, pageName .. " content crosses footer: " .. tostring(bottom))
            end
        end
    end
end)
local count = 0
for _, item in ipairs(tests) do
    if not arg[1] or item.name:find(arg[1], 1, true) then
        local ok, failure = pcall(item.fn)
        if not ok then io.stderr:write("FAIL ", item.name, "\n", tostring(failure), "\n"); os.exit(1) end
        count = count + 1; print("PASS " .. item.name)
    end
end
assert(count > 0, "No tests matched")
print("PASS: " .. count .. " menu tests")
