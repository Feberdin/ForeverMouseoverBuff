-- Purpose: local, unverified counters for already correlated normal blessing casts.
-- Input: public spell ID/cast GUID after the caller proves a successful non-self cast.
-- Output: encoded schema-2 counts and detached, explicitly available summaries.
-- Invariants: no identities/GUIDs persisted; invalid history is preserved intact.
-- Debug: tests/test_stats.lua and fixed STATS_* codes. CounterCodec must load first.
-- Base64/SHA-256 detect damaged storage, not dishonest clients or genuine casts.
local _, ns = ...
local Stats = {}
ns.Stats = Stats

local LIMIT, GUID_LIMIT = 1000000000, 128
local reported, completed, completedOrder = {}, {}, {}
-- Only ordinary Might/Wisdom/Kings ranks accepted by the cast tracker. Greater,
-- temporary and merely observed foreign blessings do not expand this scope.
local familyByID = {
    [19740] = "might", [19834] = "might", [19835] = "might", [19836] = "might",
    [19837] = "might", [19838] = "might", [25291] = "might", [27140] = "might",
    [48931] = "might", [48932] = "might", [19742] = "wisdom", [19850] = "wisdom",
    [19852] = "wisdom", [19853] = "wisdom", [19854] = "wisdom", [25290] = "wisdom",
    [27142] = "wisdom", [48935] = "wisdom", [48936] = "wisdom", [20217] = "kings",
}
local spellIDs = {19740,19742,19834,19835,19836,19837,19838,19850,19852,19853,
    19854,20217,25290,25291,27140,27142,48931,48932,48935,48936}

-- Emit each fixed code at most once per session, even when malformed data is
-- encountered repeatedly. Raw values/native exception text never enter logs.
local function report(code)
    Stats.LastCode = code
    if reported[code] then return end
    reported[code] = true
    if type(ns.Log) == "function" then
        local ok = pcall(ns.Log, ns, code)
        if not ok then Stats.LastCode = "STATS_LOG_FAILED" end
    end
end
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
local function counter(value)
    return type(value) == "number" and value == value and value >= 0
        and value <= LIMIT and value == math.floor(value)
end
local function validGUID(value)
    return public(value) and type(value) == "string" and #value <= 200
        and value:match("^Cast%-%w[%w%-]*$") ~= nil
end

local function unavailable(code)
    report(code)
    return nil, nil, nil, code
end

-- Exactly twenty big-endian uint32 words give a fixed 80-byte representation.
-- The order above is part of schema 2 and must never change without migration.
-- Example: counter 258 becomes bytes 0, 0, 1, 2; decimal counts never persist.
local function pack(counts)
    local words = {}
    for index, id in ipairs(spellIDs) do
        local value = counts[id] or 0
        words[index] = string.char(math.floor(value / 16777216),
            math.floor(value / 65536) % 256, math.floor(value / 256) % 256,
            value % 256)
    end
    return table.concat(words)
end
local function unpackCounts(binary)
    if not public(binary) or type(binary) ~= "string" or #binary ~= 80 then
        return nil, nil, "STATS_STORAGE_INVALID"
    end
    local counts, total = {}, 0
    for index, id in ipairs(spellIDs) do
        local first = (index - 1) * 4 + 1
        local a, b, c, d = string.byte(binary, first, first + 3)
        local value = ((a * 256 + b) * 256 + c) * 256 + d
        if not counter(value) then return nil, nil, "STATS_COUNT_INVALID" end
        if value > LIMIT - total then return nil, nil, "STATS_COUNT_OVER_BUDGET" end
        counts[id], total = value, total + value
    end
    return counts, total
end

-- The codec owns canonical Base64 and SHA-256. Only fixed errors are exposed;
-- native exceptions and payloads must never enter diagnostics or chat.
local function codecCall(method, value)
    if type(ns.CounterCodec) ~= "table" or type(ns.CounterCodec[method]) ~= "function" then
        return nil, "STATS_CODEC_UNAVAILABLE"
    end
    local ok, result, code = pcall(ns.CounterCodec[method], value)
    if not ok then return nil, "STATS_CODEC_FAILED" end
    if not public(result) then return nil, "STATS_DATA_RESTRICTED" end
    if result == nil or result == false then
        if public(code) and type(code) == "string" then
            if code == "COUNTER_INTEGRITY_MISMATCH" then return nil, "STATS_INTEGRITY_FAILED" end
            if code == "COUNTER_HASH_UNAVAILABLE" then return nil, "STATS_CODEC_UNAVAILABLE" end
            if code == "COUNTER_DATA_RESTRICTED" then return nil, "STATS_DATA_RESTRICTED" end
        end
        return nil, "STATS_STORAGE_INVALID"
    end
    if method == "Decode" and type(result) ~= "string" then return nil, "STATS_STORAGE_INVALID" end
    if method == "Encode" and not readable(result) then return nil, "STATS_STORAGE_INVALID" end
    return result
end

