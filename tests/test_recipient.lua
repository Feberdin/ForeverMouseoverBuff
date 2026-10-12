-- Purpose: exercise the real recipient protocol through synthetic native API boundaries.
-- Input: fake public/secret events and clock; output: PASS/FAIL, never real messages.
-- Invariants: no live API, real identity, persistence or network; Lua 5.1 and 5.5.
-- Debug: lua tests/test_recipient.lua [test_name] from the project directory.
local tests = {}
local function equal(actual, expected, reason)
    assert(actual == expected, reason or "unexpected recipient result")
end
local function fixture()
    local f = {time = 100, registered = {}, sent = {}, replies = {}, logs = {}, registerResult = 0, sendResult = 0}
    f.secret = setmetatable({}, {__tostring = function() error("secret printed") end})
    f.opaque = setmetatable({}, {__index = function() error("opaque table inspected") end})
    local env = setmetatable({}, {__index = _G})
    f.env = env
    env.issecretvalue = function(value) return rawequal(value, f.secret) end
    env.canaccesstable = function(value) return not rawequal(value, f.opaque) end
    env.GetTime = function() return f.time end
    env.UnitClass = function() error("recipient preferences must work for every class") end
    env.SendChatMessage = function() error("protocol must never send visible chat") end
    env.C_ChatInfo = {
        RegisterAddonMessagePrefix = function(prefix)
            f.registered[#f.registered + 1] = prefix
            if f.registerError then error("private registration error") end
            return f.registerResult
        end,
        SendAddonMessage = function(prefix, payload, channel, target)
            f.sent[#f.sent + 1] = {prefix = prefix, payload = payload, channel = channel, target = target}
            if f.duringSend then f.duringSend(payload) end
            if f.sendError then error("private send error") end
            return f.sendResult
        end,
    }
    local ns = {db = {receiveWhispers = true}, Log = function(_, code) f.logs[#f.logs + 1] = code end}
    local chunk
    if setfenv then chunk = assert(loadfile("src/ForeverMouseoverBuff/Recipient.lua")); setfenv(chunk, env)
    else chunk = assert(loadfile("src/ForeverMouseoverBuff/Recipient.lua", "t", env)) end
    chunk("ForeverMouseoverBuff", ns)
    f.api, f.ns = ns.Recipient, ns
    function f:init() return self.api.Initialize() end
    function f:request(target, matcher, callback)
        return self.api.Request(target or "Example-TestRealm", matcher or function(sender)
            return sender == "Example-TestRealm"
        end, callback or function(allowed) self.replies[#self.replies + 1] = allowed end)
    end
    function f:nonce(index)
        local message = self.sent[index or #self.sent]
        assert(message, "an explicit request must send its preference query")
        return assert(message.payload:match("^Q:1:([A-Za-z0-9]+)$"), "strict outbound query")
    end
    function f:answer(kind, nonce, sender)
        return self.api.OnMessage("FMB_PREF1", (kind or "A") .. ":1:" .. (nonce or self:nonce()),
            "WHISPER", sender or "Example-TestRealm")
    end
    return f
end

function tests.no_work_occurs_until_initialization_or_explicit_request()
    local f = fixture()
    equal(#f.sent, 0); equal(#f.registered, 0); equal(#f.replies, 0)
end
function tests.initialize_registers_exact_prefix_once_and_accepts_native_duplicate_code()
    for _, code in ipairs({0, 1}) do
        local f = fixture(); f.registerResult = code
        equal(f:init(), true); equal(f:init(), true)
        equal(#f.registered, 1); equal(f.registered[1], "FMB_PREF1")
    end
end
function tests.request_sends_one_bounded_nonce_query_and_waits_without_visible_chat()
    local f = fixture(); f:init()
    equal(f:request(), true); equal(#f.sent, 1); equal(#f.replies, 0)
    equal(f.sent[1].prefix, "FMB_PREF1"); equal(f.sent[1].channel, "WHISPER")
    equal(f.sent[1].target, "Example-TestRealm"); assert(#f:nonce() <= 32)
end
function tests.allow_and_deny_complete_exactly_once_and_ignore_replayed_replies()
    for _, kind in ipairs({"A", "D"}) do
        local f = fixture(); f:init(); f:request(); local nonce = f:nonce()
        f:answer(kind, nonce); f:answer(kind, nonce); f.time = 103; f.api.Tick()
        equal(#f.replies, 1); equal(f.replies[1], kind == "A")
    end
end
function tests.one_second_without_reply_allows_a_recipient_without_the_addon()
    local f = fixture(); f:init(); f:request(); local nonce = f:nonce()
    f.time = 100.999; f.api.Tick(); equal(#f.replies, 0)
    f.time = 101; f.api.Tick(); equal(#f.replies, 1); equal(f.replies[1], true)
    f:answer("D", nonce); f.api.Tick(); equal(#f.replies, 1)
end
function tests.reply_requires_exact_nonce_channel_prefix_and_sender_match()
    local f = fixture(); f:init(); f:request(); local nonce = f:nonce()
    f:answer("D", nonce, "Stranger-TestRealm")
    f:answer("D", nonce .. "x")
    f.api.OnMessage("Other", "D:1:" .. nonce, "WHISPER", "Example-TestRealm")
    f.api.OnMessage("FMB_PREF1", "D:1:" .. nonce, "PARTY", "Example-TestRealm")
    f.api.OnMessage("FMB_PREF1", "D:2:" .. nonce, "WHISPER", "Example-TestRealm")
    equal(#f.replies, 0)
    f:answer("D", nonce); equal(f.replies[1], false)
end
function tests.incoming_queries_use_live_preference_for_every_class_and_default_to_allow()
    for _, setting in ipairs({"absent", "allow", "deny"}) do
        local f = fixture()
        if setting == "absent" then f.ns.db.receiveWhispers = nil
        else f.ns.db.receiveWhispers = setting == "allow" end
        f:init()
        equal(f.api.OnMessage("FMB_PREF1", "Q:1:t100n1", "WHISPER", "Sender Testname"), true)
        equal(#f.sent, 1)
        equal(f.sent[1].payload, (setting == "deny" and "D" or "A") .. ":1:t100n1")
        equal(f.sent[1].target, "Sender Testname"); equal(f.sent[1].channel, "WHISPER")
    end
end
function tests.answer_rate_is_bounded_globally_and_for_one_sender_then_expires()
    local f = fixture(); f:init()
    for index = 1, 100 do f.api.OnMessage("FMB_PREF1", "Q:1:t100n" .. index, "WHISPER", "Sender-TestRealm") end
    equal(#f.sent, 1, "same sender receives at most one reply per second")
    local senders = {"Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Eta", "Theta", "Iota", "Kappa"}
    for index, sender in ipairs(senders) do
        f.api.OnMessage("FMB_PREF1", "Q:1:t100m" .. index, "WHISPER", sender .. "-TestRealm")
    end
    equal(#f.sent, 8, "global response budget is eight per second")
    f.time = 101; f.api.Tick()
    f.api.OnMessage("FMB_PREF1", "Q:1:t101n1", "WHISPER", "Sender-TestRealm")
    equal(#f.sent, 9, "expired sender names no longer suppress a fresh query")
end
function tests.queue_limit_rejects_only_the_seventeenth_request_without_a_send()
    local f = fixture(); f:init()
    for index = 1, 16 do equal(f:request(), true) end
    equal(f:request(), false); equal(#f.sent, 16); equal(#f.replies, 1); equal(f.replies[1], false)
    f.time = 101; f.api.Tick(); equal(#f.replies, 17)
    equal(f:request(), true)
end
function tests.every_nonce_is_unique_even_when_the_clock_does_not_advance()
    local f = fixture(); f:init(); local seen = {}
    for index = 1, 16 do
        f:request(); local nonce = f:nonce()
        assert(not seen[nonce], "nonce reuse"); seen[nonce] = true
    end
end
function tests.clock_failure_or_rollback_denies_all_pending_callbacks_once()
    for _, kind in ipairs({"backward", "missing", "secret", "throw", "nan"}) do
        local f = fixture(); f:init(); f:request(); f:request()
        if kind == "backward" then f.time = 99
        elseif kind == "missing" then f.time = nil
        elseif kind == "secret" then f.time = f.secret
        elseif kind == "nan" then f.time = 0/0
        else f.env.GetTime = function() error("private clock failure") end end
        f.api.Tick(); f.api.Tick()
        equal(#f.replies, 2, "every open callback settled once")
        equal(f.replies[1], false); equal(f.replies[2], false)
    end
end
function tests.registration_errors_and_unavailable_api_reject_instead_of_timing_out_open()
    for _, kind in ipairs({"nil", "true", "false", "invalid", "throw", "namespace", "opaque", "guard"}) do
        local f = fixture()
        if kind == "nil" then f.registerResult = nil
        elseif kind == "true" then f.registerResult = true
        elseif kind == "false" then f.registerResult = false
        elseif kind == "invalid" then f.registerResult = 2
        elseif kind == "throw" then f.registerError = true
        elseif kind == "namespace" then f.env.C_ChatInfo = nil
        elseif kind == "opaque" then f.env.C_ChatInfo = f.opaque
        else f.env.issecretvalue = false end
        equal(f:init(), false); equal(f:request(), false)
        equal(#f.replies, 1); equal(f.replies[1], false)
        f.time = 102; f.api.Tick(); equal(#f.replies, 1)
    end
end
function tests.send_only_accepts_numeric_success_and_never_retries_on_failure()
    for _, kind in ipairs({"nil", "true", "false", "throttle", "secret", "throw", "missing"}) do
        local f = fixture(); f:init()
        if kind == "nil" then f.sendResult = nil
        elseif kind == "true" then f.sendResult = true
        elseif kind == "false" then f.sendResult = false
        elseif kind == "throttle" then f.sendResult = 3
        elseif kind == "secret" then f.sendResult = f.secret
        elseif kind == "throw" then f.sendError = true
        else f.env.C_ChatInfo.SendAddonMessage = nil end
        equal(f:request(), false); equal(#f.replies, 1); equal(f.replies[1], false)
        local sends = #f.sent; f.time = 102; f.api.Tick(); equal(#f.sent, sends); equal(#f.replies, 1)
    end
end
function tests.synchronous_answer_waits_for_send_success_and_cannot_override_failed_send()
    for _, result in ipairs({0, 9}) do
        local f = fixture(); f:init(); f.sendResult = result
        f.duringSend = function(payload)
            f:answer("A", assert(payload:match("^Q:1:(.+)$")))
            equal(#f.replies, 0, "must wait for the send function's return value")
        end
        equal(f:request(), result == 0)
        equal(#f.replies, 1); equal(f.replies[1], result == 0)
    end
end
function tests.sender_match_failure_or_invalid_result_denies_once_without_raw_errors()
    for _, kind in ipairs({"throw", "secret", "not_boolean"}) do
        local f = fixture(); f:init()
        f:request(nil, function()
            if kind == "throw" then error("private name in matcher failure") end
            if kind == "secret" then return f.secret end
            return "yes"
        end)
        local nonce = f:nonce(); f:answer("A", nonce); f:answer("A", nonce)
        equal(#f.replies, 1); equal(f.replies[1], false)
        for _, code in ipairs(f.logs) do assert(code:match("^RECIPIENT_[A-Z_]+$"), "only anonymous codes") end
    end
end
function tests.callback_reentrancy_or_exception_cannot_replay_the_same_request()
    local f = fixture(); f:init(); local calls = 0
    f:request(nil, nil, function()
        calls = calls + 1
        f:answer("A", f:nonce())
        error("private callback error")
    end)
    f:answer(); f.time = 102; f.api.Tick()
    equal(calls, 1)
    equal(f.logs[#f.logs], "RECIPIENT_CALLBACK_FAILED")
end
function tests.invalid_arguments_and_unreadable_messages_never_send_or_touch_secret_data()
    local f = fixture(); f:init()
    for _, value in ipairs({"", "Bad|Name", "Bad\nName", "Bad;Name", "Bad/Name", string.rep("A", 226), f.secret, false, {}}) do
        equal(f.api.Request(value, function() return true end, function(result) equal(result, false) end), false)
    end
    equal(#f.sent, 0)
    for _, field in ipairs({"prefix", "payload", "channel", "sender"}) do
        local values = {prefix = "FMB_PREF1", payload = "Q:1:n1", channel = "WHISPER", sender = "Sender"}
        values[field] = f.secret
        equal(f.api.OnMessage(values.prefix, values.payload, values.channel, values.sender), false)
    end
    for _, payload in ipairs({"Q:2:n1", "Q:1:", "Q:1:n:1", "Q:1:n-1", "A:1:n1\n", "X:1:n1", "Q:1:" .. string.rep("A", 33)}) do
        equal(f.api.OnMessage("FMB_PREF1", payload, "WHISPER", "Sender"), false)
    end
    equal(#f.sent, 0)
end
function tests.protocol_never_persists_names_nonces_or_callback_state()
    local f = fixture(); f:init(); f:request()
    f.api.OnMessage("FMB_PREF1", "Q:1:n1", "WHISPER", "Sender")
    for key in pairs(f.ns.db) do equal(key, "receiveWhispers", "no protocol persistence") end
    for key, value in pairs(f.api) do
        assert(type(value) == "function" or (key == "LastCode" and value:match("^RECIPIENT_[A-Z_]+$")), "no protocol identity exported")
    end
end

local selected = {}
for name in pairs(tests) do if not arg[1] or arg[1] == name then selected[#selected + 1] = name end end
assert(#selected > 0, "unknown test filter"); table.sort(selected)
local failed = 0
for _, name in ipairs(selected) do
    local ok, failure = pcall(tests[name])
    if ok then print("PASS " .. name) else failed = failed + 1; print("FAIL " .. name .. ": " .. failure) end
end
print(string.format("Recipient: %d passed, %d failed", #selected - failed, failed))
if failed > 0 then os.exit(1) end
