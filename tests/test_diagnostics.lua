-- Purpose: exercise the bounded, privacy-safe diagnostic ledger without WoW.
-- Input: synthetic SavedVariables/clock guards. Output: deterministic PASS/FAIL.
-- Invariants: no account data, network, names, raw exceptions or unbounded input.
-- Debug: lua tests/test_diagnostics.lua [exact_test_name].
local tests = {}
local function equal(actual, expected, reason)
    assert(actual == expected, reason or "unexpected diagnostic result")
end
local function fixture(db)
    local f = {ns = {}, db = db or {}, now = 100, stamp = 1791810100}
    f.secret = setmetatable({}, {__tostring = function() error("secret printed") end})
    f.opaque = {}
    f.env = setmetatable({}, {__index = _G})
    f.env.issecretvalue = function(value) return rawequal(value, f.secret) end
    f.env.canaccesstable = function(value) return not rawequal(value, f.opaque) end
    f.env.GetTime = function() return f.now end
    f.env.GetServerTime = function() return f.stamp end
    f.env.UnitName = function() error("no identity read allowed") end
    f.env.UnitGUID = f.env.UnitName
    f.env.SendChatMessage = function() error("no message send allowed") end
    f.env.C_ChatInfo = {SendAddonMessage = f.env.SendChatMessage}
    local path = "src/ForeverMouseoverBuff/Diagnostics.lua"
    local handle = io.open(path, "rb")
    if handle then
        handle:close()
        local chunk
        if setfenv then chunk = assert(loadfile(path)); setfenv(chunk, f.env)
        else chunk = assert(loadfile(path, "t", f.env)) end
        chunk("ForeverMouseoverBuff", f.ns)
    end
    f.api = f.ns.DiagnosticLog
    return f
end
local function initialize(f)
    equal(type(f.api), "table", "structured local diagnostic ledger is not implemented")
    return f.api.Initialize(f.db, "0.7.2")
end

