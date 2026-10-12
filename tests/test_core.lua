-- Purpose: Deterministic safety and rank-selection tests for the pure buff policy.
-- Input: Synthetic contexts only. Output: PASS/FAIL lines and a nonzero exit on failure.
-- Invariant: No game APIs, real characters or spell casts are used.
-- Debug: lua tests/test_core.lua [test_name] from the project directory.
local namespace = {}
assert(loadfile("src/ForeverMouseoverBuff/Core.lua"))("ForeverMouseoverBuff", namespace)
local Core = namespace.Core
local tests = {}

local function equal(actual, expected, message)
    if actual ~= expected then
        error((message or "unexpected value") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual), 2)
    end
end

local function spell(id, family, level)
    return {
        spellID = id, spellName = "Testsegen " .. id, family = family,
        learnedLevel = level, known = true, inRange = true, usable = true,
    }
end

local function context()
    return {
        playerClass = "PALADIN", playerCombat = false, mounted = false,
        flying = false, inVehicle = false, mode = "auto", auraState = "ready",
        hasBlessing = false,
        target = {
            exists = true, isPlayer = true, friendly = true, dead = false,
            isSelf = false, connected = true, visible = true, combat = false,
            class = "WARRIOR", level = 18,
        },
        spells = { spell(101, "might", 4), spell(102, "might", 12),
            spell(103, "might", 22), spell(201, "wisdom", 14), spell(301, "kings", 10) },
    }
end

local function blocked(input, code)
    local result = Core.Decide(input)
    equal(result.ready, false, "must not propose a spell")
    equal(result.code, code, "wrong reason")
    equal(type(result.text), "string", "explanation must be readable")
    equal(result.spellID, nil, "blocked decision must not expose an actionable spell")
end

-- Policy happy paths: selection is a visible class default, not a hidden talent guess.
function tests.highest_eligible_known_rank_is_selected()
    local result = Core.Decide(context())
    equal(result.ready, true, "known usable Might should be ready")
    equal(result.code, "READY")
    equal(result.family, "might")
    equal(result.spellID, 102)
    equal(result.spellName, "Testsegen 102")
end

function tests.all_nine_classes_have_explicit_default_families()
    local expected = { WARRIOR = "might", ROGUE = "might", MAGE = "wisdom",
        PRIEST = "wisdom", WARLOCK = "wisdom", HUNTER = "kings", PALADIN = "kings",
        SHAMAN = "kings", DRUID = "kings" }
    for class, family in pairs(expected) do
        local input = context()
        input.target.class = class
        equal(Core.Decide(input).family, family, class)
        equal(Core.Decide(input).ready, true, class)
    end
end

function tests.manual_family_overrides_only_the_class_default()
    for _, family in ipairs({ "might", "wisdom", "kings" }) do
        local input = context()
        input.mode = family
        equal(Core.Decide(input).family, family)
        equal(Core.Decide(input).ready, true)
    end
end

function tests.unsupported_player_and_mode_are_rejected()
    local input = context()
    input.playerClass = "MAGE"
    blocked(input, "UNSUPPORTED_CLASS")
    input = context()
    input.mode = "guess"
    blocked(input, "INVALID_MODE")
end

function tests.malformed_context_is_rejected_without_throwing()
    for _, value in ipairs({ false, 12, "PALADIN" }) do blocked(value, "INVALID_CONTEXT") end
    blocked(nil, "INVALID_CONTEXT")
    blocked({}, "INVALID_CONTEXT")
end

-- Only our own combat state controls dynamic selection; target combat is irrelevant.
function tests.unknown_player_flags_are_not_assumed_safe()
    for _, key in ipairs({ "playerCombat", "mounted", "flying", "inVehicle" }) do
        local input = context()
        input[key] = nil
        blocked(input, "PLAYER_STATE_UNKNOWN")
        input[key] = "false"
        blocked(input, "PLAYER_STATE_UNKNOWN")
    end
end

function tests.player_combat_blocks_dynamic_spell_selection()
    local input = context()
    input.playerCombat = true
    blocked(input, "PLAYER_IN_COMBAT")
end

function tests.target_in_combat_can_receive_the_appropriate_blessing()
    local input = context()
    input.target.combat = true
    local result = Core.Decide(input)
    equal(result.ready, true, "target combat alone must not block a friendly buff")
    equal(result.spellID, 102, "normal class and rank selection still applies")
end

function tests.target_combat_is_not_required_for_selection()
    local input = context()
    input.target.combat = nil
    equal(Core.Decide(input).spellID, 102, "unneeded combat status must not gate selection")
