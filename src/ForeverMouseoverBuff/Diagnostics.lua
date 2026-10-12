-- Purpose: keep a bounded, structured local diagnostic ledger for offline queries.
-- Input: fixed addon codes, public settings/counters and optional public clocks.
-- Output: schema-2 SavedVariables; detached snapshots for UI/CLI consumers.
-- Invariants: no names, GUIDs, messages, key bindings, raw errors or network calls.
-- Storage is flushed by WoW only on /reload or logout, not by this module.
-- Debug: /fmb diag; /fmb debug on; tests/test_diagnostics.lua. Codes are allowlisted.
local _, ns = ...
local DiagnosticLog = {}
ns.DiagnosticLog = DiagnosticLog
local EVENT_LIMIT, CODE_LIMIT, COUNT_LIMIT = 64, 40, 1000000000
local TIME_LIMIT, REPEAT_SECONDS = 4102444800, 2

-- Explicit metadata is also the companion CLI's validation contract. New log
-- codes must be deliberately added here; a matching uppercase pattern alone
-- would allow names or arbitrary private strings into exported diagnostics.
local catalog = {
    ["API_AURAS_UNKNOWN"] = {severity = "WARN", origin = "API"},
    ["API_AURA_CHANGED"] = {severity = "INFO", origin = "API"},
    ["API_AURA_LIMIT"] = {severity = "WARN", origin = "API"},
    ["API_CALL_FAILED"] = {severity = "ERROR", origin = "API"},
    ["API_CLIENT_UNKNOWN"] = {severity = "WARN", origin = "API"},
    ["API_GUARD_UNAVAILABLE"] = {severity = "ERROR", origin = "API"},
    ["API_LOG_UNAVAILABLE"] = {severity = "ERROR", origin = "API"},
    ["API_RESTRICTED"] = {severity = "WARN", origin = "API"},
    ["API_SPELLBOOK_UNKNOWN"] = {severity = "WARN", origin = "API"},
    ["API_SPELL_NAMES_UNKNOWN"] = {severity = "WARN", origin = "API"},
    ["API_SPELL_STATE_UNKNOWN"] = {severity = "WARN", origin = "API"},
    ["API_STATE_UNKNOWN"] = {severity = "WARN", origin = "API"},
    ["API_UNAVAILABLE"] = {severity = "ERROR", origin = "API"},
    ["AURA_UNKNOWN"] = {severity = "WARN", origin = "CORE"},
    ["BUTTON_UNAVAILABLE"] = {severity = "ERROR", origin = "APP"},
    ["CAST_CONFIRMED"] = {severity = "INFO", origin = "APP"},
    ["CAST_FAILED"] = {severity = "WARN", origin = "APP"},
    ["CAST_REQUESTED"] = {severity = "INFO", origin = "APP"},
    ["CHAT_ECHO_MATCH_FAILED"] = {severity = "ERROR", origin = "CHAT"},
    ["CHAT_ECHO_UNAVAILABLE"] = {severity = "ERROR", origin = "CHAT"},
    ["CHAT_FILTER_API_UNAVAILABLE"] = {severity = "ERROR", origin = "CHAT"},
    ["CHAT_FILTER_READY"] = {severity = "INFO", origin = "CHAT"},
    ["CHAT_FILTER_REGISTRATION_FAILED"] = {severity = "ERROR", origin = "CHAT"},
    ["CHAT_FRAMES"] = {severity = "INFO", origin = "CHAT"},
    ["CHAT_GREETING_FORMAT_UNAVAILABLE"] = {severity = "ERROR", origin = "CHAT"},
    ["COMBAT_FIXED_READY"] = {severity = "INFO", origin = "APP"},
    ["COMBAT_SPELL_NOT_LEARNED"] = {severity = "INFO", origin = "APP"},
    ["COMBAT_SPELL_READY"] = {severity = "INFO", origin = "APP"},
    ["COMBAT_SPELL_UNAVAILABLE"] = {severity = "ERROR", origin = "APP"},
    ["CONTEXT_ERROR"] = {severity = "ERROR", origin = "APP"},
    ["DECISION_ERROR"] = {severity = "ERROR", origin = "APP"},
    ["DIAGNOSTIC_HISTORY_SANITIZED"] = {severity = "WARN", origin = "APP"},
    ["DIAGNOSTIC_INVALID"] = {severity = "WARN", origin = "APP"},
    ["DIAGNOSTIC_SCHEMA_UNSUPPORTED"] = {severity = "WARN", origin = "APP"},
    ["DIAGNOSTIC_SEQUENCE_LIMIT"] = {severity = "WARN", origin = "APP"},
    ["DIAGNOSTIC_STARTED"] = {severity = "INFO", origin = "APP"},
    ["DIAGNOSTIC_STORAGE_UNAVAILABLE"] = {severity = "ERROR", origin = "APP"},
    ["DISABLED"] = {severity = "INFO", origin = "APP"},
    ["EVENT_UNAVAILABLE"] = {severity = "ERROR", origin = "APP"},
    ["FEEDBACK_CLOCK_UNAVAILABLE"] = {severity = "ERROR", origin = "APP"},
    ["FEEDBACK_UI_UNAVAILABLE"] = {severity = "ERROR", origin = "APP"},
    ["FLYING"] = {severity = "INFO", origin = "CORE"},
    ["GREETING_DETAILS_OMITTED"] = {severity = "INFO", origin = "GREETING"},
    ["GREETING_SENDER_CLASS_UNAVAILABLE"] = {severity = "ERROR", origin = "GREETING"},
    ["HAS_BLESSING"] = {severity = "INFO", origin = "CORE"},
    ["INVALID_CONTEXT"] = {severity = "INFO", origin = "CORE"},
    ["INVALID_MODE"] = {severity = "INFO", origin = "CORE"},
    ["INVALID_SPELL_DATA"] = {severity = "INFO", origin = "CORE"},
    ["IN_VEHICLE"] = {severity = "INFO", origin = "CORE"},
    ["MACRO_API_UNAVAILABLE"] = {severity = "ERROR", origin = "APP"},
    ["MOUNTED"] = {severity = "INFO", origin = "CORE"},
    ["NOT_FRIENDLY"] = {severity = "INFO", origin = "CORE"},
    ["NOT_PLAYER"] = {severity = "INFO", origin = "CORE"},
    ["NOT_USABLE"] = {severity = "INFO", origin = "CORE"},
    ["NO_BINDING"] = {severity = "INFO", origin = "APP"},
    ["NO_KNOWN_SPELL"] = {severity = "INFO", origin = "CORE"},
    ["NO_TARGET"] = {severity = "INFO", origin = "CORE"},
    ["OUT_OF_RANGE"] = {severity = "INFO", origin = "CORE"},
    ["OWN_BLESSING_PRESERVED"] = {severity = "INFO", origin = "CORE"},
    ["PLAYER_IN_COMBAT"] = {severity = "INFO", origin = "CORE"},
    ["PLAYER_NOT_PALADIN"] = {severity = "INFO", origin = "APP"},
    ["PLAYER_STATE_UNKNOWN"] = {severity = "WARN", origin = "CORE"},
    ["RANKING_DATABASE_UNAVAILABLE"] = {severity = "ERROR", origin = "RANKING"},
    ["RANKING_DISABLED"] = {severity = "INFO", origin = "RANKING"},
    ["RANKING_ENABLED"] = {severity = "INFO", origin = "RANKING"},
    ["RANKING_EXPORT_FAILED"] = {severity = "ERROR", origin = "RANKING"},
    ["RANKING_PREFERENCE_INVALID"] = {severity = "WARN", origin = "RANKING"},
    ["RANKING_QUEUE_EVICTED"] = {severity = "INFO", origin = "RANKING"},
    ["RANKING_QUEUE_INVALID"] = {severity = "WARN", origin = "RANKING"},
    ["RANKING_RECORDED"] = {severity = "INFO", origin = "RANKING"},
    ["RANKING_SEQUENCE_INVALID"] = {severity = "WARN", origin = "RANKING"},
    ["RANKING_SEQUENCE_LIMIT"] = {severity = "WARN", origin = "RANKING"},
    ["RANKING_SEQUENCE_RECOVERED"] = {severity = "INFO", origin = "RANKING"},
    ["RANKING_SPELL_INVALID"] = {severity = "WARN", origin = "RANKING"},
    ["RANKING_TIME_UNAVAILABLE"] = {severity = "ERROR", origin = "RANKING"},
    ["READY"] = {severity = "INFO", origin = "CORE"},
    ["READY_FALLBACK"] = {severity = "INFO", origin = "CORE"},
    ["RECIPIENT_ALLOWED"] = {severity = "INFO", origin = "RECIPIENT"},
    ["RECIPIENT_API_UNAVAILABLE"] = {severity = "ERROR", origin = "RECIPIENT"},
    ["RECIPIENT_CALLBACK_FAILED"] = {severity = "ERROR", origin = "RECIPIENT"},
    ["RECIPIENT_CALLBACK_INVALID"] = {severity = "WARN", origin = "RECIPIENT"},
    ["RECIPIENT_CLOCK_REVERSED"] = {severity = "INFO", origin = "RECIPIENT"},
    ["RECIPIENT_CLOCK_UNAVAILABLE"] = {severity = "ERROR", origin = "RECIPIENT"},
    ["RECIPIENT_DENIED"] = {severity = "INFO", origin = "RECIPIENT"},
    ["RECIPIENT_EVENT_RESTRICTED"] = {severity = "WARN", origin = "RECIPIENT"},
    ["RECIPIENT_LOG_FAILED"] = {severity = "ERROR", origin = "RECIPIENT"},
    ["RECIPIENT_MATCH_FAILED"] = {severity = "ERROR", origin = "RECIPIENT"},
    ["RECIPIENT_NONCE_EXHAUSTED"] = {severity = "WARN", origin = "RECIPIENT"},
    ["RECIPIENT_NOT_READY"] = {severity = "INFO", origin = "RECIPIENT"},
    ["RECIPIENT_NO_REPLY"] = {severity = "INFO", origin = "RECIPIENT"},
    ["RECIPIENT_PREFERENCE_UNKNOWN"] = {severity = "WARN", origin = "RECIPIENT"},
    ["RECIPIENT_QUERY_SENT"] = {severity = "INFO", origin = "RECIPIENT"},
    ["RECIPIENT_QUEUE_FULL"] = {severity = "WARN", origin = "RECIPIENT"},
    ["RECIPIENT_READY"] = {severity = "INFO", origin = "RECIPIENT"},
    ["RECIPIENT_REGISTER_FAILED"] = {severity = "ERROR", origin = "RECIPIENT"},
    ["RECIPIENT_REQUEST_INVALID"] = {severity = "WARN", origin = "RECIPIENT"},
    ["RECIPIENT_RESPONSE_SENT"] = {severity = "INFO", origin = "RECIPIENT"},
    ["RECIPIENT_RESPONSE_THROTTLED"] = {severity = "INFO", origin = "RECIPIENT"},
    ["RECIPIENT_SEND_FAILED"] = {severity = "ERROR", origin = "RECIPIENT"},
    ["SEAL_ARMED"] = {severity = "INFO", origin = "SEAL"},
    ["SEAL_AURAS_AMBIGUOUS"] = {severity = "WARN", origin = "SEAL"},
    ["SEAL_AURAS_UNKNOWN"] = {severity = "WARN", origin = "SEAL"},
    ["SEAL_AURA_LIMIT"] = {severity = "WARN", origin = "SEAL"},
    ["SEAL_CLOCK_RESET"] = {severity = "INFO", origin = "SEAL"},
    ["SEAL_CLOCK_UNAVAILABLE"] = {severity = "ERROR", origin = "SEAL"},
    ["SEAL_EXPIRED_SOUND_REQUESTED"] = {severity = "INFO", origin = "SEAL"},
    ["SEAL_IDLE"] = {severity = "INFO", origin = "SEAL"},
    ["SEAL_LOG_UNAVAILABLE"] = {severity = "ERROR", origin = "SEAL"},
    ["SEAL_NAMES_UNAVAILABLE"] = {severity = "ERROR", origin = "SEAL"},
    ["SEAL_OBSERVATION_GAP"] = {severity = "INFO", origin = "SEAL"},
    ["SEAL_PLAYER_UNAVAILABLE"] = {severity = "ERROR", origin = "SEAL"},
    ["SEAL_REMINDER_OFF"] = {severity = "INFO", origin = "SEAL"},
    ["SEAL_REMOVED_EARLY"] = {severity = "INFO", origin = "SEAL"},
    ["SEAL_SOUND_FAILED"] = {severity = "ERROR", origin = "SEAL"},
    ["SEAL_TIMING_UNKNOWN"] = {severity = "WARN", origin = "SEAL"},
    ["SELF_TARGET"] = {severity = "INFO", origin = "CORE"},
    ["SOUND_FAILED"] = {severity = "ERROR", origin = "APP"},
    ["SOUND_REQUESTED"] = {severity = "INFO", origin = "APP"},
    ["SPELL_LINK_API_FAILED"] = {severity = "ERROR", origin = "SPELL_LINK"},
    ["SPELL_LINK_API_UNAVAILABLE"] = {severity = "ERROR", origin = "SPELL_LINK"},
    ["SPELL_LINK_INVALID"] = {severity = "WARN", origin = "SPELL_LINK"},
    ["SPELL_LINK_INVALID_ID"] = {severity = "INFO", origin = "SPELL_LINK"},
    ["SPELL_LINK_MISMATCH"] = {severity = "INFO", origin = "SPELL_LINK"},
    ["SPELL_LINK_RESTRICTED"] = {severity = "WARN", origin = "SPELL_LINK"},
    ["SPELL_LINK_UNAVAILABLE"] = {severity = "ERROR", origin = "SPELL_LINK"},
    ["STATS_CODEC_FAILED"] = {severity = "ERROR", origin = "STATS"},
    ["STATS_CODEC_UNAVAILABLE"] = {severity = "ERROR", origin = "STATS"},
    ["STATS_COUNT_INVALID"] = {severity = "WARN", origin = "STATS"},
    ["STATS_COUNT_OVER_BUDGET"] = {severity = "INFO", origin = "STATS"},
    ["STATS_COUNT_RESTRICTED"] = {severity = "WARN", origin = "STATS"},
    ["STATS_DATABASE_UNAVAILABLE"] = {severity = "ERROR", origin = "STATS"},
    ["STATS_DATA_INVALID"] = {severity = "WARN", origin = "STATS"},
    ["STATS_DATA_RESTRICTED"] = {severity = "WARN", origin = "STATS"},
    ["STATS_DUPLICATE_CAST"] = {severity = "WARN", origin = "STATS"},
    ["STATS_GUID_INVALID"] = {severity = "WARN", origin = "STATS"},
    ["STATS_INITIALIZE_FAILED"] = {severity = "ERROR", origin = "APP"},
    ["STATS_INTEGRITY_FAILED"] = {severity = "ERROR", origin = "STATS"},
    ["STATS_LOG_FAILED"] = {severity = "ERROR", origin = "STATS"},
    ["STATS_MIGRATED"] = {severity = "INFO", origin = "STATS"},
    ["STATS_RECORDED"] = {severity = "INFO", origin = "STATS"},
    ["STATS_RECORD_FAILED"] = {severity = "ERROR", origin = "STATS"},
    ["STATS_ROUNDTRIP_FAILED"] = {severity = "ERROR", origin = "STATS"},
    ["STATS_SAVE_FAILED"] = {severity = "ERROR", origin = "STATS"},
    ["STATS_SCHEMA_UNSUPPORTED"] = {severity = "WARN", origin = "STATS"},
    ["STATS_SPELL_INVALID"] = {severity = "WARN", origin = "STATS"},
    ["STATS_STARTED"] = {severity = "INFO", origin = "STATS"},
    ["STATS_STORAGE_INVALID"] = {severity = "WARN", origin = "STATS"},
    ["STATS_TOTAL_LIMIT"] = {severity = "WARN", origin = "STATS"},
    ["STATS_TOTAL_UNAVAILABLE"] = {severity = "ERROR", origin = "STATS"},
    ["TARGET_CLASS_UNKNOWN"] = {severity = "WARN", origin = "CORE"},
    ["TARGET_DEAD"] = {severity = "INFO", origin = "CORE"},
    ["TARGET_DISCONNECTED"] = {severity = "INFO", origin = "CORE"},
    ["TARGET_LEVEL_TOO_LOW"] = {severity = "INFO", origin = "CORE"},
    ["TARGET_LEVEL_UNKNOWN"] = {severity = "WARN", origin = "CORE"},
    ["TARGET_NOT_VISIBLE"] = {severity = "INFO", origin = "CORE"},
    ["TARGET_STATE_UNKNOWN"] = {severity = "WARN", origin = "CORE"},
    ["UNSUPPORTED_CLASS"] = {severity = "INFO", origin = "CORE"},
    ["WHISPER_ATTEMPT_AMBIGUOUS"] = {severity = "WARN", origin = "WHISPER"},
    ["WHISPER_ATTEMPT_EXPIRED"] = {severity = "INFO", origin = "WHISPER"},
    ["WHISPER_CAST_BOUND"] = {severity = "INFO", origin = "WHISPER"},
    ["WHISPER_CAST_NOT_SUCCEEDED"] = {severity = "WARN", origin = "WHISPER"},
    ["WHISPER_CLOCK_UNAVAILABLE"] = {severity = "ERROR", origin = "WHISPER"},
    ["WHISPER_COMPLETE_UNMATCHED"] = {severity = "INFO", origin = "WHISPER"},
    ["WHISPER_DISABLED"] = {severity = "INFO", origin = "WHISPER"},
    ["WHISPER_EVENT_RESTRICTED"] = {severity = "WARN", origin = "WHISPER"},
    ["WHISPER_GREETING_INVALID"] = {severity = "WARN", origin = "WHISPER"},
    ["WHISPER_GREETING_UNAVAILABLE"] = {severity = "ERROR", origin = "WHISPER"},
    ["WHISPER_IDENTITY_UNAVAILABLE"] = {severity = "ERROR", origin = "WHISPER"},
    ["WHISPER_LINK_UNAVAILABLE"] = {severity = "ERROR", origin = "WHISPER"},
    ["WHISPER_NAME_MODE_UNAVAILABLE"] = {severity = "ERROR", origin = "WHISPER"},
    ["WHISPER_PREPARED"] = {severity = "INFO", origin = "WHISPER"},
    ["WHISPER_REALM_UNAVAILABLE"] = {severity = "ERROR", origin = "WHISPER"},
    ["WHISPER_RECIPIENT_DECLINED"] = {severity = "INFO", origin = "WHISPER"},
    ["WHISPER_RECIPIENT_FAILED"] = {severity = "ERROR", origin = "WHISPER"},
    ["WHISPER_RECIPIENT_PENDING"] = {severity = "INFO", origin = "WHISPER"},
    ["WHISPER_RECIPIENT_UNAVAILABLE"] = {severity = "ERROR", origin = "WHISPER"},
    ["WHISPER_REQUESTED"] = {severity = "INFO", origin = "WHISPER"},
    ["WHISPER_SEND_FAILED"] = {severity = "ERROR", origin = "WHISPER"},
    ["WHISPER_SEND_UNAVAILABLE"] = {severity = "ERROR", origin = "WHISPER"},
    ["WHISPER_SENT_AMBIGUOUS"] = {severity = "WARN", origin = "WHISPER"},
    ["WHISPER_SENT_UNMATCHED"] = {severity = "INFO", origin = "WHISPER"},
    ["WHISPER_SPELL_UNAVAILABLE"] = {severity = "ERROR", origin = "WHISPER"},
    ["WHISPER_TARGET_UNAVAILABLE"] = {severity = "ERROR", origin = "WHISPER"},
    ["WIM_RECEIVE_FILTER_FAILED"] = {severity = "ERROR", origin = "CHAT"},
    ["WIM_RECEIVE_FILTER_READY"] = {severity = "INFO", origin = "CHAT"},

}
local flagKeys = {"enabled", "debug", "sound", "whisper", "receiveWhispers",
    "showOutgoingWhispers", "sealSound", "rankingEnabled", "buttonReady", "routerReady"}
