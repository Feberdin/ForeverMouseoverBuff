-- Purpose: Whisper a rotating personal blessing only after a matching successful cast.
-- Input: explicit click plus public SENT/SUCCEEDED/FAILED/INTERRUPTED events.
-- Output: at most one WHISPER request per confirmed cast, a bounded runtime echo
-- matcher for local display, and fixed diagnostic codes. WIM is never modified.
-- Invariants: names/traits/GUIDs stay closure-local, never SavedVariables or logs;
-- separate Stats/RankingExport retain bounded anonymous spell counts/events only;
-- the greeting index is anonymous and own echoes expire in 15s.
-- no target retargeting, delayed retry, sender fallback, or send on Begin/Sent.
-- Debug: /fmb debug on; tests/test_whisper.lua. WHISPER_REQUESTED is not delivery proof.
local _, ns = ...
local Whisper = {}
ns.Whisper = Whisper
local pending
local echoes, lastGreetingIndex = {}, 0
local echoLifetime, echoLimit = 15, 16
local completed, completedOrder = {}, {}
local lifetime, completedLimit = 5, 64
local blessings = {
    [19740] = true, [19834] = true, [19835] = true, [19836] = true,
    [19837] = true, [19838] = true, [25291] = true, [27140] = true,
    [48931] = true, [48932] = true, [19742] = true, [19850] = true,
    [19852] = true, [19853] = true, [19854] = true, [25290] = true,
    [27142] = true, [48935] = true, [48936] = true, [20217] = true,
}

-- Guard every game value before comparison, formatting, or indexing. Native
-- exception strings may expose private identities, so diagnostics use constants.
local function log(code)
    if type(ns.Log) == "function" then pcall(ns.Log, ns, code) end
