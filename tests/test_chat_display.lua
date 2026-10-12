-- Purpose: verify silent outgoing greetings with our real sender and chat filter.
-- Input: synthetic public/secret chat API boundaries; output: deterministic PASS/FAIL.
-- Invariants: no native WIM source, live network, user data, or real game execution.
-- Debug: lua tests/test_chat_display.lua [test_name] from the repository root.
local tests = {}
local function pack(...) return {n = select("#", ...), ...} end
local function equal(actual, expected, reason)
    assert(actual == expected, reason or "unexpected display result")
end
local function loadModule(file, env, ns)
    local path = "src/ForeverMouseoverBuff/" .. file .. ".lua"
    local chunk
    if setfenv then chunk = assert(loadfile(path)); setfenv(chunk, env)
    else chunk = assert(loadfile(path, "t", env)) end
    chunk("ForeverMouseoverBuff", ns)
end

-- Fake only WoW registration, frame identity and the WIM callback boundary.
-- The real sender creates the exact echo cache; tests never mock that decision.
local function fixture(modern)
    local f = {time = 100, filters = {}, registrations = 0, sent = {}, delegated = {}, logs = {}}
    local env = setmetatable({}, {__index = _G})
    env._G, f.env = env, env
    f.secret = setmetatable({}, {__tostring = function() error("secret printed") end})
    f.opaque = setmetatable({}, {__index = function() error("opaque inspected") end})
    env.issecretvalue = function(value) return rawequal(value, f.secret) end
    env.canaccesstable = function(value) return not rawequal(value, f.opaque) end
    env.GetTime = function() return f.time end
    env.DEFAULT_CHAT_FRAME = {}; env.ChatFrame1 = env.DEFAULT_CHAT_FRAME
    env.CHAT_FRAMES = {"ChatFrame1"}
    local function register(event, callback)
        f.filters[event] = callback; f.registrations = f.registrations + 1
    end
    if not modern then env.ChatFrame_AddMessageEventFilter = register end
    env.ChatFrameUtil = modern and {AddMessageEventFilter = register} or nil
    env.RegionalUniqueNamesEnabled = function() return true end
    env.UnitIsPlayer, env.UnitCanAssist = function() return true end, function() return true end
    env.UnitRace, env.UnitSex = nil, nil
    env.UnitClass = function() return "Paladin", "PALADIN" end
    env.NameUtil = {GetUnmodifiedUnitFullName = function(unit)
        return unit == "player" and "Testpaladin" or "Testreceiver Example"
    end}
    env.Enum = {SpellBookSpellBank = {Player = 0}}
    env.C_SpellBook = {IsSpellKnown = function(id) return id == 20217 end}
    env.C_ChatInfo = {SendChatMessage = function(message, channel, language, receiver)
        equal(channel, "WHISPER"); equal(language, nil)
        f.sent[#f.sent + 1] = {message, receiver}
        if f.onSend then f.onSend(message, receiver) end
        return f.sendResult
    end}
    env.CastSpellByName = function() error("display must not cast") end
    f.ns = {db = {whisper = true, receiveWhispers = true}, Log = function(_, code)
        f.logs[#f.logs + 1] = code
    end, Recipient = {Request = function(_, _, callback) callback(true); return true end}}
    for _, file in ipairs({"SpellLink", "GreetingCatalog", "Greetings", "Whisper", "Chat"}) do
        loadModule(file, env, f.ns)
    end
    function f:loadWIM()
        self.env.WIM = {IgnoreOrBlockEvent = function(...)
            self.delegated[#self.delegated + 1] = pack(...)
            return false, false, nil, "native-result"
        end}
    end
    function f:initialize() return self.ns.Chat.Initialize() end
    function f:buff()
        equal(self.ns.Whisper.Begin(20217), true, "synthetic blessing must begin")
        equal(self.ns.Whisper.Sent("player", "Testreceiver Example", "Cast-1", 20217), true,
            "synthetic blessing must enter the sent state")
        return self.ns.Whisper.Complete("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 20217)
    end
    function f:echo(message, receiver, event)
        local sent = self.sent[1]
        return self.env.WIM.IgnoreOrBlockEvent(event or "CHAT_MSG_WHISPER_INFORM",
            message or sent[1], receiver or sent[2], nil, 42)
    end
    return f
end

function tests.default_hides_the_exact_automatic_echo_in_wim_and_blizzard_with_either_load_order()
    for _, modern in ipairs({false, true}) do
        for _, wimFirst in ipairs({false, true}) do
            local f = fixture(modern)
            if wimFirst then f:loadWIM() end
            f:initialize()
            if not wimFirst then f:loadWIM(); f:initialize() end
            local ignored, blocked, blizzardHidden
            f.onSend = function(message, receiver)
                ignored, blocked = f:echo(message, receiver)
                blizzardHidden = f.filters.CHAT_MSG_WHISPER_INFORM(f.env.ChatFrame1,
                    "CHAT_MSG_WHISPER_INFORM", message, receiver)
            end
            equal(f:buff(), true, "synthetic blessing must complete")
            equal(ignored, true, "own automatic echo must bypass WIM popup/history/sound dispatch")
            equal(blocked, true, "WIM must suppress the ordinary whisper echo as well")
            equal(blizzardHidden, true)
            equal(#f.sent, 1, "silent display must still send the authorized greeting")
            equal(#f.delegated, 0)
        end
    end
end

function tests.showing_own_greetings_delegates_native_preferences_and_full_return_tuple()
    local f = fixture(); f:loadWIM(); f:initialize(); equal(f:buff(), true)
    f.ns.db.showOutgoingWhispers = true
    local result = pack(f:echo())
    equal(result.n, 4); equal(result[1], false); equal(result[2], false)
    equal(result[3], nil); equal(result[4], "native-result")
    equal(f.delegated[1].n, 5); equal(f.delegated[1][4], nil); equal(f.delegated[1][5], 42)
    f.ns.db.showOutgoingWhispers = false
    equal(f:echo(), true, "live setting must take effect without reload or rewrapping")
end

function tests.manual_other_receiver_expired_and_incoming_messages_keep_native_display()
    local f = fixture(); f:loadWIM(); f:initialize(); equal(f:buff(), true)
    equal(f:echo("Danke für die Gruppe!"), false)
    equal(f:echo(nil, "Another Receiver"), false)
    equal(f:echo(f.sent[1][1] .. "?"), false)
    equal(f:echo(nil, nil, "CHAT_MSG_WHISPER"), false)
    f.time = 116; equal(f:echo(), false, "a later manually repeated greeting must remain visible")
    equal(#f.delegated, 5)
end

function tests.secret_inputs_and_unreadable_preferences_are_delegated_without_inspection()
    local f = fixture(); f:loadWIM(); f:initialize(); equal(f:buff(), true)
    equal(f:echo(f.secret), false); equal(f:echo(nil, f.secret), false)
    equal(f:echo(nil, nil, f.secret), false)
    for _, db in ipairs({f.secret, f.opaque, {showOutgoingWhispers = f.secret}, "invalid"}) do
        f.ns.db = db
        equal(f:echo(), false, "unreadable preferences cannot authorize suppression")
    end
    f.ns.db = {showOutgoingWhispers = false}
    f.env.issecretvalue = function() error("synthetic guard failure") end
    equal(f:echo(), false)
end

function tests.failed_send_or_unreadable_matcher_cannot_suppress_manual_chat()
    local f = fixture(); f:loadWIM(); f:initialize(); f.sendResult = false
    equal(f:buff(), false); equal(f:echo(), false)
    for _, matcher in ipairs({f.secret, function() return f.secret end,
        function() error("private matcher detail") end}) do
        f.ns.Whisper.IsAutomaticEcho = matcher; equal(f:echo(), false)
    end
    for _, code in ipairs(f.logs) do assert(code:match("^[A-Z_]+$")) end
end

function tests.receive_opt_out_is_separate_and_reinitialization_never_stacks_wrappers()
    local f = fixture(true); f:loadWIM(); f:initialize(); equal(f:buff(), true)
    local wrapper = f.env.WIM.IgnoreOrBlockEvent
    for _ = 1, 5 do f:initialize() end
    equal(f.registrations, 2); equal(f.env.WIM.IgnoreOrBlockEvent, wrapper)
    f.ns.db.showOutgoingWhispers, f.ns.db.receiveWhispers = true, false
    equal(f:echo(), false)
    local ignore, block = f:echo(nil, nil, "CHAT_MSG_WHISPER")
    equal(ignore, true); equal(block, true)
    local calls = 0
    local outer = function(...) calls = calls + 1; return wrapper(...) end
    f.env.WIM.IgnoreOrBlockEvent = outer; f:initialize()
    equal(f.env.WIM.IgnoreOrBlockEvent, outer)
    equal(f:echo(), false); equal(calls, 1)
end

local requested, names = arg and arg[1], {}
for name in pairs(tests) do if not requested or name == requested then names[#names + 1] = name end end
table.sort(names); assert(#names > 0, "unknown test name")
for _, name in ipairs(names) do
    local ok, failure = pcall(tests[name])
    if not ok then io.stderr:write("FAIL " .. name .. ": " .. tostring(failure) .. "\n"); os.exit(1) end
    print("PASS " .. name)
end
print("PASS " .. #names .. " chat display tests")
