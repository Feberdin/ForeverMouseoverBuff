-- Purpose: verify actual local counters against a synthetic public-value boundary.
-- Input: synthetic saved data/cast IDs; output: deterministic PASS/FAIL lines.
-- Invariants: no real player data, game, network or reliance on table iteration order.
-- Debug: lua tests/test_stats.lua [test_name] from the project directory.
local tests = {}
local function equal(actual, expected, reason)
    assert(actual == expected, reason or "unexpected statistics result")
end
local ids = {
    might = {19740,19834,19835,19836,19837,19838,25291,27140,48931,48932},
    wisdom = {19742,19850,19852,19853,19854,25290,27142,48935,48936},
    kings = {20217},
}
local function fixture()
    local f = {logs = {}}
    f.secret = setmetatable({}, {__tostring = function() error("secret printed") end})
    f.opaque = setmetatable({}, {__index = function() error("opaque table read") end})
    local env = setmetatable({}, {__index = _G})
    f.env = env
    env.issecretvalue = function(value) return not not rawequal(value, f.secret) end
    env.canaccesstable = function(value) return not rawequal(value, f.opaque) end
    env.UnitClass = function() error("class scope must come from the correlated caller") end
    env.UnitName = function() error("no identity API allowed") end
    env.UnitGUID = env.UnitName
    env.SendChatMessage = function() error("no visible chat allowed") end
    env.C_ChatInfo = {SendAddonMessage = function() error("no network allowed") end}
    f.ns = {db = {}, Log = function(_, code) f.logs[#f.logs + 1] = code end}
    function f:reload()
        for _, name in ipairs({"Hash.lua", "CounterCodec.lua", "Stats.lua"}) do
            local path = "src/ForeverMouseoverBuff/" .. name
            local chunk
            if setfenv then chunk = assert(loadfile(path)); setfenv(chunk, self.env)
            else chunk = assert(loadfile(path, "t", self.env)) end
            chunk("ForeverMouseoverBuff", self.ns)
        end
        self.api = self.ns.Stats
    end
    function f:has(code)
        for _, item in ipairs(self.logs) do if item == code then return true end end
        return false
    end
    f:reload()
    return f
end

function tests.module_loading_has_no_game_network_or_saved_variable_side_effects()
    local f = fixture()
    equal(f.ns.db.buffStats, nil); equal(#f.logs, 0)
end
function tests.valid_legacy_history_migrates_to_encoded_storage_without_plaintext_counts()
    local f = fixture()
    local legacy = {schema = 1, spells = {[19740] = 7, [19742] = 3, [20217] = 4}}
    f.ns.db.buffStats = legacy
    equal(f.api.Total(), 14, "migration must preserve every known counter")
    local stored = f.ns.db.buffStats
    equal(stored.schema, 2, "valid history must migrate to encoded schema 2")
    equal(type(stored.payload), "string", "encoded payload must be saved")
    equal(type(stored.digest), "string", "integrity digest must be saved")
    equal(stored.spells, nil, "do not retain editable decimal counters in the database")
    equal(legacy.spells[19740], 7, "migration must not edit the original table in place")
    equal(f.api.Summary().families.kings, 4)
end
function tests.invalid_legacy_history_stays_untouched_and_does_not_claim_zero()
    local f = fixture()
    local legacy = {schema = 1, spells = {[19740] = 7, [20217] = "bad"}}
    f.ns.db.buffStats = legacy
    equal(f.api.Total(), nil, "invalid history must be unavailable, not a repaired partial total")
    equal(f.ns.db.buffStats, legacy, "preserve evidence instead of overwriting invalid history")
    equal(f.api.Record(20217, "Cast-invalid-history"), false)
    local summary = f.api.Summary()
    equal(summary.available, false)
    equal(summary.total, nil, "zero would falsely claim an empty valid history")
    equal(summary.error, "STATS_COUNT_INVALID")
end
function tests.new_local_history_starts_empty_without_importing_diagnostic_successes()
    local f = fixture(); f.ns.db.diagnostics = {confirmed = 923, attempts = 1300}
    equal(f.api.Total(), 0)
    equal(type(f.ns.db.buffStats), "table", "stats must start a dedicated history")
    equal(f.ns.db.buffStats.schema, 2); equal(f.ns.db.buffStats.spells, nil)
    equal(f.ns.db.diagnostics.confirmed, 923)
end
function tests.normal_blessing_ranks_aggregate_by_family_and_own_character()
    local f = fixture(); local index = 0
    for _, family in ipairs({"might", "wisdom", "kings"}) do
        for _, id in ipairs(ids[family]) do
            index = index + 1
            equal(f.api.Record(id, "Cast-test-" .. index), true, "known normal blessing must count")
        end
    end
    local summary = f.api.Summary()
    equal(summary.casterClass, "PALADIN"); equal(summary.total, 20); equal(f.api.Total(), 20)
    equal(summary.families.might, 10); equal(summary.families.wisdom, 9); equal(summary.families.kings, 1)
    for _, family in pairs(ids) do for _, id in ipairs(family) do equal(summary.spells[id], 1) end end
end
function tests.same_guid_cannot_count_twice_even_with_a_different_spell()
    local f = fixture()
    equal(f.api.Record(19740, "Cast-shared"), true)
    equal(f.api.Record(19740, "Cast-shared"), false)
    equal(f.api.Record(20217, "Cast-shared"), false)
    equal(f.api.Total(), 1); assert(f:has("STATS_DUPLICATE_CAST"))
end
function tests.distinct_casts_are_counted_and_whisper_flags_never_gate_statistics()
    local f = fixture(); f.ns.db.whisper = false; f.ns.db.receiveWhispers = false
    equal(f.api.Record(20217, "Cast-one"), true)
    equal(f.api.Record(20217, "Cast-two"), true)
    equal(f.api.Total(), 2)
end
function tests.unknown_greater_temporary_spells_and_invalid_ids_are_rejected()
    local f = fixture()
    for _, id in ipairs({25898,25782,25894,1022,1038,133,0,-1,1.5,1000000001,"20217",f.secret}) do
        equal(f.api.Record(id, "Cast-invalid"), false)
    end
    equal(f.api.Record(nil, "Cast-invalid"), false)
    equal(f.api.Record(0/0, "Cast-invalid"), false)
    equal(f.api.Total(), 0); assert(f:has("STATS_SPELL_INVALID"))
    equal(f.api.Record(20217, "Cast-invalid"), true, "invalid call must not consume a GUID")
end
function tests.guid_validation_prevents_secret_markup_unbounded_and_wrong_type_keys()
    local f = fixture()
    for _, value in ipairs({"", "Player-1", "Cast-", "Cast-has space", "Cast-|Hspell:1|h", "Cast-" .. string.rep("x", 201), 3, f.secret}) do
        equal(f.api.Record(20217, value), false)
    end
    equal(f.api.Record(20217, nil), false)
    equal(f.api.Total(), 0); assert(f:has("STATS_GUID_INVALID"))
end
function tests.reload_preserves_only_known_spell_counts_and_derives_all_sums()
    local f = fixture()
    f.ns.db.buffStats = {schema = 1, total = 900, casterClass = "MAGE", families = {kings = 900},
        spells = {[19740] = 2, [19742] = 3, [20217] = 5, [25898] = 99, ["20217"] = 100}}
    f:reload()
    local summary = f.api.Summary()
    equal(summary.total, 10); equal(summary.families.kings, 5)
    equal(summary.families.might, 2); equal(summary.families.wisdom, 3)
    equal(summary.casterClass, "PALADIN"); equal(summary.spells[25898], nil)
    equal(f.ns.db.buffStats.total, nil); equal(f.ns.db.buffStats.casterClass, nil)
    equal(f.ns.db.buffStats.spells, nil)
    equal(f.api.Record(20217, "Cast-after-reload"), true); equal(f.api.Total(), 11)
end
-- Invalid imported history is now preserved and unavailable as a whole. This
-- deliberately replaces the old partial-repair behavior that discarded evidence.
function tests.bad_known_counts_preserve_all_legacy_data_and_block_further_counting()
    local bad = {-1,1.5,1000000001,math.huge,-math.huge,"12",true,{},0/0}
    for _, value in ipairs(bad) do
        local f = fixture()
        local saved = {schema = 1, spells = {[19740] = 7, [20217] = value}}
        f.ns.db.buffStats = saved
        equal(f.api.Total(), nil)
        equal(f.api.Summary().available, false)
        equal(f.api.Record(20217, "Cast-invalid"), false)
        equal(f.ns.db.buffStats, saved)
        equal(saved.spells[19740], 7)
        assert(f:has("STATS_COUNT_INVALID"), "bad saved count must be diagnosable")
    end
    local f = fixture()
    local saved = {schema = 1, spells = {[19740] = 7, [20217] = f.secret}}
    f.ns.db.buffStats = saved
    equal(f.api.Total(), nil); equal(f.ns.db.buffStats, saved)
    assert(f:has("STATS_COUNT_RESTRICTED"))
end
function tests.summary_is_a_detached_deterministic_aggregate_not_a_write_handle()
    local f = fixture(); equal(f.api.Record(20217, "Cast-summary"), true)
    local a = f.api.Summary(); a.total = 55; a.spells[20217] = 100; a.families.kings = 100
    local b = f.api.Summary()
    equal(b.total, 1); equal(b.spells[20217], 1); equal(b.families.kings, 1)
    equal(b.spells[19740], 0)
end
function tests.counter_limit_never_overflows_and_rejected_cast_is_not_deduplicated()
    local f = fixture(); f.ns.db.buffStats = {schema = 1, spells = {[20217] = 1000000000}}
    equal(f.api.Total(), 1000000000)
    equal(f.api.Record(20217, "Cast-overflow"), false); assert(f:has("STATS_TOTAL_LIMIT"))
    equal(f.api.Total(), 1000000000)
    f.ns.db.buffStats = {schema = 1, spells = {[20217] = 0}}
    equal(f.api.Record(20217, "Cast-overflow"), true)
end
function tests.over_budget_legacy_counts_are_preserved_instead_of_partially_imported()
    local f = fixture()
    local saved = {schema = 1, spells = {[20217] = 2, [19740] = 999999999}}
    f.ns.db.buffStats = saved
    local summary = f.api.Summary()
    equal(summary.available, false); equal(summary.total, nil)
    equal(summary.error, "STATS_COUNT_OVER_BUDGET")
    equal(f.api.Record(20217, "Cast-over-budget"), false)
    equal(f.ns.db.buffStats, saved)
    assert(f:has("STATS_COUNT_OVER_BUDGET"))
end
function tests.schema_or_inaccessible_database_never_claims_history_or_overwrites_unknown_versions()
    local f = fixture(); local future = {schema = 99, spells = {[20217] = 8}}
    f.ns.db.buffStats = future
    equal(f.api.Record(20217, "Cast-future"), false); equal(f.api.Total(), nil)
    equal(f.ns.db.buffStats, future); assert(f:has("STATS_SCHEMA_UNSUPPORTED"))
    for _, kind in ipairs({"db_nil", "db_opaque", "stats_secret", "stats_opaque", "spells_opaque"}) do
        local g = fixture()
        if kind == "db_nil" then g.ns.db = nil
        elseif kind == "db_opaque" then g.ns.db = g.opaque
        elseif kind == "stats_secret" then g.ns.db.buffStats = g.secret
        elseif kind == "stats_opaque" then g.ns.db.buffStats = g.opaque
        else g.ns.db.buffStats = {schema = 1, spells = g.opaque} end
        equal(g.api.Record(20217, "Cast-unavailable"), false)
        equal(g.api.Total(), nil); assert(#g.logs > 0)
    end
end
function tests.malformed_legacy_structure_is_preserved_without_importing_old_diagnostics()
    for _, value in ipairs({false,"bad",4}) do
        local f = fixture(); f.ns.db.buffStats = value; f.ns.db.diagnostics = {confirmed = 80}
        equal(f.api.Total(), nil); equal(f.ns.db.buffStats, value)
        equal(f.api.Summary().available, false)
        assert(f:has("STATS_DATA_INVALID"))
        equal(f.api.Record(20217, "Cast-not-repaired"), false)
        equal(f.ns.db.buffStats, value)
    end
    local f = fixture(); local saved = {schema = 1, spells = false}
    f.ns.db.buffStats = saved
    equal(f.api.Total(), nil); equal(f.ns.db.buffStats, saved)
    assert(f:has("STATS_DATA_INVALID"))
end
function tests.unknown_nested_data_and_metatables_are_never_executed_or_traversed()
    local f = fixture()
    local bomb = setmetatable({}, {__index = function() error("unknown nested read") end, __pairs = function() error("unknown nested traversal") end})
    local spells = setmetatable({[20217] = 3, unknown = bomb}, {__index = function() error("inherited counter must not be read") end, __pairs = function() error("unbounded traversal") end})
    f.ns.db.buffStats = {schema = 1, spells = spells, unknown = bomb}
    equal(f.api.Total(), 3); equal(f.ns.db.buffStats.unknown, nil); equal(f.ns.db.buffStats.spells, nil)
end
function tests.guards_missing_failing_or_secret_results_fail_closed_and_recover()
    for _, kind in ipairs({"secret_missing","secret_throws","secret_wrong","access_missing","access_throws","access_secret"}) do
        local f = fixture()
        if kind == "secret_missing" then f.env.issecretvalue = false
        elseif kind == "secret_throws" then f.env.issecretvalue = function() error("private raw error") end
        elseif kind == "secret_wrong" then f.env.issecretvalue = function() return "false" end
        elseif kind == "access_missing" then f.env.canaccesstable = false
        elseif kind == "access_throws" then f.env.canaccesstable = function() error("private raw error") end
        else f.env.canaccesstable = function() return f.secret end end
        equal(f.api.Record(20217, "Cast-guard"), false); equal(f.api.Total(), nil)
        equal(f.ns.db.buffStats, nil); assert(#f.logs > 0)
        f.env.issecretvalue = function(value) return rawequal(value, f.secret) end
        f.env.canaccesstable = function(value) return not rawequal(value, f.opaque) end
        equal(f.api.Record(20217, "Cast-guard"), true)
        equal(f.api.Total(), 1)
    end
end
function tests.recent_guid_deduplication_is_bounded_to_128_and_never_persisted()
    local f = fixture()
    for index = 1, 129 do equal(f.api.Record(20217, "Cast-ring-" .. index), true) end
    equal(f.api.Record(20217, "Cast-ring-2"), false)
    equal(f.api.Record(20217, "Cast-ring-129"), false)
    equal(f.api.Record(20217, "Cast-ring-1"), true, "oldest GUID expires from bounded runtime window")
    equal(f.api.Total(), 130)
    local db = f.ns.db.buffStats
    for key in pairs(db) do assert(key == "schema" or key == "payload" or key == "digest", "unexpected persistent field") end
    equal(db.spells, nil); equal(type(db.payload), "string"); equal(type(db.digest), "string")
    equal(f.api.guids, nil); equal(f.api.completed, nil)
end
function tests.diagnostics_are_bounded_fixed_codes_and_do_not_break_valid_counting()
    local f = fixture()
    for _ = 1, 1000 do f.api.Record(999, "Cast-bad") end
    assert(#f.logs >= 1 and #f.logs <= 20, "repeated failures must have bounded diagnostic volume")
    for _, code in ipairs(f.logs) do assert(code:match("^STATS_[A-Z_]+$")) end
    f.ns.Log = function() error("private logger failure") end
    equal(f.api.Record(20217, "Cast-valid"), true); equal(f.api.Total(), 1)
    equal(f.api.LastCode, "STATS_LOG_FAILED")
end

function tests.initialize_migrates_once_and_read_only_queries_never_replace_storage()
    local f = fixture()
    f.ns.db.buffStats = {schema = 1, spells = {[19740] = 258, [20217] = 19}}
    equal(f.api.Initialize(), true)
    local encoded = f.ns.db.buffStats
    equal(encoded.schema, 2)
    local binary = assert(f.ns.CounterCodec.Decode(encoded))
    equal(#binary, 80)
    local a, b, c, d = string.byte(binary, 1, 4)
    equal(a, 0); equal(b, 0); equal(c, 1); equal(d, 2)
    equal(f.api.Total(), 277); equal(f.api.Summary().total, 277)
    equal(f.api.Initialize(), true); equal(f.ns.db.buffStats, encoded)
    f:reload()
    equal(f.api.Initialize(), true); equal(f.ns.db.buffStats, encoded)
    equal(f.api.Total(), 277); equal(f.ns.db.buffStats, encoded)
    assert(f:has("STATS_MIGRATED"))
end
function tests.new_storage_is_encoded_zero_and_does_not_copy_diagnostic_history()
    local f = fixture(); f.ns.db.diagnostics = {confirmed = 923}
    equal(f.api.Initialize(), true)
    equal(f.ns.CounterCodec.Decode(f.ns.db.buffStats), string.rep(string.char(0), 80))
    equal(f.api.Summary().available, true); equal(f.api.Total(), 0)
    equal(f.ns.db.diagnostics.confirmed, 923)
end
function tests.payload_or_digest_edits_make_history_unavailable_and_preserve_evidence()
    for _, field in ipairs({"payload", "digest"}) do
        local f = fixture(); assert(f.api.Record(20217, "Cast-valid"))
        local stored = f.ns.db.buffStats
        local original = stored[field]
        local replacement = field == "payload" and "A" or "0"
        if original:sub(1, 1) == replacement then replacement = field == "payload" and "B" or "1" end
        stored[field] = replacement .. original:sub(2)
        local changed = stored[field]
        equal(f.api.Total(), nil)
        local summary = f.api.Summary()
        equal(summary.available, false); equal(summary.total, nil)
        equal(summary.error, "STATS_INTEGRITY_FAILED")
        equal(f.api.Record(20217, "Cast-after-tamper"), false)
        equal(f.ns.db.buffStats, stored); equal(stored[field], changed)
        f:reload()
        equal(f.api.Initialize(), false); equal(f.ns.db.buffStats, stored)
        -- Restoring the exact valid value recovers without consuming failed GUIDs.
        stored[field] = original
        equal(f.api.Record(20217, "Cast-after-tamper"), true)
        equal(f.api.Total(), 2)
    end
end
function tests.invalid_encoded_words_remain_rejected_even_with_a_matching_checksum()
    local cases = {
        {string.char(255,255,255,255) .. string.rep(string.char(0), 76), "STATS_COUNT_INVALID"},
        {string.char(59,154,202,0,0,0,0,1) .. string.rep(string.char(0), 72), "STATS_COUNT_OVER_BUDGET"},
    }
    for _, case in ipairs(cases) do
        local f = fixture()
        local stored = assert(f.ns.CounterCodec.Encode(case[1]))
        f.ns.db.buffStats = stored
        equal(f.api.Total(), nil); equal(f.api.Summary().error, case[2])
        equal(f.api.Record(20217, "Cast-invalid-binary"), false)
        equal(f.ns.db.buffStats, stored)
    end
end
function tests.codec_absence_failure_and_roundtrip_mismatch_never_destroy_legacy_data()
    for _, kind in ipairs({"missing", "throwing", "bad_roundtrip"}) do
        local f = fixture()
        local original = {schema = 1, spells = {[20217] = 8}}
        f.ns.db.buffStats = original
        local codec = f.ns.CounterCodec
        if kind == "missing" then f.ns.CounterCodec = nil
        elseif kind == "throwing" then
            f.ns.CounterCodec = {Encode = function() error("private codec exception") end, Decode = codec.Decode}
        else
            f.ns.CounterCodec = {Encode = codec.Encode, Decode = function(store)
                local binary = assert(codec.Decode(store))
                return string.char(1) .. binary:sub(2)
            end}
        end
        equal(f.api.Initialize(), false); equal(f.api.Total(), nil)
        equal(f.api.Record(20217, "Cast-codec-retry"), false)
        equal(f.ns.db.buffStats, original); equal(original.spells[20217], 8)
        f.ns.CounterCodec = codec
        equal(f.api.Record(20217, "Cast-codec-retry"), true)
        equal(f.api.Total(), 9)
        for _, code in ipairs(f.logs) do assert(code:match("^STATS_[A-Z_]+$")) end
    end
end
function tests.failed_database_write_preserves_prior_counts_and_does_not_consume_guid()
    local f = fixture(); assert(f.api.Record(20217, "Cast-original"))
    local original = f.ns.db.buffStats
    f.env.rawset = function() error("private write exception") end
    equal(f.api.Record(20217, "Cast-write-retry"), false)
    equal(f.ns.db.buffStats, original); equal(f.api.Total(), 1)
    assert(f:has("STATS_SAVE_FAILED"))
    f.env.rawset = rawset
    equal(f.api.Record(20217, "Cast-write-retry"), true)
    equal(f.api.Total(), 2)
end

local names = {}
for name in pairs(tests) do if not arg[1] or arg[1] == name then names[#names + 1] = name end end
assert(#names > 0, "unknown test filter")
table.sort(names)
local failures = 0
for _, name in ipairs(names) do
    local ok, err = pcall(tests[name])
    if ok then print("PASS " .. name) else failures = failures + 1; print("FAIL " .. name .. ": " .. err) end
end
print(string.format("Stats: %d passed, %d failed", #names - failures, failures))
if failures > 0 then os.exit(1) end
