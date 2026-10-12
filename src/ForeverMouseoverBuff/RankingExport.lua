-- Purpose: opt-in, bounded export of self-reported confirmed normal blessing casts.
-- Input: spellID only AFTER Stats.Record succeeded, and explicit on/off preference.
-- Output: per-character ring and a JSON STRING for the read-only external companion.
-- Invariants: off clears export; no network/credentials/names/GUIDs/targets/locations;
-- oldest events may be lost after 1000 new events without export; local stats remain.
-- Debug: /fmb debug on; tests/test_ranking_export.lua; fixed RANKING_* codes only.
local _, ns = ...
local Export = {}
ns.RankingExport = Export
local MAX_EVENTS, MAX_SEQUENCE, MAX_TIME = 1000, 1000000000, 4102444800
local OFF = '{"schema":1,"enabled":false,"casterClass":"PALADIN","events":[]}'
local reported = {}
local allowed = {
    [19740]=true,[19834]=true,[19835]=true,[19836]=true,[19837]=true,[19838]=true,
    [25291]=true,[27140]=true,[48931]=true,[48932]=true,[19742]=true,[19850]=true,
    [19852]=true,[19853]=true,[19854]=true,[25290]=true,[27142]=true,[48935]=true,
    [48936]=true,[20217]=true,
}

-- Imported SavedVariables and API values are untrusted. Read only known keys,
-- never enumerate arbitrary nested tables or stringify a native exception.
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
local function integer(value, low, high)
    return public(value) and type(value) == "number" and value == value
        and value >= low and value <= high and value == math.floor(value)
end
local function report(code)
    Export.LastCode = code
    if reported[code] then return end
    reported[code] = true
    if type(ns.Log) == "function" then pcall(ns.Log, ns, code) end
end
local function numberText(value) return string.format("%.0f", value) end
local function epochText(value) return string.format("%010.0f", value) end
local function clear(db, code)
    ForeverMouseoverBuffRankingExport = OFF
    if db then
        rawset(db, "rankingEnabled", false)
        rawset(db, "rankingQueue", nil)
    end
    if code then report(code) end
end

-- The serializer has no arbitrary string inputs: IDs are generated/validated
-- decimal numbers plus one dash. All other JSON values are fixed or bounded ints.
-- Keep byte-identical saved event IDs across reloads; no timestamps are regenerated.
local function publish(db, queue, sequence)
    local rows = {}
    for index, event in ipairs(queue) do
        rows[index] = '{"id":"' .. event.id .. '","spellId":' .. numberText(event.spellId)
            .. ',"eventTime":' .. numberText(event.eventTime) .. '}'
    end
    rawset(db, "rankingQueue", queue)
    rawset(db, "rankingSequence", sequence)
    ForeverMouseoverBuffRankingExport = '{"schema":1,"enabled":true,"casterClass":"PALADIN","events":['
        .. table.concat(rows, ",") .. ']}'
end
local function eventCopy(entry, previousSequence)
    if not readable(entry) then return nil end
    local id, spell, stamp = rawget(entry, "id"), rawget(entry, "spellId"), rawget(entry, "eventTime")
    if not public(id) or type(id) ~= "string" or #id > 32
        or not integer(spell, 1, MAX_SEQUENCE) or not allowed[spell]
        or not integer(stamp, 1, MAX_TIME) then return nil end
    local timePart, sequencePart = id:match("^(%d+)%-(%d+)$")
    if not timePart or #timePart > 10 or #sequencePart > 10 then return nil end
    local sequence = tonumber(sequencePart)
    if not integer(sequence, 1, MAX_SEQUENCE) or sequence <= previousSequence
        or timePart ~= epochText(stamp) or sequencePart ~= numberText(sequence) then return nil end
    return {id = id, spellId = spell, eventTime = stamp}, sequence
end

-- Scan a fixed upper bound, not # or pairs on imported tables. Holes, duplicates,
-- malformed events and invalid sequences disable/purge only ranking export. Valid
-- legacy queue entries can advance a stale sequence to prevent an ID being reused.
local function state()
    local db = ns.db
    if not readable(db) then clear(nil, "RANKING_DATABASE_UNAVAILABLE"); return nil end
    local enabled = rawget(db, "rankingEnabled")
    if not public(enabled) or enabled ~= true then clear(db); return db, nil end
    local sequence = rawget(db, "rankingSequence")
    if public(sequence) and sequence == nil then sequence = 0 end
    if not integer(sequence, 0, MAX_SEQUENCE) then clear(db, "RANKING_SEQUENCE_INVALID"); return nil end
    local saved = rawget(db, "rankingQueue")
    if public(saved) and saved == nil then return db, {}, sequence end
    if not readable(saved) then clear(db, "RANKING_QUEUE_INVALID"); return nil end
    local queue, last, gap = {}, 0, false
    for index = 1, MAX_EVENTS + 1 do
        local entry = rawget(saved, index)
        if not public(entry) then clear(db, "RANKING_QUEUE_INVALID"); return nil end
        if entry == nil then gap = true
        else
            if gap or index > MAX_EVENTS then clear(db, "RANKING_QUEUE_INVALID"); return nil end
            local copied, nextSequence = eventCopy(entry, last)
            if not copied then clear(db, "RANKING_QUEUE_INVALID"); return nil end
            queue[#queue + 1], last = copied, nextSequence
        end
    end
    if sequence < last then sequence = last; report("RANKING_SEQUENCE_RECOVERED") end
    return db, queue, sequence
end

function Export.Initialize()
    -- A stale serialized global must never survive a failed state validation.
    ForeverMouseoverBuffRankingExport = OFF
    local db, queue, sequence = state()
    if not db then return false end
    if queue then publish(db, queue, sequence) end
    return true
end
function Export.SetEnabled(enabled)
    if not public(enabled) or type(enabled) ~= "boolean" then report("RANKING_PREFERENCE_INVALID"); return false end
    if not readable(ns.db) then clear(nil, "RANKING_DATABASE_UNAVAILABLE"); return false end
    if not enabled then clear(ns.db, "RANKING_DISABLED"); return true end
    rawset(ns.db, "rankingEnabled", true)
    local ready = Export.Initialize()
    if ready then report("RANKING_ENABLED") end
    return ready
end

-- The caller owns cast/identity/class evidence and Stats GUID deduplication.
-- This function never turns a failed export into a failed local buff/statistic.
function Export.Record(spellID)
    local db, queue, sequence = state()
    if not db or not queue then return false end
    if not integer(spellID, 1, MAX_SEQUENCE) or not allowed[spellID] then
        report("RANKING_SPELL_INVALID"); return false
    end
    if sequence >= MAX_SEQUENCE then report("RANKING_SEQUENCE_LIMIT"); return false end
    if not public(GetServerTime) or type(GetServerTime) ~= "function" then
        report("RANKING_TIME_UNAVAILABLE"); return false
    end
    local ok, stamp = pcall(GetServerTime)
    if not ok or not integer(stamp, 1, MAX_TIME) then report("RANKING_TIME_UNAVAILABLE"); return false end
    sequence = sequence + 1
    if #queue >= MAX_EVENTS then
        table.remove(queue, 1)
        report("RANKING_QUEUE_EVICTED")
    end
    queue[#queue + 1] = {id = epochText(stamp) .. "-" .. numberText(sequence),
        spellId = spellID, eventTime = stamp}
    publish(db, queue, sequence)
    report("RANKING_RECORDED")
    return true
end