end

function tests.mount_flight_and_vehicle_block_the_spell()
    for key, code in pairs({ mounted = "MOUNTED", flying = "FLYING", inVehicle = "IN_VEHICLE" }) do
        local input = context()
        input[key] = true
        blocked(input, code)
    end
end

function tests.missing_target_npc_and_self_are_rejected()
    local input = context()
    input.target.exists = false
    blocked(input, "NO_TARGET")
    input = context()
    input.target.isPlayer = false
    blocked(input, "NOT_PLAYER")
    input = context()
    input.target.isSelf = true
    blocked(input, "SELF_TARGET")
end

function tests.hostile_and_dead_players_are_rejected()
    local input = context()
    input.target.friendly = false
    blocked(input, "NOT_FRIENDLY")
    input = context()
    input.target.dead = true
    blocked(input, "TARGET_DEAD")
end

function tests.disconnected_and_invisible_players_are_rejected()
    local input = context()
    input.target.connected = false
    blocked(input, "TARGET_DISCONNECTED")
    input = context()
    input.target.visible = false
    blocked(input, "TARGET_NOT_VISIBLE")
end

function tests.unknown_target_flags_are_not_assumed_safe()
    for _, key in ipairs({ "exists", "isPlayer", "friendly", "dead", "isSelf", "connected", "visible" }) do
        local input = context()
        input.target[key] = nil
        blocked(input, "TARGET_STATE_UNKNOWN")
        input.target[key] = 0
        blocked(input, "TARGET_STATE_UNKNOWN")
    end
    local input = context()
    input.target = false
    blocked(input, "TARGET_STATE_UNKNOWN")
end

function tests.unknown_aura_information_prevents_overwrite()
    local input = context()
    input.auraState = "unknown"
    blocked(input, "AURA_UNKNOWN")
    input.auraState = "ready"
    input.hasBlessing = nil
    blocked(input, "AURA_UNKNOWN")
end

function tests.any_existing_paladin_blessing_is_preserved()
    local input = context()
    input.hasBlessing = true
    blocked(input, "HAS_BLESSING")
end

-- Rank rules use the live learned level; no historical minus-ten rule is inferred.
function tests.missing_family_or_only_unknown_spells_never_falls_back()
    local input = context()
    input.mode = "kings"
    input.spells[5].known = false
    blocked(input, "NO_KNOWN_SPELL")
    input.spells = {}
    blocked(input, "NO_KNOWN_SPELL")
end

function tests.exact_target_level_accepts_the_rank()
    local input = context()
    input.target.level = 12
    equal(Core.Decide(input).spellID, 102)
end

function tests.too_young_target_does_not_use_a_minus_ten_exception()
    local input = context()
    input.spells = { spell(401, "might", 22) }
    input.target.level = 18
    blocked(input, "TARGET_LEVEL_TOO_LOW")
end

function tests.unknown_higher_rank_does_not_hide_a_known_lower_rank()
    local input = context()
    input.target.level = 30
    input.spells[3].known = false
    equal(Core.Decide(input).spellID, 102)
end

function tests.out_of_range_highest_rank_does_not_silently_downrank()
    local input = context()
    input.spells[2].inRange = false
    blocked(input, "OUT_OF_RANGE")
end

function tests.unusable_highest_rank_does_not_silently_downrank()
    local input = context()
    input.spells[2].usable = false
    blocked(input, "NOT_USABLE")
end

function tests.malformed_spell_numbers_and_unknown_flags_are_rejected()
    local bad = {
        { "spellID", 0 }, { "spellID", -1 }, { "spellID", math.huge },
        { "spellID", 0 / 0 }, { "learnedLevel", 1.5 }, { "learnedLevel", "12" },
        { "known", "true" }, { "inRange", 1 }, { "usable", "false" },
    }
    for _, sample in ipairs(bad) do
        local input = context()
        input.spells[2][sample[1]] = sample[2]
        blocked(input, "INVALID_SPELL_DATA")
    end
    local input = context()
    input.spells[2].inRange = nil
    blocked(input, "INVALID_SPELL_DATA")
end

function tests.unknown_target_level_or_class_prevents_a_guess()
    for _, level in ipairs({ 0, -1, math.huge, 0 / 0, 1.5, "18" }) do
        local input = context()
        input.target.level = level
        blocked(input, "TARGET_LEVEL_UNKNOWN")
    end
    local input = context()
    input.target.class = "NEW_CLASS"
    blocked(input, "TARGET_CLASS_UNKNOWN")