local counterKeys = {attempts = true, confirmed = true, failed = true}
local state, database, blockPersistence, storageAvailable
local initialized = false
local lastTimes, seenWithoutClock, lastCode = {}, {}, nil

local function public(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret == false
end
local function readable(value)
    if not public(value) or type(value) ~= "table" or type(canaccesstable) ~= "function" then return false end
    local ok, access = pcall(canaccesstable, value)
    return ok and public(access) and access == true
end
local function integer(value, minimum, maximum)
    return public(value) and type(value) == "number" and value == value
        and value >= minimum and value <= maximum and value == math.floor(value)
end
local function knownCode(value)
    return public(value) and type(value) == "string" and #value <= 80 and catalog[value] ~= nil
end
DiagnosticLog.IsCode = knownCode
function DiagnosticLog.Normalize(code)
    return knownCode(code) and code or "DIAGNOSTIC_INVALID"
end
local function empty(version)
    local valid = public(version) and type(version) == "string" and #version <= 32
        and version:match("^%d+%.%d+%.%d+$")
    return {schema = 2, version = valid and version or "unknown", sequence = 0,
        events = {}, codes = {}, status = {}, attempts = 0, confirmed = 0, failed = 0}
end
state = empty(nil)

-- Clone only privately owned fixed fields. Neither a UI snapshot nor the table
-- exposed through SavedVariables becomes a mutation handle for the RAM ledger.
local function copyState()
    local copy = {schema = 2, version = state.version, sequence = state.sequence,
        events = {}, codes = {}, status = {}, attempts = state.attempts,
        confirmed = state.confirmed, failed = state.failed, fallbackReason = state.fallbackReason}
    for index = 1, #state.events do
        local event = state.events[index]
        copy.events[index] = {sequence = event.sequence, code = event.code,
            severity = event.severity, origin = event.origin, timestamp = event.timestamp}
    end
    for index = 1, #state.codes do copy.codes[index] = state.codes[index] end
    for _, key in ipairs(flagKeys) do copy.status[key] = state.status[key] end
    copy.status.clientVersion = state.status.clientVersion
    copy.status.clientBuild = state.status.clientBuild
    copy.status.clientInterface = state.status.clientInterface
    return copy
end
local function persist()
    if blockPersistence or not readable(database) then storageAvailable = false; return false end
    local ok = pcall(rawset, database, "diagnostics", copyState())
    storageAvailable = ok
    return ok
end
function DiagnosticLog.Snapshot()
    local snapshot = copyState()
    snapshot.storageAvailable = storageAvailable == true
    return snapshot
end
local function publicClock(fn, integerOnly)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn)
    if not ok or not public(value) or type(value) ~= "number" or value ~= value
        or value < 0 or value > TIME_LIMIT then return nil end
    if integerOnly and (value < 1 or value ~= math.floor(value)) then return nil end
    return value