-- Construct and validate a replacement before the single database assignment.
-- A failed encode, roundtrip or write leaves the original evidence untouched.
local function saveCounts(db, counts)
    local binary = pack(counts)
    local encoded, code = codecCall("Encode", binary)
    if not encoded then return false, code end
    local decoded, decodeCode = codecCall("Decode", encoded)
    if not decoded then return false, decodeCode end
    if type(decoded) ~= "string" or decoded ~= binary then
        return false, "STATS_ROUNDTRIP_FAILED"
    end
    local ok = pcall(rawset, db, "buffStats", encoded)
    if not ok then return false, "STATS_SAVE_FAILED" end
    return true
end

-- Legacy input is read only at the twenty known numeric keys. Unlike the former
-- partial repair, ONE invalid known count blocks migration of the entire record.
-- Example: Might=7, Kings='bad' -> unavailable, original data still present.
local function legacyCounts(old)
    local imported = rawget(old, "spells")
    if not public(imported) then return nil, nil, "STATS_DATA_RESTRICTED" end
    if type(imported) ~= "table" then return nil, nil, "STATS_DATA_INVALID" end
    if not readable(imported) then return nil, nil, "STATS_DATA_RESTRICTED" end
    local counts, total = {}, 0
    for _, id in ipairs(spellIDs) do
        local value = rawget(imported, id)
        if not public(value) then return nil, nil, "STATS_COUNT_RESTRICTED" end
        if value == nil then value = 0 end
        if not counter(value) then return nil, nil, "STATS_COUNT_INVALID" end
        if value > LIMIT - total then return nil, nil, "STATS_COUNT_OVER_BUDGET" end
        counts[id], total = value, total + value
    end
    return counts, total
end

-- Verify each current read so same-session edits cannot bypass a cached hash.
-- New/migrated storage is written once; ordinary Total/Summary reads never save.
local function readCounts()
    local db = ns.db
    if not readable(db) then return unavailable("STATS_DATABASE_UNAVAILABLE") end
    local old = rawget(db, "buffStats")
    if not public(old) then return unavailable("STATS_DATA_RESTRICTED") end
    local counts, total, code, migrated
    if old == nil then
        counts, total = {}, 0
    else
        if type(old) ~= "table" then return unavailable("STATS_DATA_INVALID") end
        if not readable(old) then return unavailable("STATS_DATA_RESTRICTED") end
        local schema = rawget(old, "schema")
        if not public(schema) then return unavailable("STATS_DATA_RESTRICTED") end
        if schema == 1 then
            counts, total, code = legacyCounts(old)
            migrated = true
        elseif schema == 2 then
            local binary
            binary, code = codecCall("Decode", old)
            if binary then counts, total, code = unpackCounts(binary) end
            if not counts then return unavailable(code) end
            return db, counts, total
        else
            return unavailable("STATS_SCHEMA_UNSUPPORTED")
        end
    end
    if not counts then return unavailable(code) end
    local saved, saveCode = saveCounts(db, counts)
    if not saved then return unavailable(saveCode) end
    report(migrated and "STATS_MIGRATED" or "STATS_STARTED")
    return db, counts, total
end
local function remember(castGUID)
    completed[castGUID] = true
    completedOrder[#completedOrder + 1] = castGUID
    if #completedOrder > GUID_LIMIT then
        completed[table.remove(completedOrder, 1)] = nil
    end
end

-- Login explicitly validates storage and migrates valid legacy history. The
-- same validation on queries also protects callers used before the login hook.
function Stats.Initialize()
    local db, _, _, code = readCounts()
    return db ~= nil, code
end

-- This module trusts the owning cast tracker to establish player/class/target
-- and successful-cast evidence BEFORE Record. A valid GUID alone is not proof.
-- Dedupe covers the last 128 GUIDs in RAM, not reloads or adversarial replays.
function Stats.Record(spellID, castGUID)
    if not public(spellID) or not counter(spellID) or not familyByID[spellID] then
        report("STATS_SPELL_INVALID"); return false
    end
    if not validGUID(castGUID) then report("STATS_GUID_INVALID"); return false end
    if completed[castGUID] then report("STATS_DUPLICATE_CAST"); return false end
    local db, data, total = readCounts()
    if not db then return false end
    if total >= LIMIT then report("STATS_TOTAL_LIMIT"); return false end
    data[spellID] = (data[spellID] or 0) + 1
    local saved, code = saveCounts(db, data)
    if not saved then report(code); return false end
    remember(castGUID)
    report("STATS_RECORDED")
    return true
end

function Stats.Total()
    local db, _, total = readCounts()
    if not db then return nil end
    return total
end

-- Return only fixed-scope aggregate values in newly owned tables. Mutating a UI
-- summary cannot rewrite the saved counters, and no caller gets the GUID ring.
function Stats.Summary()
    local db, data, total, code = readCounts()
    if not db then return {casterClass = "PALADIN", available = false, error = code} end
    local result = {casterClass = "PALADIN", available = true, total = total,
        families = {might = 0, wisdom = 0, kings = 0}, spells = {}}
    for _, id in ipairs(spellIDs) do
        local value = data[id] or 0
        result.spells[id] = value
        local family = familyByID[id]
        result.families[family] = result.families[family] + value
    end
    return result
end
