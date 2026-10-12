-- Purpose: Read the public Forever spellbook and current player/mouseover facts.
-- Input: selected blessing family. Output: a detached context or fixed combat spell.
-- Invariants: never cast, inspect identities, unwrap secrets, or treat unknown as safe.
-- Debug: /fmb status and fixed API.LastCode/ns:Log codes; tests/test_api.lua.
local _, namespace = ...
local API = {}
namespace.API = API
local spellCache, nameCache
local MAX_LINES, MAX_SLOTS, MAX_CANDIDATES, MAX_AURAS = 100, 2000, 200, 255
local familyIDs = { [19740] = "might", [19742] = "wisdom", [20217] = "kings" }

-- These identities identify known blessing families, not learned abilities or
-- target level rules. Localized labels additionally cover future same-name ranks.
local blessingBaseIDs = { 19740, 19742, 20217, 25782, 25894, 25898,
    1038, 25895, 19977, 25890, 20911, 25899, 6940, 1022, 1044 }
local blessingFamilies = {}
local familyRanks = {
    might = { 19740, 19834, 19835, 19836, 19837, 19838, 25291, 27140, 48931, 48932,
        25782, 25916, 27141, 48933, 48934 },
    wisdom = { 19742, 19850, 19852, 19853, 19854, 25290, 27142, 48935, 48936,
        25894, 25918, 27143, 48937, 48938 },
    kings = { 20217, 25898 },
    other = { 1038, 25895, 19977, 19978, 19979, 27144, 25890, 27145,
        20911, 20912, 20913, 20914, 27168, 25899, 27169 },
    temporary = { 6940, 20729, 27147, 27148, 1022, 5599, 10278, 1044 },
}
for family, ids in pairs(familyRanks) do
    for _, id in ipairs(ids) do blessingFamilies[id] = family end
end

-- Boundaries log only fixed local codes. Native error strings can contain
-- private information and are deliberately neither retained nor printed.
local function issue(code)
    API.LastCode = code
    if type(namespace.Log) == "function" then
        local ok = pcall(namespace.Log, namespace, code)
        if not ok then API.LastCode = "API_LOG_UNAVAILABLE" end
    end
end

local function public(value)
    if type(issecretvalue) ~= "function" then
        issue("API_GUARD_UNAVAILABLE")
        return false
    end
    local ok, restricted = pcall(issecretvalue, value)
    if not ok or type(restricted) ~= "boolean" then
        issue("API_GUARD_UNAVAILABLE")
        return false
    end
    if restricted then issue("API_RESTRICTED"); return false end
    return true
end

local function readableTable(value)
    if not public(value) or type(value) ~= "table" then return false end
    if type(canaccesstable) ~= "function" then issue("API_GUARD_UNAVAILABLE"); return false end
    local ok, accessible = pcall(canaccesstable, value)
    if not ok or not public(accessible) or type(accessible) ~= "boolean" then
        issue("API_GUARD_UNAVAILABLE")
        return false
    end
    if not accessible then issue("API_RESTRICTED"); return false end
    return true
end

local function field(value, key)
    if not readableTable(value) then return nil, false end
    local item = rawget(value, key)
    if not public(item) then return nil, false end
    return item, true
end

local function method(value, key)
    local item, ok = field(value, key)
    if ok and type(item) == "function" then return item end
end

local function call(fn, ...)
    if not public(fn) or type(fn) ~= "function" then issue("API_UNAVAILABLE"); return false end
    local ok, first, second, third, fourth = pcall(fn, ...)
    if not ok then issue("API_CALL_FAILED"); return false end
    return true, first, second, third, fourth
end

local function boolean(fn, ...)
    local ok, value = call(fn, ...)
    if ok and public(value) and type(value) == "boolean" then return value end
    issue("API_STATE_UNKNOWN")
end

local function integer(value, minimum, maximum)
    return public(value) and type(value) == "number" and value == value
        and value >= minimum and value <= maximum and value == math.floor(value)
end

local function text(value, maximum)
    return public(value) and type(value) == "string" and #value > 0 and #value <= maximum
        and value:find("%S") ~= nil and not value:find("[%c|]")
end

-- A true or unknown lock result must stop callers before any other game reads.
-- Return tri-state internally, because API.Locked's fail-closed true is not
-- evidence that the player is really in combat when the native API is missing.
local function lockState()
    local lockdown = boolean(InCombatLockdown)
    if lockdown ~= false then return lockdown end
    return boolean(UnitAffectingCombat, "player")
