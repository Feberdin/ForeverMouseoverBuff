-- Purpose: deterministic foreign-buff thanks tests with public synthetic aura/player APIs.
-- Input: fake aura snapshots and clock. Output: PASS/FAIL; never calls the game.
-- Invariant: no target, attack, spell or keybinding mutation is permitted.
-- Debug: lua tests/test_auto_thanks.lua [test-name-substring].
local tests = {}
local function test(name, fn) tests[#tests + 1] = {name, fn} end
local function eq(got, want) assert(got == want, "expected " .. tostring(want) .. ", got " .. tostring(got)) end
local function setup()
    local s = {time = 100, auras = {}, emotes = {}, logs = {}, combat = false}
    local restricted = {}
    _G.issecretvalue = function(v) return v == restricted end
    _G.canaccesstable = function(v) return v ~= restricted end
    _G.C_Secrets = {ShouldAurasBeSecret = function() return s.secret == true end}
    _G.C_UnitAuras = {GetAuraDataByIndex = function(_, i, filter)
        eq(filter, "HELPFUL")
        if s.failure then error("synthetic private exception") end
        return s.auras[i]
    end}
    _G.C_ChatInfo = nil
    _G.GetTime = function() return s.time end
    _G.UnitIsPlayer = function(u) return u ~= "pet" and u ~= "npc" end
    _G.UnitIsUnit = function(a, b) return a == b end
    _G.UnitCanAssist = function(_, u) return u ~= "enemy" end
    _G.UnitName = function(u) if s.badName then return restricted end return u == "party2" and "Borin" or "Alyndra", "Testrealm" end
    _G.UnitGUID = function(u) return u == "player" and "Player-self" or "Player-" .. u end
    _G.DoEmote = function(token, name)
        if s.emoteFailure then error("synthetic private exception") end
        s.emotes[#s.emotes + 1] = {token, name}
    end
    for _, name in ipairs({"TargetUnit", "ClearTarget", "TargetLastTarget", "AttackTarget", "StartAttack", "StopAttack", "CastSpellByName", "RunMacroText"}) do
        _G[name] = function() error("Forbidden action: " .. name) end
    end
    local ns = {db = {autoThanks = true}, Log = function(_, code) s.logs[#s.logs + 1] = code end}
    -- The baseline addon has no observer. Loading is optional so the red result
    -- measures missing thanks behavior, not an invalid module/import environment.
    local f = io.open("src/ForeverMouseoverBuff/AutoThanks.lua", "rb")
    if f then f:close(); assert(loadfile("src/ForeverMouseoverBuff/AutoThanks.lua"))("ForeverMouseoverBuff", ns) end
    local observer = ns.AutoThanks or {Reset = function() end, Check = function() end, Tick = function() end}
    local function scan() observer.Check() end
    local function tick(seconds) s.time = s.time + (seconds or 2); observer.Tick() end
    observer.Reset(); scan()
    return s, ns, observer, scan, tick, restricted
end
local function buff(id, source, expiry) return {spellId = id or 19740, sourceUnit = source or "party1", expirationTime = expiry or 400} end

test("foreign_player_buff_requests_named_thank_without_target_change", function()
    local s, _, _, scan, tick = setup()
    s.auras = {buff()}; scan(); eq(#s.emotes, 0); tick()
    eq(#s.emotes, 1); eq(s.emotes[1][1], "THANK"); eq(s.emotes[1][2], "Alyndra-Testrealm")
end)
test("buff_bundle_and_repeated_aura_refresh_are_throttled", function()
    local s, _, _, scan, tick = setup()
    s.auras = {buff(), buff(19742)}; scan(); tick(); scan(); tick()
    s.auras[1].expirationTime = 700; scan(); tick(); eq(#s.emotes, 1)
end)
test("different_casters_are_global_rate_limited", function()
    local s, _, _, scan, tick = setup()
    s.auras = {buff(), buff(19742, "party2")}; scan(); tick(); eq(#s.emotes, 1)
    tick(5); eq(#s.emotes, 2)
end)
test("self_pet_npc_hostile_heals_and_procs_are_ignored", function()
    local s, _, _, scan, tick = setup()
    s.auras = {buff(19740, "player"), buff(19742, "pet"), buff(20217, "npc"), buff(1243, "enemy"), buff(19750), buff(20178)}
    scan(); tick(); eq(#s.emotes, 0)
end)
test("missing_caster_or_restricted_name_is_ignored", function()
    local s, _, _, scan, tick = setup()
    s.badName = true; s.auras = {buff()}; scan(); tick(); eq(#s.emotes, 0)
    s.badName = false; s.auras = {{spellId = 19742, expirationTime = 400}}; scan(); tick(); eq(#s.emotes, 0)
end)
test("login_zone_and_restricted_recovery_establish_silent_baseline", function()
    local s, _, observer, scan, tick = setup()
    s.auras = {buff()}; observer.Reset(); scan(); tick(); eq(#s.emotes, 0)
    s.secret = true; scan(); s.auras = {buff(), buff(19742)}; s.secret = false; scan(); tick(); eq(#s.emotes, 0)
end)
test("setting_off_cancels_pending_and_reenable_is_silent", function()
    local s, ns, observer, scan, tick = setup()
    s.auras = {buff()}; scan(); ns.db.autoThanks = false; tick(); eq(#s.emotes, 0)
    ns.db.autoThanks = true; observer.Reset(); scan(); tick(); eq(#s.emotes, 0)
end)
test("emote_failure_has_fixed_diagnostic_and_no_retry_storm", function()
    local s, _, observer, scan, tick = setup()
    s.emoteFailure = true; s.auras = {buff()}; scan(); tick(); tick(10)
    eq(observer.LastCode, "THANKS_EMOTE_FAILED"); eq(#s.emotes, 0)
end)
test("unavailable_emote_never_falls_back_to_current_target", function()
    local s, _, observer, scan, tick = setup()
    _G.DoEmote = nil; s.auras = {buff()}; scan(); tick()
    eq(#s.emotes, 0); eq(observer.LastCode, "THANKS_EMOTE_UNAVAILABLE")
end)
test("combat_does_not_change_attack_or_protected_actions", function()
    local s, _, _, scan, tick = setup()
    _G.InCombatLockdown = function() return true end
    s.auras = {buff()}; scan(); tick(); eq(#s.emotes, 1)
end)
test("clock_rollback_discards_pending_without_spam", function()
    local s, _, _, scan, tick = setup()
    s.auras = {buff()}; scan(); s.time = 1; tick(); eq(#s.emotes, 0)
end)
test("unreadable_caster_recovery_does_not_thank_for_existing_buff", function()
    local s, _, observer, scan, tick = setup()
    s.badName = true; s.auras = {buff()}; observer.Reset(); scan()
    s.badName = false; scan(); tick(); eq(#s.emotes, 0)
end)
test("temporary_caster_gap_does_not_recreate_existing_buff", function()
    local s, _, observer, scan, tick = setup()
    s.auras = {buff()}; observer.Reset(); scan()
    s.badName = true; scan(); s.badName = false; scan(); tick(); eq(#s.emotes, 0)
end)
test("native_perform_emote_accepts_explicit_name_when_legacy_api_missing", function()
    local s, _, _, scan, tick = setup()
    _G.C_ChatInfo = {PerformEmote = _G.DoEmote}; _G.DoEmote = nil
    s.auras = {buff()}; scan(); tick(); eq(#s.emotes, 1)
    eq(s.emotes[1][2], "Alyndra-Testrealm")
end)
test("native_perform_emote_restriction_is_not_reported_as_request_success", function()
    local s, _, observer, scan, tick = setup()
    _G.DoEmote = nil; _G.C_ChatInfo = {PerformEmote = function() return true end}
    s.auras = {buff()}; scan(); tick(); eq(observer.LastCode, "THANKS_EMOTE_RESTRICTED")
end)
test("native_emote_is_preferred_and_restriction_never_retries_legacy", function()
    local s, _, observer, scan, tick = setup()
    _G.C_ChatInfo = {PerformEmote = function() return true end}
    s.auras = {buff()}; scan(); tick()
    eq(#s.emotes, 0); eq(observer.LastCode, "THANKS_EMOTE_RESTRICTED")
end)
local count, failed = 0, 0
for _, entry in ipairs(tests) do
    if not arg[1] or entry[1]:find(arg[1], 1, true) then
        count = count + 1
        local ok, err = pcall(entry[2]); if ok then print("PASS " .. entry[1]) else failed = failed + 1; print("FAIL " .. entry[1] .. ": " .. tostring(err)) end
    end
end
assert(count > 0, "No matching tests")
print(count .. " auto thanks tests, " .. failed .. " failures")
os.exit(failed == 0 and 0 or 1)
