-- Purpose: Decide whether a safe class-appropriate mouseover heal or buff can be proposed, without WoW API calls.
-- Input: Public, sanitized player/target/spell facts and optional class priorities.
-- Output: a decision table, copied class choices or validated priority lists.
-- Invariant: Never casts spells or replaces our permanent blessing in Auto mode.
-- Debug: Run tests/test_core.lua; each blocked decision has a stable reason code.
local _, namespace = ...
local Core = {}
namespace.Core = Core

-- Ordered, visible defaults avoid guessing a player's talents or group role.
-- Warrior defaults exclude mana regeneration; users can explicitly change them.
-- Druids accept all three families: Kings, then Wisdom, then Might. Manual mode
-- stays exact. These tables are private so UI edits cannot alter the defaults.
local classFamilies = {
    WARRIOR = { "might", "kings" }, ROGUE = { "might", "kings" },
    MAGE = { "wisdom", "kings" }, PRIEST = { "wisdom", "kings" },
    WARLOCK = { "wisdom", "kings" }, HUNTER = { "kings", "wisdom" },
    PALADIN = { "kings", "wisdom" }, SHAMAN = { "kings", "wisdom" },
    DRUID = { "kings", "wisdom", "might" },
}
local families = { might = true, wisdom = true, kings = true }
-- Profiles describe only direct helpful player spells. Localized names and
-- learned ranks come from the client, never from these display labels. Utility
-- that changes healing or movement is explicit-only, because context is unknown.
local buffProfiles = {
    PALADIN = { auto = { "might", "wisdom", "kings" }, families = {
        { "might", 19740, "Macht" }, { "wisdom", 19742, "Weisheit" }, { "kings", 20217, "Könige" } } },
    MAGE = { auto = { "intellect" }, families = {
        { "intellect", 1459, "Intelligenz" }, { "dampen", 604, "Magie dämpfen" },
        { "amplify", 1008, "Magie verstärken" } } },
    PRIEST = { auto = { "fortitude", "spirit", "shadow" }, families = {
        { "fortitude", 1243, "Seelenstärke" }, { "spirit", 14752, "Willenskraft" },
        { "shadow", 976, "Schattenschutz" } } },
    DRUID = { auto = { "mark", "thorns" }, families = {
        { "mark", 1126, "Mal der Wildnis" }, { "thorns", 467, "Dornen" } } },
    WARLOCK = { auto = { "breath", "invisibility" }, families = {
        { "breath", 5697, "Unterwasseratmung" }, { "invisibility", 132, "Unsichtbarkeit entdecken", 2970, 11743 } } },
    SHAMAN = { auto = { "water_breathing" }, families = {
        { "water_breathing", 131, "Wasseratmung" }, { "water_walking", 546, "Wasserwandeln" } } },
}
local allBuffFamilies = {}
for _, profile in pairs(buffProfiles) do
    for _, entry in ipairs(profile.families) do allBuffFamilies[entry[1]] = true end
end

-- Return detached data: menu edits must never mutate shared spell identities.
-- A nil profile is an explained class limitation, never a guessed party action.
function Core.BuffProfile(classToken)
    local source = buffProfiles[classToken]
    if not source then return nil end
    local result = { auto = {}, families = {} }
    for index, family in ipairs(source.auto) do result.auto[index] = family end
    for index, entry in ipairs(source.families) do
        result.families[index] = {}
        for key, value in ipairs(entry) do result.families[index][key] = value end
    end
    return result
end

