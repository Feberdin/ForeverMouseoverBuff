-- Purpose: color our label, honor recipient opt-out and silence our own auto echoes.
-- Input: public whisper events, native frame identity and live display preferences.
-- Output: optional suppression in Blizzard chat and WIM before popup/history/sound.
-- Invariants: no sending, casting, name persistence, or network color escapes;
-- only a recent exact outgoing echo from our sender qualifies for own suppression;
-- manual messages retain native preferences. No recipient identity is persisted.
-- Debug: /fmb debug on; tests/test_chat_display.lua. Logs contain fixed codes only.
local _, ns = ...
local Chat = {}
ns.Chat = Chat
local registered, reported = {}, {}
local configuredWIM
local events = {"CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM"}

-- Chat text can become secret during messaging lockdown. Never compare, measure
-- or parse such values. Missing/broken guards leave the original chat untouched.
local function public(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret == false
end
local function field(value, key)
    if not public(value) or type(value) ~= "table" or type(canaccesstable) ~= "function" then
        return nil
    end
    local ok, accessible = pcall(canaccesstable, value)
    if not ok or not public(accessible) or accessible ~= true then return nil end
    local result = rawget(value, key)
    if public(result) then return result end
    return nil
end
local function report(code)
    if reported[code] then return end
    reported[code] = true
    if type(ns.Log) == "function" then pcall(ns.Log, ns, code) end
end
local function receivingDisabled()
    return field(ns.db, "receiveWhispers") == false
end

-- A missing saved switch uses the silent default, but an unreadable or corrupt
-- value is not permission to hide chat. This distinction matters during lockdown.
local function outgoingHidden()
    local db = ns.db
    if not public(db) or type(db) ~= "table" or type(canaccesstable) ~= "function" then return false end
    local ok, accessible = pcall(canaccesstable, db)
    if not ok or not public(accessible) or accessible ~= true then return false end
    local show = rawget(db, "showOutgoingWhispers")
    return public(show) and (show == nil or show == false)
end

-- The sender records the exact message + recipient before calling SendChatMessage.
-- Example: the matching immediate echo is hidden; the same text to another player
-- or after the 15-second echo window is left to the original chat/WIM behavior.
local function automaticEcho(event, message, receiver)
    if not public(event) or event ~= events[2] or not public(message)
        or not public(receiver) or not outgoingHidden() then return false end
    local matches = field(ns.Whisper, "IsAutomaticEcho")
    if type(matches) ~= "function" then return false end
    local ok, automatic = pcall(matches, event, message, receiver)
    if not ok then report("CHAT_ECHO_MATCH_FAILED"); return false end
    return public(automatic) and automatic == true
end

-- WIM calls these same filters with its own chat display object, other addons
-- may pass nil. Only a known Blizzard frame identity qualifies for suppression;
-- a frame name or the absence of _isWIM is not proof. The native registry includes
-- temporary chat windows. Bound reads and avoid methods on untrusted frames.
local function blizzardFrame(frame)
    if not public(frame) or type(frame) ~= "table" then return false end
    if rawequal(frame, field(_G, "DEFAULT_CHAT_FRAME")) then return true end
    local frames = field(_G, "CHAT_FRAMES")
    for index = 1, 128 do
        local name = field(frames, index)
        if name == nil then return false end
        if type(name) == "string" and #name <= 32 and name:match("^ChatFrame%d+$")
            and rawequal(frame, field(_G, name)) then return true end
    end
    return false
end
local function hideOutgoing(frame, event, message, receiver)
    return blizzardFrame(frame) and automaticEcho(event, message, receiver)
end

-- Identification is deliberately narrow, but is not sender authentication:
-- another player can type the same marked text manually. Only the exact local
-- gold prefix is canonicalized, never arbitrary color codes or user messages.
-- Example: '[Forever Mouseover Buff] "Hallo!" - Sender' is ours; a plain
-- discussion mentioning that addon or an unrelated hyperlink is not.
local function greetingText(event, message)
    if not public(event) or (event ~= events[1] and event ~= events[2])
        or not public(message) or type(message) ~= "string" or #message > 300 then return nil end
    local catalog = ns.Greetings
    if type(catalog) ~= "table" or type(catalog.PlainMessage) ~= "function"
        or type(catalog.PREFIX) ~= "string" or type(catalog.COLOR_PREFIX) ~= "string" then return nil end
    local ok, plain = pcall(catalog.PlainMessage, message)
    if not ok or not public(plain) or type(plain) ~= "string" then
        report("CHAT_GREETING_FORMAT_UNAVAILABLE"); return nil
    end
    if type(catalog.ValidMessage) ~= "function" then return nil end
    local validOK, valid = pcall(catalog.ValidMessage, plain)
    if not validOK or valid ~= true then return nil end
    local body = plain:sub(#catalog.PREFIX + 1)
    return body, catalog.COLOR_PREFIX
end

-- Event filters may run for several frames. No echo is consumed by inspection:
-- no counters, chat sends, or identity logs. Returning all
-- remaining varargs preserves nil holes and future event payload extensions.
local function filter(frame, event, message, ...)
    local body, prefix = greetingText(event, message)
    if not body then return false end
    if event == events[1] and receivingDisabled() then return true end
    local receiver = ...
    if hideOutgoing(frame, event, message, receiver) then return true end
    local decorated = prefix .. body
    if message == decorated then return false end
    return false, decorated, ...
end

-- WIM normally uses the same event filters. The additional ignore/block wrapper
-- enforces recipient opt-out and our silent outgoing preference before native
-- popup/history/sound dispatch, even if WIM's filter runs first. All other
-- arguments and returns, including nil holes, are delegated without changes.
local function configureWIM()
    local original = field(WIM, "IgnoreOrBlockEvent")
    if type(original) ~= "function" then return end
    -- Another addon may wrap this callback later.
    -- Do not alternate wrappers on every preference toggle. Our registered chat
    -- filter remains the primary guard even if a foreign addon replaces its hook.
    if WIM == configuredWIM then return end
    local wrapper = function(event, ...)
        local message, receiver = ...
        if public(event) and event == events[1] and receivingDisabled()
            and greetingText(event, message) then return true, true end
        if greetingText(event, message) and automaticEcho(event, message, receiver) then
            return true, true
        end
        return original(event, ...)
    end
    WIM.IgnoreOrBlockEvent = wrapper
    configuredWIM = WIM
    report("WIM_RECEIVE_FILTER_READY")
end

-- Register each event once, retrying only missing/failed registrations on the
-- next Initialize call. App calls this after SavedVariables and when WIM loads.
-- New clients expose ChatFrameUtil; older clients retain the global alias.
function Chat.Initialize()
    local register
    if public(ChatFrame_AddMessageEventFilter) and type(ChatFrame_AddMessageEventFilter) == "function" then
        register = ChatFrame_AddMessageEventFilter
    else
        register = field(ChatFrameUtil, "AddMessageEventFilter")
    end
    if type(register) ~= "function" then
        report("CHAT_FILTER_API_UNAVAILABLE")
    else
        for _, event in ipairs(events) do
            if not registered[event] then
                local ok = pcall(register, event, filter)
                if ok then registered[event] = true
                else report("CHAT_FILTER_REGISTRATION_FAILED") end
            end
        end
    end
    local ok = pcall(configureWIM)
    if not ok then report("WIM_RECEIVE_FILTER_FAILED") end
    local ready = registered[events[1]] and registered[events[2]] or false
    if ready then report("CHAT_FILTER_READY") end
    return ready
end
