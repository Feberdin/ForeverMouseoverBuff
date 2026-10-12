-- Purpose: test lifecycle and the deliberate-click boundary with synthetic WoW frames.
-- Input: real Core/App and fake public APIs; output: PASS/FAIL and exit code.
-- Invariant: no real game calls, account data, keys or spells. The native engine is not emulated.
-- Debug: lua tests/test_app.lua [test-name-substring].
local tests = {}
local function test(name, run) tests[#tests + 1] = {name = name, run = run} end
local function eq(got, wanted, why)
    assert(got == wanted, (why or "value") .. ": expected " .. tostring(wanted) .. ", got " .. tostring(got))
end
local function fixture()
    return {playerClass = "PALADIN", playerCombat = false, mounted = false, flying = false, inVehicle = false,
        mode = "auto", auraState = "ready", hasBlessing = false,
        target = {exists = true, isPlayer = true, friendly = true, dead = false, isSelf = false,
            connected = true, visible = true, combat = false, class = "WARRIOR", level = 18},
        spells = {{spellID = 19834, spellName = "Segen der Macht", family = "might", learnedLevel = 12,
            known = true, inRange = true, usable = true}}}
end

-- The fake preserves the Blizzard template's native OnClick marker. It counts
-- attempted actions, not successful WoW casts; it also models the OOC hard gate.
local function setup(saved, modules)
    local state = {frames = {}, locked = false, nativeClicks = 0, actions = {}, reads = 0,
        context = fixture(), logs = {}, notices = {}, sounds = {}, attributeWrites = 0,
        refreshBook = 0, templateMissing = false, kingsKnown = false, now = 100}
    local function newFrame(name)
        local frame = {scripts = {}, attributes = {}, shown = true, text = ""}
        function frame:SetScript(event, handler) self.scripts[event] = handler end
        function frame:GetScript(event) return self.scripts[event] end
        function frame:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
        function frame:SetAttribute(key, value)
            state.attributeWrites = state.attributeWrites + 1
            self.attributes[key] = value
        end
        function frame:GetAttribute(key) return self.attributes[key] end
        function frame:RegisterForClicks(value) self.clickMode = value end
        function frame:SetText(value) self.text = value end
        function frame:GetText() return self.text end
        function frame:Show() self.shown = true end
        function frame:Hide() self.shown = false end
        function frame:IsShown() return self.shown end
        function frame:SetFocus() self.focused = true end
        function frame:ClearFocus() self.focused = false end
        function frame:HighlightText() self.highlighted = true end
        function frame:Enable() self.disabled = false end
        function frame:Disable() self.disabled = true end
        function frame:CreateFontString() return newFrame() end
        function frame:SetSize(width, height) self.width, self.height = width, height end
        function frame:SetWidth(width) self.width = width end
        function frame:SetHeight(height) self.height = height end
        function frame:GetWidth() return self.width or 1920 end
        function frame:GetHeight() return self.height or 1080 end
        function frame:CreateTexture() return newFrame() end
        function frame:IsEnabled() return not self.disabled end
        function frame:IsVisible() return self.shown end
        for _, method in ipairs({"SetPoint", "SetAlpha", "EnableMouse", "SetFrameStrata",
            "SetMovable", "SetClampedToScreen", "RegisterForDrag", "StartMoving", "StopMovingOrSizing",
            "SetFontObject", "SetJustifyH", "SetJustifyV", "SetTextColor",
            "SetScale", "SetFont", "SetTexture", "SetColorTexture", "SetWordWrap",
            "SetAutoFocus", "SetMultiLine", "SetMaxLetters", "SetTextInsets"}) do
            frame[method] = function() end
        end
        if name then state.frames[name] = frame end
        return frame
    end
    _G.ForeverMouseoverBuffDB = saved
    _G.ForeverMouseoverBuffButton = nil
    _G.SlashCmdList = {}
    _G.UISpecialFrames = {}
    _G.UIParent = newFrame()
    _G.DEFAULT_CHAT_FRAME = {AddMessage = function(_, message) state.logs[#state.logs + 1] = message end}
    _G.UIErrorsFrame = {AddMessage = function(_, message) state.notices[#state.notices + 1] = message end}
    _G.SOUNDKIT = {RAID_WARNING = 8959}
    _G.PlaySound = function(id)
        state.sounds[#state.sounds + 1] = id
        return true
    end
    -- Native macro parsing is a C++ boundary. This fixture accepts only our two
    -- fixed routing lines; the separate native suite loads Blizzard's handlers.
    _G.C_Macro = {RunMacroText = function(text)
        if state.locked then
            if text:find("/cast [combat,@mouseover,help,nodead] Segen der Könige", 1, true) then
                state.actions[#state.actions + 1] = {spellID = 20217, unit = "mouseover"}
            end
        elseif text:find("/click [nocombat] ForeverMouseoverBuffAutoButton LeftButton", 1, true) then
            local b = assert(state.frames.ForeverMouseoverBuffAutoButton)
            b.scripts.PreClick(b, "LeftButton", false)
            if state.beforeAutoNative then state.beforeAutoNative() end
            b.scripts.OnClick(b, "LeftButton", false)
            b.scripts.PostClick(b, "LeftButton", false)
        end
    end}
    _G.GetBindingKey = function() return "ALT-B" end
    _G.GetBindingText = function(key) return key end
    _G.GetTime = function() return state.now end
    _G.GetServerTime = function() return 1791810000 + math.floor(state.now) end
    _G.InCombatLockdown = function() return state.locked end
    _G.issecretvalue = function() return false end
    _G.canaccesstable = function() return true end
    _G.CreateFrame = function(_, name, _, template)
        if template == "InsecureActionButtonTemplate" and state.templateMissing then error("missing template") end
        local frame = newFrame(name)
        frame.template = template
        if template == "InsecureActionButtonTemplate" or template == "SecureActionButtonTemplate" then
            frame.nativeClick = function(self, button, down)
                state.nativeClicks = state.nativeClicks + 1
                if template == "SecureActionButtonTemplate" and not down and button == "LeftButton"
                    and self.attributes["*type1"] == "macro" then
                    C_Macro.RunMacroText(self.attributes["*macrotext1"])
                elseif not state.locked and not down and button == "LeftButton"
                    and self.attributes["*type1"] == "spell" then
                    state.actions[#state.actions + 1] = {spellID = self.attributes["*spell1"], unit = self.attributes.unit}
                end
            end
            frame.scripts.OnClick = frame.nativeClick
        end
        return frame
    end
    local ns = {API = {
        Locked = function() return state.locked end,
        ReadContext = function(mode) state.reads = state.reads + 1; state.context.mode = mode; return state.context end,
        RefreshSpellbook = function() state.refreshBook = state.refreshBook + 1 end,
        Client = function() return {version = "1.60.1", build = "69913", interface = 16001} end,
        CombatBlessing = function()
            if state.kingsKnown then return {spellID = 20217, spellName = "Segen der Könige"}, "COMBAT_SPELL_READY" end
            return nil, "COMBAT_SPELL_NOT_LEARNED"
        end,
    }}
    for name, module in pairs(modules or {}) do ns[name] = module end
    assert(loadfile("src/ForeverMouseoverBuff/Core.lua"))("ForeverMouseoverBuff", ns)
    local diagnosticPath = "src/ForeverMouseoverBuff/Diagnostics.lua"
    local diagnosticFile = io.open(diagnosticPath, "rb")
    if diagnosticFile then
        diagnosticFile:close()
        assert(loadfile(diagnosticPath))("ForeverMouseoverBuff", ns)
    end
    if not ns.IssueFeedback then
        assert(loadfile("src/ForeverMouseoverBuff/Feedback.lua"))("ForeverMouseoverBuff", ns)
    end
    assert(loadfile("src/ForeverMouseoverBuff/Theme.lua"))("ForeverMouseoverBuff", ns)
    assert(loadfile("src/ForeverMouseoverBuff/Menu.lua"))("ForeverMouseoverBuff", ns)
    local feedbackPath = "src/ForeverMouseoverBuff/FeedbackUI.lua"
    local feedbackFile = io.open(feedbackPath, "rb")
    if feedbackFile then
        feedbackFile:close()
        assert(loadfile(feedbackPath))("ForeverMouseoverBuff", ns)
    end
    assert(loadfile("src/ForeverMouseoverBuff/App.lua"))("ForeverMouseoverBuff", ns)
    ns:Initialize()
    return ns, state
end
local function click(state, between)
    local button = assert(state.frames.ForeverMouseoverBuffButton, "native buff button must exist")
    if button.scripts.PreClick then button.scripts.PreClick(button, "LeftButton", false) end
    if between then between() end
    button.scripts.OnClick(button, "LeftButton", false)
    if button.scripts.PostClick then button.scripts.PostClick(button, "LeftButton", false) end
end

-- GitHub is a deliberate external boundary. Synthetic builders let these
-- contracts observe exactly when diagnostics and URLs reach the copy dialog.
local function feedbackSetup()
    local builds = {}
    local ns, state = setup(nil, {IssueFeedback = {Build = function(kind, snapshot, include)
        builds[#builds + 1] = {kind = kind, snapshot = snapshot, include = include}
        return {url = "https://github.com/Feberdin/ForeverMouseoverBuff/issues/new?template=" .. kind
            .. (include and "&environment=synthetic" or ""),
            preview = include and "Synthetic technical preview" or "No technical data", kind = kind}
    end}})
    return ns, state, builds
end
test("issue_feedback_command_opens_without_technical_data_or_game_actions", function()
    local ns, state, builds = feedbackSetup()
    local mode, enabled, writes = ns.db.mode, ns.db.enabled, state.attributeWrites
    ns:Command("feedback")
    assert(ns.feedbackPanel and ns.feedbackPanel:IsShown(), "Feedback command must open the report dialog")
    eq(builds[#builds].kind, "bug"); eq(builds[#builds].include, false)
    eq(builds[#builds].snapshot, nil, "No diagnostic read before opt-in")
    eq(ns.feedbackURL:GetText():find("environment", 1, true), nil)
    eq(ns.feedbackURL.focused, false, "Opening must not steal keyboard focus")
    eq(ns.db.mode, mode); eq(ns.db.enabled, enabled); eq(state.attributeWrites, writes)
    eq(#state.actions, 0); eq(#state.sounds, 0)
end)
test("issue_feedback_opt_in_preview_selection_and_reopen_are_consistent", function()
    local ns, state, builds = feedbackSetup()
    ns:Command("feedback wish")
    assert(ns.feedbackPanel, "Feedback command must create the report dialog")
    eq(builds[#builds].kind, "wish")
    ns.feedbackTechnicalButton.scripts.OnClick()
    eq(builds[#builds].include, true)
    eq(builds[#builds].snapshot.version, ns.VERSION)
    eq(ns.feedbackPreview:GetText(), "Synthetic technical preview")
    assert(ns.feedbackURL:GetText():find("environment=synthetic", 1, true))
    ns.feedbackKindButtons.feature.scripts.OnClick()
    eq(builds[#builds].kind, "feature"); eq(builds[#builds].include, true)
    ns.feedbackSelectButton.scripts.OnClick()
    eq(ns.feedbackURL.focused, true); eq(ns.feedbackURL.highlighted, true)
    ns.feedbackURL.scripts.OnEnterPressed(ns.feedbackURL)
    eq(ns.feedbackURL.focused, false)
    ns.feedbackTechnicalButton.scripts.OnClick()
    eq(builds[#builds].snapshot, nil)
    eq(ns.feedbackURL:GetText():find("environment", 1, true), nil)
    ns.feedbackTechnicalButton.scripts.OnClick()
    ns.feedbackURL.scripts.OnEscapePressed(ns.feedbackURL)
    eq(ns.feedbackPanel:IsShown(), false); eq(ns.feedbackURL.focused, false)
    ns:Command("feedback")
    eq(builds[#builds].include, false, "Each newly opened report needs its own opt-in")
    eq(#state.actions, 0)
end)
test("issue_feedback_missing_builder_shows_recovery_and_disables_link", function()
    local ns = setup()
    ns.IssueFeedback = nil
    ns:Command("feedback")
    assert(ns.feedbackPanel, "Feedback command must create an actionable fallback dialog")
    eq(ns.feedbackURL:GetText(), "")
    eq(ns.feedbackSelectButton.disabled, true)
    assert(ns.feedbackPreview:GetText():find("Addonpaket", 1, true), "Recovery must explain how to repair installation")
end)
test("issue_feedback_real_builder_excludes_private_context_and_reuses_one_dialog", function()
    local ns, state = setup({playerName = "PRIVATE_PLAYER", whisperText = "PRIVATE_CHAT"})
    ns.db.mode = "wisdom"
    ns:Command("feedback feature")
    local panel = ns.feedbackPanel
    local specialCount = #UISpecialFrames
    eq(ns.feedbackURL:GetText(), "https://github.com/Feberdin/ForeverMouseoverBuff/issues/new?template=03-feature.yml")
    ns.decision = {text = "PRIVATE_DECISION"}
    ns.feedbackTechnicalButton.scripts.OnClick()
    assert(ns.feedbackURL:GetText():find("environment=", 1, true))
    assert(ns.feedbackPreview:GetText():find("Addon: " .. ns.VERSION, 1, true))
    assert(ns.feedbackPreview:GetText():find("Modus: wisdom", 1, true))
    eq(ns.feedbackURL:GetText():find("PRIVATE", 1, true), nil)
    eq(ns.feedbackPreview:GetText():find("PRIVATE", 1, true), nil)
    ns:Command("feedback bug")
    eq(ns.feedbackPanel, panel); eq(#UISpecialFrames, specialCount)
    eq(ns.feedbackURL:GetText():find("environment=", 1, true), nil)
    eq(#state.actions, 0); eq(#state.sounds, 0)
end)
test("issue_feedback_main_menu_exposes_button_and_copy_text_cannot_drift", function()
    local ns = feedbackSetup()
    ns:ShowPanel()
    assert(ns.feedbackButton, "Main menu must expose feedback without remembering a slash command")
    ns.feedbackButton.scripts.OnClick()
    local original = ns.feedbackURL:GetText()
    ns.feedbackURL:SetText("edited.example")
    ns.feedbackURL.scripts.OnTextChanged(ns.feedbackURL, true)
    eq(ns.feedbackURL:GetText(), original, "Copy field must stay consistent with preview")
    ns.feedbackURL:SetFocus()
    ns.feedbackPanel.scripts.OnHide()
    eq(ns.feedbackURL.focused, false)
end)

test("creates_native_ooc_button_without_replacing_onclick", function()
    local ns = setup()
    local b = ns.button
    assert(b, "mouse-over buff needs a native OOC button")
    eq(b.template, "InsecureActionButtonTemplate")
    eq(b:GetScript("OnClick"), b.nativeClick, "native action handler must be unchanged")
    eq(b:GetAttribute("unit"), "mouseover")
    eq(b:GetAttribute("useOnKeyDown"), false)
    eq(b.clickMode, "AnyUp")
end)
test("hover_and_periodic_refresh_never_arm_or_cast", function()
    local ns, state = setup()
    ns:Refresh()
    ns:OnEvent("UPDATE_MOUSEOVER_UNIT")
    ns:Tick(1)
    eq(#state.actions, 0); eq(state.nativeClicks, 0)
    eq(ns.button:GetAttribute("type1"), nil)
    eq(ns.button:GetAttribute("*type1"), nil)
    eq(ns.button:GetAttribute("*spell1"), nil)
end)
test("deliberate_click_rechecks_and_clears_action", function()
    local ns, state = setup()
    click(state)
    eq(#state.actions, 1); eq(state.actions[1].spellID, 19834); eq(state.actions[1].unit, "mouseover")
    eq(ns.button:GetAttribute("type1"), nil)
    eq(ns.button:GetAttribute("*type1"), nil)
    eq(ns.button:GetAttribute("*spell1"), nil)
    eq(ns.button:GetAttribute("spell1"), nil)
end)
test("target_changed_since_preview_cannot_receive_stale_buff", function()
    local ns, state = setup(); ns:Refresh()
    state.context.target.isPlayer = false
    click(state)
    eq(#state.actions, 0)
end)
test("native_gate_blocks_combat_entering_between_preclick_and_click", function()
    local _, state = setup()
    click(state, function() state.locked = true end)
    eq(#state.actions, 0)
end)
test("combat_refresh_and_click_do_not_read_target", function()
    local ns, state = setup()
    state.locked = true
    local previous = state.reads
    ns:Refresh(); ns:Tick(1); click(state)
    eq(state.reads, previous); eq(#state.actions, 0)
end)
test("combat_transition_clears_prepared_action_when_safe_again", function()
    local ns, state = setup()
    click(state, function() state.locked = true end)
    state.locked = false
    ns:OnEvent("PLAYER_REGEN_ENABLED")
    eq(state.frames.ForeverMouseoverBuffButton:GetAttribute("type1"), nil, "combat-interrupted action must be cleared")
    eq(state.frames.ForeverMouseoverBuffButton:GetAttribute("spell1"), nil)
end)
test("disabled_mode_blocks_even_previously_ready_target", function()
    local ns, state = setup()
    ns:Command("off"); click(state)
    eq(#state.actions, 0); eq(ns.db.enabled, false)
end)
test("manual_family_selection_does_not_cast_on_settings_change", function()
    local ns, state = setup()
    ns:Command("wisdom")
    eq(ns.db.mode, "wisdom"); eq(#state.actions, 0)
    click(state); eq(#state.actions, 0)
end)
test("invalid_saved_settings_use_safe_defaults", function()
    local ns = setup({mode = "danger", enabled = "yes", debug = {}})
    eq(ns.db.mode, "auto"); eq(ns.db.enabled, true); eq(ns.db.debug, false)
end)
test("spell_events_invalidate_cache_and_diagnostics_have_no_identity", function()
    local ns, state = setup()
    local previous = state.refreshBook
    ns:OnEvent("SPELLS_CHANGED")
    assert(state.refreshBook > previous)
    local text = ns:Diagnostics()
    assert(text:find("69913", 1, true)); assert(text:find("ALT-B", 1, true))
    ns:Command("debug on"); ns:Command("status"); ns:Command("debug off")
    assert(#state.logs > 0)
end)
test("frame_and_binding_configuration_do_not_overwrite_user_keys", function()
    local ns, state = setup()
    ns:Command(""); ns:Command("help")
    local file = assert(io.open("src/ForeverMouseoverBuff/App.lua", "r"))
    local source = file:read("*a"); file:close()
    for _, forbidden in ipairs({"SetBindingClick(", "SetOverrideBinding", "SaveBindings(", "CastSpellBy", "RunMacro(", "C_Macro.RunMacroText(", "SecureHandlerWrapScript", ":Execute("}) do
        assert(not source:find(forbidden, 1, true), "unexpected game mutation boundary: " .. forbidden)
    end
    eq(#state.actions, 0)
end)
test("real_api_core_and_native_button_contract_select_and_skip_buff", function()
    local ns, state = setup()
    local auraPresent, known = false, true
    _G.canaccesstable = function(value) return type(value) == "table" end
    _G.UnitAffectingCombat = function() return state.locked end
    _G.UnitClass = function(unit) return "unused", unit == "player" and "PALADIN" or "WARRIOR" end
    _G.UnitExists = function() return true end
    _G.UnitIsPlayer = function() return true end
    _G.UnitCanAssist = function() return true end
    _G.UnitIsDeadOrGhost = function() return false end
    _G.UnitIsUnit = function() return false end
    _G.UnitIsConnected = function() return true end
    _G.UnitIsVisible = function() return true end
    _G.UnitLevel = function() return 18 end
    _G.IsMounted = function() return false end
    _G.IsFlying = function() return false end
    _G.UnitInVehicle = function() return false end
    _G.GetBuildInfo = function() return "1.60.1", "69913", "", 16001 end
    _G.Enum = {SpellBookSpellBank = {Player = 0}, SpellBookItemType = {Spell = 1}}
    _G.C_Secrets = {ShouldAurasBeSecret = function() return false end}
    _G.C_Spell = {
        GetSpellName = function(id)
            return ({[19740] = "Segen der Macht", [19742] = "Segen der Weisheit", [20217] = "Segen der Könige"})[id]
        end,
        IsSpellInRange = function() return true end,
        IsSpellUsable = function() return true, false end,
    }
    _G.C_SpellBook = {
        GetNumSpellBookSkillLines = function() return 1 end,
        GetSpellBookSkillLineInfo = function() return {itemIndexOffset = 0, numSpellBookItems = 2} end,
        GetSpellBookItemInfo = function(slot)
            return {itemType = 1, isPassive = false, isOffSpec = false, spellID = slot == 1 and 19740 or 19834}
        end,
        GetSpellBookItemName = function() return "Segen der Macht", "" end,
        GetSpellBookItemLevelLearned = function(slot) return slot == 1 and 4 or 12 end,
        IsSpellKnown = function() return known end,
    }
    _G.C_UnitAuras = {GetAuraDataByIndex = function(_, index, filter)
        -- This fixture is a foreign blessing; the PLAYER-filtered scan is empty.
        if filter == "HELPFUL|PLAYER" then return nil end
        if auraPresent and index == 1 then return {spellId = 19740, name = "Segen der Macht"} end
    end}
    -- Replace only the WoW boundary fixture with the actual API module. Core and
    -- App remain the same objects, giving an end-to-end offline contract check.
    assert(loadfile("src/ForeverMouseoverBuff/API.lua"))("ForeverMouseoverBuff", ns)
    ns:Refresh(); eq(ns.decision.code, "READY")
    click(state); eq(#state.actions, 1); eq(state.actions[1].spellID, 19834)
    auraPresent = true
    click(state); eq(#state.actions, 1); eq(ns.decision.code, "HAS_BLESSING")
    auraPresent, known = false, false
    ns:OnEvent("SPELLS_CHANGED")
    click(state); eq(#state.actions, 1); eq(ns.decision.code, "NO_KNOWN_SPELL")
end)

-- Regressions for supportable operation: explain missing input and retain only
-- bounded, anonymous evidence. A prepared action is not a confirmed server cast.
test("missing_binding_explains_why_hover_cannot_buff", function()
    local ns, state = setup()
    _G.GetBindingKey = function() return nil end
    ns:Refresh()
    eq(ns.decision.code, "NO_BINDING")
    assert(ns.decision.text:find("Taste", 1, true))
    click(state)
    eq(#state.actions, 0)
end)
test("diagnostic_codes_survive_reload_without_player_data", function()
    local ns = setup()
    ns:Log("AURA_UNKNOWN")
    local saved = ns.db
    local nextSession = setup(saved)
    assert(table.concat(nextSession.logs, ","):find("AURA_UNKNOWN", 1, true),
        "Diagnostic reason must survive a reload for passive log analysis")
    eq(nextSession.db.diagnostics.version, nextSession.VERSION)
end)
test("stored_diagnostic_codes_are_sanitized_and_bounded", function()
    local codes = {"AURA_UNKNOWN", "private player name", {}, "API_RESTRICTED"}
    local ns = setup({diagnostics = {codes = codes, attempts = -1, confirmed = "bad"}})
    local text = table.concat(ns.logs, ",")
    assert(not text:find("private", 1, true))
    eq(ns.db.diagnostics.attempts, 0)
    eq(ns.db.diagnostics.confirmed, 0)
    for index = 1, 60 do ns:Log(index % 2 == 0 and "NO_TARGET" or "OUT_OF_RANGE") end
    assert(#ns.db.diagnostics.codes <= 40)
end)
test("cast_preparation_is_only_confirmed_by_matching_player_event", function()
    local ns, state = setup()
    click(state)
    eq(ns.db.diagnostics.attempts, 1)
    eq(ns.db.diagnostics.confirmed, 0)
    ns:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "party1", "SyntheticCast", 19834)
    ns:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "SyntheticCast", 19742)
    eq(ns.db.diagnostics.confirmed, 0)
    ns:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "SyntheticCast", 19834)
    eq(ns.db.diagnostics.confirmed, 1)
    ns:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "SyntheticCast", 19834)
    eq(ns.db.diagnostics.confirmed, 1)
end)
test("failed_or_expired_attempt_is_not_reported_as_success", function()
    local ns, state = setup()
    click(state)
    ns:OnEvent("UNIT_SPELLCAST_FAILED", "player", "SyntheticCast", 19834)
    eq(ns.db.diagnostics.failed, 1)
    eq(ns.db.diagnostics.confirmed, 0)
    click(state)
    state.now = state.now + 10
    ns:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "SyntheticCast", 19834)
    eq(ns.db.diagnostics.confirmed, 0)
end)

test("stable_fallback_preview_does_not_fill_diagnostic_history", function()
    local ns, state = setup()
    state.context.hasBlessing = true
    state.context.blessings = {{family = "might", spellID = 19838, sourceIsPlayer = false}}
    state.context.spells[2] = {spellID = 20217, spellName = "Segen der Könige", family = "kings",
        learnedLevel = 10, known = true, inRange = true, usable = true}
    ns:Refresh()
    eq(ns.decision.code, "READY_FALLBACK")
    local count = #ns.logs
    for index = 1, 10 do ns:Refresh() end
    eq(#ns.logs, count, "An unchanged preview must not flood saved diagnostics")
    click(state)
    eq(state.actions[1].spellID, 20217)
    state.context.blessings[2] = {family = "kings", spellID = 20217, sourceIsPlayer = true}
    click(state)
    eq(#state.actions, 1, "Own alternative must not be rotated on a second click")
end)

test("repeated_api_failure_keeps_history_and_debug_output_readable", function()
    local ns, state = setup()
    ns.db.debug = true
    local normalRead = ns.API.ReadContext
    local function failingRead(mode)
        ns:Log("API_CALL_FAILED")
        ns:Log("API_AURAS_UNKNOWN")
        state.context.auraState = "unknown"
        return normalRead(mode)
    end
    ns.API.ReadContext = failingRead
    ns:Refresh()
    local historyCount, chatCount = #ns.logs, #state.logs
    for index = 1, 20 do ns:Refresh() end
    eq(#ns.logs, historyCount, "An unchanged API failure must keep the useful history")
    eq(#state.logs, chatCount, "An unchanged API failure must not flood debug chat")
    ns.API.ReadContext = normalRead
    state.context.auraState = "ready"
    ns:Refresh()
    ns.API.ReadContext = failingRead
    ns:Refresh()
    assert(#ns.logs > historyCount, "A recovered and recurring failure is a new episode")
end)

-- Feedback must follow an actual failed user action, never the 4Hz preview.
-- The public sound/UI APIs are the only new fake boundary; selection stays real.
test("feedback_blocked_click_reports_reason_and_plays_sound_with_panel_hidden", function()
    local ns, state = setup()
    ns.panel:Hide()
    state.context.target.exists = false
    click(state)
    eq(#state.actions, 0)
    eq(#state.notices, 1, "Blocked click must show a visible explanation")
    assert(state.notices[1]:find(ns.decision.text, 1, true))
    assert(state.logs[1]:find(ns.decision.text, 1, true))
    eq(#state.sounds, 1, "Blocked click must request one warning sound")
    eq(state.sounds[1], 8959)
end)
test("feedback_preserved_blessing_unknown_spell_and_range_use_real_reasons", function()
    for _, reason in ipairs({"OWN_BLESSING_PRESERVED", "NO_KNOWN_SPELL", "OUT_OF_RANGE", "NOT_USABLE"}) do
        local ns, state = setup()
        if reason == "OWN_BLESSING_PRESERVED" then
            state.context.hasBlessing = true
            state.context.blessings = {{family = "might", spellID = 19834, sourceIsPlayer = true}}
        elseif reason == "NO_KNOWN_SPELL" then state.context.spells = {}
        elseif reason == "OUT_OF_RANGE" then state.context.spells[1].inRange = false
        else state.context.spells[1].usable = false end
        click(state)
        eq(ns.decision.code, reason); eq(#state.actions, 0)
        eq(#state.notices, 1); eq(#state.sounds, 1)
        assert(state.notices[1]:find(ns.decision.text, 1, true))
    end
end)
test("feedback_hover_keydown_other_button_and_ready_click_stay_silent", function()
    local ns, state = setup()
    state.context.target.exists = false
    ns:Refresh(); ns:Tick(1); ns:OnEvent("UPDATE_MOUSEOVER_UNIT")
    ns:PreClick(ns.button, "LeftButton", true)
    ns:PreClick(ns.button, "RightButton", false)
    eq(#state.notices, 0); eq(#state.sounds, 0)
    state.context.target.exists = true
    click(state)
    eq(#state.actions, 1); eq(#state.notices, 0); eq(#state.sounds, 0)
end)
test("feedback_combat_click_is_explained_without_target_reads_or_attribute_writes", function()
    local ns, state = setup()
    state.locked = true
    local reads, writes = state.reads, state.attributeWrites
    click(state)
    eq(state.reads, reads); eq(state.attributeWrites, writes); eq(#state.actions, 0)
    eq(#state.notices, 1); eq(#state.sounds, 1)
    assert(state.notices[1]:find("Kampf", 1, true))
end)
test("feedback_combat_transition_after_preparation_is_explained", function()
    local ns, state = setup()
    click(state, function() state.locked = true end)
    eq(#state.actions, 0); eq(#state.sounds, 1); eq(#state.notices, 1)
    assert(state.notices[1]:find("Kampf", 1, true))
end)
test("feedback_confirmed_cast_does_not_become_failure_on_combat_transition", function()
    local ns, state = setup()
    state.beforeAutoNative = function()
        ns:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Synthetic", 19834)
        state.locked = true
    end
    click(state)
    eq(ns.db.diagnostics.confirmed, 1)
    eq(#state.notices, 0, "Already confirmed cast must not be called a failure")
    eq(#state.sounds, 0)
end)
test("feedback_repeated_clicks_are_throttled_but_changed_reason_is_visible", function()
    local _, state = setup()
    state.context.target.exists = false
    click(state); click(state)
    eq(#state.notices, 1); eq(#state.sounds, 1)
    state.now = state.now + 0.5
    state.context.target.exists = true
    state.context.spells[1].inRange = false
    click(state)
    eq(#state.notices, 2); eq(#state.sounds, 1, "Sound throttle covers changed reasons too")
    state.now = state.now + 2
    click(state)
    eq(#state.notices, 3); eq(#state.sounds, 2)
end)
test("feedback_cast_failure_warns_once_but_unrelated_and_secret_events_stay_silent", function()
    local ns, state = setup()
    click(state)
    ns:OnEvent("UNIT_SPELLCAST_FAILED", "party1", "Synthetic", 19834)
    ns:OnEvent("UNIT_SPELLCAST_FAILED", "player", "Synthetic", 19742)
    _G.issecretvalue = function(value) return value == 19834 end
    ns:OnEvent("UNIT_SPELLCAST_FAILED", "player", "Synthetic", 19834)
    eq(#state.sounds, 0); eq(#state.notices, 0)
    _G.issecretvalue = function() return false end
    ns:OnEvent("UNIT_SPELLCAST_FAILED", "player", "Synthetic", 19834)
    ns:OnEvent("UNIT_SPELLCAST_FAILED", "player", "Synthetic", 19834)
    eq(#state.sounds, 1); eq(#state.notices, 1); eq(ns.db.diagnostics.failed, 1)
    assert(state.notices[1]:find("fehlgeschlagen", 1, true))
end)
test("feedback_sound_setting_defaults_on_and_can_be_disabled_without_losing_text", function()
    local ns, state = setup({sound = "invalid"})
    eq(ns.db.sound, true)
    ns:Command("sound off")
    state.context.target.exists = false
    click(state)
    eq(ns.db.sound, false); eq(#state.sounds, 0); eq(#state.notices, 1)
    local restored = setup(ns.db)
    eq(restored.db.sound, false, "Explicit off survives reload")
end)
test("feedback_sound_test_is_explicit_and_does_not_cast", function()
    local ns, state = setup()
    ns:Command("soundtest")
    eq(#state.sounds, 1); eq(#state.actions, 0)
    ns:Command("sound off"); ns:Command("soundtest")
    eq(#state.sounds, 1)
    ns:Command("sound on"); ns:Command("soundtest")
    eq(#state.sounds, 2)
end)
test("feedback_broken_sound_api_preserves_text_and_action_cleanup", function()
    for _, failure in ipairs({"missing", "throw", "false", "secret"}) do
        local ns, state = setup()
        local marker = {}
        if failure == "missing" then _G.PlaySound = nil
        elseif failure == "throw" then _G.PlaySound = function() error("private raw error") end
        elseif failure == "secret" then
            _G.PlaySound = function() return marker end
            _G.issecretvalue = function(value) return value == marker end
        else _G.PlaySound = function() return false end end
        state.context.target.exists = false
        click(state)
        eq(#state.notices, 1); eq(#state.actions, 0)
        eq(ns.button:GetAttribute("*type1"), nil)
        assert(table.concat(ns.logs, ","):find("SOUND_FAILED", 1, true))
        assert(not table.concat(state.logs, ","):find("private raw error", 1, true))
    end
end)
test("feedback_missing_ui_or_clock_preserves_chat_without_repeated_sound", function()
    local ns, state = setup()
    _G.GetTime = nil
    _G.UIErrorsFrame = nil
    state.context.target.exists = false
    click(state); click(state)
    eq(#state.sounds, 1)
    assert(state.logs[1]:find(ns.decision.text, 1, true))
    assert(table.concat(ns.logs, ","):find("FEEDBACK_CLOCK_UNAVAILABLE", 1, true))
end)

test("combat_learned_kings_casts_on_same_key_without_dynamic_target_reads", function()
    local ns, state = setup()
    state.kingsKnown = true
    ns:OnEvent("SPELLS_CHANGED")
    state.locked = true
    local reads, writes = state.reads, state.attributeWrites
    click(state)
    eq(#state.actions, 1, "Learned Kings must work on the existing key during combat")
    eq(state.actions[1].spellID, 20217); eq(state.actions[1].unit, "mouseover")
    eq(state.reads, reads); eq(state.attributeWrites, writes)
    eq(#state.sounds, 0); eq(#state.notices, 0)
end)
test("combat_unlearned_kings_explains_waiting_without_a_fallback", function()
    local ns, state = setup()
    state.locked = true
    click(state)
    eq(#state.actions, 0); eq(#state.sounds, 1)
    assert(state.notices[1]:find("Könige", 1, true))
    assert(state.notices[1]:find("gelernt", 1, true))
end)
test("combat_disable_is_deferred_until_unlock_and_reported_honestly", function()
    local ns, state = setup()
    state.kingsKnown = true
    ns:OnEvent("SPELLS_CHANGED")
    state.locked = true
    local writes = state.attributeWrites
    ns:Command("off")
    eq(state.attributeWrites, writes)
    assert(table.concat(state.logs, " "):find("nach dem Kampf", 1, true))
    click(state); eq(#state.actions, 1, "Combat binding stays fixed until unlock")
    state.locked = false
    ns:OnEvent("PLAYER_REGEN_ENABLED")
    state.locked = true
    click(state); eq(#state.actions, 1, "Deferred disable must apply after unlock")
end)
test("combat_spell_changes_wait_for_unlock_and_no_spells_cast_from_events", function()
    local ns, state = setup()
    state.locked = true
    state.kingsKnown = true
    local writes = state.attributeWrites
    ns:OnEvent("SPELLS_CHANGED")
    eq(state.attributeWrites, writes); eq(#state.actions, 0)
    click(state); eq(#state.actions, 0)
    state.locked = false
    ns:OnEvent("PLAYER_REGEN_ENABLED")
    eq(#state.actions, 0)
    state.locked = true
    click(state); eq(#state.actions, 1); eq(state.actions[1].spellID, 20217)
end)

-- End-to-end offline event forwarding: load the real whisper module as well.
-- Names below are synthetic; only the final native send boundary is captured.
local function enableWhisperFixture(ns, state)
    state.messages = {}
    _G.UnitFullName = function(unit) return unit == "player" and "Paladin" or "Example", "TestRealm" end
    _G.UnitIsPlayer = function() return true end
    _G.UnitCanAssist = function() return true end
    _G.GetNormalizedRealmName = function() return "TestRealm" end
    _G.RegionalUniqueNamesEnabled = function() return false end
    _G.UnitRace, _G.UnitSex = nil, nil
    _G.UnitClass = function() return "Paladin","PALADIN" end
    _G.canaccesstable = function() return true end
    _G.Enum = {SpellBookSpellBank = {Player = 0}}
    _G.C_SpellBook = {IsSpellKnown = function() return true end}
    _G.C_ChatInfo = {SendChatMessage = function(message, channel, language, target)
        state.messages[#state.messages + 1] = {message = message, channel = channel, target = target}
    end}
    ns.Recipient = {Request = function(_, _, callback) callback(true); return true end}
    assert(loadfile("src/ForeverMouseoverBuff/GreetingCatalog.lua"))("ForeverMouseoverBuff", ns)
    assert(loadfile("src/ForeverMouseoverBuff/Greetings.lua"))("ForeverMouseoverBuff", ns)
    assert(loadfile("src/ForeverMouseoverBuff/Whisper.lua"))("ForeverMouseoverBuff", ns)
end
test("whisper_real_module_receives_ooc_and_combat_cast_events_only_after_click", function()
    for _, combat in ipairs({false, true}) do
        local ns, state = setup()
        enableWhisperFixture(ns, state)
        if combat then
            state.kingsKnown = true
            ns:OnEvent("SPELLS_CHANGED")
            state.locked = true
        end
        local id = combat and 20217 or 19834
        ns:Refresh(); eq(#state.messages, 0)
        click(state); eq(#state.messages, 0)
        ns:OnEvent("UNIT_SPELLCAST_SENT", "player", "Example-TestRealm", "Cast-1", id)
        eq(#state.messages, 0)
        ns:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", id)
        eq(#state.messages, 1)
        eq(state.messages[1].message, '[Forever Mouseover Buff] "Das Licht sei mit Euch, Example!" - Paladin')
        eq(state.messages[1].target, "Example-TestRealm")
        ns:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", id)
        eq(#state.messages, 1)
        assert(not table.concat(ns.logs, ","):find("Example", 1, true))
    end
end)
test("whisper_off_command_preserves_casting_and_prevents_pending_message", function()
    local ns, state = setup()
    enableWhisperFixture(ns, state)
    click(state)
    ns:OnEvent("UNIT_SPELLCAST_SENT", "player", "Example-TestRealm", "Cast-1", 19834)
    ns:Command("whisper off")
    eq(ns.db.whisper, false, "User can switch automatic whispers off")
    ns:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 19834)
    eq(#state.messages, 0); eq(#state.actions, 1)
    local restored = setup(ns.db)
    eq(restored.db.whisper, false)
end)
test("whisper_camelot_full_names_pass_through_complete_app_event_flow", function()
    local ns, state = setup()
    enableWhisperFixture(ns, state)
    _G.RegionalUniqueNamesEnabled = function() return true end
    _G.NameUtil = {GetUnmodifiedUnitFullName = function(unit)
        return unit == "player" and "Paladin Tester" or "Example Recipient"
    end}
    click(state)
    ns:OnEvent("UNIT_SPELLCAST_SENT", "player", "Example Recipient", "Cast-2", 19834)
    ns:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 19834)
    eq(#state.messages, 1)
    eq(state.messages[1].message, '[Forever Mouseover Buff] "Das Licht sei mit Euch, Example Recipient!" - Paladin Tester')
    eq(state.messages[1].target, "Example Recipient")
end)
test("seal_reminder_runs_on_player_aura_and_tick_without_casting_or_whispering", function()
    local ns, state = setup()
    local checks = 0
    ns.SealReminder = {Check = function() checks = checks + 1 end}
    ns:OnEvent("UNIT_AURA", "party1")
    eq(checks, 0)
    ns:OnEvent("UNIT_AURA", "player")
    eq(checks, 1, "Own aura events must update the seal reminder")
    ns:Tick(0.25)
    eq(checks, 2); eq(#state.actions, 0)
    ns:Command("seal off")
    eq(ns.db.sealSound, false)
    local restored = setup(ns.db)
    eq(restored.db.sealSound, false)
end)

test("receiver_setting_is_independent_persistent_and_available_to_non_paladins", function()
    local ns, state = setup()
    eq(ns.db.receiveWhispers, true, "default receive option")
    state.context.playerClass = "MAGE"
    ns:Command("receive off")
    eq(ns.db.receiveWhispers, false)
    eq(ns.db.whisper, true, "receiving preference must not change sending")
    eq(#state.actions, 0)
    assert(ns.receiveButton:GetText():find("aus", 1, true))
    local after = setup(ns.db)
    eq(after.db.receiveWhispers, false, "survive reload")
    after:Command("receive on")
    eq(after.db.receiveWhispers, true)
end)
test("recipient_network_and_late_chat_addon_events_are_forwarded_without_casting", function()
    local ns, state = setup()
    local calls, ticks, init = {}, 0, 0
    ns.Recipient = {OnMessage = function(...) calls = {...} end,
        Tick = function() ticks = ticks + 1 end}
    ns.Chat = {Initialize = function() init = init + 1 end}
    ns:OnEvent("CHAT_MSG_ADDON", "FMB_PREF1", "Q:1:123", "WHISPER", "Synthetic Sender")
    eq(calls[1], "FMB_PREF1"); eq(calls[4], "Synthetic Sender")
    ns:OnEvent("ADDON_LOADED", "WIM")
    eq(init, 1)
    ns:Tick(0.25); eq(ticks, 1)
    eq(#state.actions, 0)
end)

test("statistics_cast_tracking_starts_even_with_outgoing_whispers_off", function()
    local ns, state = setup({whisper = false})
    local tracked = 0
    ns.Whisper = {Begin = function(id) eq(id, 19834); tracked = tracked + 1 end}
    click(state)
    eq(tracked, 1, "shared cast tracking must be independent from the sending switch")
end)
test("statistics_command_shows_local_unverified_totals_and_families", function()
    local ns, state = setup()
    ns.Stats = {Summary = function() return {casterClass="PALADIN", total=42,
        families={might=30,wisdom=10,kings=2},spells={[19740]=30,[19742]=10,[20217]=2}} end}
    ns:Command("stats")
    local output = table.concat(state.logs," ")
    assert(output:find("42",1,true) and output:find("Macht: 30",1,true))
    assert(output:find("lokal",1,true) and output:find("unbestätigt",1,true))
    eq(#state.actions, 0)
end)

test("ranking_toggle_uses_export_module_and_reports_opt_in_state", function()
    local ns, state = setup()
    local values = {}
    ns.RankingExport = {SetEnabled = function(enabled)
        values[#values + 1] = enabled; ns.db.rankingEnabled = enabled; return true
    end}
    ns:Command("ranking on"); ns:Command("ranking off")
    eq(#values, 2); eq(values[1], true); eq(values[2], false)
    eq(ns.db.rankingEnabled, false); eq(#state.actions, 0)
    local output = table.concat(state.logs," ")
    assert(output:find("Export an",1,true) and output:find("Export aus",1,true))
end)

test("outgoing_chat_display_defaults_to_hidden_without_disabling_whispers", function()
    local ns, state = setup()
    eq(ns.db.showOutgoingWhispers, false)
    eq(ns.db.whisper, true); eq(ns.db.receiveWhispers, true)
    assert(ns.outgoingButton.text:find("aus", 1, true))
    assert(ns:Diagnostics():find("Eigene Grüße im Chat: aus", 1, true))
    eq(#state.actions, 0)
end)

test("outgoing_chat_toggle_persists_and_keeps_receiver_and_sender_controls_independent", function()
    local ns, state = setup({receiveWhispers = false, whisper = true})
    ns:Command("outgoing on")
    eq(ns.db.showOutgoingWhispers, true)
    eq(ns.db.receiveWhispers, false); eq(ns.db.whisper, true)
    local reloaded = setup(ns.db)
    eq(reloaded.db.showOutgoingWhispers, true)
    reloaded.outgoingButton.scripts.OnClick()
    eq(reloaded.db.showOutgoingWhispers, false)
    eq(reloaded.db.receiveWhispers, false); eq(reloaded.db.whisper, true)
    eq(#state.actions, 0)
end)

test("ranking_upload_help_and_export_control_are_visible_without_automatic_upload", function()
    local ns, state = setup()
    assert(ns.rankingButton, "ranking export control must be visible in the addon panel")
    assert(ns.uploadHelpButton, "upload help must be available next to export control")
    local requested = {}
    ns.RankingExport = {SetEnabled = function(value)
        requested[#requested + 1] = value; ns.db.rankingEnabled = value; return true
    end}
    ns.rankingButton.scripts.OnClick()
    eq(requested[1], true)
    assert(ns.rankingButton.text:find("an", 1, true))
    ns.uploadHelpButton.scripts.OnClick()
    eq(#requested, 1, "upload help must not enable or send anything")
    local output = table.concat(state.logs, " ")
    assert(output:find("JSON", 1, true) and output:find("unbestätigt", 1, true))
    assert(output:find("/reload", 1, true))
    eq(#state.actions, 0)
end)

test("counter_integrity_initializes_after_saved_database_and_diagnostics", function()
    local initialized = 0
    local ns, state = setup({}, {Stats = {Initialize = function()
        assert(type(ForeverMouseoverBuffDB.diagnostics) == "table")
        initialized = initialized + 1
        return true
    end}})
    eq(initialized, 1, "counter storage must be validated on login")
    ns:Initialize()
    eq(initialized, 1, "duplicate lifecycle must not remigrate")
    eq(#state.actions, 0)
end)
test("counter_integrity_failure_is_visible_at_login_without_reset", function()
    local original = {schema = 2, payload = "damaged", digest = "invalid"}
    local _, state = setup({buffStats = original}, {Stats = {Initialize = function() return false end}})
    assert(table.concat(state.logs, " "):find("Zählerspeicher", 1, true), "login must expose unavailable storage")
    eq(ForeverMouseoverBuffDB.buffStats, original, "preserve damaged evidence")
end)
test("counter_integrity_command_shows_unavailable_instead_of_fake_zero", function()
    local ns = setup()
    ns.Stats = {Summary = function() return {available=false, code="STATS_INTEGRITY_FAILED",
        total=0, families={might=0,wisdom=0,kings=0}} end}
    local previous = DEFAULT_CHAT_FRAME.AddMessage
    local messages = {}
    DEFAULT_CHAT_FRAME.AddMessage = function(_, text) messages[#messages + 1] = text end
    ns:Command("stats")
    DEFAULT_CHAT_FRAME.AddMessage = previous
    local output = table.concat(messages, " ")
    assert(output:find("nicht verfügbar",1,true), "statistics must expose unavailable state")
    assert(not output:find("0 Segen",1,true), "damaged data must not appear as zero")
end)

test("structured_diagnostics_persist_bounded_events_and_a_privacy_safe_snapshot", function()
    local ns, state = setup()
    ns:Log("STATS_INTEGRITY_FAILED")
    eq(ns.db.diagnostics.schema, 2, "structured diagnostics need the queryable schema")
    local record = ns.db.diagnostics.events[#ns.db.diagnostics.events]
    eq(record.code, "STATS_INTEGRITY_FAILED")
    eq(record.severity, "ERROR"); eq(record.origin, "STATS")
    eq(type(record.sequence), "number"); eq(record.timestamp, 1791810100)
    ns:Command("outgoing on")
    eq(ns.db.diagnostics.status.showOutgoingWhispers, true)
    eq(ns.db.diagnostics.status.clientBuild, "69913")
    eq(ns.db.diagnostics.status.binding, nil, "a key binding must not enter the persisted report")
    eq(#state.actions, 0)
end)

test("structured_diagnostics_command_reports_short_history_and_disk_freshness", function()
    local ns, state = setup()
    ns:Log("STATS_INTEGRITY_FAILED")
    ns:Command("diag")
    local output = table.concat(state.logs, "\n")
    assert(output:find("Diagnoseprotokoll", 1, true), "diag must be an available user command")
    assert(output:find("STATS_INTEGRITY_FAILED", 1, true), "latest failure must be visible")
    assert(output:find("/reload", 1, true), "file freshness must be explained")
    eq(#state.actions, 0); eq(#state.sounds, 0)
end)

test("structured_diagnostics_rejects_unknown_uppercase_identity_as_a_log_code", function()
    local ns = setup()
    ns:Log("SYNTHETIC_PRIVATE_PLAYER")
    assert(not table.concat(ns.logs, ","):find("SYNTHETIC_PRIVATE_PLAYER", 1, true),
        "uppercase shape alone is not a privacy-safe diagnostic allowlist")
    assert(table.concat(ns.logs, ","):find("DIAGNOSTIC_INVALID", 1, true))
end)

test("structured_diagnostics_unreadable_saved_history_does_not_block_the_ui_or_casts", function()
    local ns, state = setup()
    local inaccessible = {}
    ns.db.diagnostics = inaccessible
    _G.canaccesstable = function(value) return not rawequal(value, inaccessible) end
    ns:InitializeDiagnostics()
    ns:Command("diag")
    click(state)
    eq(#state.actions, 1, "diagnostic storage must remain an observer")
    eq(ns.db.diagnostics, inaccessible, "preserve unreadable history")
    assert(table.concat(state.logs, "\n"):find("Arbeitsspeicher", 1, true))
end)

local count, failures = 0, 0
for _, entry in ipairs(tests) do
    if not arg[1] or entry.name:find(arg[1], 1, true) then
        count = count + 1
        local ok, why = pcall(entry.run)
        if ok then print("PASS " .. entry.name) else failures = failures + 1; print("FAIL " .. entry.name .. ": " .. tostring(why)) end
    end
end
assert(count > 0, "No matching tests")
print(count .. " app tests, " .. failures .. " failures")
os.exit(failures == 0 and 0 or 1)