end
local function public(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret == false
end
local function field(value, key)
    if not public(value) or type(value) ~= "table" or type(canaccesstable) ~= "function" then
        return nil, false
    end
    local ok, accessible = pcall(canaccesstable, value)
    if not ok or not public(accessible) or accessible ~= true then return nil, false end
    local item = rawget(value, key)
    if not public(item) then return nil, false end
    return item, true
end
local function call(fn, ...)
    if not public(fn) or type(fn) ~= "function" then return false end
    local ok, first, second = pcall(fn, ...)
    if not ok or not public(first) or not public(second) then return false end
    return true, first, second
end
local function clock()
    local ok, value = call(GetTime)
    if ok and type(value) == "number" and value == value and value >= 0 and value < math.huge then
        return value
    end
end
local function positiveID(value)
    return public(value) and type(value) == "number" and value >= 1
        and value <= 1000000000 and value == math.floor(value)
end
local function name(value)
    return public(value) and type(value) == "string" and #value >= 1 and #value <= 96
        and value:match("^[A-Za-z\128-\255][A-Za-z\128-\255 %-]*$") ~= nil
        and value:match("[ %-]$") == nil
end
local function realm(value)
    if not public(value) or type(value) ~= "string" or #value == 0 or #value > 128
        or not value:match("^[A-Za-z0-9\128-\255 '%-]+$") then return nil end
    local normalized = value:gsub(" ", "")
    if #normalized == 0 then return nil end
    return normalized
end
local function guid(value)
    return public(value) and type(value) == "string" and #value <= 200
        and value:match("^Cast%-%w[%w%-]*$") ~= nil
end
local function unitName(unit)
    if not public(UnitFullName) then return nil end
    local reader = UnitFullName
    if reader == nil then reader = UnitName end
    local ok, value, server = call(reader, unit)
    if ok and name(value) then return value, server end
end
local function playerFlag(fn, ...)
    local ok, value = call(fn, ...)
    return ok and value == true
end
local function learned(id)
    local bankTable = field(Enum, "SpellBookSpellBank")
    local bank = field(bankTable, "Player")
    local known = field(C_SpellBook, "IsSpellKnown")
    if type(bank) ~= "number" or bank < 0 or bank > 10 or bank ~= math.floor(bank) then return false end
    return playerFlag(known, id, bank)
end
local function enabled()
    return not ns.db or ns.db.whisper ~= false
end
local function reject(code)
    pending = nil
    log(code)
    return false
end
local function current()
    if not pending then return nil end
    local stamp = clock()
    if not stamp or stamp < pending.started or stamp - pending.started > lifetime then
        reject("WHISPER_ATTEMPT_EXPIRED")
        return nil
    end
    return pending
end

-- Traits are optional flavor, never evidence for identity or buff selection.
-- Recipient race/sex only affect the address. Sender race/class choose the voice.
-- Missing/secret traits remain absent; the formatter uses neutral words instead.
local function recipientProfile(attempt)
    local profile = {receiverName = attempt.regional and attempt.receiver or attempt.name,
        senderName = attempt.sender}
    local raceOK, _, raceToken = call(UnitRace, "mouseover")
    if raceOK and type(raceToken) == "string" and #raceToken <= 40
        and raceToken:match("^[A-Za-z]+$") then profile.raceToken = raceToken end
    local senderRaceOK, _, senderRace = call(UnitRace, "player")
    if senderRaceOK and type(senderRace) == "string" and #senderRace <= 40
        and senderRace:match("^[A-Za-z]+$") then profile.senderRace = senderRace end
    local sexOK, sex = call(UnitSex, "mouseover")
    if sexOK and (sex == 2 or sex == 3) then profile.sex = sex end
    return profile
end

-- Snapshot only the clicked friendly player and the sender. Local short event
-- names are safe only after proving that their realm equals our current realm.
-- Example: Example-OtherRealm must not match SENT target "Example" alone.
function Whisper.Begin(spellID)
    if current() then
        pending.ambiguous = true
        log("WHISPER_ATTEMPT_AMBIGUOUS")
        return false
    end
    if not positiveID(spellID) or not blessings[spellID] or not learned(spellID) then
        return reject("WHISPER_SPELL_UNAVAILABLE")
    end
    local stamp = clock()
    if not stamp then return reject("WHISPER_CLOCK_UNAVAILABLE") end
    if not playerFlag(UnitIsPlayer, "mouseover") or not playerFlag(UnitCanAssist, "player", "mouseover") then
        return reject("WHISPER_TARGET_UNAVAILABLE")
    end
    local modeOK, regional = call(RegionalUniqueNamesEnabled)
    if not modeOK or type(regional) ~= "boolean" then return reject("WHISPER_NAME_MODE_UNAVAILABLE") end
    if regional then
        -- Camelot's native helper joins first name + surname. The second value
        -- of UnitName is a surname here, never a realm to append or reinterpret.
        local fullName = field(NameUtil, "GetUnmodifiedUnitFullName")
        local senderOK, sender = call(fullName, "player")
        local targetOK, target = call(fullName, "mouseover")
        if not senderOK or not targetOK or not name(sender) or not name(target) then
            return reject("WHISPER_IDENTITY_UNAVAILABLE")
        end
        pending = {spellID = spellID, started = stamp, receiver = target,
            sender = sender, regional = true}
    else
        local sender, senderRealm = unitName("player")
        local target, targetRealm = unitName("mouseover")
        if not sender or not target then return reject("WHISPER_IDENTITY_UNAVAILABLE") end
        if not public(GetNormalizedRealmName) then return reject("WHISPER_REALM_UNAVAILABLE") end
        local localRealm
        if GetNormalizedRealmName == nil then
            localRealm = realm(senderRealm)
        else
            local ok, value = call(GetNormalizedRealmName)
            if ok then localRealm = realm(value) end
        end
        if not localRealm then return reject("WHISPER_REALM_UNAVAILABLE") end
        if targetRealm == nil or targetRealm == "" then targetRealm = localRealm end
        targetRealm = realm(targetRealm)
        if not targetRealm then return reject("WHISPER_REALM_UNAVAILABLE") end
        pending = {spellID = spellID, started = stamp, name = target, realm = targetRealm,
            receiver = target .. "-" .. targetRealm, sender = sender, localRealm = localRealm,
            regional = false}
    end
    pending.isSelf = pending.regional and pending.receiver == pending.sender
        or not pending.regional and pending.name == pending.sender and pending.realm == pending.localRealm
    local classOK, _, classToken = call(UnitClass, "player")
    pending.paladin = classOK and classToken == "PALADIN"
    pending.profile = recipientProfile(pending)
    if classOK and type(classToken) == "string" and #classToken <= 32
        and classToken:match("^[A-Z]+$") then
        pending.profile.senderClass = classToken
    else log("GREETING_SENDER_CLASS_UNAVAILABLE") end
    log("WHISPER_PREPARED")
    return true
end

local function matchesTarget(attempt, target)
    if not public(target) or type(target) ~= "string" or #target > 225 then return false end
    if attempt.regional then return target == attempt.receiver end
    if target == attempt.name then return attempt.realm == attempt.localRealm end
    -- The name may itself contain hyphens: match its proven complete prefix,
    -- then validate only the remaining realm rather than splitting at a hyphen.
    local prefix = attempt.name .. "-"
    if target:sub(1, #prefix) ~= prefix then return false end
    return realm(target:sub(#prefix + 1)) == attempt.realm
end

-- SENT is the only source of the cast GUID. Conflicting SENT events invalidate
-- the attempt; duplicate delivery of the exact same event remains idempotent.
function Whisper.Sent(unit, target, castGUID, spellID)
    local attempt = current()
    if not attempt then return false end
    if not public(unit) then return reject("WHISPER_EVENT_RESTRICTED") end
    if unit ~= "player" then return false end
    if attempt.ambiguous or not positiveID(spellID) or spellID ~= attempt.spellID
        or not guid(castGUID) or completed[castGUID] or not matchesTarget(attempt, target) then
        return reject("WHISPER_SENT_UNMATCHED")
    end
    if attempt.castGUID and attempt.castGUID ~= castGUID then
        return reject("WHISPER_SENT_AMBIGUOUS")
    end
    attempt.castGUID = castGUID
    log("WHISPER_CAST_BOUND")
    return true
end

-- Prefer the current client namespace. The legacy global is used only when the
-- namespace/method is absent, never to work around an opaque or broken namespace.
local function senderAPI()
    if not public(C_ChatInfo) then return nil end
    if C_ChatInfo ~= nil then
        local method, readable = field(C_ChatInfo, "SendChatMessage")
        if not readable then return nil end
        if method ~= nil then return type(method) == "function" and method or nil end
    end
    if public(SendChatMessage) and type(SendChatMessage) == "function" then return SendChatMessage end
end
local function remember(castGUID)
    completed[castGUID] = true
    completedOrder[#completedOrder + 1] = castGUID
    if #completedOrder > completedLimit then
        completed[table.remove(completedOrder, 1)] = nil
    end
end

-- A persisted integer rotates the twelve texts across reloads without keeping
-- a recipient history. Failed casts/sends never consume the next greeting.
local function greeting(attempt)
    local catalog = ns.Greetings
    if type(catalog) ~= "table" or type(catalog.Format) ~= "function"
        or not positiveID(catalog.COUNT) or catalog.COUNT > 100 then
        log("WHISPER_GREETING_UNAVAILABLE"); return nil
    end
    local previous = ns.db and ns.db.greetingIndex
    if public(previous) and previous == nil then previous = lastGreetingIndex end
    if not public(previous) or type(previous) ~= "number" or previous ~= previous
        or previous < 0 or previous > catalog.COUNT or previous ~= math.floor(previous) then
        previous = 0
    end
    local index = previous % catalog.COUNT + 1
    local ok, message, code = pcall(catalog.Format, attempt.profile, index)
    if not ok or not public(message) or type(message) ~= "string" or #message == 0
        or #message > 255 or type(catalog.ValidMessage) ~= "function"
        or not catalog.ValidMessage(message, attempt.spellID) then
        log("WHISPER_GREETING_INVALID"); return nil
    end
    if code == "GREETING_DETAILS_OMITTED" then log(code) end
    return message, index
end

-- Chat frames can inspect the same echo repeatedly, so entries are not consumed by a
-- first match. Both exact text and the already verified receiver must match.
-- At most sixteen transient entries survive; clock failure clears them safely.
local function pruneEchoes()
    local stamp = clock()
    for index = #echoes, 1, -1 do
        local entry = echoes[index]
        if not stamp or stamp < entry.started or stamp - entry.started > echoLifetime then
            table.remove(echoes, index)
        end
    end
    return stamp
end
local function rememberEcho(attempt, message)
    local stamp = pruneEchoes()
    if not stamp then log("CHAT_ECHO_UNAVAILABLE"); return nil end
    local entry = {attempt = attempt, message = message, started = stamp}
    echoes[#echoes + 1] = entry
    if #echoes > echoLimit then table.remove(echoes, 1) end
    return entry
end
local function forgetEcho(entry)
    if not entry then return end
    for index = #echoes, 1, -1 do
        if echoes[index] == entry then table.remove(echoes, index); return end
    end
end
-- Read-only public match contract for Chat.lua. A manually typed identical text
-- to the same receiver within 15s is indistinguishable from the native echo.
-- No private entry/table is returned and callers cannot consume an echo.
function Whisper.IsAutomaticEcho(event, message, receiver)
    pruneEchoes()
    if not public(event) or event ~= "CHAT_MSG_WHISPER_INFORM"
        or not public(message) or type(message) ~= "string" or #message > 300 then return false end
    if ns.Greetings and type(ns.Greetings.PlainMessage) == "function" then
        local ok, plain = pcall(ns.Greetings.PlainMessage, message)
        if not ok or not public(plain) or type(plain) ~= "string" then return false end
        message = plain
    end
    for _, entry in ipairs(echoes) do
        if message == entry.message and matchesTarget(entry.attempt, receiver) then return true end
    end
    return false
end

-- The cast is already confirmed. A recipient handshake may delay this request,
-- so recheck the sender switch and clock before formatting the next greeting.
local function sendGreeting(attempt)
    if not enabled() then log("WHISPER_DISABLED"); return false end
    local stamp = clock()
    if not stamp or stamp < attempt.started or stamp - attempt.started > lifetime + 2 then
        log("WHISPER_ATTEMPT_EXPIRED"); return false
    end
    local send = senderAPI()
    if not send then log("WHISPER_SEND_UNAVAILABLE"); return false end
    local message, index = greeting(attempt)
    if not message then return false end
    -- Register before SendChatMessage: even a synchronous echo can be filtered.
    -- A failed request removes its entry and cannot hide a later manual message.
    local echo = rememberEcho(attempt, message)
    local ok, result = pcall(send, message, "WHISPER", nil, attempt.receiver)
    if not ok or not public(result) or result == false then
        forgetEcho(echo)
        log("WHISPER_SEND_FAILED"); return false
    end
    lastGreetingIndex = index
    if ns.db then ns.db.greetingIndex = index end
    log("WHISPER_REQUESTED")
    return true
end

-- Count the matched client event independently of chat preferences/delivery.
-- Only a friendly other player and a proven Paladin caster qualify. Snapshot the
-- count now: a delayed recipient response must not display a later cast's count.
local function recordSuccess(attempt)
    if attempt.isSelf or not attempt.paladin then return end
    if ns.Stats and type(ns.Stats.Record) == "function" then
        local ok, counted = pcall(ns.Stats.Record, attempt.spellID, attempt.castGUID)
        if not ok then log("STATS_RECORD_FAILED"); return end
        if counted == true then
            local totalOK, total = pcall(ns.Stats.Total)
            if totalOK and public(total) and type(total) == "number" and total >= 0
                and total <= 1000000000 and total == math.floor(total) then
                attempt.profile.buffCount = total
            else log("STATS_TOTAL_UNAVAILABLE") end
            if ns.RankingExport and type(ns.RankingExport.Record) == "function" then
                local exportOK = pcall(ns.RankingExport.Record, attempt.spellID)
                if not exportOK then log("RANKING_EXPORT_FAILED") end
            end
        end
    end
end

-- Consume the attempt before invoking native chat, even when the API errors.
-- A send error must not turn a later duplicate event into a second message.
function Whisper.Complete(event, unit, castGUID, spellID)
    local attempt = current()
    if not attempt then return false end
    if not public(unit) then return reject("WHISPER_EVENT_RESTRICTED") end
    if unit ~= "player" then return false end
    if not public(event) or not guid(castGUID) or not positiveID(spellID)
        or attempt.ambiguous or not attempt.castGUID or castGUID ~= attempt.castGUID
        or spellID ~= attempt.spellID or completed[castGUID] then
        return reject("WHISPER_COMPLETE_UNMATCHED")
    end
    pending = nil
    remember(castGUID)
    if event ~= "UNIT_SPELLCAST_SUCCEEDED" then log("WHISPER_CAST_NOT_SUCCEEDED"); return false end
    if not name(attempt.sender) or not matchesTarget(attempt, attempt.receiver) then
        log("WHISPER_IDENTITY_UNAVAILABLE"); return false
    end
    recordSuccess(attempt)
    if not enabled() then log("WHISPER_DISABLED"); return false end
    if ns.SpellLink and type(ns.SpellLink.Get) == "function" then
        local linkOK, link = pcall(ns.SpellLink.Get, spellID)
        if linkOK and public(link) and type(link) == "string" then
            attempt.profile.spellLink = link
        else log("WHISPER_LINK_UNAVAILABLE") end
    end
    local recipient = ns.Recipient
    if type(recipient) ~= "table" or type(recipient.Request) ~= "function" then
        log("WHISPER_RECIPIENT_UNAVAILABLE"); return false
    end
    local consumed, delivered = false, false
    local function decision(allowed)
        if consumed then return end
        consumed = true
        if not public(allowed) or allowed ~= true then
            log("WHISPER_RECIPIENT_DECLINED"); return
        end
        delivered = sendGreeting(attempt)
    end
    local ok, accepted = pcall(recipient.Request, attempt.receiver,
        function(sender) return matchesTarget(attempt, sender) end, decision)
    if not ok or accepted ~= true then
        log("WHISPER_RECIPIENT_FAILED"); return false
    end
    -- Immediate callbacks preserve synchronous failure diagnostics; normally the
    -- result arrives on CHAT_MSG_ADDON or the bounded one-second no-addon timeout.
    if consumed then return delivered end
    log("WHISPER_RECIPIENT_PENDING")
    return true
end
