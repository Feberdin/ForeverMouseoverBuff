-- Purpose: remind once when a publicly observed personal Paladin seal expires.
-- Input: explicit Check calls and public player auras. Output: one sound request.
-- Invariants: no casts, messages, identities, key changes or persistence of auras.
-- Debug: fixed SEAL_* codes through namespace.Log; tests/test_seal_reminder.lua.
local _, namespace = ...
local SealReminder = {}
namespace.SealReminder = SealReminder
local MAX_AURAS = 255
-- Eight normal 0.25-second polls allow brief frame delays without trusting an
-- old observation after loading, sleep, or a stalled game loop.
local MAX_OBSERVATION_GAP = 2
local expiration, previousTime, cachedNames

-- These Classic IDs are documented in the locally maintained PallyPower
-- LibClassicDurations/classAbilities.lua:830-835. HealBot also identifies 20154
-- as Righteousness. Public localized names recognize future same-family ranks.
local baseIDs = {20154, 21084, 20164, 20165, 20166, 21082, 20375}
local sealIDs = {}
for _, id in ipairs({
    20154, 21084, 20287, 20288, 20289, 20290, 20291, 20292, 20293,
    20164, 20165, 20347, 20348, 20349, 20166, 20356, 20357,
    20162, 20305, 20306, 20307, 20308, 21082, 20375, 20915, 20918, 20919, 20920,
}) do sealIDs[id] = true end

-- Only fixed local codes are retained; repeating a polling state is silent.
-- A failed logging hook leaves an inspectable local code instead of its exception.
local function log(code)
    if SealReminder.LastCode == code then return end
    SealReminder.LastCode = code
    if type(namespace.Log) == "function" then
        local ok = pcall(namespace.Log, namespace, code)
        if not ok then SealReminder.LastCode = "SEAL_LOG_UNAVAILABLE" end
    end
end

