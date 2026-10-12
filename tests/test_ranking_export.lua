-- Purpose: prove opt-in, bounded, identity-free ranking export from confirmed casts.
-- Input: synthetic saved data/public API boundary; output: PASS/FAIL, no game I/O.
-- Invariants: no network, credentials, real identities, Lua eval, or live files.
-- Debug: lua tests/test_ranking_export.lua [test_name].
local tests = {}
local disabled = '{"schema":1,"enabled":false,"casterClass":"PALADIN","events":[]}'
local empty = '{"schema":1,"enabled":true,"casterClass":"PALADIN","events":[]}'
local function equal(actual, expected, context)
    if actual ~= expected then error(context or "unexpected export value", 2) end
end
local function fixture()
    local f = {time = 1791763200, clockCalls = 0, logs = {}}
    f.secret = setmetatable({}, {__tostring = function() error("secret printed") end})
    f.opaque = setmetatable({}, {__index = function() error("opaque read") end})
    local env = setmetatable({}, {__index = _G})
    f.env = env
    env.issecretvalue = function(value) return rawequal(value, f.secret) end
    env.canaccesstable = function(value) return not rawequal(value, f.opaque) end
    env.GetServerTime = function() f.clockCalls = f.clockCalls + 1; return f.time end
    env.UnitName = function() error("no identity API allowed") end
    env.UnitGUID, env.UnitClass = env.UnitName, env.UnitName
    env.C_ChatInfo = {SendAddonMessage = function() error("no network allowed") end}
    f.ns = {db = {}, Log = function(_, code) f.logs[#f.logs + 1] = code end}
    function f:reload()
        local path = "src/ForeverMouseoverBuff/RankingExport.lua"
        local chunk
        if setfenv then chunk = assert(loadfile(path)); setfenv(chunk, env)
        else chunk = assert(loadfile(path, "t", env)) end
        chunk("ForeverMouseoverBuff", f.ns)
        f.api = f.ns.RankingExport
    end
    function f:has(code)
        for _, item in ipairs(self.logs) do if item == code then return true end end
        return false
    end
    f:reload()
    return f
end

function tests.default_off_initialization_clears_old_export_without_any_clock_or_identity_api()
    local f = fixture()
    f.env.ForeverMouseoverBuffRankingExport = "stale export"
    f.ns.db.rankingQueue = {{id = "old", recipient = "Synthetic old data"}}
    equal(f.api.Initialize(), true, "off initialization must succeed without opt-in")
    equal(f.ns.db.rankingEnabled, false)
    equal(f.ns.db.rankingQueue, nil)
    equal(f.env.ForeverMouseoverBuffRankingExport, disabled)
    equal(f.clockCalls, 0)
    equal(f.api.Record(20217), false)
    equal(f.clockCalls, 0); equal(f.ns.db.rankingQueue, nil)
end

function tests.explicit_opt_in_records_exact_minimal_json_with_unique_monotonic_ids()
    local f = fixture()
    equal(f.api.SetEnabled(true), true, "explicit opt-in must enable export")
    equal(f.env.ForeverMouseoverBuffRankingExport, empty)
    equal(f.api.Record(19740), true)
    equal(f.api.Record(20217), true)
    equal(f.ns.db.rankingSequence, 2)
    local expected = '{"schema":1,"enabled":true,"casterClass":"PALADIN","events":['
        .. '{"id":"1791763200-1","spellId":19740,"eventTime":1791763200},'
        .. '{"id":"1791763200-2","spellId":20217,"eventTime":1791763200}]}'
    equal(f.env.ForeverMouseoverBuffRankingExport, expected)
    for _, entry in ipairs(f.ns.db.rankingQueue) do
        local count = 0
        for key in pairs(entry) do
            assert(key == "id" or key == "spellId" or key == "eventTime")
            count = count + 1
        end
        equal(count, 3)
    end
end

function tests.reload_preserves_ids_and_sequence_while_off_purges_queue_not_local_counts()
    local f = fixture(); f.ns.db.buffStats = {schema = 1, spells = {[20217] = 9}}
    f.api.SetEnabled(true); f.api.Record(20217)
    local before = f.env.ForeverMouseoverBuffRankingExport
    f:reload(); equal(f.api.Initialize(), true)
    equal(f.env.ForeverMouseoverBuffRankingExport, before)
    f.api.Record(20217)
    equal(f.ns.db.rankingQueue[2].id, "1791763200-2")
    equal(f.api.SetEnabled(false), true)
    equal(f.ns.db.rankingQueue, nil); equal(f.ns.db.rankingSequence, 2)
    equal(f.env.ForeverMouseoverBuffRankingExport, disabled)
    equal(f.ns.db.buffStats.spells[20217], 9)
    f.api.SetEnabled(true); f.api.Record(20217)
    equal(f.ns.db.rankingQueue[1].id, "1791763200-3")
end

function tests.full_ring_keeps_latest_thousand_events_and_warns_about_export_loss()
    local f = fixture(); f.api.SetEnabled(true)
    for _ = 1, 1000 do equal(f.api.Record(20217), true) end
    equal(f.api.Record(20217), true)
    equal(#f.ns.db.rankingQueue, 1000); equal(f.ns.db.rankingSequence, 1001)
    equal(f.ns.db.rankingQueue[1].id, "1791763200-2")
    equal(f.ns.db.rankingQueue[1000].id, "1791763200-1001")
    assert(f:has("RANKING_QUEUE_EVICTED"))
end

function tests.all_twenty_normal_blessings_are_allowed_unknown_or_secret_ids_are_not()
    local f = fixture(); f.api.SetEnabled(true)
    local ids = {19740,19834,19835,19836,19837,19838,25291,27140,48931,48932,
        19742,19850,19852,19853,19854,25290,27142,48935,48936,20217}
    for _, id in ipairs(ids) do equal(f.api.Record(id), true) end
    for _, id in ipairs({25898,25782,25894,1022,133,0,-1,1.5,"20217",f.secret}) do
        equal(f.api.Record(id), false)
    end
    equal(f.api.Record(nil), false); equal(f.api.Record(0/0), false)
    equal(#f.ns.db.rankingQueue, 20)
end

function tests.invalid_or_secret_server_time_does_not_enqueue_or_advance_sequence()
    local f = fixture(); f.api.SetEnabled(true)
    for _, stamp in ipairs({0,-1,1.5,math.huge,0/0,"1791763200",f.secret}) do
        f.time = stamp
        equal(f.api.Record(20217), false)
        equal(f.ns.db.rankingSequence, 0); equal(#f.ns.db.rankingQueue, 0)
    end
    f.env.GetServerTime = function() error("native error with private content") end
    equal(f.api.Record(20217), false)
    assert(f:has("RANKING_TIME_UNAVAILABLE"))
end

function tests.short_epoch_values_still_produce_valid_length_stable_transport_ids()
    local f = fixture(); f.api.SetEnabled(true); f.time = 1
    equal(f.api.Record(20217), true)
    equal(f.ns.db.rankingQueue[1].id, "0000000001-1",
        "epoch prefix must remain long enough for the backend ID contract")
    f:reload(); equal(f.api.Initialize(), true)
    equal(f.ns.db.rankingQueue[1].id, "0000000001-1")
end

function tests.unreadable_guards_fail_closed_and_do_not_call_clock()
    for _, mode in ipairs({"secret_absent", "secret_error", "access_absent", "access_error", "access_secret"}) do
        local f = fixture(); f.ns.db.rankingEnabled = true
        f.env.ForeverMouseoverBuffRankingExport = "stale"
        if mode == "secret_absent" then f.env.issecretvalue = nil
        elseif mode == "secret_error" then f.env.issecretvalue = function() error("private") end
        elseif mode == "access_absent" then f.env.canaccesstable = nil
        elseif mode == "access_error" then f.env.canaccesstable = function() error("private") end
        else f.env.canaccesstable = function() return f.secret end end
        equal(f.api.Initialize(), false)
        equal(f.env.ForeverMouseoverBuffRankingExport, disabled)
        equal(f.api.Record(20217), false); equal(f.clockCalls, 0)
    end
end

function tests.invalid_preferences_never_opt_in_and_clear_stale_export()
    for _, value in ipairs({1,"true",{},false}) do
        local f = fixture(); f.ns.db.rankingEnabled = value
        f.ns.db.rankingQueue = {{id = "stale"}}
        f.env.ForeverMouseoverBuffRankingExport = "stale"
        f.api.Initialize()
        equal(f.ns.db.rankingEnabled, false); equal(f.ns.db.rankingQueue, nil)
        equal(f.env.ForeverMouseoverBuffRankingExport, disabled); equal(f.clockCalls, 0)
    end
    local f = fixture(); f.ns.db.rankingEnabled = f.secret
    f.api.Initialize(); equal(f.env.ForeverMouseoverBuffRankingExport, disabled)
    equal(f.api.SetEnabled("true"), false); equal(f.api.SetEnabled(f.secret), false)
end

function tests.bad_saved_queue_disables_export_with_fixed_code_and_no_native_calls()
    local bad = {
        "bad",
        {{id = "1791763200-1", spellId = 133, eventTime = 1791763200}},
        {{id = "1791763200-1", spellId = 20217, eventTime = -1}},
        {{id = "arbitrary", spellId = 20217, eventTime = 1791763200}},
        {{id = "1791763200-2", spellId = 20217, eventTime = 1791763200},
         {id = "1791763200-2", spellId = 20217, eventTime = 1791763200}},
        {[2] = {id = "1791763200-1", spellId = 20217, eventTime = 1791763200}},
    }
    for _, queue in ipairs(bad) do
        local f = fixture(); f.ns.db.rankingEnabled = true
        f.ns.db.rankingSequence, f.ns.db.rankingQueue = 2, queue
        equal(f.api.Initialize(), false)
        equal(f.env.ForeverMouseoverBuffRankingExport, disabled)
        equal(f.ns.db.rankingEnabled, false); equal(f.ns.db.rankingQueue, nil)
        assert(f:has("RANKING_QUEUE_INVALID")); equal(f.clockCalls, 0)
    end
end

function tests.sequence_is_validated_and_never_reused_or_overflowed()
    local f = fixture(); f.ns.db.rankingEnabled = true
    f.ns.db.rankingSequence = -1
    equal(f.api.Initialize(), false); equal(f.ns.db.rankingEnabled, false)
    assert(f:has("RANKING_SEQUENCE_INVALID"))
    local g = fixture(); g.ns.db.rankingEnabled = true; g.ns.db.rankingSequence = 1
    g.ns.db.rankingQueue = {{id = "1791763200-7", spellId = 20217, eventTime = 1791763200}}
    equal(g.api.Initialize(), true); equal(g.ns.db.rankingSequence, 7)
    equal(g.api.Record(20217), true); equal(g.ns.db.rankingQueue[2].id, "1791763200-8")
    g.ns.db.rankingSequence = 1000000000
    equal(g.api.Record(20217), false); assert(g:has("RANKING_SEQUENCE_LIMIT"))
end

function tests.opaque_database_or_queue_never_exposes_a_previous_export()
    local f = fixture(); f.ns.db = f.opaque
    f.env.ForeverMouseoverBuffRankingExport = "stale"
    equal(f.api.Initialize(), false); equal(f.env.ForeverMouseoverBuffRankingExport, disabled)
    local g = fixture(); g.ns.db.rankingEnabled = true; g.ns.db.rankingQueue = g.secret
    equal(g.api.Initialize(), false); equal(g.env.ForeverMouseoverBuffRankingExport, disabled)
end

function tests.unknown_saved_fields_are_not_serialized_or_traversed()
    local f = fixture(); f.ns.db.rankingEnabled = true; f.ns.db.rankingSequence = 1
    local bomb = setmetatable({}, {__index = function() error("unknown value read") end,
        __pairs = function() error("unknown table enumerated") end})
    f.ns.db.rankingQueue = {{id = "1791763200-1", spellId = 20217,
        eventTime = 1791763200, recipient = bomb, token = "not exported"}}
    equal(f.api.Initialize(), true)
    equal(f.ns.db.rankingQueue[1].recipient, nil); equal(f.ns.db.rankingQueue[1].token, nil)
    equal(f.env.ForeverMouseoverBuffRankingExport:find("token", 1, true), nil)
end

local names, requested = {}, arg and arg[1]
for name in pairs(tests) do if not requested or name == requested then names[#names + 1] = name end end
table.sort(names); assert(#names > 0, "unknown test name")
local failures = 0
for _, name in ipairs(names) do
    local ok, reason = pcall(tests[name])
    if ok then print("PASS " .. name)
    else failures = failures + 1; io.stderr:write("FAIL " .. name .. ": " .. tostring(reason) .. "\n") end
end
print(string.format("RESULT %d/%d passed", #names - failures, #names))
os.exit(failures == 0 and 0 or 1)