end

function API.Locked()
    return lockState() ~= false
end

local function classToken(unit)
    local ok, _, token = call(UnitClass, unit)
    if ok and text(token, 30) and token:match("^[A-Z]+$") then return token end
    issue("API_STATE_UNKNOWN")
end

local function spellName(id)
    local getter = method(C_Spell, "GetSpellName")
    if getter then
        local ok, name = call(getter, id)
        if ok and text(name, 200) then return name end
    end
    getter = method(C_Spell, "GetSpellInfo")
    if getter then
        local ok, info = call(getter, id)
        if ok then
            local name = field(info, "name")
            if text(name, 200) then return name end
        end
    end
end

-- The secure combat binding is prepared before lockdown from one learned spell.
-- It deliberately does not inspect mouseover, auras, range, mana, or spell ranks:
-- the hardware-triggered macro and native client decide whether the cast works.
-- Example: learned 20217 -> localized Kings; only Greater Kings -> no binding.
function API.CombatBlessing()
    API.LastCode = nil
    local function unavailable(code)
        issue(code)
        return nil, code
    end
    local locked = lockState()
    if locked == true then return unavailable("PLAYER_IN_COMBAT") end
    if locked ~= false then return unavailable("COMBAT_SPELL_UNAVAILABLE") end
    local class = classToken("player")
    if class == nil then return unavailable("COMBAT_SPELL_UNAVAILABLE") end
    if class ~= "PALADIN" then return unavailable("PLAYER_NOT_PALADIN") end

    local bankTable = field(Enum, "SpellBookSpellBank")
    local bank = field(bankTable, "Player")
    local isKnown = method(C_SpellBook, "IsSpellKnown")
    if not integer(bank, 0, 10) or not isKnown then
        return unavailable("COMBAT_SPELL_UNAVAILABLE")
    end
    local known = boolean(isKnown, 20217, bank)
    if known == nil then return unavailable("COMBAT_SPELL_UNAVAILABLE") end
    if not known then return unavailable("COMBAT_SPELL_NOT_LEARNED") end
    local name = spellName(20217)
    -- Macro command separators/conditionals must never enter the /cast argument.
    -- The shared text guard already rejects control characters and pipe markup.
    if not text(name, 200) or name:find("[;%[%]/]") then
        return unavailable("COMBAT_SPELL_UNAVAILABLE")
    end
    locked = lockState()
    if locked == true then return unavailable("PLAYER_IN_COMBAT") end
    if locked ~= false then return unavailable("COMBAT_SPELL_UNAVAILABLE") end
    issue("COMBAT_SPELL_READY")
    return { spellID = 20217, spellName = name }, "COMBAT_SPELL_READY"
end

local function names()
    if nameCache then return nameCache end
    local result = { families = {}, blessings = {} }
    for _, id in ipairs(blessingBaseIDs) do
        local name = spellName(id)
        if name then
            result.blessings[name] = blessingFamilies[id]
            if familyIDs[id] then result.families[name] = familyIDs[id] end
        elseif familyIDs[id] then
            issue("API_SPELL_NAMES_UNKNOWN")
            return nil
        end
    end
    nameCache = result
    return result
end