end
local function appendCode(code)
    if state.codes[#state.codes] == code then return end
    state.codes[#state.codes + 1] = code
    if #state.codes > CODE_LIMIT then table.remove(state.codes, 1) end
end

-- Legacy codes keep their historical transition semantics. Structured events
-- additionally limit repeated alternating errors to one per code per 2 seconds.
-- Without a readable monotonic clock, one event per code/session is the safe cap.
function DiagnosticLog.Record(value)
    local code = DiagnosticLog.Normalize(value)
    if lastCode == code then return false, code end
    lastCode = code
    appendCode(code)
    local clock = publicClock(GetTime, false)
    local previous = lastTimes[code]
    local due
    if clock then
        due = not previous or clock < previous or clock - previous >= REPEAT_SECONDS
    else
        due = not seenWithoutClock[code]
    end
    if due and state.sequence < COUNT_LIMIT then
        local metadata = catalog[code]
        state.sequence = state.sequence + 1
        state.events[#state.events + 1] = {sequence = state.sequence, code = code,
            severity = metadata.severity, origin = metadata.origin,
            timestamp = publicClock(GetServerTime, true)}
        if #state.events > EVENT_LIMIT then table.remove(state.events, 1) end
        if clock then lastTimes[code] = clock else seenWithoutClock[code] = true end
    elseif due then
        appendCode("DIAGNOSTIC_SEQUENCE_LIMIT")
    end
    persist()
    return true, code
end

-- Read at most 40 legacy codes / 64 events via rawget. Unknown metadata is never
-- reused: severity and origin are reconstructed from the fixed local catalog.
local function importHistory(old)
    local codes = rawget(old, "codes")
    if readable(codes) then
        for index = 1, CODE_LIMIT do
            local code = rawget(codes, index)
            if knownCode(code) then appendCode(code) end
        end
    end
    for key in pairs(counterKeys) do
        local value = rawget(old, key)
        if integer(value, 0, COUNT_LIMIT) then state[key] = value end
    end
    local fallback = rawget(old, "fallbackReason")
    if knownCode(fallback) then state.fallbackReason = fallback end
    local events = rawget(old, "events")
    if readable(events) then
        for index = 1, EVENT_LIMIT do
            local event = rawget(events, index)
            if readable(event) then
                local code, sequence = rawget(event, "code"), rawget(event, "sequence")
                if knownCode(code) and integer(sequence, 1, COUNT_LIMIT) and sequence > state.sequence then
                    local metadata, stamp = catalog[code], rawget(event, "timestamp")
                    state.sequence = sequence
                    state.events[#state.events + 1] = {sequence = sequence, code = code,
                        severity = metadata.severity, origin = metadata.origin,
                        timestamp = integer(stamp, 1, TIME_LIMIT) and stamp or nil}
                end
            end
        end
    end
    local sequence = rawget(old, "sequence")
    if integer(sequence, state.sequence, COUNT_LIMIT) then state.sequence = sequence end
end

function DiagnosticLog.Initialize(db, version)
    -- RegisterEvent can fail while App.lua is loading, before PLAYER_LOGIN has
    -- supplied SavedVariables. Preserve these fixed startup codes for diagnosis.
    local startupCodes = {}
    if not initialized then
        for index = 1, #state.codes do startupCodes[index] = state.codes[index] end
    end
    initialized = true
    state, database = empty(version), db
    lastTimes, seenWithoutClock, lastCode = {}, {}, nil
    blockPersistence, storageAvailable = false, false
    local function finish(code)
        DiagnosticLog.Record(code)
        for index = 1, #startupCodes do DiagnosticLog.Record(startupCodes[index]) end
        return storageAvailable == true
    end
    if not readable(db) then
        blockPersistence = true
        return finish("DIAGNOSTIC_STORAGE_UNAVAILABLE")
    end
    local old = rawget(db, "diagnostics")
    if not public(old) or (type(old) == "table" and not readable(old)) then
        blockPersistence = true
        return finish("DIAGNOSTIC_STORAGE_UNAVAILABLE")
    end
    if type(old) == "table" then
        local schema = rawget(old, "schema")
        if not public(schema) or (schema ~= nil and schema ~= 2) then
            blockPersistence = true
            return finish("DIAGNOSTIC_SCHEMA_UNSUPPORTED")
        end
        importHistory(old)
    end
    return finish("DIAGNOSTIC_STARTED")
end

function DiagnosticLog.Increment(key)
    if not public(key) or not counterKeys[key] then return nil end
    state[key] = math.min(COUNT_LIMIT, state[key] + 1)
    persist()
    return state[key]
end
function DiagnosticLog.SetFallback(code)
    local updated = knownCode(code) and code or nil
    if state.fallbackReason == updated then return end
    state.fallbackReason = updated
    persist()
end

-- Status is a deliberately small, public configuration snapshot. Never persist
-- binding labels, target facts, localized status text or arbitrary module data.
function DiagnosticLog.UpdateStatus(status)
    if not readable(status) then return false end
    local updated = {}
    for _, key in ipairs(flagKeys) do
        local value = rawget(status, key)
        if public(value) and type(value) == "boolean" then updated[key] = value end
    end
    local version, build = rawget(status, "clientVersion"), rawget(status, "clientBuild")
    if public(version) and type(version) == "string" and #version <= 32
        and version:match("^%d+%.%d+%.%d+$") then updated.clientVersion = version end
    if public(build) and type(build) == "string" and #build <= 12
        and build:match("^%d+$") then updated.clientBuild = build end
    local interface = rawget(status, "clientInterface")
    if integer(interface, 1, 1000000) then updated.clientInterface = interface end
    local changed = false
    for _, key in ipairs(flagKeys) do
        if updated[key] ~= state.status[key] then changed = true end
    end
    for _, key in ipairs({"clientVersion", "clientBuild", "clientInterface"}) do
        if updated[key] ~= state.status[key] then changed = true end
    end
    if not changed then return storageAvailable == true end
    state.status = updated
    return persist()
end
