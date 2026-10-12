-- Purpose: Decide whether a safe mouseover blessing can be proposed, without WoW API calls.
-- Input: Public, sanitized player/target/spell facts. Output: a decision table.
-- Invariant: This module never casts spells. Debugging uses the stable decision code.
local _, namespace = ...
local Core = {}
namespace.Core = Core

-- Ordered, visible defaults avoid guessing a player's talents or group role.
-- A warrior never falls back to mana regeneration. Hybrids get Wisdom after
-- Kings, rather than assuming they deal melee damage. Manual mode stays exact.
local classFamilies = {
    WARRIOR = { "might", "kings" }, ROGUE = { "might", "kings" },
    MAGE = { "wisdom", "kings" }, PRIEST = { "wisdom", "kings" },
    WARLOCK = { "wisdom", "kings" }, HUNTER = { "kings", "wisdom" },
    PALADIN = { "kings", "wisdom" }, SHAMAN = { "kings", "wisdom" },
    DRUID = { "kings", "wisdom" },
}
local families = { might = true, wisdom = true, kings = true }
local messages = {
    INVALID_CONTEXT = "Spielerdaten fehlen oder sind ungültig. Bitte erneut über einen Spieler fahren.",
    UNSUPPORTED_CLASS = "Diese Version unterstützt die Segen des Paladins.",
    PLAYER_STATE_UNKNOWN = "Dein Kampf-, Reit- oder Fahrzeugstatus ist nicht sicher bekannt.",
    PLAYER_IN_COMBAT = "Im Kampf wird kein Buff vorbereitet.",
    MOUNTED = "Bitte zuerst absteigen; das Addon steigt nicht automatisch ab.",
    FLYING = "Während des Fliegens wird kein Buff vorbereitet.",
    IN_VEHICLE = "Bitte zuerst das Fahrzeug verlassen.",
    NO_TARGET = "Fahre mit der Maus über einen anderen befreundeten Spieler.",
    TARGET_STATE_UNKNOWN = "Der Zustand dieses Spielers ist nicht sicher bekannt.",
    NOT_PLAYER = "Nur Spieler werden unterstützt, keine Begleiter oder NPCs.",
    NOT_FRIENDLY = "Dieser Spieler kann nicht freundlich gebufft werden.",
    TARGET_DEAD = "Tote Spieler und Geister werden nicht gebufft.",
    SELF_TARGET = "Dieses Addon ist für andere Spieler gedacht.",
    TARGET_DISCONNECTED = "Dieser Spieler ist nicht verbunden.",
    TARGET_NOT_VISIBLE = "Dieser Spieler ist nicht sichtbar oder seine Daten fehlen.",
    TARGET_LEVEL_UNKNOWN = "Die Stufe dieses Spielers ist unbekannt; kein Rang wird geraten.",
    TARGET_CLASS_UNKNOWN = "Die Klasse dieses Spielers ist unbekannt; kein Segen wird geraten.",
    AURA_UNKNOWN = "Vorhandene Segen sind noch nicht sicher bekannt; bitte kurz warten.",
    HAS_BLESSING = "Vorhandene Segen bleiben erhalten; kein zusätzlicher passender Segen ist verfügbar.",
    OWN_BLESSING_PRESERVED = "Dein passender Segen ist bereits vorhanden und bleibt erhalten.",
    INVALID_MODE = "Die Buff-Auswahl ist ungültig. Bitte Auto, Macht, Weisheit oder Könige wählen.",
    INVALID_SPELL_DATA = "Zauber-, Rang- oder Reichweitendaten fehlen. Bitte erneut versuchen.",
    NO_KNOWN_SPELL = "Kein Segen aus der gewählten Auswahl ist gelernt.",
    TARGET_LEVEL_TOO_LOW = "Kein gelernter Rang passt sicher zur Stufe dieses Spielers.",
    OUT_OF_RANGE = "Dieser Spieler ist außerhalb der Reichweite des ausgewählten Segens.",
    NOT_USABLE = "Der ausgewählte Segen ist gerade nicht nutzbar, beispielsweise wegen fehlenden Manas.",
}