end

function tests.selection_does_not_mutate_the_input()
    local input = context()
    local first, second = input.spells[1], input.spells[2]
    local result = Core.Decide(input)
    equal(input.spells[1], first)
    equal(input.spells[2], second)
    equal(input.mode, "auto")
    equal(input.hasBlessing, false)
    result.spellName = "changed"
    equal(input.spells[2].spellName, "Testsegen 102")
end

function tests.sparse_or_duplicate_spell_lists_are_rejected()
    local input = context()
    input.spells = { [1] = spell(1, "might", 1), [3] = spell(3, "might", 3) }
    blocked(input, "INVALID_SPELL_DATA")
    input.spells = { spell(1, "might", 1), spell(1, "might", 1) }
    blocked(input, "INVALID_SPELL_DATA")
    input.spells = false
    blocked(input, "INVALID_SPELL_DATA")
end

function tests.unsafe_or_missing_spell_strings_are_rejected()
    for _, name in ipairs({ "", string.rep("x", 201), "Spell\n/target player", "|Hspell:1|hTest|h" }) do
        local input = context()
        input.spells[1].spellName = name
        blocked(input, "INVALID_SPELL_DATA")
    end
    local input = context()
    input.spells[1].family = "unsupported"
    blocked(input, "INVALID_SPELL_DATA")
end

-- Regression: a known family can serve a class when its preferred blessing is
-- unavailable or already supplied by another paladin. No effective strength is guessed.
local function blessing(family, owned, id)
    return { family = family, sourceIsPlayer = owned, spellID = id or 19740 }
end

local function withBlessings(input, list)
    input.blessings = list
    input.hasBlessing = #list > 0
    return input
end

function tests.hybrid_without_kings_falls_back_to_known_wisdom()
    local input = context()
    input.target.class = "PALADIN"
    input.spells[5].known = false
    local result = Core.Decide(input)
    equal(result.ready, true, "unlearned Kings must not prevent useful known Wisdom")
    equal(result.code, "READY_FALLBACK")
    equal(result.family, "wisdom")
    equal(result.spellID, 201)
    equal(result.fallbackFrom, "kings")
    equal(result.fallbackReason, "NO_KNOWN_SPELL")
end

function tests.foreign_might_falls_back_to_kings_without_overwriting()
    local input = withBlessings(context(), { blessing("might", false) })
    local original = input.blessings[1]
    local result = Core.Decide(input)
    equal(result.ready, true, "existing foreign Might should allow useful Kings")
    equal(result.code, "READY_FALLBACK")
    equal(result.family, "kings")
    equal(result.spellID, 301)
    equal(result.fallbackReason, "HAS_BLESSING")
    equal(input.blessings[1], original, "decision must preserve aura input")
end

function tests.foreign_unknown_or_lower_rank_is_never_overwritten()
    for _, rank in ipairs({ 1, 20 }) do
        local input = withBlessings(context(), { blessing("might", false) })
        input.blessings[1].rank = rank
        equal(Core.Decide(input).family, "kings", "rank must not claim effective talent strength")
    end
    local input = withBlessings(context(), { blessing("might", false) })
    equal(Core.Decide(input).family, "kings", "unreadable rank preserves same family")
end

function tests.foreign_different_family_allows_preferred_blessing()
    local input = withBlessings(context(), { blessing("kings", false, 20217) })
    local result = Core.Decide(input)
    equal(result.ready, true)
    equal(result.code, "READY")
    equal(result.family, "might")
end

