-- Purpose: Exercise public game-data boundaries and the real Core/API contract.
-- Input: Synthetic game facts; output: named PASS/FAIL lines and exit status.
-- Invariants: No real players, external access, protected actions, or UI simulation.
-- Debug: lua tests/test_api.lua [test_name] from the project directory.
local tests = {}
local function equal(actual, expected, message)
    if actual ~= expected then
        error((message or "unexpected value") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual), 2)
    end
end

local function loadModule(path, env, namespace)
    local chunk
    if setfenv then
        chunk = assert(loadfile(path))
        setfenv(chunk, env)
    else
        chunk = assert(loadfile(path, "t", env))
    end
    chunk("ForeverMouseoverBuff", namespace)
end

-- Only native boundaries are faked. Spell discovery, guards, caches, and the
-- final decision are actual production modules. Poison sentinels are never cast.
local function fixture()
    local f = { calls = {}, combat = false, targetCombat = false, locked = false,
        auras = {}, ownedAuras = {}, known = {}, range = {}, usable = {}, mounted = false,
        level = 18, targetClass = "WARRIOR", auraRestricted = false }
    local env = setmetatable({}, { __index = _G })
    f.env = env
    f.secret = setmetatable({}, { __tostring = function() error("secret printed") end })
    f.opaque = setmetatable({}, { __index = function() error("opaque indexed") end })
    env.issecretvalue = function(value) return rawequal(value, f.secret) end
    env.canaccesstable = function(value) return not rawequal(value, f.opaque) end
    local function count(name)
        f.calls[name] = (f.calls[name] or 0) + 1
    end
    local function unitAllowed(unit)
        assert(unit == "player" or unit == "mouseover", "only allowed unit tokens")
    end
    env.InCombatLockdown = function() count("lock"); return f.locked end
    env.UnitAffectingCombat = function(unit)
        unitAllowed(unit); count("combat:" .. unit)
        if unit == "player" then return f.combat end
        return f.targetCombat
    end
    env.UnitClass = function(unit)
        unitAllowed(unit); count("class:" .. unit)
        return "Localized class", unit == "player" and "PALADIN" or f.targetClass
    end
    env.IsMounted = function() return f.mounted end
    env.IsFlying = function() return false end
    env.UnitInVehicle = function(unit) unitAllowed(unit); return false end
    env.UnitExists = function(unit) unitAllowed(unit); return true end
    env.UnitIsPlayer = function(unit) unitAllowed(unit); return true end
    env.UnitCanAssist = function(one, two) unitAllowed(one); unitAllowed(two); return true end
    env.UnitIsDeadOrGhost = function(unit) unitAllowed(unit); return false end
    env.UnitIsUnit = function(one, two) unitAllowed(one); unitAllowed(two); return false end
    env.UnitIsConnected = function(unit) unitAllowed(unit); return true end
    env.UnitIsVisible = function(unit) unitAllowed(unit); return true end
    env.UnitLevel = function(unit) unitAllowed(unit); return f.level end
    env.UnitName = function() error("must not read player names") end
    env.UnitGUID = function() error("must not read GUIDs") end
    env.GetBuildInfo = function() return "1.60.1", "69913", "public-date", 16001 end
    env.Enum = { SpellBookSpellBank = { Player = 0 }, SpellBookItemType = { Spell = 1 } }
    f.names = {
        [19740] = "Segen der Macht", [19742] = "Segen der Weisheit", [20217] = "Segen der Könige",
        [25782] = "Großer Segen der Macht", [25894] = "Großer Segen der Weisheit",
        [25898] = "Großer Segen der Könige", [1038] = "Segen der Rettung",
        [25895] = "Großer Segen der Rettung", [19977] = "Segen des Lichts",
        [25890] = "Großer Segen des Lichts", [20911] = "Segen des Refugiums",
        [25899] = "Großer Segen des Refugiums", [6940] = "Segen der Opferung",
        [1022] = "Segen des Schutzes", [1044] = "Segen der Freiheit",
    }
    f.entries = {
        { id = 19740, familyID = 19740, level = 4 },
        { id = 19834, familyID = 19740, level = 12 },
        { id = 19835, familyID = 19740, level = 22 },
        { id = 19742, familyID = 19742, level = 14 },
        { id = 20217, familyID = 20217, level = 20 },
    }
    f.lines = { { itemIndexOffset = 0, numSpellBookItems = #f.entries } }
    env.C_SpellBook = {
        GetNumSpellBookSkillLines = function() count("book"); return #f.lines end,
        GetSpellBookSkillLineInfo = function(index) return f.lines[index] end,
        GetSpellBookItemInfo = function(index, bank)
            equal(bank, 0); count("slot")
            local entry = f.entries[index]
            return entry and { spellID = entry.id, actionID = entry.id,
                itemType = 1, isPassive = entry.passive or false, isOffSpec = entry.offspec or false }
        end,
        GetSpellBookItemName = function(index, bank)
            equal(bank, 0); local entry = f.entries[index]
            return f.names[entry.familyID], "Rang " .. index
        end,
        GetSpellBookItemLevelLearned = function(index, bank)
            equal(bank, 0); return f.entries[index].level
        end,
        IsSpellKnown = function(id, bank)
            equal(bank, 0); count("known")
            if f.known[id] == nil then return true end
            return f.known[id]
        end,
    }
    env.C_Spell = {
        GetSpellName = function(id) return f.names[id] end,
        GetSpellInfo = function(id) return f.names[id] and { name = f.names[id] } end,
        IsSpellInRange = function(id, unit)
            equal(unit, "mouseover"); count("range")
            if f.range[id] == nil then return true end
            return f.range[id]
        end,
        IsSpellUsable = function(id)
            count("usable")
            if f.usable[id] == nil then return true, false end
            return f.usable[id], false
        end,
    }
    env.C_Secrets = { ShouldAurasBeSecret = function() return f.auraRestricted end }
    env.C_UnitAuras = { GetAuraDataByIndex = function(unit, index, filter)
        equal(unit, "mouseover")
        if filter == "HELPFUL|PLAYER" then
            count("ownAura")
            return f.ownedAuras[index]
        end
        equal(filter, "HELPFUL"); count("aura")
        return f.auras[index]
    end }
    local namespace = { logs = {} }
    function namespace:Log(code) self.logs[#self.logs + 1] = code end
    f.namespace = namespace
    loadModule("src/ForeverMouseoverBuff/Core.lua", env, namespace)
    loadModule("src/ForeverMouseoverBuff/API.lua", env, namespace)
    f.api, f.core = namespace.API, namespace.Core
    function f:read(mode) return self.api.ReadContext(mode or "auto") end
    function f:decision(mode) return self.core.Decide(self:read(mode)) end
    return f
end

function tests.learned_low_ranks_are_captured_and_highest_eligible_rank_is_ready()
    local f = fixture()
    local data = f:read()
    equal(data.playerClass, "PALADIN", "public player class is captured")
    equal(#data.spells, 5, "all learned ranks, not just the displayed highest rank")
    equal(data.spells[2].learnedLevel, 12)
    equal(f.core.Decide(data).spellID, 19834)
end

-- The real API must pass existing families and complete learned spells to the
-- policy, rather than stopping at a single "some blessing exists" flag.
function tests.foreign_blessings_preserve_families_and_do_not_hide_learned_spells()
    local f = fixture()
    f.auras = {
        { spellId = 19838, name = "Segen der Macht" },
        { spellId = 25894, name = "Großer Segen der Weisheit" },
    }
    local data = f:read()
    equal(type(data.spells), "table", "existing foreign blessings must not hide learned spells")
    equal(data.hasBlessing, true)
    equal(#data.blessings, 2)
    equal(data.blessings[1].family, "might")
    equal(data.blessings[1].spellID, 19838)
    equal(data.blessings[1].sourceIsPlayer, false)
    equal(data.blessings[2].family, "wisdom", "greater blessing keeps its normal family")
    equal(data.blessings[2].sourceIsPlayer, false)
    equal(data.blessings[1].sourceUnit, nil, "identity tokens never enter Core")
end

function tests.own_filtered_blessing_proves_ownership_without_names_or_guids()
    local f = fixture()
    f.auras = {
        { spellId = 19838, name = "Segen der Macht" },
        { spellId = 20217, name = "Segen der Könige" },
    }
    f.ownedAuras = { f.auras[2] }
    local data = f:read()
    equal(data.blessings[1].sourceIsPlayer, false)
    equal(data.blessings[2].sourceIsPlayer, true)
    equal(f.calls.ownAura, 2, "native PLAYER filter must reach a proven end")
end

function tests.unreadable_or_changed_owned_aura_scan_invalidates_whole_snapshot()
    for _, kind in ipairs({ "secret", "changed", "failure" }) do
        local f = fixture()
        f.auras = { { spellId = 19838, name = "Segen der Macht" } }
        if kind == "secret" then f.ownedAuras = { f.secret }
        elseif kind == "changed" then
            f.ownedAuras = { { spellId = 20217, name = "Segen der Könige" } }
        else
            local original = f.env.C_UnitAuras.GetAuraDataByIndex
            f.env.C_UnitAuras.GetAuraDataByIndex = function(unit, index, filter)
                if filter == "HELPFUL|PLAYER" then error("native failure must not be retained") end
                return original(unit, index, filter)
            end
        end
        local data = f:read()
        equal(data.auraState, "unknown", kind)
        equal(data.blessings, nil, "incomplete ownership cannot reach policy")
        equal(data.spells, nil)
    end
end

function tests.cache_is_detached_and_refresh_invalidates_without_native_reads()
    local f = fixture()
    local first = f:read()
    first.spells[1].spellID = 999999
    local second = f:read()
    equal(second.spells[1].spellID, 19740)
    equal(f.calls.book, 1, "metadata cache reused")
    f.api.RefreshSpellbook()
    equal(f.calls.book, 1, "refresh only invalidates")
    f:read()
    equal(f.calls.book, 2)
end

function tests.metadata_existence_never_implies_a_spell_is_learned()
    local f = fixture()
    for _, entry in ipairs(f.entries) do f.known[entry.id] = false end
    equal(f:decision().code, "NO_KNOWN_SPELL")
    equal(f.calls.range, nil, "range only queried for learned candidates")
    equal(f.calls.usable, nil)
end

function tests.passive_offspec_and_unrelated_spells_are_not_candidates()
    local f = fixture()
    f.entries[2].passive = true
    f.entries[3].offspec = true
    f.entries[4].familyID = 900001
    f.names[900001] = "Unrelated spell"
    local data = f:read()
    equal(#data.spells, 2)
    equal(f.core.Decide(data).spellID, 19740)
end

function tests.missing_optional_spell_name_api_uses_public_info_fallback()
    local f = fixture()
    f.env.C_Spell.GetSpellName = nil
    f.env.C_Secrets = nil
    equal(f:decision().ready, true)
end

function tests.range_and_usable_false_preserve_distinct_decisions()
    local f = fixture()
    f.range[19834] = false
    equal(f:decision().code, "OUT_OF_RANGE")
    f.range[19834], f.usable[19834] = true, false
    equal(f:decision().code, "NOT_USABLE")
end

function tests.nil_range_and_missing_power_result_are_not_false_facts()
    local f = fixture()
    f.env.C_Spell.IsSpellInRange = function() return nil end
    equal(f:decision().code, "INVALID_SPELL_DATA")
    f = fixture()
    f.env.C_Spell.IsSpellUsable = function() return true, nil end
    equal(f:decision().code, "INVALID_SPELL_DATA")
end

function tests.player_combat_stops_before_other_reads()
    local f = fixture()
    f.combat = true
    equal(f:read().playerCombat, true)
    equal(f.calls["class:player"], nil)
    equal(f.calls["combat:mouseover"], nil)
    equal(f.calls.aura, nil)
    equal(f.calls.book, nil)
end

function tests.native_lockdown_stops_before_even_player_combat_read()
    local f = fixture()
    f.locked = true
    equal(f.api.Locked(), true)
    equal(f.calls["combat:player"], nil)
    f:read()
    equal(f.calls.book, nil)
end

function tests.combat_change_before_return_invalidates_the_read_context()
    local f = fixture()
    f.env.C_Spell.IsSpellUsable = function() f.combat = true; return true, false end
    local data = f:read()
    equal(data.playerCombat, true)
    equal(data.spells, nil, "no actionable spell snapshot crosses combat transition")
    equal(data.blessings, nil, "no aura snapshot crosses combat transition")
    equal(f.core.Decide(data).ready, false)
end

function tests.unknown_lock_guard_or_native_failure_is_locked()
    local f = fixture()
    f.env.InCombatLockdown = function() error("private native error") end
    equal(f.api.Locked(), true)
    f = fixture()
    f.env.issecretvalue = false
    equal(f.api.Locked(), true)
    f = fixture()
    f.env.UnitAffectingCombat = function() return nil end
    equal(f.api.Locked(), true)
end

function tests.missing_player_and_target_state_is_not_interpreted_as_safe_false()
    local f = fixture()
    f.env.IsMounted = function() return nil end
    equal(f:decision().ready, false)
    f = fixture()
    f.env.UnitIsVisible = function() return nil end
    equal(f:decision().code, "TARGET_STATE_UNKNOWN")
    f = fixture()
    f.env.UnitInVehicle = false
    equal(f:decision().ready, false)
end

function tests.no_target_skips_auras_and_spellbook()
    local f = fixture()
    f.env.UnitExists = function() return false end
    equal(f:decision().code, "NO_TARGET")
    equal(f.calls.book, nil)
    equal(f.calls.aura, nil)
end

function tests.target_in_combat_uses_public_auras_and_normal_spell_selection()
    local f = fixture()
    f.targetCombat = true
    local result = f:decision()
    equal(result.ready, true, "a fighting target is eligible while the caster is outside combat")
    equal(result.spellID, 19834)
    assert(f.calls.aura and f.calls.book, "buff and rank checks must still run")
    equal(f.calls["combat:mouseover"], nil, "irrelevant target combat must not be queried")
end

function tests.target_combat_status_is_not_read_even_when_secret_or_unavailable()
    for _, state in ipairs({ "secret", "missing", "failure" }) do
        local f = fixture()
        f.env.UnitAffectingCombat = function(unit)
            if unit == "player" then return false end
            f.calls.targetCombatAttempt = true
            if state == "secret" then return f.secret end
            if state == "failure" then error("target combat unavailable") end
        end
        equal(f:decision().spellID, 19834, state)
        equal(f.calls.targetCombatAttempt, nil, "target combat must not cross the API boundary")
    end
end

function tests.target_in_combat_preserves_existing_blessing_and_chooses_useful_alternative()
    local f = fixture()
    f.targetCombat, f.level = true, 30
    f.auras = { { spellId = 19835, name = "Segen der Macht" } }
    local result = f:decision()
    equal(result.code, "READY_FALLBACK")
    equal(result.family, "kings")
    equal(result.spellID, 20217, "existing Might must not be replaced")
end

function tests.target_in_combat_still_rejects_restricted_or_secret_auras()
    for _, kind in ipairs({ "restricted", "secret", "failure" }) do
        local f = fixture()
        f.targetCombat = true
        if kind == "restricted" then f.auraRestricted = true
        elseif kind == "secret" then f.auras = { f.secret }
        else f.env.C_UnitAuras.GetAuraDataByIndex = function() error("aura unavailable") end end
        local result = f:decision()
        equal(result.code, "AURA_UNKNOWN", kind)
        equal(result.ready, false)
        equal(result.spellID, nil, "unknown buffs must not produce a cast")
        equal(f.calls.book, nil, "no spell choice may bypass aura protection")
    end
end

function tests.temporary_and_unmanaged_blessings_remain_protected()
    for _, id in ipairs({ 1022, 1044, 6940, 1038, 20911 }) do
        local f = fixture()
        f.auras = { { spellId = id, name = "Synthetic localized aura" } }
        equal(f:decision().code, "HAS_BLESSING", "known blessing ID " .. id)
    end
end

function tests.localized_name_recognizes_unknown_future_blessing_rank()
    local f = fixture()
    f.auras = { { spellId = 990000, name = "Großer Segen der Könige" } }
    local data = f:read()
    equal(data.blessings[1].family, "kings")
    equal(f.core.Decide(data).spellID, 19834, "foreign Kings does not hide missing Might")
end

function tests.foreign_might_selects_kings_then_keeps_our_kings_stable()
    local f = fixture()
    f.level = 30
    f.auras = { { spellId = 19838, name = "Segen der Macht" } }
    local decision = f:decision()
    equal(decision.code, "READY_FALLBACK")
    equal(decision.spellID, 20217)
    f.auras[2] = { spellId = 20217, name = "Segen der Könige" }
    f.ownedAuras = { f.auras[2] }
    equal(f:decision().code, "OWN_BLESSING_PRESERVED", "another hover must not rotate own blessing")
end

function tests.duplicate_foreign_and_own_spell_ids_preserve_our_family()
    local f = fixture()
    f.auras = {
        { spellId = 19834, name = "Segen der Macht" },
        { spellId = 19834, name = "Segen der Macht" },
    }
    f.ownedAuras = { f.auras[2] }
    equal(f:decision().code, "OWN_BLESSING_PRESERVED")
end

function tests.unrelated_auras_and_clean_end_nil_are_not_blessings()
    local f = fixture()
    f.auras = { { spellId = 123, name = "Unrelated buff" } }
    equal(f:decision().ready, true)
    equal(f.calls.aura, 2, "must prove the end of the list")
end

function tests.restricted_empty_auras_are_unknown_not_missing()
    local f = fixture()
    f.auraRestricted = true
    equal(f:decision().code, "AURA_UNKNOWN")
    equal(f.calls.aura, nil)
    f = fixture()
    f.env.C_Secrets.ShouldAurasBeSecret = function() error("native denied") end
    equal(f:decision().code, "AURA_UNKNOWN")
end

function tests.secret_or_opaque_aura_restriction_namespace_cannot_be_skipped()
    for _, kind in ipairs({ "secret", "opaque", "broken" }) do
        local f = fixture()
        if kind == "broken" then f.env.C_Secrets = { ShouldAurasBeSecret = false }
        else f.env.C_Secrets = f[kind] end
        equal(f:decision().code, "AURA_UNKNOWN", kind)
        equal(f.calls.aura, nil, "do not read auras when restriction status is unavailable")
    end
end

function tests.secret_mode_is_removed_before_the_pure_core_receives_it()
    local f = fixture()
    local context = f.api.ReadContext(f.secret)
    assert(context.mode == nil, "opaque input must not cross into the pure policy")
    equal(f.core.Decide(context).ready, false)
end

function tests.aura_secret_opaque_or_unreadable_field_blocks_without_touching_it()
    for _, kind in ipairs({ "secret", "opaque", "field", "failure" }) do
        local f = fixture()
        if kind == "secret" then f.auras[1] = f.secret
        elseif kind == "opaque" then f.auras[1] = f.opaque
        elseif kind == "field" then f.auras[1] = { spellId = f.secret, name = "Secret" }
        else f.env.C_UnitAuras.GetAuraDataByIndex = function() error("native private detail") end end
        equal(f:decision().code, "AURA_UNKNOWN", kind)
    end
end

function tests.aura_limit_requires_end_nil_and_does_not_publish_partial_results()
    local f = fixture()
    for index = 1, 255 do f.auras[index] = { spellId = 100000 + index, name = "Unrelated" } end
    equal(f:decision().ready, true)
    equal(f.calls.aura, 256)
    f.auras[256] = { spellId = 12345, name = "One too many" }
    equal(f:decision().code, "AURA_UNKNOWN")
end

function tests.native_failures_and_opaque_spell_data_never_propose_partial_book()
    local f = fixture()
    f.env.C_SpellBook.GetSpellBookItemInfo = function() return f.opaque end
    equal(f:decision().code, "INVALID_SPELL_DATA")
    f = fixture()
    f.env.C_SpellBook.IsSpellKnown = function() return f.secret end
    equal(f:decision().code, "INVALID_SPELL_DATA")
    f = fixture()
    f.env.C_SpellBook.GetSpellBookItemLevelLearned = function() return nil end
    equal(f:decision().code, "INVALID_SPELL_DATA")
end

function tests.spellbook_line_slot_and_overlap_bounds_fail_closed()
    for _, kind in ipairs({ "lines", "slots", "overlap" }) do
        local f = fixture()
        if kind == "lines" then f.env.C_SpellBook.GetNumSpellBookSkillLines = function() return 101 end
        elseif kind == "slots" then f.lines[1].numSpellBookItems = 2001
        else f.lines[2] = { itemIndexOffset = 0, numSpellBookItems = 1 } end
        equal(f:decision().code, "INVALID_SPELL_DATA", kind)
        assert((f.calls.slot or 0) <= 2000)
    end
end

function tests.cache_is_invalidated_after_failed_refresh_and_recovers_fresh()
    local f = fixture()
    equal(f:decision().ready, true)
    f.api.RefreshSpellbook()
    f.lines[1].numSpellBookItems = 2001
    equal(f:decision().code, "INVALID_SPELL_DATA")
    f.lines[1].numSpellBookItems = 5
    f.api.RefreshSpellbook()
    equal(f:decision().ready, true)
end

function tests.client_contains_only_validated_public_build_metadata()
    local f = fixture()
    local client = f.api.Client()
    equal(client.version, "1.60.1")
    equal(client.build, "69913")
    equal(client.interface, 16001)
    f.env.GetBuildInfo = function() return f.secret, "private", "", 16001 end
    equal(f.api.Client().version, nil)
end

function tests.logs_never_include_native_errors_or_identifiers()
    local f = fixture()
    f.env.C_SpellBook.GetNumSpellBookSkillLines = function() error("private-native-value") end
    equal(f:decision().ready, false)
    assert(#f.namespace.logs > 0, "failure produces a diagnostic code")
    for _, code in ipairs(f.namespace.logs) do
        assert(type(code) == "string" and code:match("^[A-Z_]+$"), "fixed codes only")
    end
end

-- Combat bindings need one fixed, learned spell before lockdown. These tests
-- prohibit target-dependent reads and macro syntax in the localized name.
local function combatBlessing(f)
    assert(type(f.api.CombatBlessing) == "function",
        "the fixed learned Kings combat binding must be available")
    return f.api.CombatBlessing()
end

function tests.combat_blessing_returns_only_learned_normal_kings_without_target_reads()
    local f = fixture()
    local function forbidden() error("combat preparation must not inspect a target") end
    for _, key in ipairs({ "UnitExists", "UnitIsPlayer", "UnitCanAssist", "UnitIsDeadOrGhost",
        "UnitIsUnit", "UnitIsConnected", "UnitIsVisible", "UnitLevel" }) do
        f.env[key] = forbidden
    end
    f.env.C_UnitAuras.GetAuraDataByIndex = forbidden
    f.env.C_Spell.IsSpellInRange, f.env.C_Spell.IsSpellUsable = forbidden, forbidden
    f.env.C_SpellBook.GetNumSpellBookSkillLines = forbidden
    f.env.C_SpellBook.IsSpellKnown = function(id, bank)
        equal(id, 20217, "only ordinary Kings is an allowed combat choice")
        equal(bank, 0, "the Player spellbook bank must be used")
        return true
    end
    local result, code = combatBlessing(f)
    equal(result.spellID, 20217)
    equal(result.spellName, "Segen der Könige")
    equal(code, "COMBAT_SPELL_READY")
    equal(f.api.LastCode, code)
    equal(f.calls["class:mouseover"], nil)
    equal(f.calls["combat:mouseover"], nil)
    equal(f.calls.book, nil)
end

function tests.combat_blessing_never_falls_back_when_kings_is_not_learned()
    local f = fixture()
    f.known[20217] = false
    local result, code = combatBlessing(f)
    equal(result, nil)
    equal(code, "COMBAT_SPELL_NOT_LEARNED")
    equal(f.api.LastCode, code)
    f.known[20217] = true
    equal(combatBlessing(f).spellID, 20217, "newly learned Kings must be discovered without a reload")
    f.known[20217] = false
    equal(combatBlessing(f), nil, "a formerly learned spell must not be returned from a stale cache")
end

function tests.combat_blessing_stops_before_spell_reads_for_combat_and_non_paladin()
    for _, state in ipairs({ "lockdown", "combat", "class", "unknown" }) do
        local f = fixture()
        local expected = "PLAYER_IN_COMBAT"
        if state == "lockdown" then f.locked = true
        elseif state == "combat" then f.combat = true
        elseif state == "class" then
            f.env.UnitClass = function() return "Mage", "MAGE" end
            expected = "PLAYER_NOT_PALADIN"
        else
            f.env.InCombatLockdown = function() return nil end
            expected = "COMBAT_SPELL_UNAVAILABLE"
        end
        local result, code = combatBlessing(f)
        equal(result, nil, state)
        equal(code, expected, state)
        equal(f.calls.known, nil, "no spellbook lookup after an unsafe player state")
    end
end

function tests.combat_blessing_invalidates_preparation_if_combat_starts_during_lookup()
    local f = fixture()
    f.env.C_SpellBook.IsSpellKnown = function() f.combat = true; return true end
    local result, code = combatBlessing(f)
    equal(result, nil)
    equal(code, "PLAYER_IN_COMBAT")
end

function tests.combat_blessing_rejects_secret_or_unavailable_spellbook_values()
    for _, state in ipairs({ "known_secret", "known_nil", "known_failure", "bank_secret",
        "bank_missing", "book_opaque", "method_missing", "guard_missing", "class_secret" }) do
        local f = fixture()
        if state == "known_secret" then f.env.C_SpellBook.IsSpellKnown = function() return f.secret end
        elseif state == "known_nil" then f.env.C_SpellBook.IsSpellKnown = function() return nil end
        elseif state == "known_failure" then f.env.C_SpellBook.IsSpellKnown = function() error("private native detail") end
        elseif state == "bank_secret" then f.env.Enum.SpellBookSpellBank.Player = f.secret
        elseif state == "bank_missing" then f.env.Enum.SpellBookSpellBank.Player = nil
        elseif state == "book_opaque" then f.env.C_SpellBook = f.opaque
        elseif state == "method_missing" then f.env.C_SpellBook.IsSpellKnown = nil
        elseif state == "guard_missing" then f.env.issecretvalue = nil
        else f.env.UnitClass = function() return "Private", f.secret end end
        local result, code = combatBlessing(f)
        equal(result, nil, state)
        equal(code, "COMBAT_SPELL_UNAVAILABLE", state)
        for _, logged in ipairs(f.namespace.logs) do
            assert(logged:match("^[A-Z_]+$"), "only fixed diagnostic codes may be logged")
        end
    end
end

function tests.combat_blessing_accepts_public_spellinfo_name_fallback()
    local f = fixture()
    f.env.C_Spell.GetSpellName = nil
    equal(combatBlessing(f).spellName, "Segen der Könige")
end

function tests.combat_blessing_rejects_unsafe_missing_and_secret_names()
    for _, name in ipairs({ "Segen\n/cast Another", "Segen\rAnother", "Segen\tAnother",
        "Segen|Another", "Segen;Another", "Segen[help]", "Segen]", "Segen/Another", "", " ",
        string.rep("a", 201) }) do
        local f = fixture()
        f.names[20217] = name
        local result, code = combatBlessing(f)
        equal(result, nil, "unsafe macro name must never leave the boundary")
        equal(code, "COMBAT_SPELL_UNAVAILABLE")
    end
    for _, state in ipairs({ "missing", "secret", "opaque_info" }) do
        local f = fixture()
        if state == "missing" then f.names[20217] = nil
        elseif state == "secret" then f.names[20217] = f.secret
        else
            f.env.C_Spell.GetSpellName = nil
            f.env.C_Spell.GetSpellInfo = function() return f.opaque end
        end
        local result, code = combatBlessing(f)
        equal(result, nil, state)
        equal(code, "COMBAT_SPELL_UNAVAILABLE", state)
    end
end

local names = {}
for name in pairs(tests) do if not arg[1] or arg[1] == name then names[#names + 1] = name end end
table.sort(names)
assert(#names > 0, "unknown test filter")
local failed = 0
for _, name in ipairs(names) do
    local ok, message = pcall(tests[name])
    if ok then print("PASS " .. name) else failed = failed + 1; print("FAIL " .. name .. ": " .. message) end
end
print(string.format("API: %d passed, %d failed", #names - failed, failed))
if failed > 0 then os.exit(1) end