function Core.BuffModes(classToken)
    local profile = Core.BuffProfile(classToken)
    local result = { { "auto", "Auto" } }
    if profile then
        for _, entry in ipairs(profile.families) do result[#result + 1] = { entry[1], entry[3] } end
    end
    return result
end

local healFamilies = { flash = true, holy_light = true }
local permanentFamilies = { "might", "wisdom", "kings" }
local classOptions = {
    { token = "DRUID", name = "Druide" }, { token = "WARLOCK", name = "Hexenmeister" },
    { token = "HUNTER", name = "Jäger" }, { token = "WARRIOR", name = "Krieger" },
    { token = "MAGE", name = "Magier" }, { token = "PALADIN", name = "Paladin" },
    { token = "PRIEST", name = "Priester" }, { token = "SHAMAN", name = "Schamane" },
    { token = "ROGUE", name = "Schurke" },
}
-- Keep cause and next action together: the same text reaches preview, chat and
-- explicit status. Unknown usability never proves mana loss or a cooldown.
local messages = {
    INVALID_CONTEXT = "Spielerdaten fehlen oder sind ungültig. Bitte erneut über einen Spieler fahren.",
    UNSUPPORTED_CLASS = "Diese Klasse hat keinen direkten dauerhaften Buff für einzelne andere Spieler. Gruppenrufe, Aspekte, Waffen- und Eigenbuffs bitte direkt über WoW nutzen.",
    PLAYER_STATE_UNKNOWN = "Kampf-, Reit- oder Fahrzeugstatus unbekannt. Kurz warten; bleibt es so: /reload, dann /fmb status.",
    PLAYER_IN_COMBAT = "Auto-Auswahl im Kampf gesperrt. Nach dem Kampf erneut drücken. Nur Paladine haben eine feste vorbereitete Könige-Belegung.",
    MOUNTED = "Bitte zuerst absteigen; das Addon steigt nicht automatisch ab.",
    FLYING = "Im Flug wird kein Buff vorbereitet. Erst landen und absteigen, dann erneut drücken.",
    IN_VEHICLE = "Bitte zuerst das Fahrzeug verlassen.",
    NO_TARGET = "Fahre mit der Maus über einen anderen befreundeten Spieler.",
    TARGET_STATE_UNKNOWN = "Zieldaten unbekannt. Maus erneut auf einen nahen freundlichen Spieler halten; bleibt es so: /reload.",
    NOT_PLAYER = "Dieses Ziel ist kein Spieler. Maus auf einen befreundeten Spieler halten und Taste loslassen.",
    NOT_FRIENDLY = "Dieses Ziel kann nicht freundlich gebufft werden. Einen befreundeten Spieler wählen.",
    TARGET_DEAD = "Dieses Ziel ist tot oder ein Geist. Einen lebenden befreundeten Spieler wählen.",
    SELF_TARGET = "Eigene Figur gewählt. Maus auf einen anderen befreundeten Spieler halten und Taste loslassen.",
    TARGET_DISCONNECTED = "Dieser Spieler ist offline. Einen verbundenen befreundeten Spieler wählen.",
    TARGET_NOT_VISIBLE = "Ziel unsichtbar oder Daten fehlen. Näher herangehen und Maus erneut auf den Spieler halten.",
    TARGET_PVP = "PvP-geflaggte Spieler werden nicht gebufft. Bitte ein nicht markiertes Ziel wählen.",
    COMBAT_PVP_UNCHECKABLE = "Im Kampf lässt WoW die sichere Prüfung des PvP-Ziels nicht zu. Buffs sind dort gesperrt; nach dem Kampf erneut drücken.",
    TARGET_LEVEL_UNKNOWN = "Zielstufe unbekannt. Näher herangehen und erneut über den Spieler fahren; bleibt es so: /reload.",
    TARGET_CLASS_UNKNOWN = "Zielklasse unbekannt. Maus erneut auf den Spieler halten; bleibt es so: /reload.",
    AURA_UNKNOWN = "Vorhandene Buffs noch unbekannt. Kurz warten und erneut drücken; bleibt es so: /reload, dann /fmb status.",
    HAS_BLESSING = "Vorhandene gleichartige Buffs bleiben erhalten. Anderen Spieler wählen oder warten, bis ein Segen abläuft.",
    OWN_BLESSING_PRESERVED = "Dein Segen ist schon vorhanden. Kein erneuter Buff nötig; Auto erhält ihn bis zum Ablauf.",
    INVALID_MODE = "Die Buff-Auswahl passt nicht zu deiner Klasse. Bitte /fmb auto oder einen Klassenbuff im Menü wählen.",
    INVALID_PRIORITIES = "Klassen-Prioritäten ungültig. Mit /fmb priorities reset die Standardwerte wiederherstellen.",
    CLASS_DISABLED = "Für diese Zielklasse ist kein Auto-Buff aktiviert oder sinnvoll. Klassenbuff im Menü wählen oder ein passendes Ziel suchen.",
    INVALID_SPELL_DATA = "Zauber-, Rang- oder Reichweitendaten fehlen. Maus neu aufs Ziel halten; bleibt es so: /reload, dann /fmb status.",
    NO_KNOWN_SPELL = "Kein Buff der Auswahl gelernt. Gewünschten Zauber lernen oder mit /fmb auto gelernte Alternativen nutzen.",
    TARGET_LEVEL_TOO_LOW = "Gelernte Ränge sind für die Zielstufe zu hoch. Niedrigeren Rang lernen oder höherstufigen Spieler wählen.",
    OUT_OF_RANGE = "Dieser Spieler ist außer Reichweite. Bitte näher herangehen und die Buff-Taste erneut drücken und loslassen.",
    NOT_USABLE = "WoW meldet den gewählten Buff als nicht nutzbar. Mana, Reagenzien und WoW-Hinweis prüfen; /fmb status hilft bei Dauerproblemen.",
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

-- Settings are small plain lists. Reject holes, duplicates and inherited data
-- so malformed saved settings never cause an unintended implicit fallback.
-- Example: { "wisdom", "kings" } is valid; { [2] = "kings" } is not.
function Core.ValidPriorityList(list)
    if type(list) ~= "table" or getmetatable(list) ~= nil then return false end
    local count, seen = 0, {}
    for index, family in pairs(list) do
        count = count + 1
        if count > 3 or not positiveInteger(index, 3) or type(family) ~= "string"
            or not families[family] or seen[family] then
            return false
        end
        seen[family] = true
    end
    for index = 1, count do
        if list[index] == nil then return false end
    end
    return true
end

-- The whole configuration must be valid before selecting a class. Missing
-- class rows use defaults; an explicit empty row means the class is disabled.
function Core.GetPriorities(config, classToken)
    if type(classToken) ~= "string" or not classFamilies[classToken] then return nil end
    if config ~= nil then
        if type(config) ~= "table" or getmetatable(config) ~= nil then return nil end
        for token, list in pairs(config) do
            if type(token) ~= "string" or not classFamilies[token]
                or not Core.ValidPriorityList(list) then
                return nil
            end
        end
    end
    local source = config and config[classToken] or classFamilies[classToken]
    local result = {}
    for index, family in ipairs(source) do result[index] = family end
    return result
end

-- Return fresh rows as well as a fresh list, since the menu may retain a view
-- while another settings refresh obtains the same alphabetical class choices.
function Core.ClassOptions()
    local result = {}
    for index, option in ipairs(classOptions) do
        result[index] = { token = option.token, name = option.name }
    end
    return result
end

-- WoW facts may arrive at different times. Unknown is never treated as false/safe.
-- An absent target can be handled before requiring the remaining target facts.
local function checkSafety(context)
    if type(context) ~= "table" or type(context.playerClass) ~= "string" then
        return "INVALID_CONTEXT"
    end
    if not buffProfiles[context.playerClass] then return "UNSUPPORTED_CLASS" end
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
    if not knownBooleans(target, { "isPlayer", "friendly", "pvp", "freeForAll", "dead", "isSelf", "connected", "visible" }) then
        return "TARGET_STATE_UNKNOWN"
    end
    if not target.isPlayer then return "NOT_PLAYER" end
    if not target.friendly then return "NOT_FRIENDLY" end
    if target.pvp or target.freeForAll then return "TARGET_PVP" end
    if target.dead then return "TARGET_DEAD" end
    if target.isSelf then return "SELF_TARGET" end
    if not target.connected then return "TARGET_DISCONNECTED" end
    if not target.visible then return "TARGET_NOT_VISIBLE" end
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
            or not (allBuffFamilies[blessing.family] or blessing.family == "temporary" or blessing.family == "other")
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
local function validSpells(spells, allowedFamilies)
    allowedFamilies = allowedFamilies or allBuffFamilies
    if type(spells) ~= "table" then return false end
    local count, seenIDs = 0, {}
    for index, spell in pairs(spells) do
        count = count + 1
        if count > 200 or not positiveInteger(index, 200) or type(spell) ~= "table" then
            return false
        end
        if not positiveInteger(spell.spellID, 1000000000) or seenIDs[spell.spellID]
            or not positiveInteger(spell.learnedLevel, 1000) or not plainName(spell.spellName)
            or type(spell.family) ~= "string" or not allowedFamilies[spell.family]
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

-- Healing needs only a safe recipient, public low health and proven stillness.
-- It precedes blessing-specific aura/class rules; unknown facts retain buff policy.
-- Healing ranks have no recipient-level restriction: a level-1 target can receive
-- the highest learned heal. An unusable top Flash falls back to top Holy Light.
local function healingDecision(context)
    local target = context.target
    local function finiteNonnegative(value)
        return type(value) == "number" and value == value and value >= 0 and value < math.huge
    end
    if not finiteNonnegative(context.playerSpeed) or context.playerSpeed ~= 0
        or not finiteNonnegative(target.health) or not finiteNonnegative(target.maxHealth)
        or target.health <= 0 or target.maxHealth <= 0 or target.health >= target.maxHealth * 0.5
        or not validSpells(context.heals, healFamilies) then return nil end
    for _, family in ipairs({ "flash", "holy_light" }) do
        local spell = selectRank(context.heals, family, 1000)
        if spell and spell.usable and spell.inRange then
            return { ready = true, code = "READY_HEAL", action = "heal", healFamily = family,
                spellID = spell.spellID, spellName = spell.spellName,
                text = spell.spellName .. " bereit: Heilung unter 50 % im Stehen – Taste drücken und loslassen." }
        end
    end
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
    local heal = context.playerClass == "PALADIN" and healingDecision(context)
    if heal then return heal end
    -- Recipient level, class and auras constrain blessings, never direct heals.
    local target = context.target
    if not positiveInteger(target.level, 1000) then return blocked("TARGET_LEVEL_UNKNOWN") end
    if type(target.class) ~= "string" or not classFamilies[target.class] then
        return blocked("TARGET_CLASS_UNKNOWN")
    end
    if context.auraState ~= "ready" or type(context.hasBlessing) ~= "boolean" then
        return blocked("AURA_UNKNOWN")
    end
    local profile = buffProfiles[context.playerClass]
    local allowed = {}
    for _, entry in ipairs(profile.families) do allowed[entry[1]] = true end
    if context.mode ~= "auto" and not allowed[context.mode] then
        return blocked("INVALID_MODE")
    end
    local priorities
    if context.mode == "auto" then
        if context.playerClass == "PALADIN" then
            priorities = Core.GetPriorities(context.classPriorities, context.target.class)
        else
            priorities = {}
            for _, family in ipairs(profile.auto) do
                -- Intelligence and mana regeneration cannot benefit energy/rage.
                if not ((family == "intellect" or family == "spirit")
                    and (target.class == "WARRIOR" or target.class == "ROGUE")) then
                    priorities[#priorities + 1] = family
                end
            end
        end
        if not priorities then return blocked("INVALID_PRIORITIES") end
        if #priorities == 0 then return blocked("CLASS_DISABLED") end
    else
        priorities = { context.mode }
    end
    local primary = priorities[1]
    local state, auraReason = blessingState(context)
    if not state then return blocked(auraReason, primary) end
    if not validSpells(context.spells) then return blocked("INVALID_SPELL_DATA", primary) end
    if context.playerClass == "PALADIN" and context.mode == "auto" then
        -- Even a newly disabled family must survive: casting a different family
        -- would remove our existing blessing and make settings edits destructive.
        for _, family in ipairs(permanentFamilies) do
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
