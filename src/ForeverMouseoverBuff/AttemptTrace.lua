-- Purpose: retain the last 16 anonymous, hardware-triggered buff/heal attempts.
-- Input: existing public context/decision facts and matched cast results; no game API reads.
-- Output: copied diagnosticAttempts SavedVariables and readable /fmb diag lines.
-- Invariants: observer only; fixed fields/tokens, no names/GUIDs/text, fail closed on secret data.
-- Debug: lua tests/test_classes.lua. Reload flushes SavedVariables; chat works immediately.
local _, ns = ...
local Trace = {}
ns.AttemptTrace = Trace
local history, database, sequence = {}, nil, 0
local families = {might = true, wisdom = true, kings = true, flash = true, holy_light = true}
local modes = {auto = true, might = true, wisdom = true, kings = true}
-- Share fixed profile tokens without retaining arbitrary user/API strings.
-- Rank summaries below deliberately keep their existing Paladin schema.
if ns.Core then
    for _, option in ipairs(ns.Core.ClassOptions()) do
        for _, row in ipairs(ns.Core.BuffModes(option.token)) do
            modes[row[1]] = true
            if row[1] ~= "auto" then families[row[1]] = true end
        end
    end
end
local classes = {PRIEST = true, PALADIN = true, WARRIOR = true, MAGE = true, WARLOCK = true,
    HUNTER = true, ROGUE = true, DRUID = true, SHAMAN = true}
local results = {CAST_REQUESTED = true, CAST_CONFIRMED = true, CAST_FAILED = true, UNCONFIRMED = true}

-- Guard before type checks, comparisons, indexing or formatting. A secret value
-- must never be converted to text, even when diagnostics cannot be retained.
local function public(value)
    if type(issecretvalue) ~= 'function' then return false end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret == false
end
local function readable(value)
    if not public(value) or type(value) ~= 'table' or type(canaccesstable) ~= 'function' then return false end
    local ok, access = pcall(canaccesstable, value)
    return ok and public(access) and access == true
end
local function field(value, key)
    if not readable(value) then return nil end
    local item = rawget(value, key)
    if public(item) then return item end
end
local function integer(value, maximum)
    if public(value) and type(value) == 'number' and value == value and value >= 0
        and value <= maximum and value == math.floor(value) then return value end
end
local function token(value, allowed)
    if public(value) and type(value) == 'string' and allowed[value] then return value end
end
local function code(value)
    if public(value) and ns.DiagnosticLog and ns.DiagnosticLog.IsCode(value) then return value end
end
local function copy(value)
    local result = {}
    for key, item in pairs(value) do result[key] = type(item) == 'table' and copy(item) or item end
    return result
end
local function persist()
    if readable(database) then pcall(rawset, database, 'diagnosticAttempts', Trace.Snapshot()) end
end

-- This is evidence of the CURRENT selection rule, not an assertion of the
-- client's minimum recipient level. Example: learned14 + target11 => eligible0.
-- Keep those facts separate so a wrong eligibility rule remains diagnosable.
function Trace.Capture(context, decision)
    local target = field(context, 'target')
    local entry = {class = token(field(target, 'class'), classes), level = integer(field(target, 'level'), 1000),
        mode = token(field(context, 'mode'), modes), spellID = integer(field(decision, 'spellID'), 1000000000),
        family = token(field(decision, 'family'), families), code = code(field(decision, 'code')),
        fallbackFrom = token(field(decision, 'fallbackFrom'), families),
        fallbackReason = code(field(decision, 'fallbackReason'))}
    local spells = field(context, 'spells')
    if readable(spells) then
        for _, family in ipairs({'wisdom', 'might', 'kings'}) do
            local summary = {known = 0, eligible = 0}
            for index = 1, 200 do
                local spell = field(spells, index)
                if spell == nil then break end
                local learned = integer(field(spell, 'learnedLevel'), 1000)
                if field(spell, 'family') == family and field(spell, 'known') == true and learned then
                    summary.known = summary.known + 1
                    summary.minimumLevel = math.min(summary.minimumLevel or learned, learned)
                    if entry.level and learned <= entry.level then summary.eligible = summary.eligible + 1 end
                end
            end
            entry[family] = summary
        end
    end
    return entry
