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
    _G.C_CombatLog = nil
    _G.IsInRaid = function() return s.raid == true end
    _G.GetNumGroupMembers = function() return #(s.members or {}) end
    _G.GetNumSubgroupMembers = function() return #(s.members or {}) end
    _G.CombatLogGetCurrentEventInfo = function()
        if s.logFailure then error("private event failure") end
        return unpack(s.event or {}, 1, 18)
    end
    _G.GetTime = function() return s.time end
    _G.UnitIsPlayer = function(u) return u ~= "pet" and u ~= "npc" end
    _G.UnitIsUnit = function(a, b) return a == b end
    _G.UnitCanAssist = function(_, u) return u ~= "enemy" end
    _G.UnitName = function(u) if s.badName then return restricted end return u == "party2" and "Borin" or "Alyndra", "Testrealm" end
    _G.UnitGUID = function(u)
        if s.rosterRestricted and u ~= "player" then return restricted end
        local index = u:match("^party(%d+)$") or u:match("^raid(%d+)$")
        return u == "player" and "Player-self" or (index and s.members and s.members[tonumber(index)]) or "Player-" .. u
    end
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
-- Synthetic CLEU shape: amount/overhealing follow the three spell fields.
-- Flags 0x518 mean outsider affiliation, friendly reaction, player control/type.
local function heal(s, observer, changes)
    s.event = {100, "SPELL_HEAL", false, "Player-healer", "Alyndra-Testrealm", 1304,
        0, "Player-self", "Me", 1297, 0, 2061, "Flash Heal", 2, 100, 10, 0, false}
    for index, value in pairs(changes or {}) do s.event[index] = value end
    if observer.OnCombatLog then observer.OnCombatLog() end
end
test("heal_outsider_direct_and_periodic_request_named_thank", function()
    for _, event in ipairs({"SPELL_HEAL", "SPELL_PERIODIC_HEAL"}) do
        local s, _, observer, _, tick = setup()
        heal(s, observer, {[2] = event}); eq(#s.emotes, 0); tick()
        eq(#s.emotes, 1); eq(s.emotes[1][2], "Alyndra-Testrealm")
    end
end)
test("heal_rejects_self_pet_npc_party_raid_wrong_destination_damage_and_overheal", function()
    for _, changes in ipairs({{[4]="Player-self"}, {[6]=4376}, {[6]=2584},
        {[6]=1298}, {[6]=1300}, {[8]="Player-other"}, {[2]="SPELL_DAMAGE"},
        {[15]=0}, {[16]=100}, {[16]=101}, {[5]="bad name"}, {[6]=1288}}) do
        local s, _, observer, _, tick = setup()
        heal(s, observer, changes); tick(); eq(#s.emotes, 0)
    end
end)
test("heal_shares_buff_bundling_and_per_caster_cooldown", function()
    local s, _, observer, scan, tick = setup()
    s.auras = {buff(19740, "healer")}; scan(); heal(s, observer); tick(); eq(#s.emotes, 1)
    heal(s, observer); tick(5); eq(#s.emotes, 1)
    tick(60); heal(s, observer); tick(); eq(#s.emotes, 2)
end)
test("heal_group_membership_rechecked_before_send_and_buff_behavior_preserved", function()
    for _, raid in ipairs({false, true}) do
        local s, _, observer, _, tick = setup()
        heal(s, observer); s.members = {"Player-healer"}; s.raid = raid; tick(); eq(#s.emotes, 0)
    end
    local s, _, observer, scan, tick = setup()
    heal(s, observer); s.members = {"Player-healer"}; s.auras = {buff(19740, "healer")}
    scan(); tick(); eq(#s.emotes, 1)
end)
test("heal_disabled_unknown_roster_or_secret_event_fail_closed", function()
    for _, mode in ipairs({"disabled", "roster", "secret", "api", "missing"}) do
        local s, ns, observer, _, tick, secret = setup()
        if mode == "disabled" then ns.db.autoThanks = false end
        if mode == "roster" then s.members = {"Player-other"}; s.rosterRestricted = true end
        if mode == "api" then s.logFailure = true end
        if mode == "missing" then _G.CombatLogGetCurrentEventInfo = nil end
        heal(s, observer, mode == "secret" and {[15] = secret} or nil)
        tick(); eq(#s.emotes, 0)
    end
end)
test("heal_non_heal_events_ignore_missing_heal_fields_without_diagnostics", function()
    local s, _, observer, _, tick = setup()
    s.event = {100, "UNIT_DIED"}
    observer.OnCombatLog(); tick(); eq(#s.emotes, 0); eq(#s.logs, 0)
end)
-- Forever may have neither public combat-log API. That must disable only
-- healing observation; the public aura path must still request buff thanks.
test("heal_missing_combat_log_apis_keep_buff_observation_available", function()
    local s, _, observer, scan, tick = setup()
    _G.C_CombatLog = nil; _G.CombatLogGetCurrentEventInfo = nil
    observer.OnCombatLog()
    eq(observer.LastCode, "THANKS_HEAL_UNAVAILABLE"); eq(#s.emotes, 0)
    s.auras = {buff()}; scan(); tick(); eq(#s.emotes, 1)
end)
test("heal_native_combat_log_works_without_legacy_global", function()
    local s, _, observer, _, tick = setup()
    _G.C_CombatLog = {GetCurrentEventInfo = _G.CombatLogGetCurrentEventInfo,
        IsCombatLogRestricted = function() return false end}
    _G.CombatLogGetCurrentEventInfo = nil
    heal(s, observer); tick(); eq(#s.emotes, 1)
end)
test("heal_native_restriction_blocks_legacy_fallback", function()
    local s, _, observer, _, tick = setup()
    _G.C_CombatLog = {IsCombatLogRestricted = function() return true end}
    heal(s, observer); tick(); eq(#s.emotes, 0)
end)
test("heal_secret_native_api_fields_never_fall_back_to_legacy", function()
    for _, key in ipairs({"GetCurrentEventInfo", "IsCombatLogRestricted"}) do
        local s, _, observer, _, tick, secret = setup()
        _G.C_CombatLog = {[key] = secret}
        heal(s, observer); tick(); eq(#s.emotes, 0)
    end
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