function tests.own_useful_fallback_does_not_oscillate_after_foreign_buff_expires()
    local input = withBlessings(context(), { blessing("kings", true, 20217) })
    blocked(input, "OWN_BLESSING_PRESERVED")
    input.blessings[#input.blessings + 1] = blessing("might", false)
    blocked(input, "OWN_BLESSING_PRESERVED")
end

function tests.own_useful_primary_is_preserved_without_guessing_talents()
    local input = withBlessings(context(), { blessing("might", true) })
    input.blessings[1].rank = 1
    blocked(input, "OWN_BLESSING_PRESERVED")
end

function tests.own_unhelpful_wisdom_on_warrior_allows_might()
    local input = withBlessings(context(), { blessing("wisdom", true, 19742) })
    local result = Core.Decide(input)
    equal(result.ready, true)
    equal(result.family, "might")
end

function tests.every_class_has_only_the_documented_useful_fallback()
    local expected = { WARRIOR = "kings", ROGUE = "kings", MAGE = "kings",
        PRIEST = "kings", WARLOCK = "kings", HUNTER = "wisdom", PALADIN = "wisdom",
        SHAMAN = "wisdom", DRUID = "wisdom" }
    for class, fallback in pairs(expected) do
        local input = context()
        input.target.class = class
        local preferred = Core.Decide(input).family
        withBlessings(input, { blessing(preferred, false) })
        local result = Core.Decide(input)
        equal(result.ready, true, class)
        equal(result.code, "READY_FALLBACK", class)
        equal(result.family, fallback, class)
    end
end

function tests.warrior_never_gets_wisdom_when_useful_families_are_unavailable()
    local input = context()
    input.spells = { spell(201, "wisdom", 14) }
    blocked(input, "NO_KNOWN_SPELL")
end

function tests.fallback_selects_highest_eligible_rank_without_downranking_for_range()
    local input = withBlessings(context(), { blessing("might", false) })
    input.spells[#input.spells + 1] = spell(302, "kings", 15)
    input.spells[#input.spells + 1] = spell(303, "kings", 25)
    equal(Core.Decide(input).spellID, 302)
    input.spells[6].inRange = false
    blocked(input, "OUT_OF_RANGE")
    input.spells[6].inRange, input.spells[6].usable = true, false
    blocked(input, "NOT_USABLE")
end

function tests.primary_with_no_level_eligible_rank_can_use_eligible_fallback()
    local input = context()
    input.spells = { spell(103, "might", 22), spell(301, "kings", 10) }
    local result = Core.Decide(input)
    equal(result.ready, true)
    equal(result.family, "kings")
    equal(result.fallbackReason, "TARGET_LEVEL_TOO_LOW")
end

function tests.manual_mode_never_substitutes_a_different_family()
    local input = withBlessings(context(), { blessing("might", false) })
    input.mode = "might"
    blocked(input, "HAS_BLESSING")
    input = context()
    input.target.class, input.mode, input.spells[5].known = "PALADIN", "kings", false
    blocked(input, "NO_KNOWN_SPELL")
end

function tests.manual_mode_can_intentionally_replace_a_different_own_family()
    local input = withBlessings(context(), { blessing("kings", true, 20217) })
    input.mode = "might"
    equal(Core.Decide(input).family, "might")
    equal(Core.Decide(input).ready, true)
end

function tests.all_useful_families_present_leave_every_blessing_untouched()
    local input = withBlessings(context(), { blessing("might", false), blessing("kings", false, 20217) })
    blocked(input, "HAS_BLESSING")
end

function tests.unknown_ownership_and_unclassified_blessings_block_conservatively()
    local input = withBlessings(context(), { blessing("might", nil) })
    blocked(input, "AURA_UNKNOWN")
    for _, family in ipairs({ "temporary", "other" }) do
        input = withBlessings(context(), { blessing(family, false) })
        blocked(input, "HAS_BLESSING")
    end
end

function tests.malformed_or_inconsistent_blessing_lists_are_rejected()
    local cases = {
        { blessings = false, hasBlessing = true },
        { blessings = {}, hasBlessing = true },
        { blessings = { blessing("might", false) }, hasBlessing = false },
        { blessings = { [2] = blessing("might", false) }, hasBlessing = true },
        { blessings = { blessing("unknown", false) }, hasBlessing = true },
        { blessings = { blessing("might", "false") }, hasBlessing = true },
        { blessings = { blessing("might", false, 0) }, hasBlessing = true },
    }
    for _, sample in ipairs(cases) do
        local input = context()
        input.blessings, input.hasBlessing = sample.blessings, sample.hasBlessing
        blocked(input, "AURA_UNKNOWN")
    end
end

function tests.explicit_empty_blessing_list_matches_safe_legacy_context()
    local input = context()
    input.blessings = {}
    equal(Core.Decide(input).spellID, 102)
end

-- A named filter makes the exact first red test reproducible without hiding failures.
local names = {}
for name in pairs(tests) do
    if not arg[1] or arg[1] == name then names[#names + 1] = name end
end
table.sort(names)
assert(#names > 0, "No matching tests; check the requested test name.")
local failures = 0
for _, name in ipairs(names) do
    local ok, message = pcall(tests[name])
    if ok then
        print("PASS " .. name)
    else
        failures = failures + 1
        print("FAIL " .. name .. ": " .. tostring(message))
    end
end
print(string.format("Core tests: %d passed, %d failed", #names - failures, failures))
if failures > 0 then os.exit(1) end
