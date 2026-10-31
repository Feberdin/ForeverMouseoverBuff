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
        receiveWhispers = false, showOutgoingWhispers = false, sealSound = true, rankingEnabled = false,
        classPriorities = {}},
        VERSION = "0.7.4", initialized = true,
        decision = {ready = false, text = "Fahre mit der Maus über einen anderen befreundeten Spieler."},
        API = {Locked = function() return false end}}
    -- Load the actual visual controls as an integration boundary: hit areas,
    -- selected state and child geometry must not depend on a second theme fake.
    assert(loadfile("src/ForeverMouseoverBuff/Theme.lua"))("ForeverMouseoverBuff", ns)
    assert(loadfile("src/ForeverMouseoverBuff/Core.lua"))("ForeverMouseoverBuff", ns)
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
    -- App is the settings boundary: record intentional writes without mocking
    -- the Core priority ordering/validation that the real menu consumes.
    state.priorityWrites, state.priorityResets, state.casts = {}, {}, 0
    ns.SetClassPriorities = function(_, token, list)
        state.priorityWrites[#state.priorityWrites + 1] = {token = token, list = list}
        if state.rejectPriorityWrites then return false end
        assert(ns.Core.ValidPriorityList(list), "Menu must submit a valid priority list")
        ns.db.classPriorities[token] = {}
        for index, family in ipairs(list) do ns.db.classPriorities[token][index] = family end
        ns.Menu.Refresh()
        return true
    end
    ns.ResetClassPriorities = function(_, token)
        state.priorityResets[#state.priorityResets + 1] = token
        ns.db.classPriorities[token] = nil
        ns.Menu.Refresh()
        return true
    end
    _G.CastSpellByName = function() state.casts = state.casts + 1 end
    _G.CastSpellByID = function() state.casts = state.casts + 1 end
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

-- Release setup must be reachable through visible controls, without casting or
-- changing any key simply because a user opens the menu.
test("binding setup offers a deliberate key picker in the buffs page", function()
    local ns, state = setup()
    local picker
    for _, node in ipairs(state.nodes) do
        if node.kind == "Button" and node.label and node.label.text == "Taste wählen" then picker = node end
    end
    assert(picker, "Buffs & Taste must offer a visible Taste wählen control")
    picker:Click()
    eq(ns.Menu.capture:IsShown(), true, "click opens key capture")
    eq(state.casts, 0, "opening key setup cannot cast")
end)

-- Use the real binding module with a native API boundary fake. The UI tests
-- exercise actual press/release handlers, rather than calling Assign directly.
local function bindingSetup()
    local ns, state = setup()
    state.bindings, state.bindingWrites, state.bindingSaves = {F1 = "TARGETSELF"}, 0, 0
    local command = "CLICK ForeverMouseoverBuffButton:LeftButton"
    _G.GetBindingKey = function()
        local result = {}
        for key, actionName in pairs(state.bindings) do
            if actionName == command then result[#result + 1] = key end
        end
        table.sort(result)
        return unpack(result)
    end
    _G.GetBindingAction = function(key) return state.bindings[key] or "" end
    _G.GetCurrentBindingSet = function() return 2 end
    _G.SetBinding = function(key, actionName)
        state.bindingWrites = state.bindingWrites + 1
        state.bindings[key] = actionName
        return true
    end
    _G.SaveBindings = function(scope) eq(scope, 2); state.bindingSaves = state.bindingSaves + 1 end
    _G.IsShiftKeyDown = function() return state.shift == true end
    _G.IsControlKeyDown, _G.IsAltKeyDown, _G.IsMetaKeyDown = function() return false end, function() return false end, function() return false end
    _G.issecretvalue = function() return false end
    ns.API.Locked = function() return state.locked == true end
    ns.BindingLabel = function() return GetBindingKey() or "Noch keine Taste" end
    assert(loadfile("src/ForeverMouseoverBuff/Keybinding.lua"))("ForeverMouseoverBuff", ns)
    return ns, state, command
end
local function keyboard(ns, event, key)
    ns.Menu.capture.scripts[event](ns.Menu.capture, key)
end
test("binding setup consumes press and release then saves the selected chord once", function()
    local ns, state, command = bindingSetup()
    ns.Menu.bindingChoose:Click()
    eq(state.bindingWrites, 0, "opening must not assign")
    eq(ns.Menu.capture.propagateKeyboard, false)
    eq(ns.Menu.capture.keyboardEnabled, true)
    state.shift = true
    keyboard(ns, "OnKeyDown", "F6")
    eq(state.bindingWrites, 0, "press alone must not assign")
    state.shift = false
    keyboard(ns, "OnKeyUp", "LSHIFT")
    eq(state.bindingWrites, 0, "modifier release must not assign")
    keyboard(ns, "OnKeyUp", "F6")
    eq(state.bindings["SHIFT-F6"], command)
    eq(state.bindingSaves, 1)
    eq(state.bindings.F1, "TARGETSELF")
    eq(ns.Menu.binding.text, "SHIFT-F6")
    eq(ns.Menu.capture:IsShown(), false)
    eq(ns.Menu.capture.keyboardEnabled, false)
    eq(state.casts, 0)
end)
test("binding setup collision keeps the picker open with a useful explanation", function()
    local ns, state = bindingSetup()
    ns.Menu.bindingChoose:Click()
    keyboard(ns, "OnKeyDown", "F1"); keyboard(ns, "OnKeyUp", "F1")
    eq(state.bindings.F1, "TARGETSELF"); eq(state.bindingWrites, 0)
    eq(ns.Menu.capture:IsShown(), true)
    assert(ns.Menu.captureMessage.text:find("bereits belegt", 1, true))
    keyboard(ns, "OnKeyDown", "ESCAPE")
    eq(ns.Menu.capture:IsShown(), false); eq(ns.Menu.capture.keyboardEnabled, false)
    eq(ns.panel:IsShown(), true, "Escape leaves settings available")
end)
test("binding setup cancels pending input on close navigation combat and explicit cancel", function()
    for _, reason in ipairs({"close", "page", "combat", "cancel"}) do
        local ns, state = bindingSetup()
        ns.Menu.bindingChoose:Click(); keyboard(ns, "OnKeyDown", "F6")
        if reason == "close" then ns.panel:Hide()
        elseif reason == "page" then ns.Menu.Select("messages")
        elseif reason == "combat" then state.locked = true; ns.Menu.Refresh()
        else ns.Menu.captureCancel:Click() end
        eq(ns.Menu.capture:IsShown(), false, reason)
        eq(ns.Menu.capture.keyboardEnabled, false, reason)
        keyboard(ns, "OnKeyUp", "F6")
        eq(state.bindingWrites, 0, reason); eq(state.casts, 0)
    end
end)
test("binding setup refuses to open in combat and rejects release without press", function()
    local ns, state = bindingSetup()
    state.locked = true; ns.Menu.BeginBinding()
    eq(ns.Menu.capture:IsShown(), false)
    assert(ns.Menu.bindingNotice.text:find("Kampf", 1, true))
    state.locked = false; ns.Menu.BeginBinding()
    keyboard(ns, "OnKeyUp", "F6"); eq(state.bindingWrites, 0)
end)
test("binding setup supports mouse buttons wheel and explicit removal", function()
    local ns, state, command = bindingSetup()
    ns.Menu.bindingChoose:Click()
    local capture = ns.Menu.capture
    capture.scripts.OnMouseDown(capture, "Button5")
    eq(state.bindingWrites, 0)
    capture.scripts.OnMouseUp(capture, "Button5")
    eq(state.bindings.BUTTON5, command)
    ns.Menu.bindingChoose:Click()
    capture.scripts.OnMouseWheel(capture, -1)
    eq(state.bindings.MOUSEWHEELDOWN, command); eq(state.bindings.BUTTON5, nil)
    ns.Menu.bindingClear:Click()
    eq(state.bindings.MOUSEWHEELDOWN, nil); eq(state.bindings.F1, "TARGETSELF")
    eq(state.casts, 0)
end)
test("introduction controls lead to setup messages and replay without changing preferences", function()
    local ns, state = bindingSetup()
    ns.Menu.ShowIntroduction()
    eq(ns.Menu.current, "intro"); eq(ns.db.introductionSeen, true)
    ns.Menu.introBinding:Click(); eq(ns.Menu.capture:IsShown(), true)
    ns.Menu.captureCancel:Click()
    ns.Menu.ShowIntroduction(); ns.Menu.introMessages:Click()
    eq(ns.Menu.current, "messages"); eq(ns.db.whisper, true)
    ns.Menu.Select("help"); ns.Menu.introReplay:Click()
    eq(ns.Menu.current, "intro")
    ns.Menu.introDone:Click(); eq(ns.Menu.current, "buffs")
    eq(state.bindingWrites, 0); eq(state.casts, 0)
end)

test("approved spacious menu replaces the old narrow button stack", function()
    local ns = setup()
    eq(ns.panel.width, 840, "main menu width")
    eq(ns.panel.height, 620, "main menu height")
    eq(ns.Menu.current, "buffs")
end)
test("seven settings pages plus introduction switch exclusively", function()
    local ns = setup()
    local count = 0
    for _ in pairs(ns.Menu.pages) do count = count + 1 end
    eq(count, 8)
    ns.Menu.Select("messages")
    for name, page in pairs(ns.Menu.pages) do eq(page:IsShown(), name == "messages", name) end
    eq(ns.Menu.Select("unknown"), false)
    eq(ns.Menu.current, "messages")
end)
-- The user edits an ordered set of active families. Inactive families remain
-- visible below it so they can be re-enabled without remembering their names.
local function priorities(ns, token)
    return table.concat(ns.Core.GetPriorities(ns.db.classPriorities, token), ",")
end
local function openPriorities(ns)
    eq(ns.Menu.Select("priorities"), true, "class priority page must be available")
    assert(ns.Menu.classButtons.DRUID, "Druid class selector must be visible")
    ns.Menu.classButtons.DRUID:Click()
end

test("class priorities show nine classes and the three druid defaults", function()
    local ns, state = setup()
    openPriorities(ns)
    local count = 0
    for token, button in pairs(ns.Menu.classButtons) do
        count = count + 1
        eq(button:IsVisible(), true, token .. " class is visible")
        eq(button.selected, token == "DRUID", token .. " selected state")
    end
    eq(count, 9)
    eq(priorities(ns, "DRUID"), "kings,wisdom,might")
    for index, family in ipairs({"kings", "wisdom", "might"}) do
        local row = ns.Menu.priorityRows[index]
        eq(row.family, family, "displayed priority " .. index)
        eq(row.active.selected, true, family .. " enabled")
    end
    eq(ns.Menu.priorityRows[1].up:IsEnabled(), false, "first cannot move up")
    eq(ns.Menu.priorityRows[3].down:IsEnabled(), false, "last cannot move down")
    eq(#state.priorityWrites, 0, "viewing defaults must not create an override")
    assert(textContains(state, "außerhalb des Kampfes"))
    assert(textContains(state, "Eigene vorhandene Segen bleiben erhalten"))
    assert(textContains(state, "anderen Paladinen"))
end)
test("class priorities reorder only the selected class without casting", function()
    local ns, state = setup()
    openPriorities(ns)
    local mageDefault = priorities(ns, "MAGE")
    ns.Menu.priorityRows[2].up:Click()
    eq(priorities(ns, "DRUID"), "wisdom,kings,might")
    eq(ns.Menu.priorityRows[1].family, "wisdom", "redraw uses saved ordering")
    eq(priorities(ns, "MAGE"), mageDefault, "another class is unchanged")
    ns.Menu.priorityRows[2].down:Click()
    eq(priorities(ns, "DRUID"), "wisdom,might,kings")
    eq(state.priorityWrites[1].token, "DRUID")
    ns.Menu.classButtons.MAGE:Click()
    eq(ns.Menu.classButtons.MAGE.selected, true)
    eq(ns.Menu.classButtons.DRUID.selected, false)
    ns.Menu.classButtons.DRUID:Click()
    eq(ns.Menu.priorityRows[3].family, "kings", "class switches retain ordering")
    eq(state.casts, 0); eq(#state.commands, 0)
end)
test("class priorities disable and reenable families at the end", function()
    local ns, state = setup()
    openPriorities(ns)
    ns.Menu.priorityRows[1].active:Click()
    eq(priorities(ns, "DRUID"), "wisdom,might")
    eq(ns.Menu.priorityRows[3].family, "kings", "inactive family stays visible last")
    eq(ns.Menu.priorityRows[3].active.selected, false)
    eq(ns.Menu.priorityRows[3].up:IsEnabled(), false)
    eq(ns.Menu.priorityRows[3].down:IsEnabled(), false)
    eq(ns.Menu.priorityRows[2].down:IsEnabled(), false, "active list ends before inactive families")
    ns.Menu.priorityRows[3].active:Click()
    eq(priorities(ns, "DRUID"), "wisdom,might,kings")
    eq(ns.Menu.priorityRows[3].active.selected, true)
    ns.Menu.priorityRows[1].active:Click()
    ns.Menu.priorityRows[1].active:Click()
    ns.Menu.priorityRows[1].active:Click()
    eq(priorities(ns, "DRUID"), "", "all families may be deliberately disabled")
    assert(textContains(state, "Kein Segen aktiviert"), "empty priorities need an explicit status")
    eq(state.casts, 0)
end)
test("class priorities reset only the selected override", function()
    local ns, state = setup()
    ns.db.classPriorities.MAGE = {"might"}
    openPriorities(ns)
    ns.Menu.priorityRows[2].up:Click()
    ns.Menu.priorityReset:Click()
    eq(ns.db.classPriorities.DRUID, nil)
    eq(priorities(ns, "DRUID"), "kings,wisdom,might")
    eq(priorities(ns, "MAGE"), "might")
    eq(state.priorityResets[1], "DRUID")
    eq(ns.Menu.priorityRows[1].family, "kings")
    eq(state.casts, 0)
end)
test("class priorities reject invalid saved data until an explicit reset", function()
    local ns, state = setup()
    local damaged = {"kings", "kings"}
    ns.db.classPriorities.DRUID = damaged
    openPriorities(ns)
    assert(textContains(state, "Ungültige Priorität"), "bad data needs a reset instruction")
    for _, row in ipairs(ns.Menu.priorityRows) do
        eq(row.active:IsEnabled(), false); eq(row.up:IsEnabled(), false); eq(row.down:IsEnabled(), false)
        row.active:Click(); row.up:Click(); row.down:Click()
    end
    eq(#state.priorityWrites, 0)
    eq(ns.db.classPriorities.DRUID, damaged, "opening a damaged setting must not overwrite it")
    ns.Menu.priorityReset:Click()
    eq(priorities(ns, "DRUID"), "kings,wisdom,might")
    eq(ns.Menu.priorityRows[1].active:IsEnabled(), true)
end)
test("class priorities explain how to repair a malformed complete map", function()
    local ns, state = setup()
    ns.db.classPriorities = "damaged"
    openPriorities(ns)
    assert(textContains(state, "/fmb priorities reset"), "malformed maps need the explicit all-classes recovery command")
    assert(textContains(state, "alle Klassen"), "the recovery scope must be clear")
    eq(ns.db.classPriorities, "damaged", "the UI must preserve malformed data until an explicit reset")
    eq(#state.priorityWrites, 0); eq(state.casts, 0)
end)
test("class priorities keep displayed ordering when the App rejects a write", function()
    local ns, state = setup()
    openPriorities(ns)
    state.rejectPriorityWrites = true
    ns.Menu.priorityRows[2].up:Click()
    eq(priorities(ns, "DRUID"), "kings,wisdom,might")
    eq(ns.Menu.priorityRows[1].family, "kings")
    assert(textContains(state, "nicht übernommen"), "failed changes need visible feedback")
    eq(state.casts, 0)
end)
test("class priority navigation and class controls keep clear hit areas above the footer", function()
    local ns = setup()
    openPriorities(ns)
    local rectangles = {}
    for _, button in pairs(ns.Menu.navigation) do
        local point = button.points[1]
        local top = -point[5]
        assert(top + button.height <= 493, "navigation must stay above the all-classes note")
        rectangles[#rectangles + 1] = {left = point[4], top = top, width = button.width, height = button.height}
    end
    for _, button in pairs(ns.Menu.classButtons) do
        eq(button:IsVisible(), true)
        assert(button.width >= 175 and button.height >= 28, "class choices need readable hit areas")
        local point = button.points[1]
        rectangles[#rectangles + 1] = {left = point[4] + 228, top = -point[5] + 137,
            width = button.width, height = button.height}
    end
    for index, first in ipairs(rectangles) do
        for nextIndex = index + 1, #rectangles do
            local second = rectangles[nextIndex]
            local overlap = first.left < second.left + second.width and second.left < first.left + first.width
                and first.top < second.top + second.height and second.top < first.top + first.height
            eq(overlap, false, "controls must not overlap")
        end
    end
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