local function blocked(code, family)
    return { ready = false, code = code, text = messages[code], family = family }
end

local function positiveInteger(value, maximum)
    return type(value) == "number" and value == value and value >= 1
        and value <= maximum and value == math.floor(value)
end

local function plainName(value)
    return type(value) == "string" and #value > 0 and #value <= 200
        and value:find("%S") ~= nil and not value:find("[%c|]")
end

local function knownBooleans(value, keys)
    for _, key in ipairs(keys) do
        if type(value[key]) ~= "boolean" then return false end
    end
    return true
end

-- WoW facts may arrive at different times. Unknown is never treated as false/safe.
-- An absent target can be handled before requiring the remaining target facts.
local function checkSafety(context)
    if type(context) ~= "table" or type(context.playerClass) ~= "string" then
        return "INVALID_CONTEXT"
    end
    if context.playerClass ~= "PALADIN" then return "UNSUPPORTED_CLASS" end
    if not knownBooleans(context, { "playerCombat", "mounted", "flying", "inVehicle" }) then
        return "PLAYER_STATE_UNKNOWN"
    end
    if context.playerCombat then return "PLAYER_IN_COMBAT" end
    if context.mounted then return "MOUNTED" end
    if context.flying then return "FLYING" end
    if context.inVehicle then return "IN_VEHICLE" end

    local target = context.target
    if type(target) ~= "table" or type(target.exists) ~= "boolean" then
        return "TARGET_STATE_UNKNOWN"
    end
    if not target.exists then return "NO_TARGET" end
    if not knownBooleans(target, { "isPlayer", "friendly", "dead", "isSelf", "connected", "visible" }) then
        return "TARGET_STATE_UNKNOWN"
    end
    if not target.isPlayer then return "NOT_PLAYER" end
    if not target.friendly then return "NOT_FRIENDLY" end
    if target.dead then return "TARGET_DEAD" end
    if target.isSelf then return "SELF_TARGET" end
    if not target.connected then return "TARGET_DISCONNECTED" end
    if not target.visible then return "TARGET_NOT_VISIBLE" end
    -- A recipient may be fighting while we are outside lockdown. Only our own
    -- combat state blocks dynamic selection; aura safety still applies below.
    if not positiveInteger(target.level, 1000) then return "TARGET_LEVEL_UNKNOWN" end
    if type(target.class) ~= "string" or not classFamilies[target.class] then
        return "TARGET_CLASS_UNKNOWN"
    end
    if context.auraState ~= "ready" or type(context.hasBlessing) ~= "boolean" then
        return "AURA_UNKNOWN"
    end
end

-- Effective strength includes talents and is not reliably public. Preserve
-- every existing family instead of treating a lower spell ID/rank as weaker.
-- Ownership is needed because casting another family replaces our own blessing.
-- Old callers without detail keep their conservative all-blessings protection.
local function blessingState(context)
    if context.blessings == nil then
        if context.hasBlessing then return nil, "HAS_BLESSING" end
        return { present = {}, owned = {} }
    end
    if type(context.blessings) ~= "table" then return nil, "AURA_UNKNOWN" end
    local count, state = 0, { present = {}, owned = {} }
    for index, blessing in pairs(context.blessings) do
        count = count + 1
        if count > 255 or not positiveInteger(index, 255) or type(blessing) ~= "table"
            or not positiveInteger(blessing.spellID, 1000000000)
            or type(blessing.family) ~= "string"
            or not (families[blessing.family] or blessing.family == "temporary" or blessing.family == "other")
            or type(blessing.sourceIsPlayer) ~= "boolean" then
            return nil, "AURA_UNKNOWN"
        end
        state.present[blessing.family] = true
        if blessing.sourceIsPlayer then state.owned[blessing.family] = true end
    end
    for index = 1, count do
        if context.blessings[index] == nil then return nil, "AURA_UNKNOWN" end
    end
    if context.hasBlessing ~= (count > 0) then return nil, "AURA_UNKNOWN" end
    -- Protection/Freedom and unfamiliar utility blessings are not replaced by
    -- a guessed routine buff. Their effects may be immediately important.
    if state.present.temporary or state.present.other then return nil, "HAS_BLESSING" end
    return state