function tests.public_events_have_sequence_origin_severity_and_optional_server_time()
    local f = fixture(); assert(initialize(f))
    assert(f.api.Record("STATS_INTEGRITY_FAILED"))
    local saved = f.db.diagnostics
    equal(saved.schema, 2); equal(saved.version, "0.7.2")
    local event = saved.events[#saved.events]
    equal(event.code, "STATS_INTEGRITY_FAILED"); equal(event.origin, "STATS")
    equal(event.severity, "ERROR"); equal(event.timestamp, f.stamp)
    equal(event.sequence, saved.sequence)
    equal(saved.codes[#saved.codes], event.code)
end

function tests.event_registration_failure_before_login_survives_database_initialization()
    local f = fixture()
    equal(type(f.api), "table")
    f.api.Record("EVENT_UNAVAILABLE")
    assert(initialize(f))
    local found = false
    for _, event in ipairs(f.api.Snapshot().events) do
        if event.code == "EVENT_UNAVAILABLE" then found = true end
    end
    assert(found, "pre-login event registration failure must survive initialization")
end

function tests.different_events_are_bounded_and_sequences_survive_a_reload()
    local f = fixture(); initialize(f)
    for index = 1, 150 do
        f.now = f.now + 3; f.stamp = f.stamp + 3
        f.api.Record(index % 2 == 0 and "NO_TARGET" or "OUT_OF_RANGE")
    end
    equal(#f.db.diagnostics.events, 64)
    equal(#f.db.diagnostics.codes, 40)
    local previous = f.db.diagnostics.sequence
    local reloaded = fixture(f.db); initialize(reloaded)
    assert(reloaded.db.diagnostics.sequence > previous)
    local events = reloaded.db.diagnostics.events
    for index = 2, #events do assert(events[index].sequence > events[index - 1].sequence) end
end

function tests.poll_replays_are_deduplicated_and_per_code_events_are_throttled()
    local f = fixture(); initialize(f)
    f.api.Record("API_CALL_FAILED"); f.api.Record("API_AURAS_UNKNOWN")
    local initial = #f.api.Snapshot().events
    for _ = 1, 100 do
        f.api.Record("API_CALL_FAILED"); f.api.Record("API_AURAS_UNKNOWN")
    end
    equal(#f.api.Snapshot().events, initial)
    f.now = f.now + 3
    f.api.Record("API_CALL_FAILED")
    equal(#f.api.Snapshot().events, initial + 1)
    f.api.Record("API_CALL_FAILED")
    equal(#f.api.Snapshot().events, initial + 1)
end

function tests.missing_or_secret_clocks_do_not_block_logging_or_leak_values()
    local f = fixture(); initialize(f)
    f.env.GetTime = nil; f.env.GetServerTime = function() return f.secret end
    f.api.Record("SEAL_SOUND_FAILED")
    local first = f.api.Snapshot()
    equal(first.events[#first.events].timestamp, nil)
    for _ = 1, 20 do f.api.Record("SEAL_IDLE"); f.api.Record("SEAL_SOUND_FAILED") end
    equal(#f.api.Snapshot().events, #first.events + 1)
end

function tests.code_allowlist_discards_names_guids_payloads_and_unknown_uppercase_values()
    local f = fixture(); initialize(f)
    for _, value in ipairs({"SYNTHETIC_PRIVATE_PLAYER", "Player-1-abc", "|Hspell:1|h",
        "private exception", string.rep("A", 10000), {}, f.secret}) do
        f.api.Record(value)
    end
    local snapshot = f.api.Snapshot()
    equal(snapshot.codes[#snapshot.codes], "DIAGNOSTIC_INVALID")
    for _, event in ipairs(snapshot.events) do
        assert(event.code == "DIAGNOSTIC_STARTED" or event.code == "DIAGNOSTIC_INVALID")
        for key in pairs(event) do
            assert(key == "sequence" or key == "code" or key == "origin"
                or key == "severity" or key == "timestamp", "unexpected persistent event field")
        end
    end
end

function tests.legacy_codes_and_counters_migrate_without_unbounded_or_metatable_reads()
    local old = {codes = {"AURA_UNKNOWN", "PRIVATE_PLAYER", "API_RESTRICTED"},
        attempts = 8, confirmed = 5, failed = -1, player = "private"}
    setmetatable(old, {__index = function() error("metatable read") end,
        __pairs = function() error("unknown enumeration") end})
    local f = fixture({diagnostics = old}); initialize(f)
    equal(f.db.diagnostics.attempts, 8); equal(f.db.diagnostics.confirmed, 5)
    equal(f.db.diagnostics.failed, 0); equal(f.db.diagnostics.player, nil)
    assert(table.concat(f.db.diagnostics.codes, ","):find("AURA_UNKNOWN", 1, true))
    assert(not table.concat(f.db.diagnostics.codes, ","):find("PRIVATE_PLAYER", 1, true))
end

function tests.schema_two_import_validates_fields_instead_of_trusting_event_metadata()
    local old = {schema = 2, sequence = 9, attempts = 2, codes = {"CAST_CONFIRMED"},
        events = {{sequence = 8, code = "CAST_CONFIRMED", severity = "private", origin = "Name", timestamp = 1791810000},
            {sequence = 9, code = "UPPERCASE_PRIVATE_NAME", timestamp = 1791810001}}}
    local f = fixture({diagnostics = old}); initialize(f)
    local events = f.db.diagnostics.events
    equal(events[1].code, "CAST_CONFIRMED"); equal(events[1].origin, "APP")
    equal(events[1].severity, "INFO"); equal(events[1].timestamp, 1791810000)
    for _, event in ipairs(events) do assert(event.code ~= "UPPERCASE_PRIVATE_NAME") end
    equal(f.db.diagnostics.attempts, 2)
end

function tests.unknown_schema_or_inaccessible_history_stays_untouched_but_ui_snapshot_works()
    local f = fixture(); initialize(f)
    for _, history in ipairs({{schema = 99}, f.secret, f.opaque}) do
        f.db.diagnostics = history
        equal(f.api.Initialize(f.db, "0.7.2"), false)
        f.api.Record("CAST_REQUESTED")
        equal(f.db.diagnostics, history, "do not replace unavailable or newer data")
        equal(type(f.api.Snapshot().events), "table")
    end
end

function tests.readonly_database_and_failed_guards_keep_bounded_runtime_diagnostics()
    local f = fixture()
    local realRawset = f.env.rawset
    f.env.rawset = function(tableValue, key, value)
        if tableValue == f.db then error("private read-only failure") end
        return realRawset(tableValue, key, value)
    end
    equal(initialize(f), false)
    f.api.Record("CAST_FAILED")
    equal(type(f.api.Snapshot().events), "table")
    equal(f.api.Snapshot().storageAvailable, false)
    f.env.issecretvalue = false
    equal(f.api.Initialize(f.db, "0.7.2"), false)
    equal(type(f.api.Snapshot()), "table")
end

function tests.numeric_counters_are_bounded_and_only_known_keys_can_increment()
    local f = fixture({diagnostics = {attempts = 1000000000, confirmed = 1, failed = "bad"}})
    initialize(f)
    equal(f.api.Increment("attempts"), 1000000000)
    equal(f.api.Increment("confirmed"), 2); equal(f.api.Increment("failed"), 1)
    equal(f.api.Increment("PLAYER_PRIVATE"), nil)
    equal(f.db.diagnostics.PLAYER_PRIVATE, nil)
end

function tests.snapshot_is_detached_and_status_only_accepts_known_public_values()
    local f = fixture(); initialize(f)
    f.api.UpdateStatus({enabled = true, whisper = false, rankingEnabled = true,
        clientVersion = "1.60.1", clientBuild = "70338", clientInterface = 16001,
        binding = "ALT-X", target = "Private", debug = f.secret, sound = "yes"})
    local snapshot = f.api.Snapshot()
    equal(snapshot.status.enabled, true); equal(snapshot.status.whisper, false)
    equal(snapshot.status.rankingEnabled, true); equal(snapshot.status.clientBuild, "70338")
    equal(snapshot.status.clientInterface, 16001); equal(snapshot.status.binding, nil)
    equal(snapshot.status.target, nil); equal(snapshot.status.debug, nil); equal(snapshot.status.sound, nil)
    snapshot.events[1].code = "PRIVATE"; snapshot.codes[1] = "PRIVATE"
    snapshot.status.clientBuild = "PRIVATE"
    assert(f.api.Snapshot().events[1].code ~= "PRIVATE")
    equal(f.api.Snapshot().status.clientBuild, "70338")
end

local names = {}
for name in pairs(tests) do if not arg[1] or arg[1] == name then names[#names + 1] = name end end
assert(#names > 0, "unknown test filter"); table.sort(names)
local failures = 0
for _, name in ipairs(names) do
    local ok, errorText = pcall(tests[name])
    if ok then print("PASS " .. name)
    else failures = failures + 1; print("FAIL " .. name .. ": " .. errorText) end
end
print(string.format("Diagnostics: %d passed, %d failed", #names - failures, failures))
if failures > 0 then os.exit(1) end
