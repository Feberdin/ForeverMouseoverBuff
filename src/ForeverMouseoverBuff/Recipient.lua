-- Purpose: ask one confirmed buff recipient whether an addon greeting is welcome.
-- Input: explicit request plus native addon messages/ticks; output: one boolean callback.
-- Invariants: no chat messages, class checks, broadcasts, saved identities or retries.
-- Debug: tests/test_recipient.lua and anonymous RECIPIENT_* diagnostic codes.
local _, ns = ...
local Recipient = {}
ns.Recipient = Recipient

local PREFIX = "FMB_PREF1"
local ready, session, sequence = false, nil, 0
local pending, pendingCount = {}, 0
local lastClock
local responses = {}
local PENDING_LIMIT, DEADLINE = 16, 1
local RESPONSE_LIMIT, RESPONSE_WINDOW = 8, 1

-- Never publish raw native errors: even transport errors can contain identities.
-- LastCode remains observable if the owning addon's diagnostic callback fails.
local function log(code)
    Recipient.LastCode = code
    if type(ns.Log) == "function" then
        local ok = pcall(ns.Log, ns, code)
        if not ok then Recipient.LastCode = "RECIPIENT_LOG_FAILED" end
    end
end
local function public(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret == false
end
local function field(value, key)
    if not public(value) or type(value) ~= "table" or type(canaccesstable) ~= "function" then return nil, false end
    local ok, accessible = pcall(canaccesstable, value)
    if not ok or not public(accessible) or accessible ~= true then return nil, false end
    local result = rawget(value, key)
    if not public(result) then return nil, false end
    return result, true
end
local function method(key)
    local fn, readable = field(C_ChatInfo, key)
    if readable and type(fn) == "function" then return fn end
end
local function identity(value)
    -- Keep the exact native name/realm string; the caller owns identity matching.
    return public(value) and type(value) == "string" and #value >= 1 and #value <= 225
        and value:match("^[A-Za-z\128-\255][A-Za-z0-9\128-\255 '%-]*$") ~= nil
        and value:match("[ %-]$") == nil
end
local function runCallback(callback, allowed)
    -- Callbacks are local code supplied by Whisper, not native game data.
    if type(callback) ~= "function" then log("RECIPIENT_CALLBACK_INVALID"); return end
    local ok = pcall(callback, allowed)
    if not ok then log("RECIPIENT_CALLBACK_FAILED") end
end
local function reject(callback, code)
    log(code)
    runCallback(callback, false)
    return false
end

-- Consume before invoking external callbacks. Reentrant or duplicate replies
-- cannot send two greetings, even if a callback throws or processes another event.
local function complete(entry, allowed, code)
    if entry.done then return end
    entry.done = true
    if pending[entry.nonce] == entry then
        pending[entry.nonce] = nil
        pendingCount = pendingCount - 1
    end
    local callback = entry.callback
    entry.callback, entry.matchesSender = nil, nil
    log(code)
    runCallback(callback, allowed)
end
local function abortPending(code)
    local entries = pending
    pending, pendingCount, responses = {}, 0, {}
    log(code)
    for _, entry in pairs(entries) do complete(entry, false, code) end
end

-- Any unreadable/backwards clock closes pending requests; it is never interpreted
-- as a successful one-second wait. New requests can recover on a later good tick.
local function clock()
    local ok, stamp
    if public(GetTime) and type(GetTime) == "function" then ok, stamp = pcall(GetTime) end
    if not ok or not public(stamp) or type(stamp) ~= "number" or stamp ~= stamp
        or stamp < 0 or stamp > 1000000000 then
        abortPending("RECIPIENT_CLOCK_UNAVAILABLE"); return nil
    end
    if lastClock and stamp < lastClock then
        lastClock = stamp
        abortPending("RECIPIENT_CLOCK_REVERSED"); return nil
    end
    lastClock = stamp
    return stamp
end
local function pruneResponses(stamp)
    for index = #responses, 1, -1 do
        if stamp - responses[index].stamp >= RESPONSE_WINDOW then table.remove(responses, index) end
    end
end
local function expire(stamp)
    -- Take a snapshot: callbacks may enqueue another request during completion.
    local due = {}
    for _, entry in pairs(pending) do
        if not entry.sending and stamp - entry.started >= DEADLINE then due[#due + 1] = entry end
    end
    for _, entry in ipairs(due) do complete(entry, true, "RECIPIENT_NO_REPLY") end
    pruneResponses(stamp)
end

-- Native 70338 enum contract: registration Success=0, DuplicatePrefix=1;
-- sending Success=0. Legacy true/nil are intentionally not guessed as success.
-- Sources are pinned under docs/recipient-2026-10-11/Chat*Documentation.lua.
function Recipient.Initialize()
    if ready then return true end
    local register = method("RegisterAddonMessagePrefix")
    if not register or not method("SendAddonMessage") then log("RECIPIENT_API_UNAVAILABLE"); return false end
    local stamp = clock()
    if not stamp then return false end
    local ok, result = pcall(register, PREFIX)
    if not ok or not public(result) or type(result) ~= "number" or (result ~= 0 and result ~= 1) then
        log("RECIPIENT_REGISTER_FAILED"); return false
    end
    session = "t" .. string.format("%.0f", math.floor(stamp * 1000))
    ready = true
    log("RECIPIENT_READY")
    return true
end
local function send(payload, target)
    local fn = method("SendAddonMessage")
    if not fn then return false, "RECIPIENT_API_UNAVAILABLE" end
    local ok, result = pcall(fn, PREFIX, payload, "WHISPER", target)
    if not ok or not public(result) or type(result) ~= "number" or result ~= 0 then
        return false, "RECIPIENT_SEND_FAILED"
    end
    return true
end

-- Only the confirmed-cast caller may request a check. This module cannot infer
-- that authorization from a target token, so it never watches units or spellcasts.
function Recipient.Request(receiver, matchesSender, callback)
    if type(callback) ~= "function" then log("RECIPIENT_CALLBACK_INVALID"); return false end
    if not identity(receiver) or type(matchesSender) ~= "function" then
        return reject(callback, "RECIPIENT_REQUEST_INVALID")
    end
    if not ready and not Recipient.Initialize() then return reject(callback, "RECIPIENT_NOT_READY") end
    local stamp = clock()
    if not stamp then return reject(callback, "RECIPIENT_CLOCK_UNAVAILABLE") end
    expire(stamp)
    if pendingCount >= PENDING_LIMIT then return reject(callback, "RECIPIENT_QUEUE_FULL") end
    if sequence >= 1000000000 then return reject(callback, "RECIPIENT_NONCE_EXHAUSTED") end
    sequence = sequence + 1
    local nonce = session .. "n" .. string.format("%.0f", sequence)
    local entry = {nonce = nonce, started = stamp, callback = callback,
        matchesSender = matchesSender, sending = true}
    pending[nonce], pendingCount = entry, pendingCount + 1
    local ok, code = send("Q:1:" .. nonce, receiver)
    entry.sending = false
    if entry.done then return false end
    if not ok then complete(entry, false, code); return false end
    -- A synchronous reply is buffered until the native send returns Success.
    if entry.answer ~= nil then complete(entry, entry.answer, entry.answerCode)
    else log("RECIPIENT_QUERY_SENT") end
    return true
end
function Recipient.Tick()
    if not ready then return end
    local stamp = clock()
    if stamp then expire(stamp) end
end

local function replyAllowed(stamp, sender)
    pruneResponses(stamp)
    if #responses >= RESPONSE_LIMIT then log("RECIPIENT_RESPONSE_THROTTLED"); return false end
    for _, entry in ipairs(responses) do
        if entry.sender == sender then log("RECIPIENT_RESPONSE_THROTTLED"); return false end
    end
    -- Count even failed sends, preventing an API failure from causing retry spam.
    responses[#responses + 1] = {sender = sender, stamp = stamp}
    return true
end
local function receivePreference()
    if public(ns.db) and ns.db == nil then return true end
    local value, readable = field(ns.db, "receiveWhispers")
    if not readable or (value ~= nil and type(value) ~= "boolean") then
        log("RECIPIENT_PREFERENCE_UNKNOWN"); return false
    end
    return value ~= false
end
local function acceptAnswer(entry, allowed, code)
    if entry.sending then
        -- A later denial may override an early allow within a reentrant native call.
        if entry.answer == nil or not allowed then entry.answer, entry.answerCode = allowed, code end
    else complete(entry, allowed, code) end
end

-- Event arguments are checked before string operations or matching. Only the
-- native sender argument can satisfy the caller's already proven recipient match.
function Recipient.OnMessage(prefix, payload, channel, sender)
    if not public(prefix) or not public(channel) or not public(payload) or not public(sender) then
        log("RECIPIENT_EVENT_RESTRICTED"); return false
    end
    if prefix ~= PREFIX or channel ~= "WHISPER" then return false end
    if type(payload) ~= "string" or #payload > 36 or not identity(sender) then return false end
    local kind, nonce = payload:match("^([QAD]):1:([A-Za-z0-9]+)$")
    if not kind or #nonce > 32 then return false end
    if not ready and not Recipient.Initialize() then return false end
    local stamp = clock()
    if not stamp then return false end
    expire(stamp)
    if kind == "Q" then
        if not replyAllowed(stamp, sender) then return false end
        local answer = receivePreference() and "A" or "D"
        local ok, code = send(answer .. ":1:" .. nonce, sender)
        log(ok and "RECIPIENT_RESPONSE_SENT" or code)
        return ok
    end
    local entry = pending[nonce]
    if not entry then return false end
    local ok, matches = pcall(entry.matchesSender, sender)
    if not ok or not public(matches) or type(matches) ~= "boolean" then
        acceptAnswer(entry, false, "RECIPIENT_MATCH_FAILED"); return false
    end
    if not matches then return false end
    local allowed = kind == "A"
    acceptAnswer(entry, allowed, allowed and "RECIPIENT_ALLOWED" or "RECIPIENT_DENIED")
    return true
end
