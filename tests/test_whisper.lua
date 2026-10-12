-- Purpose: Prove exact recipient/cast correlation before an authorized buff whisper.
-- Input: synthetic names and game events; output: PASS/FAIL and exit status.
-- Invariants: the native message boundary is fake; no real chats, identities or network.
-- Debug: lua tests/test_whisper.lua [test_name] from the project directory.
local tests = {}
local function equal(actual, expected, message)
    if actual ~= expected then
        error((message or "unexpected value") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual), 2)
    end
end
local function fixture(saved)
    local f = { time = 100, target = "Example", realm = "TestRealm", player = "Paladin",
        localRealm = "TestRealm", messages = {}, logs = {}, playerTarget = true, friendly = true }
    local env = setmetatable({}, {__index = _G})
    f.env = env
    f.secret = setmetatable({}, {__tostring = function() error("secret printed") end})
    f.opaque = setmetatable({}, {__index = function() error("opaque indexed") end})
    env.issecretvalue = function(v) return rawequal(v, f.secret) end
    env.canaccesstable = function(v) return not rawequal(v, f.opaque) end
    env.GetTime = function() return f.time end
    env.RegionalUniqueNamesEnabled = function() return false end
    env.UnitIsPlayer = function(unit) equal(unit, "mouseover"); return f.playerTarget end
    env.UnitCanAssist = function(a, b) equal(a, "player"); equal(b, "mouseover"); return f.friendly end
    env.UnitFullName = function(unit)
        if unit == "mouseover" then return f.target, f.realm end
        equal(unit, "player"); return f.player, f.localRealm
    end
    env.UnitName = env.UnitFullName
    env.UnitClass = function(unit) equal(unit,"player"); return "Paladin","PALADIN" end
    env.UnitRace = function(unit)
        if unit == "player" then return nil,nil end
        equal(unit, "mouseover"); f.raceReads = (f.raceReads or 0) + 1
        return "Localized race", f.raceToken
    end
    env.UnitSex = function(unit)
        equal(unit, "mouseover"); f.sexReads = (f.sexReads or 0) + 1
        return f.sex
    end
    env.GetNormalizedRealmName = function() return f.localRealm end
    env.Enum = {SpellBookSpellBank = {Player = 0}}
    env.C_SpellBook = {IsSpellKnown = function(id, bank)
        equal(bank, 0); return f.known ~= false
    end}
    env.C_ChatInfo = {SendChatMessage = function(message, channel, language, target)
        f.messages[#f.messages + 1] = {message = message, channel = channel, language = language, target = target}
    end}
    local ns = {Log = function(_, code) f.logs[#f.logs + 1] = code end, db = saved or {whisper = true}}
    ns.Recipient = {Request = function(receiver, matches, callback) callback(true); return true end}
    for _, file in ipairs({"GreetingCatalog.lua", "Greetings.lua", "Whisper.lua"}) do
        local chunk
        local path = "src/ForeverMouseoverBuff/" .. file
        if setfenv then chunk = assert(loadfile(path)); setfenv(chunk, env)
        else chunk = assert(loadfile(path, "t", env)) end
        chunk("ForeverMouseoverBuff", ns)
    end
    f.api, f.ns = ns.Whisper, ns
    function f:sent(guid, target, id)
        return self.api.Sent("player", target or self.target .. "-" .. self.realm, guid or "Cast-1", id or 20217)
    end
    function f:complete(event, guid, id)
        return self.api.Complete(event or "UNIT_SPELLCAST_SUCCEEDED", "player", guid or "Cast-1", id or 20217)
    end
    return f
end

function tests.success_whispers_exact_text_only_to_correlated_buff_recipient()
    local f = fixture()
    f.api.Begin(20217)
    equal(#f.messages, 0, "preparing a click must not send")
    f:sent()
    equal(#f.messages, 0, "SENT does not prove success")
    f:complete()
    equal(#f.messages, 1, "a confirmed matching successful blessing must whisper exactly once")
    equal(f.messages[1].message, '[Forever Mouseover Buff] "Das Licht sei mit Euch, Example!" - Paladin')
    equal(f.messages[1].channel, "WHISPER")
    equal(f.messages[1].language, nil)
    equal(f.messages[1].target, "Example-TestRealm")
    equal(f.logs[#f.logs], "WHISPER_REQUESTED")
end

-- Echo matching is ready before the native send boundary. Display decisions
-- belong to Chat; the sender must not wrap or replace WIM's own preferences.
function tests.successful_blessing_registers_echo_without_changing_wim_before_send()
    local f = fixture()
    local existing = {tag = "existing", pattern = "unchanged", enabled = true}
    local original = function() return false, true, "native block" end
    f.env.WIM = {filters = {existing}, IgnoreOrBlockEvent = original}
    local nativeSend = f.env.C_ChatInfo.SendChatMessage
    local recognized, ignored, blocked, extra
    f.env.C_ChatInfo.SendChatMessage = function(message, channel, language, target)
        recognized = f.api.IsAutomaticEcho("CHAT_MSG_WHISPER_INFORM", message, target)
        ignored, blocked, extra = f.env.WIM.IgnoreOrBlockEvent("CHAT_MSG_WHISPER_INFORM", message, target)
        return nativeSend(message, channel, language, target)
    end
    f.api.Begin(20217); f:sent(); f:complete()
    equal(recognized, true, "the exact automatic echo must be registered before native send")
    equal(ignored, false); equal(blocked, true); equal(extra, "native block")
    equal(f.env.WIM.IgnoreOrBlockEvent, original, "never replace WIM's native decision")
    equal(#f.messages, 1, "display preferences must not cancel the authorized whisper")
    equal(#f.env.WIM.filters, 1); equal(f.env.WIM.filters[1], existing)
end

function tests.wim_integration_is_idempotent_and_preserves_original_arguments_and_returns()
    local f = fixture()
    local a, b = {tag = "a"}, {tag = "b"}
    local calls, args = 0
    f.env.WIM = {filters = {a, b}, IgnoreOrBlockEvent = function(...)
        calls, args = calls + 1, {...}
        return false, true, "untouched"
    end}
    local installed = f.env.WIM.IgnoreOrBlockEvent
    for index = 1, 2 do
        f.api.Begin(20217); f:sent("Cast-" .. index); f:complete(nil, "Cast-" .. index)
        equal(f.env.WIM.IgnoreOrBlockEvent, installed, "Do not change WIM on any buff")
    end
    local rules = f.env.WIM.filters
    equal(#rules, 2); equal(rules[1], a); equal(rules[2], b); equal(#f.messages, 2)
    local ignore, block, extra = installed("CHAT_MSG_WHISPER", "Normal answer", "Example", nil, 42)
    equal(ignore, false); equal(block, true); equal(extra, "untouched"); equal(calls, 1)
    equal(args[1], "CHAT_MSG_WHISPER"); equal(args[2], "Normal answer")
    equal(args[3], "Example"); equal(args[4], nil); equal(args[5], 42)
end

function tests.failed_blessing_does_not_change_wim_filters()
    local f = fixture()
    local original = {tag = "existing"}
    f.env.WIM = {filters = {original}, modules = {Filters = {enabled = true}}}
    f.api.Begin(20217); f:sent(); f:complete("UNIT_SPELLCAST_FAILED")
    equal(#f.messages, 0); equal(#f.env.WIM.filters, 1)
    equal(f.env.WIM.filters[1], original)
end

function tests.missing_or_unreadable_wim_never_prevents_the_authorized_whisper()
    for _, kind in ipairs({"missing", "opaque", "secret", "not_ready", "bad_method", "secret_method"}) do
        local f = fixture()
        if kind == "opaque" then f.env.WIM = f.opaque
        elseif kind == "secret" then f.env.WIM = f.secret
        elseif kind == "not_ready" then f.env.WIM = {}
        elseif kind == "bad_method" then f.env.WIM = {IgnoreOrBlockEvent = "bad"}
        elseif kind == "secret_method" then f.env.WIM = {IgnoreOrBlockEvent = f.secret}
        end
        f.api.Begin(20217); f:sent(); f:complete()
        equal(#f.messages, 1, kind .. ": optional WIM integration must not stop sending")
    end
end

function tests.wim_is_unchanged_and_echo_matcher_rejects_unrelated_or_restricted_messages()
    local f = fixture()
    local calls = 0
    f.env.WIM = {IgnoreOrBlockEvent = function() calls = calls + 1; return false, false end}
    f.api.Begin(20217); f:sent(); f:complete()
    local originalText = f.messages[1].message
    for _, entry in ipairs({
        {"CHAT_MSG_WHISPER", originalText}, {"CHAT_MSG_BN_WHISPER_INFORM", originalText},
        {"CHAT_MSG_WHISPER_INFORM", "Normal message"},
        {"CHAT_MSG_WHISPER_INFORM", "prefix " .. originalText},
        {"CHAT_MSG_WHISPER_INFORM", originalText .. "?"},
        {"CHAT_MSG_WHISPER_INFORM", originalText .. "\n"},
        {"CHAT_MSG_WHISPER_INFORM", originalText .. " "},
        {"CHAT_MSG_WHISPER_INFORM", f.secret}, {f.secret, originalText},
    }) do
        local before = calls
        local ignore, block = f.env.WIM.IgnoreOrBlockEvent(entry[1], entry[2], "Example")
        equal(ignore, false); equal(block, false); equal(calls, before + 1)
        equal(f.api.IsAutomaticEcho(entry[1], entry[2], "Example"), false)
    end
    local ignore, block = f.env.WIM.IgnoreOrBlockEvent("CHAT_MSG_WHISPER_INFORM", originalText, "Example")
    equal(ignore, false); equal(block, false)
    equal(f.api.IsAutomaticEcho("CHAT_MSG_WHISPER_INFORM", originalText, "Example"), true)
end

function tests.changed_mouseover_after_sent_never_changes_the_bound_recipient()
    local f = fixture()
    equal(f.api.Begin(20217), true)
    equal(f:sent(), true)
    f.target, f.realm = "Unrelated", "AnotherRealm"
    equal(f:complete(), true)
    equal(f.messages[1].target, "Example-TestRealm")
end

-- Personalization is part of the clicked recipient snapshot, not a new lookup
-- after success. These names/races are synthetic and never contact the game.
function tests.personal_greeting_snapshots_race_sex_and_name_before_mouseover_changes()
    local f = fixture()
    f.raceToken, f.sex, f.target = "NightElf", 3, "Alyndra"
    equal(f.api.Begin(20217), true)
    equal(f:sent(), true)
    f.target, f.raceToken, f.sex = "Other", "Dwarf", 2
    equal(f:complete(), true)
    equal(f.messages[1].message, '[Forever Mouseover Buff] "Das Licht sei mit Euch, edle Nachtelfe Alyndra!" - Paladin')
    equal(f.messages[1].target, "Alyndra-TestRealm")
    equal(f.raceReads, 1); equal(f.sexReads, 1)
end

function tests.personal_greeting_private_or_unavailable_traits_fall_back_to_name()
    for _, kind in ipairs({"secret_race", "secret_sex", "missing_race", "missing_sex", "throw", "unknown"}) do
        local f = fixture()
        f.raceToken, f.sex = "NightElf", 3
        if kind == "secret_race" then f.raceToken = f.secret
        elseif kind == "secret_sex" then f.sex = f.secret
        elseif kind == "missing_race" then f.env.UnitRace = nil
        elseif kind == "missing_sex" then f.env.UnitSex = nil
        elseif kind == "throw" then f.env.UnitRace = function() error("private trait") end
        else f.raceToken, f.sex = "FutureRace", 1 end
        f.api.Begin(20217); f:sent(); f:complete()
        equal(#f.messages, 1, "optional traits must not prevent a safely addressed message")
        equal(f.messages[1].message, '[Forever Mouseover Buff] "Das Licht sei mit Euch, Example!" - Paladin', kind)
        for _, code in ipairs(f.logs) do assert(code:match("^[A-Z_]+$")) end
    end
end

function tests.personal_greeting_twelve_variants_rotate_persist_and_wrap()
    local f = fixture()
    local seen = {}
    for index = 1, 12 do
        local id = "Cast-" .. index
        f.api.Begin(20217); f:sent(id); equal(f:complete(nil, id), true)
        local message = f.messages[index].message
        assert(not seen[message], "all twelve successive greetings must differ")
        seen[message] = true
        assert(message:find("Example", 1, true) and message:find("Paladin", 1, true))
        assert(#message <= 255, "chat byte limit must not be exceeded")
        equal(f.ns.db.greetingIndex, index)
    end
    local restored = fixture(f.ns.db)
    restored.api.Begin(20217); restored:sent(); restored:complete()
    equal(restored.ns.db.greetingIndex, 1)
    equal(restored.messages[1].message, f.messages[1].message, "wrap after twelve greetings across reload")
    local nextSession = fixture(restored.ns.db)
    nextSession.api.Begin(20217); nextSession:sent(); nextSession:complete()
    equal(nextSession.messages[1].message, f.messages[2].message, "reload must continue the sequence")
end

function tests.personal_greeting_failure_and_duplicate_events_do_not_advance_rotation()
    local f = fixture()
    f.api.Begin(20217); f:sent(); f:complete("UNIT_SPELLCAST_FAILED")
    equal(f.ns.db.greetingIndex, nil); equal(#f.messages, 0)
    local send = f.env.C_ChatInfo.SendChatMessage
    f.env.C_ChatInfo.SendChatMessage = function() return false end
    f.api.Begin(20217); f:sent("Cast-2"); equal(f:complete(nil, "Cast-2"), false)
    equal(f.ns.db.greetingIndex, nil)
    f.env.C_ChatInfo.SendChatMessage = send
    f.api.Begin(20217); f:sent("Cast-3"); f:complete(nil, "Cast-3")
    equal(f.ns.db.greetingIndex, 1)
    f:complete(nil, "Cast-3")
    equal(f.ns.db.greetingIndex, 1); equal(#f.messages, 1)
end

function tests.personal_greeting_invalid_saved_index_resets_safely()
    for _, value in ipairs({-1, 13, 1.5, "two", true, math.huge}) do
        local f = fixture({whisper = true, greetingIndex = value})
        f.api.Begin(20217); f:sent(); equal(f:complete(), true)
        equal(f.ns.db.greetingIndex, 1)
        equal(f.messages[1].message, '[Forever Mouseover Buff] "Das Licht sei mit Euch, Example!" - Paladin')
    end
end

function tests.automatic_echo_requires_matching_receiver_and_expires()
    local f = fixture()
    f.api.Begin(20217); f:sent(); f:complete()
    local message = f.messages[1].message
    equal(f.api.IsAutomaticEcho("CHAT_MSG_WHISPER_INFORM", message, "Other"), false)
    equal(f.api.IsAutomaticEcho("CHAT_MSG_WHISPER_INFORM", message, "Example-OtherRealm"), false)
    equal(f.api.IsAutomaticEcho("CHAT_MSG_WHISPER_INFORM", message, "Example"), true)
    equal(f.api.IsAutomaticEcho("CHAT_MSG_WHISPER_INFORM", message, f.secret), false)
    f.time = f.time + 16
    equal(f.api.IsAutomaticEcho("CHAT_MSG_WHISPER_INFORM", message, "Example"), false,
        "manual identical wording must stop being ignored after the short echo window")
end

function tests.automatic_echo_window_is_bounded_and_clock_failures_clear_it()
    local f = fixture()
    for index = 1, 17 do
        f.target = "Example" .. string.char(64 + index)
        local id = "Cast-" .. index
        f.api.Begin(20217); f:sent(id); f:complete(nil, id)
    end
    local first, last = f.messages[1], f.messages[17]
    equal(f.api.IsAutomaticEcho("CHAT_MSG_WHISPER_INFORM", first.message, first.target), false)
    equal(f.api.IsAutomaticEcho("CHAT_MSG_WHISPER_INFORM", last.message, last.target), true)
    f.time = 99
    equal(f.api.IsAutomaticEcho("CHAT_MSG_WHISPER_INFORM", last.message, last.target), false)
    f.time = f.secret
    equal(f.api.IsAutomaticEcho("CHAT_MSG_WHISPER_INFORM", last.message, last.target), false)
end

function tests.failed_send_does_not_reserve_manual_messages()
    local f = fixture()
    local attempted
    f.env.C_ChatInfo.SendChatMessage = function(message) attempted = message; return false end
    f.api.Begin(20217); f:sent(); equal(f:complete(), false)
    equal(f.api.IsAutomaticEcho("CHAT_MSG_WHISPER_INFORM", attempted, "Example"), false)
end

function tests.local_short_sent_name_requires_proven_same_realm()
    local f = fixture()
    f.realm = ""
    equal(f.api.Begin(20217), true)
    equal(f:sent("Cast-1", "Example"), true)
    f:complete()
    equal(f.messages[1].target, "Example-TestRealm")
    f = fixture()
    f.realm = "OtherRealm"
    f.api.Begin(20217); f:sent("Cast-1", "Example"); f:complete()
    equal(#f.messages, 0, "a cross-realm short name is ambiguous")
end

function tests.unit_name_legacy_fallback_and_normalized_realm_are_supported()
    local f = fixture()
    f.env.UnitFullName = nil
    f.realm, f.localRealm = "Test Realm", "TestRealm"
    f.api.Begin(20217); f:sent("Cast-1", "Example-TestRealm"); f:complete()
    equal(#f.messages, 1)
    equal(f.messages[1].target, "Example-TestRealm")
end

function tests.secret_normalized_realm_never_falls_back_to_an_alternative_identity()
    local f = fixture()
    f.env.GetNormalizedRealmName = function() return f.secret end
    equal(f.api.Begin(20217), false, "a secret realm must not be replaced with another identity source")
    f:sent(); f:complete()
    equal(#f.messages, 0)
end

function tests.mismatched_sent_target_spell_or_guid_never_sends()
    for _, kind in ipairs({"name", "realm", "spell", "guid", "missing", "secret", "ambiguous"}) do
        local f = fixture()
        f.api.Begin(20217)
        if kind == "name" then f:sent("Cast-1", "Stranger-TestRealm")
        elseif kind == "realm" then f:sent("Cast-1", "Example-WrongRealm")
        elseif kind == "spell" then f:sent("Cast-1", nil, 19740)
        elseif kind == "guid" then f:sent("", nil)
        elseif kind == "missing" then f.api.Sent("player", nil, "Cast-1", 20217)
        elseif kind == "secret" then f.api.Sent("player", f.secret, "Cast-1", 20217)
        else f:sent("Cast-1"); f:sent("Cast-2") end
        f:complete()
        equal(#f.messages, 0, kind)
    end
end

function tests.success_requires_sent_and_same_public_player_guid_and_spell()
    for _, kind in ipairs({"unsent", "unit", "guid", "spell", "secret_unit", "secret_guid", "secret_spell", "secret_event"}) do
        local f = fixture()
        f.api.Begin(20217)
        if kind ~= "unsent" then f:sent() end
        if kind == "unit" then f.api.Complete("UNIT_SPELLCAST_SUCCEEDED", "party1", "Cast-1", 20217)
        elseif kind == "guid" then f:complete(nil, "Cast-2")
        elseif kind == "spell" then f:complete(nil, nil, 19740)
        elseif kind == "secret_unit" then f.api.Complete("UNIT_SPELLCAST_SUCCEEDED", f.secret, "Cast-1", 20217)
        elseif kind == "secret_guid" then f.api.Complete("UNIT_SPELLCAST_SUCCEEDED", "player", f.secret, 20217)
        elseif kind == "secret_spell" then f.api.Complete("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", f.secret)
        elseif kind == "secret_event" then f.api.Complete(f.secret, "player", "Cast-1", 20217)
        else f:complete() end
        equal(#f.messages, 0, kind)
    end
end

function tests.failed_interrupted_unknown_and_disabled_casts_never_whisper()
    for _, event in ipairs({"UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_START"}) do
        local f = fixture(); f.api.Begin(20217); f:sent(); f:complete(event)
        equal(#f.messages, 0, event)
        f:complete(); equal(#f.messages, 0, "an invalidated completion cannot revive")
    end
    local f = fixture(); f.api.Begin(20217); f:sent(); f.ns.db.whisper = false; f:complete()
    equal(#f.messages, 0)
end

function tests.timeouts_clock_failures_and_backward_clock_never_whisper()
    for _, kind in ipairs({"expired", "backward", "secret", "missing", "failure"}) do
        local f = fixture(); f.api.Begin(20217); f:sent()
        if kind == "expired" then f.time = 105.001
        elseif kind == "backward" then f.time = 99
        elseif kind == "secret" then f.time = f.secret
        elseif kind == "missing" then f.env.GetTime = nil
        else f.env.GetTime = function() error("private clock failure") end end
        f:complete(); equal(#f.messages, 0, kind)
    end
    local f = fixture(); f.api.Begin(20217); f:sent(); f.time = 105; f:complete()
    equal(#f.messages, 1, "five seconds inclusive remains valid")
end

function tests.duplicate_guid_sends_once_but_new_success_same_target_sends_again()
    local f = fixture(); f.api.Begin(20217); f:sent(); f:sent(); f:complete(); f:complete()
    equal(#f.messages, 1)
    f.api.Begin(20217); f:sent(); f:complete()
    equal(#f.messages, 1, "replaying the same GUID across clicks cannot send again")
    f.api.Begin(20217); f:sent("Cast-2"); f:complete(nil, "Cast-2")
    equal(#f.messages, 2, "a real new success must not be throttled by recipient")
end

function tests.overlapping_clicks_are_ambiguous_and_never_reassign_an_old_cast()
    local f = fixture(); f.api.Begin(20217); f.api.Begin(20217); f:sent(); f:complete()
    equal(#f.messages, 0)
    f.time = 106
    equal(f.api.Begin(20217), true, "after expiry a new attempt can start")
    f:sent("Cast-2"); f:complete(nil, "Cast-2")
    equal(#f.messages, 1)
end

function tests.invalid_unlearned_non_blessing_and_secret_spell_ids_do_not_begin()
    local f = fixture()
    for _, id in ipairs({0, -1, 1.5, 1000000001, 25898, 133, "20217", f.secret}) do
        equal(f.api.Begin(id), false)
        f:sent(); f:complete(); equal(#f.messages, 0)
    end
    f.known = false
    equal(f.api.Begin(20217), false)
    f:sent(); f:complete(); equal(#f.messages, 0)
end

function tests.unreadable_or_unsafe_names_realms_and_player_state_do_not_begin()
    for _, kind in ipairs({"target_secret", "player_secret", "realm_secret", "name_missing", "realm_missing",
        "name_markup", "name_control", "name_slash", "realm_control", "realm_markup", "realm_slash",
        "npc", "enemy", "player_secret_flag", "guard_missing", "opaque_book", "known_secret"}) do
        local f = fixture()
        if kind == "target_secret" then f.target = f.secret
        elseif kind == "player_secret" then f.player = f.secret
        elseif kind == "realm_secret" then f.realm = f.secret
        elseif kind == "name_missing" then f.target = nil
        elseif kind == "realm_missing" then f.realm = nil; f.localRealm = nil
        elseif kind == "name_markup" then f.target = "Example|Hplayer"
        elseif kind == "name_control" then f.target = "Example\nOther"
        elseif kind == "name_slash" then f.target = "Example/Other"
        elseif kind == "realm_control" then f.realm = "Realm\nOther"
        elseif kind == "realm_markup" then f.realm = "Realm|Other"
        elseif kind == "realm_slash" then f.realm = "Realm/Other"
        elseif kind == "npc" then f.playerTarget = false
        elseif kind == "enemy" then f.friendly = false
        elseif kind == "player_secret_flag" then f.playerTarget = f.secret
        elseif kind == "guard_missing" then f.env.issecretvalue = nil
        elseif kind == "opaque_book" then f.env.C_SpellBook = f.opaque
        else f.env.C_SpellBook.IsSpellKnown = function() return f.secret end end
        equal(f.api.Begin(20217), false, kind)
        f.api.Sent("player", "Example-TestRealm", "Cast-1", 20217); f:complete()
        equal(#f.messages, 0, kind)
    end
end

function tests.broken_send_api_logs_fixed_failure_without_retry_or_identity_leak()
    for _, kind in ipairs({"throw", "false", "missing", "opaque", "secret"}) do
        local f = fixture(); f.api.Begin(20217); f:sent()
        if kind == "throw" then f.env.C_ChatInfo.SendChatMessage = function() error("private Example-TestRealm") end
        elseif kind == "false" then f.env.C_ChatInfo.SendChatMessage = function() return false end
        elseif kind == "missing" then f.env.C_ChatInfo = nil; f.env.SendChatMessage = nil
        elseif kind == "opaque" then f.env.C_ChatInfo = f.opaque
        else f.env.C_ChatInfo.SendChatMessage = f.secret end
        equal(f:complete(), false, kind)
        equal(#f.messages, 0)
        for _, code in ipairs(f.logs) do assert(code:match("^[A-Z_]+$"), "diagnostics contain only fixed codes") end
        f.env.C_ChatInfo = {SendChatMessage = function() error("must not retry") end}
        equal(f:complete(), false)
    end
end

function tests.legacy_sendchatmessage_fallback_is_used_only_when_modern_api_is_absent()
    local f = fixture()
    f.env.SendChatMessage = f.env.C_ChatInfo.SendChatMessage
    f.env.C_ChatInfo = nil
    f.api.Begin(20217); f:sent(); f:complete()
    equal(#f.messages, 1)
end

-- Camelot treats the second UnitName value as a surname. Native NameUtil is
-- the authoritative regional name constructor; never relabel the surname realm.
function tests.regional_camelot_uses_exact_native_full_name_without_invented_realm()
    local f = fixture()
    f.env.RegionalUniqueNamesEnabled = function() return true end
    f.env.NameUtil = {GetUnmodifiedUnitFullName = function(unit)
        if unit == "player" then return "Paladin Example" end
        equal(unit, "mouseover"); return "Example Person"
    end}
    f.env.UnitFullName = function() error("regional identity must come from native NameUtil") end
    f.env.UnitName = function() error("surname must not be treated as realm") end
    f.env.GetNormalizedRealmName = function() error("regional names need no guessed realm") end
    f.api.Begin(20217)
    f.api.Sent("player", "Example Person", "Cast-1", 20217)
    f:complete()
    equal(#f.messages, 1, "public native first/surname must support the requested whisper")
    equal(f.messages[1].target, "Example Person")
    equal(f.messages[1].message, '[Forever Mouseover Buff] \"Das Licht sei mit Euch, Example Person!\" - Paladin Example')
end

function tests.nonregional_public_compound_names_keep_exact_spelling_and_realm()
    for _, target in ipairs({"Example-Person", "Example Person"}) do
        local f = fixture(); f.target = target; f.player = "Paladin Example"
        f.api.Begin(20217); f:sent(); f:complete()
        equal(#f.messages, 1, "compound public name must not be split at its first hyphen")
        equal(f.messages[1].target, target .. "-TestRealm")
        equal(f.messages[1].message, '[Forever Mouseover Buff] \"Das Licht sei mit Euch, ' .. target .. '!\" - Paladin Example')
    end
end

function tests.unknown_regional_mode_never_guesses_how_to_interpret_unitname()
    for _, kind in ipairs({"missing", "secret", "nil", "throw"}) do
        local f = fixture()
        if kind == "missing" then f.env.RegionalUniqueNamesEnabled = nil
        elseif kind == "secret" then f.env.RegionalUniqueNamesEnabled = function() return f.secret end
        elseif kind == "nil" then f.env.RegionalUniqueNamesEnabled = function() return nil end
        else f.env.RegionalUniqueNamesEnabled = function() error("native failure") end end
        equal(f.api.Begin(20217), false, kind)
        f:sent(); f:complete(); equal(#f.messages, 0)
    end
end

function tests.regional_names_require_readable_native_helper_and_exact_sent_identity()
    for _, kind in ipairs({"missing", "opaque", "secret", "surname", "hyphen", "realm"}) do
        local f = fixture(); f.env.RegionalUniqueNamesEnabled = function() return true end
        f.env.NameUtil = {GetUnmodifiedUnitFullName = function(unit)
            if kind == "secret" then return f.secret end
            return unit == "player" and "Paladin Example" or "Example Person"
        end}
        if kind == "missing" then f.env.NameUtil = nil
        elseif kind == "opaque" then f.env.NameUtil = f.opaque end
        f.api.Begin(20217)
        local target = "Example Person"
        if kind == "surname" then target = "Example Stranger"
        elseif kind == "hyphen" then target = "Example-Person"
        elseif kind == "realm" then target = "Example Person-TestRealm" end
        f.api.Sent("player", target, "Cast-1", 20217); f:complete()
        equal(#f.messages, 0, kind .. ": do not invent or normalize a regional recipient")
    end
end

function tests.no_identity_or_message_is_written_to_namespace_saved_variables_or_logs()
    local f = fixture(); f.api.Begin(20217); f:sent(); f:complete()
    for key in pairs(f.ns.db) do
        assert(key == "whisper" or key == "greetingIndex", "only an anonymous rotation index may be added")
    end
    equal(f.ns.db.greetingIndex, 1)
    for _, code in ipairs(f.logs) do assert(code:match("^[A-Z_]+$")) end
    for key in pairs(f.api) do
        assert(key == "Begin" or key == "Sent" or key == "Complete" or key == "IsAutomaticEcho",
            "only public functions are exposed; pending private data remains closure-local")
        equal(type(f.api[key]), "function")
    end
end


-- Receiver preference is an asynchronous boundary, after confirmed casting only.
function tests.receiver_opt_out_prevents_message_and_rotation_after_success()
    local f = fixture()
    local reply
    f.ns.Recipient.Request = function(receiver, matches, callback)
        equal(receiver, "Example-TestRealm")
        equal(matches("Example-TestRealm"), true)
        equal(matches("Stranger-TestRealm"), false)
        reply = callback
        return true
    end
    f.api.Begin(20217); f:sent(); equal(reply, nil)
    f:complete(); equal(#f.messages, 0, "wait for receiver preference before sending")
    assert(reply, "confirmed cast must check recipient preference")
    reply(false)
    equal(#f.messages, 0); equal(f.ns.db.greetingIndex, nil)
end
function tests.receiver_allows_bound_target_once_and_late_disable_cancels_send()
    for _, disable in ipairs({false, true}) do
        local f = fixture(); local reply
        f.ns.Recipient.Request = function(_, _, callback) reply = callback; return true end
        f.api.Begin(20217); f:sent(); f:complete()
        equal(#f.messages, 0, "no premature visible whisper")
        f.target = "SomeoneElse"
        if disable then f.ns.db.whisper = false end
        reply(true); reply(true)
        equal(#f.messages, disable and 0 or 1, "at most once and recheck sender setting")
        if not disable then equal(f.messages[1].target, "Example-TestRealm") end
    end
end
function tests.receiver_missing_or_rejected_check_fails_closed_without_message()
    for _, kind in ipairs({"missing", "rejected", "error"}) do
        local f = fixture()
        if kind == "missing" then f.ns.Recipient = nil
        elseif kind == "rejected" then f.ns.Recipient.Request = function() return false end
        else f.ns.Recipient.Request = function() error("synthetic boundary failure") end end
        f.api.Begin(20217); f:sent(); f:complete()
        equal(#f.messages, 0, kind)
        equal(f.ns.db.greetingIndex, nil)
    end
end
function tests.colored_outgoing_echo_still_matches_only_our_own_display_exception()
    local f = fixture()
    f.api.Begin(20217); f:sent(); f:complete()
    local plain = f.messages[1].message
    local colored = f.ns.Greetings.COLOR_PREFIX .. plain:sub(#f.ns.Greetings.PREFIX + 1)
    equal(f.api.IsAutomaticEcho("CHAT_MSG_WHISPER_INFORM", colored, "Example-TestRealm"), true)
    equal(f.api.IsAutomaticEcho("CHAT_MSG_WHISPER_INFORM", colored, "Another-TestRealm"), false)
    equal(f.api.IsAutomaticEcho("CHAT_MSG_WHISPER", colored, "Example-TestRealm"), false)
end

-- Two addon instances exchange only synthetic protocol events. This exercises
-- the real consent state machine together with the real cast/whisper module.
local function enableRecipientProtocol(f, route)
    f.addonMessages = {}
    f.env.C_ChatInfo.RegisterAddonMessagePrefix = function() return 0 end
    f.env.C_ChatInfo.SendAddonMessage = function(prefix, payload, channel, target)
        f.addonMessages[#f.addonMessages + 1] = {prefix, payload, channel, target}
        if route then route(prefix, payload, channel, target) end
        return 0
    end
    local path = "src/ForeverMouseoverBuff/Recipient.lua"
    local chunk
    if setfenv then chunk = assert(loadfile(path)); setfenv(chunk, f.env)
    else chunk = assert(loadfile(path, "t", f.env)) end
    chunk("ForeverMouseoverBuff", f.ns)
    equal(f.ns.Recipient.Initialize(), true, "native prefix must register")
end
function tests.two_addons_honor_receiver_toggle_before_any_visible_whisper()
    for _, allowed in ipairs({false, true}) do
        local sender, receiver = fixture(), fixture()
        receiver.ns.db.receiveWhispers = allowed
        enableRecipientProtocol(receiver, function(prefix, payload, channel, target)
            equal(target, "Paladin-TestRealm")
            sender.ns.Recipient.OnMessage(prefix, payload, channel, "Example-TestRealm")
        end)
        enableRecipientProtocol(sender, function(prefix, payload, channel, target)
            equal(target, "Example-TestRealm")
            receiver.ns.Recipient.OnMessage(prefix, payload, channel, "Paladin-TestRealm")
        end)
        sender.api.Begin(20217); sender:sent()
        equal(#sender.addonMessages, 0, "no query before successful cast")
        sender:complete()
        equal(#sender.addonMessages, 1); equal(#receiver.addonMessages, 1)
        equal(#sender.messages, allowed and 1 or 0)
        equal(#receiver.messages, 0, "receiver never sends visible replies")
        equal(sender.ns.db.greetingIndex, allowed and 1 or nil)
        sender.time = 102; sender.ns.Recipient.Tick()
        equal(#sender.messages, allowed and 1 or 0, "timeout cannot send a duplicate")
    end
end
function tests.real_protocol_no_reply_times_out_without_retargeting_or_secret_data()
    local sender = fixture()
    enableRecipientProtocol(sender)
    sender.api.Begin(20217); sender:sent(); sender:complete()
    equal(#sender.messages, 0)
    sender.target = "SomeoneElse"
    sender.time = 100.75; sender.ns.Recipient.Tick(); equal(#sender.messages, 0)
    sender.time = 101; sender.ns.Recipient.Tick(); equal(#sender.messages, 1)
    equal(sender.messages[1].target, "Example-TestRealm")
end


local function loadRealStatsAndLink(f)
    f.env.UnitClass = function(unit) equal(unit, "player"); return "Paladin", "PALADIN" end
    f.env.C_Spell = {GetSpellLink = function(id)
        return "|cff71d5ff|Hspell:" .. id .. "|h[Segen der Könige]|h|r"
    end}
    for _, file in ipairs({"Hash.lua", "CounterCodec.lua", "Stats.lua", "SpellLink.lua"}) do
        local path = "src/ForeverMouseoverBuff/" .. file
        local chunk
        if setfenv then chunk = assert(loadfile(path)); setfenv(chunk, f.env)
        else chunk = assert(loadfile(path, "t", f.env)) end
        chunk("ForeverMouseoverBuff", f.ns)
    end
end
function tests.statistics_count_confirmed_cast_even_when_whispers_are_off_or_declined()
    for _, reason in ipairs({"off", "declined", "send_failed", "missing_recipient"}) do
        local f = fixture(); loadRealStatsAndLink(f)
        if reason == "off" then f.ns.db.whisper = false
        elseif reason == "declined" then f.ns.Recipient.Request = function(_,_,cb) cb(false); return true end
        elseif reason == "send_failed" then f.env.C_ChatInfo.SendChatMessage = function() return false end
        else f.ns.Recipient = nil end
        f.api.Begin(20217); f:sent(); f:complete()
        equal(f.ns.Stats.Total(), 1, reason .. ": real buff success is independent from chat")
        f:complete(); equal(f.ns.Stats.Total(), 1, "duplicate success does not count twice")
    end
end
function tests.statistics_never_count_failure_unbound_self_or_nonplayer_targets()
    for _, kind in ipairs({"failed", "interrupted", "unsent", "wrong_guid", "self", "npc", "nonpaladin"}) do
        local f = fixture(); loadRealStatsAndLink(f)
        if kind == "self" then f.target = f.player
        elseif kind == "npc" then f.playerTarget = false
        elseif kind == "nonpaladin" then f.env.UnitClass = function() return "Mage", "MAGE" end end
        f.api.Begin(20217)
        if kind ~= "unsent" then f:sent() end
        if kind == "failed" then f:complete("UNIT_SPELLCAST_FAILED")
        elseif kind == "interrupted" then f:complete("UNIT_SPELLCAST_INTERRUPTED")
        elseif kind == "wrong_guid" then f:complete(nil,"Cast-Wrong")
        else f:complete() end
        equal(f.ns.Stats.Total(), 0, kind)
    end
end
function tests.pending_greeting_keeps_its_cast_count_snapshot_and_native_buff_link()
    local f = fixture(); loadRealStatsAndLink(f)
    local replies = {}
    f.ns.Recipient.Request = function(_,_,cb) replies[#replies+1] = cb; return true end
    f.api.Begin(20217); f:sent("Cast-First"); f:complete(nil,"Cast-First")
    f.api.Begin(20217); f:sent("Cast-Second"); f:complete(nil,"Cast-Second")
    equal(f.ns.Stats.Total(), 2)
    replies[1](true); replies[2](true)
    equal(#f.messages, 2)
    assert(f.messages[1].message:find("Paladin [lokal: 1 Buffs]",1,true))
    assert(f.messages[2].message:find("Paladin [lokal: 2 Buffs]",1,true))
    assert(f.messages[1].message:find("|Hspell:20217|h",1,true))
end

-- Corrupt optional statistics must not stop a confirmed greeting or invent a
-- zero count. This characterizes the existing cast tracker's failure boundary.
function tests.damaged_statistics_preserve_greeting_but_block_count_and_export()
    local f = fixture(); loadRealStatsAndLink(f)
    assert(f.ns.Stats.Initialize())
    local original = f.ns.db.buffStats
    original.digest = string.rep("f", 64)
    local exports = 0
    f.ns.RankingExport = {Record = function() exports = exports + 1; return true end}
    f.api.Begin(20217); f:sent(); f:complete()
    equal(f.ns.db.buffStats, original, "invalid evidence must stay untouched")
    equal(f.ns.Stats.Total(), nil, "damaged count is unavailable, not zero")
    equal(exports, 0, "no event export when local counting failed")
    equal(#f.messages, 1, "optional statistics cannot suppress valid greetings")
    assert(not f.messages[1].message:find("[lokal:", 1, true))
    assert(f.messages[1].message:find("|Hspell:20217|h", 1, true))
end

function tests.confirmed_cast_calls_statistics_even_with_whispers_off()
    local f = fixture(); local counted = 0
    f.ns.db.whisper = false
    f.env.UnitClass = function() return "Paladin", "PALADIN" end
    f.ns.Stats = {Record = function(id, castGUID)
        equal(id, 20217); equal(castGUID, "Cast-1"); counted = counted + 1; return true
    end, Total = function() return counted end}
    f.api.Begin(20217); f:sent(); f:complete()
    equal(counted, 1, "a confirmed buff must reach statistics with chat disabled")
    equal(#f.messages, 0)
end

function tests.confirmed_counted_cast_exports_once_without_sending_whispers()
    local f = fixture(); loadRealStatsAndLink(f)
    f.ns.db.whisper = false
    local calls = 0
    f.ns.RankingExport = {Record = function(id) equal(id,20217); calls = calls + 1; return true end}
    f.api.Begin(20217); f:sent(); f:complete(); f:complete()
    equal(calls, 1); equal(f.ns.Stats.Total(), 1); equal(#f.messages, 0)
end

function tests.real_export_receives_only_correlated_successes_and_off_clears_queue()
    local f = fixture(); loadRealStatsAndLink(f)
    f.env.GetServerTime = function() return 1791734400 end
    local path = "src/ForeverMouseoverBuff/RankingExport.lua"
    local chunk
    if setfenv then chunk = assert(loadfile(path)); setfenv(chunk, f.env)
    else chunk = assert(loadfile(path, "t", f.env)) end
    chunk("ForeverMouseoverBuff", f.ns)
    f.ns.RankingExport.Initialize()
    f.api.Begin(20217); f:sent("Cast-Off"); f:complete(nil,"Cast-Off")
    equal(f.ns.Stats.Total(),1); equal(f.ns.db.rankingQueue,nil)
    assert(f.env.ForeverMouseoverBuffRankingExport:find('"enabled":false',1,true))
    f.ns.RankingExport.SetEnabled(true)
    f.api.Begin(20217); f:sent("Cast-Failure"); f:complete("UNIT_SPELLCAST_FAILED","Cast-Failure")
    equal(#f.ns.db.rankingQueue,0)
    f.ns.db.whisper = false
    f.api.Begin(20217); f:sent("Cast-On"); f:complete(nil,"Cast-On"); f:complete(nil,"Cast-On")
    equal(f.ns.Stats.Total(),2); equal(#f.ns.db.rankingQueue,1)
    equal(f.ns.db.rankingQueue[1].spellId,20217)
    equal(f.ns.db.rankingQueue[1].id,"1791734400-1")
    assert(not f.env.ForeverMouseoverBuffRankingExport:find("Example",1,true))
    assert(not f.env.ForeverMouseoverBuffRankingExport:find("Cast-On",1,true))
    f.ns.RankingExport.SetEnabled(false)
    equal(f.ns.db.rankingQueue,nil); equal(f.ns.Stats.Total(),2)
end

function tests.sender_class_and_race_are_snapshotted_before_delayed_recipient_response()
    local f = fixture()
    local class, race, classReads, raceReads = "SHAMAN", "Orc", 0, 0
    f.env.UnitClass = function(unit) equal(unit,"player"); classReads=classReads+1; return "Class",class end
    local previousRace = f.env.UnitRace
    f.env.UnitRace = function(unit)
        if unit == "player" then raceReads=raceReads+1; return "Race",race end
        return previousRace(unit)
    end
    f.raceToken, f.sex = "NightElf",3
    local callback, captured
    f.ns.Recipient.Request = function(_,_,fn) callback=fn; return true end
    local originalFormat = f.ns.Greetings.Format
    f.ns.Greetings.Format = function(input,variant) captured=input; return originalFormat(input,variant) end
    f.api.Begin(20217); f:sent(); f:complete()
    class, race, f.raceToken, f.sex = "PALADIN","Human","Dwarf",2
    callback(true)
    equal(captured.senderClass,"SHAMAN", "style must belong to the buffing class at click time")
    equal(captured.senderRace,"Orc"); equal(captured.raceToken,"NightElf"); equal(captured.sex,3)
    equal(classReads,1); equal(raceReads,1); equal(f.raceReads,1)
    equal(#f.messages,1); assert(not f.messages[1].message:find("Licht",1,true))
end
function tests.unavailable_sender_traits_never_leak_or_prevent_neutral_delivery()
    for _, kind in ipairs({"missing", "unknown", "secret", "localized_secret", "failure"}) do
        local f = fixture()
        local previousRace = f.env.UnitRace
        f.env.UnitRace = function(unit)
            if unit ~= "player" then return previousRace(unit) end
            if kind == "failure" then error("private sender race") end
            if kind == "secret" then return "Race",f.secret end
            if kind == "localized_secret" then return f.secret,"Orc" end
            return nil,nil
        end
        f.env.UnitClass = function()
            if kind == "failure" then error("private sender class") end
            if kind == "secret" then return "Class",f.secret end
            if kind == "localized_secret" then return f.secret,"SHAMAN" end
            return "Class",kind == "unknown" and "UNKNOWN" or nil
        end
        local captured
        local originalFormat = f.ns.Greetings.Format
        f.ns.Greetings.Format = function(input,variant) captured=input; return originalFormat(input,variant) end
        f.api.Begin(20217); f:sent(); f:complete()
        equal(#f.messages,1,kind .. ": optional traits cannot stop safe greeting")
        assert(not f.messages[1].message:find("Licht",1,true))
        assert(captured.senderRace == nil and (captured.senderClass == nil or captured.senderClass == "UNKNOWN"))
        for _, code in ipairs(f.logs) do assert(code:match("^[A-Z_]+$")) end
        equal(f.ns.db.senderRace,nil); equal(f.ns.db.senderClass,nil)
    end
end

local names = {}
for name in pairs(tests) do if not arg[1] or arg[1] == name then names[#names + 1] = name end end
assert(#names > 0, "unknown test filter")
table.sort(names)
local failed = 0
for _, name in ipairs(names) do
    local ok, err = pcall(tests[name])
    if ok then print("PASS " .. name) else failed = failed + 1; print("FAIL " .. name .. ": " .. err) end
end
print(string.format("Whisper: %d passed, %d failed", #names - failed, failed))
if failed > 0 then os.exit(1) end