end

-- Imported data is sanitized again; never trust SavedVariables as a private
-- table. Reconstruct only fixed fields rather than carrying arbitrary keys.
local function sanitizeEntry(item)
    if not readable(item) then return nil end
    local entry = Trace.Capture({mode = field(item, 'mode'), target = {
        class = field(item, 'class'), level = field(item, 'level')}}, item)
    entry.sequence = integer(field(item, 'sequence'), 1000000000)
    entry.result = token(field(item, 'result'), results)
    if not entry.sequence or not entry.result then return nil end
    for _, family in ipairs({'wisdom', 'might', 'kings'}) do
        local rank = field(item, family)
        local known, eligible = integer(field(rank, 'known'), 200), integer(field(rank, 'eligible'), 200)
        if known and eligible and eligible <= known then
            entry[family] = {known = known, eligible = eligible,
                minimumLevel = integer(field(rank, 'minimumLevel'), 1000)}
        end
    end
    return entry
end
function Trace.Initialize(db)
    history, database, sequence = {}, readable(db) and db or nil, 0
    local old = field(db, 'diagnosticAttempts')
    if not readable(old) then return end
    for index = 1, 16 do
        local item = field(old, index)
        if item == nil then break end
        local entry = sanitizeEntry(item)
        if entry then
            history[#history + 1] = entry
            sequence = math.max(sequence, entry.sequence)
        end
    end
end
function Trace.Snapshot() return copy(history) end
function Trace.Begin(entry, spellID)
    -- Revalidate even internal callers so a future UI hook cannot inject text.
    sequence = math.min(1000000000, sequence + 1)
    local fresh = sanitizeEntry({sequence = sequence, result = 'CAST_REQUESTED',
        class = field(entry, 'class'), level = field(entry, 'level'), mode = field(entry, 'mode'),
        spellID = spellID, family = field(entry, 'family'), code = field(entry, 'code'),
        fallbackFrom = field(entry, 'fallbackFrom'), fallbackReason = field(entry, 'fallbackReason'),
        wisdom = field(entry, 'wisdom'), might = field(entry, 'might'), kings = field(entry, 'kings')})
    if not fresh then return nil end
    history[#history + 1] = fresh
    if #history > 16 then table.remove(history, 1) end
    persist()
    return sequence
end
function Trace.Finish(id, result)
    result = token(result, results)
    if not integer(id, 1000000000) or not result then return end
    for _, entry in ipairs(history) do
        if entry.sequence == id and entry.result == 'CAST_REQUESTED' then entry.result = result; persist(); return end
    end
end

-- Render fixed tokens and public numbers only. The log's API_RESTRICTED code
-- may concern another optional API; the per-attempt reason identifies selection.
function Trace.Report()
    local entry = history[#history]
    if not entry then return 'Versuchsdetails: noch kein Tastendruck erfasst (Diagnose lokal aktiv).' end
    local function show(value) return value == nil and '?' or tostring(value) end
    local lines = {'Letzter Versuch #' .. entry.sequence .. ': ' .. show(entry.result)
        .. ' | Klasse=' .. show(entry.class) .. ' | Ziel-Level=' .. show(entry.level) .. ' | Modus=' .. show(entry.mode),
        'Auswahl: ' .. show(entry.family) .. ' | Zauber-ID=' .. show(entry.spellID) .. ' | ' .. show(entry.code),
        'Alternative von=' .. show(entry.fallbackFrom) .. ' | Grund=' .. show(entry.fallbackReason)}
    for _, family in ipairs({'wisdom', 'might', 'kings'}) do
        local rank = entry[family]
        if rank then lines[#lines + 1] = family .. ': bekannte Ränge=' .. rank.known
            .. ' | niedrigstes Lernlevel=' .. show(rank.minimumLevel) .. ' | nach aktueller Levelregel zulässig=' .. rank.eligible end
    end
    lines[#lines + 1] = 'Lernlevel ist keine bestätigte Mindeststufe des Empfängers; die Levelregel wird hier nur protokolliert.'
    return table.concat(lines, '\n')
end
