-- Purpose: verify reviewable GitHub issue links and their minimal data contract.
-- Input: synthetic diagnostic snapshots and guarded values; output: PASS/FAIL.
-- Invariants: no network, account data, SavedVariables writes or secret printing.
-- Debug: lua tests/test_feedback.lua [exact_test_name].
local tests = {}
local function equal(actual, expected, reason)
    assert(actual == expected, reason or "unexpected issue report result")
end
local function fixture()
    local f = {ns = {Feedback = function() return "existing cast feedback" end}}
    f.secret = setmetatable({}, {__tostring = function() error("secret printed") end})
    f.opaque = {}
    f.env = setmetatable({}, {__index = _G})
    f.env.issecretvalue = function(value) return rawequal(value, f.secret) end
    f.env.canaccesstable = function(value) return not rawequal(value, f.opaque) end
    f.env.SendChatMessage = function() error("reports must not send messages") end
    f.env.C_ChatInfo = {SendAddonMessage = f.env.SendChatMessage}
    local function loadModule(filename)
        local path = "src/ForeverMouseoverBuff/" .. filename
        local handle = io.open(path, "rb")
        if not handle then return end
        handle:close()
        local chunk
        if setfenv then chunk = assert(loadfile(path)); setfenv(chunk, f.env)
        else chunk = assert(loadfile(path, "t", f.env)) end
        chunk("ForeverMouseoverBuff", f.ns)
    end
    loadModule("Diagnostics.lua")
    loadModule("Feedback.lua")
    f.api = f.ns.IssueFeedback
    return f
end
local function build(f, kind, snapshot, includeTechnical)
    equal(type(f.api), "table", "reviewable GitHub issue link builder is not implemented")
    return f.api.Build(kind, snapshot, includeTechnical)
end
local function query(url)
    equal(url:match("^([^?]+)"), "https://github.com/Feberdin/ForeverMouseoverBuff/issues/new")
    local fields = {}
    for key, value in url:gmatch("[?&]([^=&]+)=([^&]*)") do
        fields[key] = value:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
    end
    return fields
end
local function snapshot()
    return {version = "0.7.3", mode = "auto", status = {clientVersion = "1.60.1",
        clientBuild = "70338", clientInterface = 16001, enabled = true, whisper = false,
        receiveWhispers = false, sound = true}, codes = {"READY", "CAST_REQUESTED", "CAST_CONFIRMED"}}
end

function tests.default_link_selects_bug_form_without_reading_diagnostic_data()
    local f = fixture()
    local private = setmetatable({}, {__index = function() error("snapshot was read") end,
        __pairs = function() error("snapshot was enumerated") end})
    local result = assert(build(f, "bug", private))
    equal(result.kind, "bug")
    equal(result.url, "https://github.com/Feberdin/ForeverMouseoverBuff/issues/new?template=01-bug.yml")
    equal(result.environment, nil); equal(result.diagnostics, nil)
    assert(result.preview:find("Keine technischen Angaben", 1, true))
    equal(f.ns.Feedback(), "existing cast feedback", "must not replace cast-feedback method")
end

function tests.all_report_types_select_their_matching_github_form()
    local f = fixture()
    for kind, filename in pairs({bug = "01-bug.yml", wish = "02-wish.yml", feature = "03-feature.yml"}) do
        local result = assert(build(f, kind, nil, false))
        equal(query(result.url).template, filename)
        equal(result.kind, kind)
    end
end