end

-- Invalid spell lists are refused as a whole. This prevents a partially loaded
-- higher rank from silently causing selection of an unintended lower rank.
local function validSpells(spells)
    if type(spells) ~= "table" then return false end
    local count, seenIDs = 0, {}
    for index, spell in pairs(spells) do
        count = count + 1
        if count > 200 or not positiveInteger(index, 200) or type(spell) ~= "table" then
            return false
        end
        if not positiveInteger(spell.spellID, 1000000000) or seenIDs[spell.spellID]
            or not positiveInteger(spell.learnedLevel, 1000) or not plainName(spell.spellName)
            or type(spell.family) ~= "string" or not families[spell.family]
            or not knownBooleans(spell, { "known", "inRange", "usable" }) then
            return false
        end
        seenIDs[spell.spellID] = true
    end
    for index = 1, count do
        if spells[index] == nil then return false end
    end
    return true
end

-- Example: learned levels 4/12/22 and target level 18 select level 12.
-- Range or mana failure of that chosen rank blocks the action, without downranking.
local function selectRank(spells, family, targetLevel)
    local selected, familyKnown = nil, false
    for _, spell in ipairs(spells) do
        if spell.family == family and spell.known then
            familyKnown = true
            if spell.learnedLevel <= targetLevel then
                if not selected or spell.learnedLevel > selected.learnedLevel
                    or (spell.learnedLevel == selected.learnedLevel and spell.spellID > selected.spellID) then
                    selected = spell
                end
            end
        end
    end
    return selected, familyKnown
end

-- Check one family without falling back to an unnecessarily low rank for mana
-- or range. Those transient failures stop selection, even in automatic mode.
local function familyCandidate(context, state, family)
    if state.present[family] then return nil, "HAS_BLESSING" end
    local selected, familyKnown = selectRank(context.spells, family, context.target.level)
    if not familyKnown then return nil, "NO_KNOWN_SPELL" end
    if not selected then return nil, "TARGET_LEVEL_TOO_LOW" end
    if not selected.inRange then return nil, "OUT_OF_RANGE" end
    if not selected.usable then return nil, "NOT_USABLE" end
    return selected
end

-- Example: another paladin supplies Might on a warrior. Auto proposes known
-- Kings. After our Kings lands, it is retained even if the foreign Might expires;
-- repeatedly hovering never rotates our own blessings back and forth.
function Core.Decide(context)
    local reason = checkSafety(context)
    if reason then return blocked(reason) end
    if context.mode ~= "auto" and not families[context.mode] then
        return blocked("INVALID_MODE")
    end
    local priorities = context.mode == "auto" and classFamilies[context.target.class] or { context.mode }
    local primary = priorities[1]
    local state, auraReason = blessingState(context)
    if not state then return blocked(auraReason, primary) end
    if not validSpells(context.spells) then return blocked("INVALID_SPELL_DATA", primary) end
    if context.mode == "auto" then
        for _, family in ipairs(priorities) do
            if state.owned[family] then return blocked("OWN_BLESSING_PRESERVED", family) end
        end
    end

    local firstReason
    for index, family in ipairs(priorities) do
        local selected, candidateReason = familyCandidate(context, state, family)
        if selected then
            local fallback = index > 1
            return {
                ready = true, code = fallback and "READY_FALLBACK" or "READY",
                text = selected.spellName .. (fallback and " als Alternative bereit – per Tastendruck buffen."
                    or " bereit – per Tastendruck buffen."),
                spellID = selected.spellID, spellName = selected.spellName, family = family,
                fallbackFrom = fallback and primary or nil,
                fallbackReason = fallback and firstReason or nil,
            }
        end
        if candidateReason == "OUT_OF_RANGE" or candidateReason == "NOT_USABLE" then
            return blocked(candidateReason, family)
        end
        if not firstReason then firstReason = candidateReason end
    end
    return blocked(firstReason, primary)
end