local function public(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, restricted = pcall(issecretvalue, value)
    return ok and restricted == false
end

local function readable(value)
    if not public(value) or type(value) ~= "table" or type(canaccesstable) ~= "function" then return false end
    local ok, accessible = pcall(canaccesstable, value)
    return ok and public(accessible) and accessible == true
end

local function field(value, key)
    if not readable(value) then return nil, false end
    local result = rawget(value, key)
    if not public(result) then return nil, false end
    return result, true
end

local function method(value, name)
    local candidate, ok = field(value, name)
    if ok and type(candidate) == "function" then return candidate end
end

local function call(fn, ...)
    if not public(fn) or type(fn) ~= "function" then return false end
    local ok, first, second = pcall(fn, ...)
    -- A native exception is not a string-valued API result. Drop it here so it
    -- can never become a cached localized label or retained diagnostic value.
    if not ok then return false end
    return true, first, second
end

local function finite(value)
    return public(value) and type(value) == "number" and value == value
        and value >= 0 and value < math.huge
end

local function text(value)
    return public(value) and type(value) == "string" and #value > 0 and #value <= 200
        and value:find("%S") ~= nil and not value:find("[%c|]")
end

-- Do not publish partial names: a missing family's localized label could hide
-- a replacement rank and make its disappearance look like natural expiry.
local function sealNames()
    if cachedNames then return cachedNames end
    local getName, getInfo = method(C_Spell, "GetSpellName"), method(C_Spell, "GetSpellInfo")
    local result = {}
    for _, id in ipairs(baseIDs) do
        local ok, name = call(getName, id)
        if not ok or not text(name) then
            local infoOK, info = call(getInfo, id)
            if infoOK then name = field(info, "name") end
        end
        if not text(name) then return nil end
        result[name] = true
    end
    cachedNames = result
    return result
end

-- A complete public HELPFUL scan is required even after finding one seal.
-- More than one seal is ambiguous. Expired-but-still-visible auras remain armed;
-- a timer reaching zero alone is never enough to play the sound.
local function scan()
    if not public(C_Secrets) then return nil, "SEAL_AURAS_UNKNOWN" end
    if C_Secrets ~= nil then
        local ok, restricted = call(method(C_Secrets, "ShouldAurasBeSecret"))
        if not ok or not public(restricted) or restricted ~= false then return nil, "SEAL_AURAS_UNKNOWN" end
    end
    local names = sealNames()
    if not names then return nil, "SEAL_NAMES_UNAVAILABLE" end
    local getter = method(C_UnitAuras, "GetAuraDataByIndex")
    if not getter then return nil, "SEAL_AURAS_UNKNOWN" end
    local activeExpiration, activeDuration
    for index = 1, MAX_AURAS + 1 do
        local ok, aura = call(getter, "player", index, "HELPFUL")
        if not ok or not public(aura) then return nil, "SEAL_AURAS_UNKNOWN" end
        if aura == nil then return {expiration = activeExpiration, duration = activeDuration} end
        if index > MAX_AURAS then return nil, "SEAL_AURA_LIMIT" end
        local id, idOK = field(aura, "spellId")
        local name, nameOK = field(aura, "name")
        if not idOK or not nameOK or not finite(id) or id < 1 or id > 1000000000
            or id ~= math.floor(id) or not text(name) then return nil, "SEAL_AURAS_UNKNOWN" end
        if sealIDs[id] or names[name] then
            if activeExpiration then return nil, "SEAL_AURAS_AMBIGUOUS" end
            local expiry, expiryOK = field(aura, "expirationTime")
            local duration, durationOK = field(aura, "duration")
            if not expiryOK or not durationOK or not finite(expiry) or expiry <= 0
                or not finite(duration) or duration <= 0 then return nil, "SEAL_TIMING_UNKNOWN" end
            activeExpiration, activeDuration = expiry, duration
        end
    end
end

local function forget(code)
    expiration = nil
    log(code)
end

-- The only output boundary consumes the armed state before calling the sound
-- hook. Duplicate events, failed playback, or reentrant calls cannot retry it.
local function sound()
    if type(namespace.PlayFeedbackSound) ~= "function" then log("SEAL_SOUND_FAILED"); return end
    local ok, accepted = pcall(namespace.PlayFeedbackSound, namespace)
    if not ok or not public(accepted) or accepted ~= true then log("SEAL_SOUND_FAILED")
    else log("SEAL_EXPIRED_SOUND_REQUESTED") end
end

function SealReminder.Check()
    if type(namespace.db) ~= "table" or namespace.db.sealSound ~= true then
        previousTime = nil
        forget("SEAL_REMINDER_OFF")
        return
    end
    local classOK, _, class = call(UnitClass, "player")
    if not classOK or not public(class) or class ~= "PALADIN" then
        previousTime = nil
        forget("SEAL_PLAYER_UNAVAILABLE")
        return
    end
    local timeOK, stamp = call(GetTime)
    if not timeOK or not finite(stamp) then
        previousTime = nil
        forget("SEAL_CLOCK_UNAVAILABLE")
        return
    end
    if previousTime and stamp < previousTime then
        previousTime = stamp
        forget("SEAL_CLOCK_RESET")
        return
    end
    local observationGap = previousTime and stamp - previousTime > MAX_OBSERVATION_GAP
    if observationGap then forget("SEAL_OBSERVATION_GAP") end
    previousTime = stamp
    local snapshot, reason = scan()
    if not snapshot then forget(reason or "SEAL_AURAS_UNKNOWN"); return end
    if snapshot.expiration then
        -- The first observation must really be active now. Keep an already
        -- observed seal through one late removal frame, but never arm from a
        -- stale expired aura or an impossible start time in the future.
        if snapshot.expiration - snapshot.duration > stamp
            or (snapshot.expiration <= stamp and snapshot.expiration ~= expiration) then
            forget("SEAL_TIMING_UNKNOWN")
            return
        end
        expiration = snapshot.expiration
        log("SEAL_ARMED")
        return
    end

    local endedAt = expiration
    expiration = nil
    if not endedAt then
        if not observationGap then log("SEAL_IDLE") end
        return
    end
    -- Zero early tolerance: a seal removed at 129.99 with expiry 130 is cleared,
    -- not announced. With the app's 0.25-second poll, natural expiry is detected
    -- at/after the public deadline once an empty complete scan confirms it.
    if stamp < endedAt then log("SEAL_REMOVED_EARLY"); return end
    sound()
end