function tests.opted_in_fields_roundtrip_and_preview_matches_the_prefill_exactly()
    local f = fixture()
    local input = snapshot()
    local result = assert(build(f, "bug", input, true))
    local fields = query(result.url)
    equal(fields.environment, result.environment)
    equal(fields.diagnostics, result.diagnostics)
    equal(result.preview, result.environment .. "\n\n" .. result.diagnostics)
    assert(result.environment:find("Addon: 0.7.3", 1, true))
    assert(result.environment:find("WoW: 1.60.1", 1, true))
    assert(result.environment:find("Build: 70338", 1, true))
    assert(result.environment:find("Interface: 16001", 1, true))
    assert(result.environment:find("Modus: auto", 1, true))
    assert(result.environment:find("whisper=false", 1, true))
    assert(result.diagnostics:find("CAST_CONFIRMED", 1, true))
    assert(result.url:find("%%0A")); assert(result.url:find("%%3A"))
    assert(not result.url:find("[^%w%-%._~:/?&=%%]"), "link must contain only ASCII URL-safe bytes")
    equal(input.status.clientBuild, "70338"); equal(#input.codes, 3)
    equal(input.environment, nil, "report preparation must not mutate source snapshot")
end

function tests.privacy_allowlist_discards_names_messages_counters_unknown_codes_and_extra_fields()
    local f = fixture()
    local input = snapshot()
    input.player = "PRIVATE_PLAYER_CANARY"; input.whisper = "PRIVATE_WHISPER_CANARY"
    input.attempts = 987654321; input.confirmed = 987654321; input.failed = 987654321
    input.status.binding = "PRIVATE_BINDING_CANARY"; input.status.target = "PRIVATE_TARGET_CANARY"
    input.events = {{code = "API_CALL_FAILED", timestamp = 1987654321, player = "PRIVATE_EVENT_CANARY"}}
    input.codes = {"READY", "PRIVATE_CODE_CANARY", "CAST_CONFIRMED", "Player-1-private"}
    local result = assert(build(f, "bug", input, true))
    for _, value in ipairs({"PRIVATE_", "987654321", "1987654321", "Player-1-private", "API_CALL_FAILED"}) do
        assert(not result.preview:find(value, 1, true), "a field outside the allowlist reached preview")
        assert(not result.url:find(value, 1, true), "a field outside the allowlist reached link")
    end
    assert(result.diagnostics:find("READY", 1, true))
    assert(result.diagnostics:find("CAST_CONFIRMED", 1, true))
end

function tests.recent_unique_codes_are_limited_to_five_and_raw_sparse_input_has_a_fixed_read_budget()
    local f = fixture()
    local input = snapshot()
    input.codes = {"READY", "NO_TARGET", "CAST_REQUESTED", "CAST_FAILED", "CAST_CONFIRMED",
        "SEAL_IDLE", "SEAL_SOUND_FAILED", "SEAL_SOUND_FAILED"}
    input.codes[10000000] = "PRIVATE_FAR_INDEX"
    setmetatable(input.codes, {__len = function() error("unbounded length read") end,
        __index = function() error("metatable access") end,
        __pairs = function() error("enumeration") end})
    local result = assert(build(f, "bug", input, true))
    assert(not result.diagnostics:find("READY", 1, true))
    assert(not result.diagnostics:find("NO_TARGET", 1, true))
    for _, code in ipairs({"CAST_REQUESTED", "CAST_FAILED", "CAST_CONFIRMED", "SEAL_IDLE", "SEAL_SOUND_FAILED"}) do
        local _, count = result.diagnostics:gsub(code, "")
        equal(count, 1, "recent code must appear once")
    end
    assert(#result.url <= 6000, "report URL exceeded the public size contract")
end

function tests.secret_and_malformed_fields_are_omitted_without_stringification_or_arithmetic()
    local f = fixture()
    local input = snapshot()
    input.version = f.secret; input.mode = f.secret; input.status.clientVersion = f.secret
    input.status.clientBuild = f.secret; input.status.clientInterface = f.secret
    input.status.enabled = f.secret; input.codes = {f.secret, "API_RESTRICTED"}
    local result = assert(build(f, "bug", input, true))
    assert(not result.environment:find("Addon:", 1, true))
    assert(not result.environment:find("WoW:", 1, true))
    assert(not result.environment:find("Build:", 1, true))
    assert(not result.environment:find("Interface:", 1, true))
    assert(not result.environment:find("enabled=", 1, true))
    assert(result.diagnostics:find("API_RESTRICTED", 1, true))
    input.version = string.rep("9", 100000)
    input.mode = "auto&assignees=malicious"
    input.status.clientVersion = "PRIVATE_VERSION_CANARY"
    input.status.clientBuild = "70338&title=PRIVATE_TITLE_CANARY"
    input.status.clientInterface = math.huge
    input.status.enabled = "true"
    input.codes = {string.rep("A", 100000), "PRIVATE_CODE_CANARY"}
    result = assert(build(f, "feature", input, true))
    assert(not result.preview:find("PRIVATE_", 1, true))
    assert(not result.url:find("assignees", 1, true)); assert(not result.url:find("title=", 1, true))
    assert(#result.url <= 6000)
end

function tests.unknown_kinds_and_non_boolean_consent_fail_with_fixed_errors()
    local f = fixture()
    for _, kind in ipairs({"private-name", "Bug", {}, f.secret}) do
        local result, code = build(f, kind, nil, false)
        equal(result, nil); equal(code, "ISSUE_KIND_INVALID")
    end
    for _, consent in ipairs({"true", 1, {}, f.secret}) do
        local result, code = build(f, "bug", snapshot(), consent)
        equal(result, nil); equal(code, "ISSUE_OPTIONS_INVALID")
    end
end

function tests.missing_or_failed_guards_fail_closed_without_including_details()
    local f = fixture()
    f.env.issecretvalue = false
    local result, code = build(f, "bug", snapshot(), true)
    equal(result, nil); equal(code, "ISSUE_GUARD_UNAVAILABLE")
    f.env.issecretvalue = function() error("PRIVATE_ERROR_CANARY") end
    result, code = build(f, "bug", snapshot(), true)
    equal(result, nil); equal(code, "ISSUE_KIND_INVALID")
    f = fixture(); f.env.canaccesstable = false
    result, code = build(f, "bug", snapshot(), true)
    equal(result, nil); equal(code, "ISSUE_SNAPSHOT_UNAVAILABLE")
    assert(build(f, "bug", f.secret, false), "link without details must not read snapshot")
    f = fixture()
    for _, value in ipairs({f.secret, f.opaque, 9, "private"}) do
        result, code = build(f, "bug", value, true)
        equal(result, nil); equal(code, "ISSUE_SNAPSHOT_UNAVAILABLE")
    end
end

function tests.absent_diagnostic_catalog_never_exports_pattern_matching_private_codes()
    local f = fixture()
    f.ns.DiagnosticLog = nil
    local input = snapshot()
    input.codes = {"CAST_CONFIRMED", "PRIVATE_PLAYER_CANARY"}
    local result = assert(build(f, "bug", input, true))
    assert(not result.diagnostics:find("CAST_CONFIRMED", 1, true))
    assert(not result.diagnostics:find("PRIVATE_", 1, true))
    assert(result.diagnostics:find("Keine freigegebenen Diagnosecodes", 1, true))
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
print(string.format("Issue feedback: %d passed, %d failed", #names - failures, failures))
if failures > 0 then os.exit(1) end
