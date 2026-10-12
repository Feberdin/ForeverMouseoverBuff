-- Purpose: verify natural seal-expiry sounds against the real reminder module.
-- Input: synthetic public/secret aura and clock boundaries; no player data.
-- Output: deterministic named PASS/FAIL lines and nonzero status on failure.
-- Invariants: no game, network, whispers, spell casts, or filesystem writes.
-- Debug: lua tests/test_seal_reminder.lua [test_name_substring].
local tests = {}
local function test(name, run) tests[#tests + 1] = {name = name, run = run} end
local function equal(actual, expected, reason)
    assert(actual == expected, (reason or "value") .. ": expected " .. tostring(expected)
        .. ", got " .. tostring(actual))
end
local function fixture()
    local state = {now = 100, auras = {}, sounds = 0, scans = 0, logs = {},
        class = "PALADIN", restricted = false}
    local env = setmetatable({}, {__index = _G})
    local secret = setmetatable({}, {
        __tostring = function() error("secret printed") end,
        __add = function() error("secret added") end,
        __sub = function() error("secret subtracted") end,
        __lt = function() error("secret compared") end,
        __le = function() error("secret compared") end,
    })
    local opaque = setmetatable({}, {__index = function() error("opaque indexed") end})
    state.secret, state.opaque, state.env = secret, opaque, env
    env.issecretvalue = function(value) return rawequal(value, secret) end
    env.canaccesstable = function(value) return not rawequal(value, opaque) end
    env.GetTime = function() return state.now end
    env.UnitClass = function(unit)
        equal(unit, "player", "Only the local player class may be read")
        return "Paladin", state.class
    end
    state.names = {
        [20154] = "Siegel der Rechtschaffenheit", [21084] = "Siegel der Rechtschaffenheit",
        [20164] = "Siegel der Gerechtigkeit", [20165] = "Siegel des Lichts",
        [20166] = "Siegel der Weisheit", [21082] = "Siegel des Kreuzfahrers",
        [20375] = "Siegel des Befehls",
    }
    env.C_Spell = {
        GetSpellName = function(id) return state.names[id] end,
        GetSpellInfo = function(id)
            return state.names[id] and {name = state.names[id]} or nil
        end,
    }
    env.C_Secrets = {ShouldAurasBeSecret = function() return state.restricted end}
    env.C_UnitAuras = {GetAuraDataByIndex = function(unit, index, filter)
        equal(unit, "player", "Never query another player's auras")
        equal(filter, "HELPFUL")
        state.scans = state.scans + 1
        return state.auras[index]
    end}
    env.CastSpellByID = function() error("Reminder cannot cast spells") end
    env.SendChatMessage = function() error("Reminder cannot send chat or whispers") end
    env.UnitName = function() error("Reminder cannot read names") end
    env.UnitGUID = function() error("Reminder cannot read GUIDs") end
    local ns = {db = {sealSound = true, sound = false}}
    function ns:Log(code) state.logs[#state.logs + 1] = code end
    function ns:PlayFeedbackSound() state.sounds = state.sounds + 1; return true end
    local chunk
    if setfenv then
        chunk = assert(loadfile("src/ForeverMouseoverBuff/SealReminder.lua"))
        setfenv(chunk, env)
    else
        chunk = assert(loadfile("src/ForeverMouseoverBuff/SealReminder.lua", "t", env))
    end
    chunk("ForeverMouseoverBuff", ns)
    state.ns = ns
    function state:check() ns.SealReminder.Check() end
    -- Model the actual quarter-second polling while the current aura snapshot
    -- remains unchanged. This advances no wall clock and weakens no assertion.
    function state:observeUntil(stamp)
        assert(stamp >= self.now, "Synthetic observations cannot go backwards")
        while self.now + 0.25 <= stamp do
            self.now = self.now + 0.25
            self:check()
        end
        if self.now < stamp then self.now = stamp; self:check() end
    end
    function state:seal(id, expiry, duration, name)
        self.auras = {{spellId = id or 21084, name = name or "Siegel der Rechtschaffenheit",
            expirationTime = expiry or 130, duration = duration or 30}}
    end
    return state
end

test("observed_natural_expiry_plays_once_even_with_duplicate_event_and_poll", function()
    local f = fixture()
    f:seal(); f:check()
    equal(f.sounds, 0, "An active seal is silent")
    f:observeUntil(129.75)
    f.now, f.auras = 130, {}
    f:check(); f:check(); f:check()
    equal(f.sounds, 1, "The observed seal's natural expiry must request exactly one sound")
end)

test("long_observation_gap_discards_stale_expiry_without_catchup_sound", function()
    local f = fixture()
    f:seal(21084, 130, 30); f:check()
    f.now, f.auras = 10000, {}
    f:check(); f:check()
    equal(f.sounds, 0, "Returning from sleep/loading must not play an old expiry reminder")
end)

test("two_second_gap_boundary_preserves_recent_observations_only", function()
    for _, elapsed in ipairs({2, 2.01}) do
        local f = fixture()
        f:seal(21084, 100 + elapsed, 30); f:check()
        f.now, f.auras = 100 + elapsed, {}; f:check()
        equal(f.sounds, elapsed == 2 and 1 or 0,
            "Observation gaps greater than two seconds must discard the old seal")
    end
end)

test("after_long_gap_current_active_seal_is_observed_as_a_new_seal", function()
    local f = fixture()
    f:seal(); f:check()
    f.now = 10000
    f:seal(21084, 10001, 30); f:check()
    equal(f.sounds, 0, "Resuming with a new active seal must not announce the old one")
    f.now, f.auras = 10001, {}; f:check(); f:check()
    equal(f.sounds, 1, "A freshly observed current seal can still expire normally")
end)

test("login_without_seal_and_unrelated_buff_are_silent", function()
    local f = fixture()
    f:check()
    f.auras = {{spellId = 19740, name = "Segen der Macht", duration = 300, expirationTime = 400}}
    f:check()
    f.now, f.auras = 400, {}
    f:check()
    equal(f.sounds, 0)
end)

test("early_removal_or_judgement_never_warns_at_the_old_deadline", function()
    for _, removedAt in ipairs({110, 129.99}) do
        local f = fixture()
        f:seal(); f:check()
        f:observeUntil(removedAt - 0.25)
        f.now, f.auras = removedAt, {}
        f:check()
        equal(f.ns.SealReminder.LastCode, "SEAL_REMOVED_EARLY")
        f:observeUntil(131)
        equal(f.sounds, 0, "Disappearance before the public deadline must discard the old seal")
    end
end)

test("refresh_or_replacement_uses_only_the_new_expiry", function()
    local f = fixture()
    f:seal(); f:check()
    f:observeUntil(120)
    f:seal(20375, 150, 30, "Siegel des Befehls"); f:check()
    f:observeUntil(131)
    equal(f.sounds, 0, "Replacing a seal must not alarm at the old deadline")
    f:observeUntil(149.75)
    f.now, f.auras = 150, {}; f:check()
    equal(f.sounds, 1)
end)

test("remaining_aura_at_deadline_is_not_missing_and_can_expire_next_poll", function()
    local f = fixture()
    f:seal(); f:check()
    f:observeUntil(130)
    equal(f.sounds, 0, "A timer alone must never emit the reminder")
    f.now, f.auras = 130.25, {}; f:check()
    equal(f.sounds, 1)
end)

test("disabling_discards_tracking_and_is_independent_of_buff_error_sound", function()
    local f = fixture()
    f:seal(); f:check()
    f.ns.db.sealSound = false; f:check()
    f.now, f.auras = 131, {}; f:check()
    f.ns.db.sealSound = true; f:check()
    equal(f.sounds, 0, "Re-enabling must not resurrect an expired tracked seal")
    f:seal(21084, 161, 30); f:check()
    f:observeUntil(160.75)
    f.now, f.auras = 161, {}; f:check()
    equal(f.sounds, 1, "db.sound=false must not disable the distinct seal reminder")
end)

test("unknown_or_secret_aura_snapshot_discards_previous_deadline", function()
    for _, kind in ipairs({"secret", "opaque", "restricted", "throw", "bad_field", "no_guard"}) do
        local f = fixture()
        f.now = 129
        f:seal(); f:check()
        f.now = 129.5
        if kind == "secret" then f.auras = {f.secret}
        elseif kind == "opaque" then f.auras = {f.opaque}
        elseif kind == "restricted" then f.restricted = true
        elseif kind == "throw" then f.env.C_UnitAuras.GetAuraDataByIndex = function() error("private engine error") end
        elseif kind == "bad_field" then f.auras[1].spellId = f.secret
        else f.env.canaccesstable = nil end
        f:check()
        f.env.canaccesstable = function() return true end
        f.env.C_UnitAuras.GetAuraDataByIndex = function() return nil end
        f.restricted = false
        f.now, f.auras = 131, {}; f:check()
        equal(f.sounds, 0, kind .. " must discard prior tracking")
        assert(not table.concat(f.logs, ","):find("private", 1, true))
    end
end)

test("secret_clock_or_expiry_never_reaches_arithmetic_or_sound", function()
    for _, field in ipairs({"clock", "expirationTime", "duration"}) do
        local f = fixture()
        f.now = 129
        f:seal()
        if field == "clock" then f.now = f.secret else f.auras[1][field] = f.secret end
        f:check()
        f.now, f.auras = 131, {}; f:check()
        equal(f.sounds, 0, field)
    end
end)

test("missing_or_throwing_api_does_not_emit_or_keep_stale_tracking", function()
    for _, name in ipairs({"GetTime", "UnitClass", "C_UnitAuras", "C_Spell", "issecretvalue"}) do
        local f = fixture()
        f.now = 129
        f.env[name] = nil
        f:seal(); f:check()
        f.now, f.auras = 131, {}; f:check()
        equal(f.sounds, 0, name)
    end
    local f = fixture()
    f.now = 129
    f:seal(); f:check()
    f.env.GetTime = function() error("private clock exception") end
    f:check()
    f.env.GetTime = function() return 131 end
    f.auras = {}; f:check()
    equal(f.sounds, 0)
    assert(not table.concat(f.logs, ","):find("private", 1, true))
end)

test("throwing_localized_name_read_is_not_accepted_as_spell_label", function()
    local f = fixture()
    f.now = 129
    f.env.C_Spell.GetSpellName = function() error("private metadata exception") end
    f.env.C_Spell.GetSpellInfo = nil
    f:seal(); f:check()
    f.now, f.auras = 130, {}; f:check()
    equal(f.sounds, 0, "A caught API exception cannot become a valid cached localized label")
    assert(not table.concat(f.logs, ","):find("private", 1, true))
end)

test("non_paladin_and_unknown_class_are_silent", function()
    for _, value in ipairs({"MAGE", false}) do
        local f = fixture()
        f.class = value
        f:seal(); f:check()
        f.now, f.auras = 131, {}; f:check()
        equal(f.sounds, 0)
        equal(f.scans, 0, "Do not inspect seal auras without a public Paladin class")
    end
end)

test("all_supported_classic_seals_and_localized_future_rank_are_detected", function()
    local examples = {
        {20154, "Siegel der Rechtschaffenheit"}, {20293, "Siegel der Rechtschaffenheit"},
        {20164, "Siegel der Gerechtigkeit"}, {20349, "Siegel des Lichts"},
        {20357, "Siegel der Weisheit"}, {20308, "Siegel des Kreuzfahrers"},
        {20920, "Siegel des Befehls"}, {999991, "Siegel des Befehls"},
    }
    for _, sample in ipairs(examples) do
        local f = fixture()
        f:seal(sample[1], 130, 30, sample[2]); f:check()
        f:observeUntil(129.75)
        f.now, f.auras = 130, {}; f:check()
        equal(f.sounds, 1, "Supported seal " .. sample[1])
    end
end)

test("aura_limit_requires_proven_clean_end_before_an_expiry_alarm", function()
    local f = fixture()
    f:seal(); f:check()
    f:observeUntil(129.75)
    f.now = 130
    f.env.C_UnitAuras.GetAuraDataByIndex = function(_, index)
        return {spellId = 100000 + index, name = "Unrelated aura"}
    end
    local before = f.scans
    f:check()
    equal(f.sounds, 0)
    f.env.C_UnitAuras.GetAuraDataByIndex = function() return nil end
    f:check()
    equal(f.sounds, 0, "Truncated aura scan must discard the prior seal")
end)

test("first_seen_expired_or_future_start_aura_cannot_arm_false_reminder", function()
    for _, expiry in ipairs({99, 100, 140}) do
        local f = fixture()
        f:seal(21084, expiry, 30); f:check()
        equal(f.ns.SealReminder.LastCode, "SEAL_TIMING_UNKNOWN",
            "Impossible initial timing must be rejected before any polling gap")
        f.now, f.auras = 101, {}; f:check()
        equal(f.sounds, 0, "Only an actually active previously seen seal may arm a reminder")
    end
end)

test("invalid_duration_expiry_and_nonfinite_numbers_are_not_armed", function()
    for _, value in ipairs({0, -1, math.huge, 0 / 0, "30"}) do
        for _, field in ipairs({"duration", "expirationTime"}) do
            local f = fixture()
            f.now = 129
            f:seal(); f.auras[1][field] = value; f:check()
            equal(f.ns.SealReminder.LastCode, "SEAL_TIMING_UNKNOWN")
            f.now, f.auras = 131, {}; f:check()
            equal(f.sounds, 0, field)
        end
    end
end)

test("multiple_active_seals_are_ambiguous_and_do_not_schedule_guess", function()
    local f = fixture()
    f.now = 129
    f:seal()
    f.auras[2] = {spellId = 20375, name = "Siegel des Befehls", expirationTime = 130, duration = 30}
    f:check()
    f.now, f.auras = 131, {}; f:check()
    equal(f.sounds, 0)
end)

test("sound_boundary_failure_is_logged_once_without_retries_or_raw_error", function()
    local f = fixture()
    f.ns.PlayFeedbackSound = function() error("private sound failure") end
    f:seal(); f:check()
    f:observeUntil(129.75)
    f.now, f.auras = 130, {}; f:check(); f:check()
    equal(f.sounds, 0)
    local count = 0
    for _, code in ipairs(f.logs) do if code == "SEAL_SOUND_FAILED" then count = count + 1 end end
    equal(count, 1)
    assert(not table.concat(f.logs, ","):find("private", 1, true))
end)

local count, failed = 0, 0
for _, entry in ipairs(tests) do
    if not arg[1] or entry.name:find(arg[1], 1, true) then
        count = count + 1
        local ok, message = pcall(entry.run)
        if ok then print("PASS " .. entry.name)
        else failed = failed + 1; print("FAIL " .. entry.name .. ": " .. tostring(message)) end
    end
end
assert(count > 0, "No matching seal-reminder test")
print(string.format("Seal reminder: %d passed, %d failed", count - failed, failed))
os.exit(failed == 0 and 0 or 1)