-- Metadata is cached, range/mana and targets are not. Failure discards the whole
-- book rather than publishing a partial list with a missing stronger rank.
-- The UI's ShowAllSpellRanks filter is intentionally not applied to raw slots.
local function buildSpellbook()
    local labels = names()
    if not labels then return nil end
    local bankTable = field(Enum, "SpellBookSpellBank")
    local typeTable = field(Enum, "SpellBookItemType")
    local bank = field(bankTable, "Player")
    local spellType = field(typeTable, "Spell")
    if not integer(bank, 0, 10) or not integer(spellType, 0, 10) then return nil end
    local api = {}
    for _, name in ipairs({ "GetNumSpellBookSkillLines", "GetSpellBookSkillLineInfo",
        "GetSpellBookItemInfo", "GetSpellBookItemName", "GetSpellBookItemLevelLearned", "IsSpellKnown" }) do
        api[name] = method(C_SpellBook, name)
        if not api[name] then return nil end
    end
    local ok, lineCount = call(api.GetNumSpellBookSkillLines)
    if not ok or not integer(lineCount, 1, MAX_LINES) then return nil end
    local slotIndices, seenSlots = {}, {}
    for index = 1, lineCount do
        local lineOK, info = call(api.GetSpellBookSkillLineInfo, index)
        if not lineOK then return nil end
        local offset, offsetOK = field(info, "itemIndexOffset")
        local count, countOK = field(info, "numSpellBookItems")
        if not offsetOK or not countOK or not integer(offset, 0, 100000)
            or not integer(count, 0, MAX_SLOTS) or offset + count > 100000
            or #slotIndices + count > MAX_SLOTS then return nil end
        for slot = offset + 1, offset + count do
            if seenSlots[slot] then return nil end
            seenSlots[slot] = true
            slotIndices[#slotIndices + 1] = slot
        end
    end
    local result, seenIDs = {}, {}
    for _, slot in ipairs(slotIndices) do
        local itemOK, info = call(api.GetSpellBookItemInfo, slot, bank)
        if not itemOK then return nil end
        local kind, kindOK = field(info, "itemType")
        if not kindOK or not integer(kind, 0, 10) then return nil end
        if kind == spellType then
            local passive, passiveOK = field(info, "isPassive")
            local offspec, offspecOK = field(info, "isOffSpec")
            if not passiveOK or not offspecOK or type(passive) ~= "boolean"
                or type(offspec) ~= "boolean" then return nil end
            if not passive and not offspec then
                local spellID, idOK = field(info, "spellID")
                local actionID, actionOK = field(info, "actionID")
                if not idOK or not actionOK then return nil end
                if spellID == nil then spellID = actionID end
                if not integer(spellID, 1, 1000000000) then return nil end
                local nameOK, name = call(api.GetSpellBookItemName, slot, bank)
                if not nameOK or not text(name, 200) then return nil end
                local family = labels.families[name]
                if family then
                    local known = boolean(api.IsSpellKnown, spellID, bank)
                    if known == nil then return nil end
                    if known then
                        local levelOK, level = call(api.GetSpellBookItemLevelLearned, slot, bank)
                        if not levelOK or not integer(level, 1, 1000) then return nil end
                        local old = seenIDs[spellID]
                        if old then
                            if old.family ~= family or old.learnedLevel ~= level or old.spellName ~= name then return nil end
                        else
                            if #result >= MAX_CANDIDATES then return nil end
                            local entry = { spellID = spellID, spellName = name, family = family,
                                learnedLevel = level, known = true }
                            result[#result + 1], seenIDs[spellID] = entry, entry
                        end
                    end
                end
            end
        end
    end
    return result
end

function API.RefreshSpellbook()
    spellCache, nameCache = nil, nil
end

local function readSpells()
    if not spellCache then
        spellCache = buildSpellbook()
        if not spellCache then issue("API_SPELLBOOK_UNKNOWN"); return nil end
    end
    local range = method(C_Spell, "IsSpellInRange")
    local usable = method(C_Spell, "IsSpellUsable")
    local result = {}
    for _, item in ipairs(spellCache) do
        local inRange = boolean(range, item.spellID, "mouseover")
        local ok, isUsable, insufficientPower = call(usable, item.spellID)
        if inRange == nil or not ok or not public(isUsable) or not public(insufficientPower)
            or type(isUsable) ~= "boolean" or type(insufficientPower) ~= "boolean" then
            issue("API_SPELL_STATE_UNKNOWN")
            return nil
        end
        result[#result + 1] = { spellID = item.spellID, spellName = item.spellName,
            family = item.family, learnedLevel = item.learnedLevel, known = true,
            inRange = inRange, usable = isUsable and not insufficientPower }
    end
    return result
end

-- Both scans must reach a proven clean end. The native PLAYER filter identifies
-- our blessings without reading caster names, GUIDs, sourceUnit, or arbitrary
-- unit tokens. Matching a duplicate spell ID as ours is deliberately conservative:
-- the policy will keep that family instead of replacing a possibly own blessing.
local function scanBlessings(getter, labels, filter)
    local result = {}
    for index = 1, MAX_AURAS + 1 do
        local ok, aura = call(getter, "mouseover", index, filter)
        if not ok or not public(aura) then return nil end
        if aura == nil then return result end
        if index > MAX_AURAS then issue("API_AURA_LIMIT"); return nil end
        local id, idOK = field(aura, "spellId")
        local name, nameOK = field(aura, "name")
        if not idOK or not nameOK or not integer(id, 1, 1000000000) or not text(name, 200) then
            issue("API_AURAS_UNKNOWN")
            return nil
        end
        local family = blessingFamilies[id] or labels.blessings[name]
        if family then result[#result + 1] = { spellID = id, family = family } end
    end
end

-- A foreign Might/Greater Might no longer hides the learned spellbook. Core can
-- choose a missing useful family, while preserving every existing family. Rank
-- alone cannot establish effective strength because talents may improve a buff.
local function readBlessings()
    if not public(C_Secrets) then return "unknown" end
    if C_Secrets ~= nil then
        local predicate = method(C_Secrets, "ShouldAurasBeSecret")
        if not predicate then issue("API_AURAS_UNKNOWN"); return "unknown" end
        if boolean(predicate) ~= false then return "unknown" end
    end
    local labels = names()
    local getter = method(C_UnitAuras, "GetAuraDataByIndex")
    if not labels or not getter then issue("API_AURAS_UNKNOWN"); return "unknown" end
    local blessings = scanBlessings(getter, labels, "HELPFUL")
    if not blessings then return "unknown" end
    if #blessings == 0 then return "ready", false, blessings end

    local ownBlessings = scanBlessings(getter, labels, "HELPFUL|PLAYER")
    if not ownBlessings then return "unknown" end
    local allIDs, ownIDs = {}, {}
    for _, aura in ipairs(blessings) do allIDs[aura.spellID] = true end
    for _, aura in ipairs(ownBlessings) do
        -- An aura appearing only in the second scan means the snapshot changed.
        -- Defer instead of publishing contradictory ownership or a partial list.
        if not allIDs[aura.spellID] then issue("API_AURA_CHANGED"); return "unknown" end
        ownIDs[aura.spellID] = true
    end
    for _, aura in ipairs(blessings) do aura.sourceIsPlayer = ownIDs[aura.spellID] == true end
    return "ready", true, blessings
end

local function finish(context)
    local locked = lockState()
    if locked ~= false then
        context.playerCombat = locked
        context.spells, context.auraState, context.hasBlessing, context.blessings = nil, nil, nil, nil
    end
    return context
end

-- Contexts deliberately contain no actor names, GUIDs, identities or unit chains.
-- Only these two literal tokens can be passed to game APIs by this module.
function API.ReadContext(mode)
    API.LastCode = nil
    if not text(mode, 20) then mode = nil end
    local context = { mode = mode, playerCombat = lockState() }
    if context.playerCombat ~= false then return context end
    context.playerClass = classToken("player")
    context.mounted = boolean(IsMounted)
    context.flying = boolean(IsFlying)
    context.inVehicle = boolean(UnitInVehicle, "player")
    if context.playerClass ~= "PALADIN" or context.mounted ~= false
        or context.flying ~= false or context.inVehicle ~= false then return finish(context) end
    local target = { exists = boolean(UnitExists, "mouseover") }
    context.target = target
    if target.exists ~= true then return finish(context) end
    target.isPlayer = boolean(UnitIsPlayer, "mouseover")
    target.friendly = boolean(UnitCanAssist, "player", "mouseover")
    target.dead = boolean(UnitIsDeadOrGhost, "mouseover")
    target.isSelf = boolean(UnitIsUnit, "player", "mouseover")
    target.connected = boolean(UnitIsConnected, "mouseover")
    target.visible = boolean(UnitIsVisible, "mouseover")
    -- Target combat does not lock the caster's action button. Do not query it:
    -- missing/secret combat flags are irrelevant, unlike the aura data below.
    if target.isPlayer ~= true or target.friendly ~= true or target.dead ~= false
        or target.isSelf ~= false or target.connected ~= true or target.visible ~= true then return finish(context) end
    target.class = classToken("mouseover")
    local levelOK, level = call(UnitLevel, "mouseover")
    if levelOK and integer(level, 1, 1000) then target.level = level end
    if target.class == nil or target.level == nil then return finish(context) end
    context.auraState, context.hasBlessing, context.blessings = readBlessings()
    if context.auraState ~= "ready" then return finish(context) end
    context.spells = readSpells()
    return finish(context)
end

function API.Client()
    local ok, version, build, _, interface = call(GetBuildInfo)
    if not ok or not text(version, 40) or not text(build, 40) or not integer(interface, 1, 1000000) then
        issue("API_CLIENT_UNKNOWN")
        return {}
    end
    return { version = version, build = build, interface = interface }
end
