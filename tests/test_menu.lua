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
    eq(ns.outgoingButton.value, false, "Showing echoes means quiet mode is off")
    eq(ns.rankingButton.value, true)
end)
test("greeting sending can be switched off while quiet display stays enabled", function()
    local ns, state = setup()
    ns.Menu.Select("messages")
    eq(ns.outgoingButton.value, true, "Hide own greetings must show ON by default")
    assert(ns.outgoingButton:GetText():find("Eigene Grüße verbergen", 1, true))
    assert(textContains(state, "WIM"), "Quiet-display scope must mention WIM")
    eq(ns.Menu.controls.whisper.value, true, "Sending starts enabled")
    ns.Menu.controls.whisper:Click()
    eq(state.commands[1], "whisper off")
    eq(ns.db.whisper, false); eq(ns.outgoingButton.value, true)
    eq(ns.db.showOutgoingWhispers, false); eq(ns.db.receiveWhispers, false)
    ns.outgoingButton:Click()
    eq(state.commands[2], "outgoing on")
    eq(ns.db.showOutgoingWhispers, true); eq(ns.outgoingButton.value, false)
    eq(ns.db.whisper, false, "Showing echoes must not turn sending back on")
    ns.outgoingButton:Click()
    eq(state.commands[3], "outgoing off"); eq(ns.outgoingButton.value, true)
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
-- Model the timer/event boundary, but execute the real menu and feedback code.
-- WoW's Escape sweep may visit both special windows in either order; returning
-- on the next frame prevents that same sweep from closing the restored menu.
local function feedbackSetup()
    local ns, state = setup()
    state.pending = {}
    _G.C_Timer = {After = function(delay, callback)
        eq(delay, 0, "UI return must wait only until the next frame")
        state.pending[#state.pending + 1] = callback
    end}
    function state.flush()
        local pending = state.pending; state.pending = {}
        for _, callback in ipairs(pending) do callback() end
    end
    ns.IssueFeedback = {Build = function()
        return {url = "https://github.com/Feberdin/ForeverMouseoverBuff/issues/new", preview = "Synthetic report"}
    end}
    assert(loadfile("src/ForeverMouseoverBuff/FeedbackUI.lua"))("ForeverMouseoverBuff", ns)
    ns.Menu.Select("help")
    return ns, state
end

test("feedback hides the main menu and its descendants without changing preferences", function()
    local ns = feedbackSetup()
    local db = ns.db
    ns.feedbackButton:Click()
    eq(ns.panel:IsShown(), false, "Main menu must be hidden behind feedback")
    eq(ns.Menu.pages.help:IsVisible(), false, "Main-menu children must not bleed through")
    eq(ns.feedbackButton:IsVisible(), false)
    eq(ns.feedbackPanel:IsShown(), true)
    eq(ns.Menu.current, "help"); eq(ns.db, db); eq(ns.db.mode, "auto")
end)
test("feedback close returns to the selected page and releases copy focus once", function()
    local ns, state = feedbackSetup()
    ns.feedbackButton:Click(); ns.feedbackSelectButton:Click()
    ns.feedbackPanel.closeButton:Click()
    eq(ns.feedbackPanel:IsShown(), false); eq(ns.feedbackURL.focused, false)
    state.flush()
    eq(ns.panel:IsShown(), true); eq(ns.Menu.current, "help")
    ns.panel:Hide(); ns.feedbackPanel:Hide(); state.flush()
    eq(ns.panel:IsShown(), false, "Repeated Hide must not reopen a closed menu")
end)
test("feedback Escape in the copy field restores the prior page", function()
    local ns, state = feedbackSetup()
    ns:ShowFeedbackPanel(); ns.feedbackSelectButton:Click()
    ns.feedbackURL.scripts.OnEscapePressed(ns.feedbackURL)
    state.flush()
    eq(ns.feedbackURL.focused, false); eq(ns.feedbackPanel:IsShown(), false)
    eq(ns.panel:IsShown(), true); eq(ns.Menu.current, "help")
end)
test("feedback global Escape restores after either special-window sweep order", function()
    for _, reverse in ipairs({false, true}) do
        local ns, state = feedbackSetup()
        ns:ShowFeedbackPanel()
        local frames = reverse and {ns.feedbackPanel, ns.panel} or {ns.panel, ns.feedbackPanel}
        for _, frame in ipairs(frames) do if frame:IsShown() then frame:Hide() end end
        state.flush()
        eq(ns.panel:IsShown(), true, "Escape must return to the menu after the sweep")
        eq(ns.feedbackPanel:IsShown(), false)
        for _, frame in ipairs(frames) do if frame:IsShown() then frame:Hide() end end
        state.flush(); eq(ns.panel:IsShown(), false)
    end
end)
test("feedback opened alone closes without resurrecting the menu", function()
    local ns, state = feedbackSetup()
    ns.panel:Hide(); ns:ShowFeedbackPanel()
    ns.feedbackPanel.closeButton:Click(); state.flush()
    eq(ns.panel:IsShown(), false); eq(ns.feedbackPanel:IsShown(), false)
end)
test("feedback is dismissed when the main menu is explicitly opened", function()
    local ns, state = feedbackSetup()
    ns:ShowFeedbackPanel(); ns.feedbackSelectButton:Click()
    ns:ShowPanel()
    eq(ns.feedbackPanel:IsShown(), false, "Explicit menu opening must close feedback")
    eq(ns.feedbackURL.focused, false); eq(ns.panel:IsShown(), true)
    ns.panel:Hide(); state.flush()
    eq(ns.panel:IsShown(), false, "Stale return callback must not undo a later close")
end)
test("feedback reopening cancels the previous deferred return", function()
    local ns, state = feedbackSetup()
    ns:ShowFeedbackPanel(); ns.feedbackPanel:Hide()
    ns:ShowFeedbackPanel("wish"); state.flush()
    eq(ns.panel:IsShown(), false); eq(ns.feedbackPanel:IsShown(), true)
    ns.feedbackPanel:Hide(); state.flush()
    eq(ns.panel:IsShown(), true); eq(ns.Menu.current, "help")
end)
test("feedback kind changes preserve the original return destination", function()
    local ns, state = feedbackSetup()
    ns:ShowFeedbackPanel("bug"); ns:ShowFeedbackPanel("wish")
    ns:ShowFeedbackPanel("feature")
    eq(ns.panel:IsShown(), false); eq(ns.feedbackKind, "feature")
    ns.feedbackPanel:Hide(); state.flush()
    eq(ns.panel:IsShown(), true); eq(ns.Menu.current, "help")
end)
test("feedback queued return is canceled by a later menu open and close", function()
    local ns, state = feedbackSetup()
    ns:ShowFeedbackPanel(); ns.feedbackPanel:Hide()
    ns:ShowPanel(); ns.panel:Hide(); state.flush()
    eq(ns.panel:IsShown(), false); eq(ns.feedbackPanel:IsShown(), false)
end)
test("feedback inherited parent hide does not restore another window", function()
    local ns, state = feedbackSetup()
    ns:ShowFeedbackPanel()
    UIParent:Hide()
    -- A hidden parent emits OnHide, while the child's own shown bit stays true.
    ns.feedbackPanel.scripts.OnHide(ns.feedbackPanel)
    state.flush(); eq(ns.panel:IsShown(), false)
    UIParent:Show(); eq(ns.feedbackPanel:IsVisible(), true)
    ns.feedbackPanel:Hide(); state.flush(); eq(ns.panel:IsShown(), true)
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
