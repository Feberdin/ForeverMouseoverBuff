-- Purpose: prepare a reviewable GitHub issue link without opening or submitting it.
-- Input: fixed report kind, detached DiagnosticSnapshot and explicit detail consent.
-- Output: URL and matching readable preview, or nil plus a fixed error code.
-- Invariants: no network, persistence, names, messages, counters or raw log export.
-- Debug: /fmb feedback; lua tests/test_feedback.lua. Guards fail closed.
local _, ns = ...
local IssueFeedback = {}
ns.IssueFeedback = IssueFeedback
local BASE_URL = "https://github.com/Feberdin/ForeverMouseoverBuff/issues/new"
local templates = {bug = "01-bug.yml", wish = "02-wish.yml", feature = "03-feature.yml"}
local modes = {auto = true, might = true, wisdom = true, kings = true}
local flagKeys = {"enabled", "debug", "sound", "whisper", "receiveWhispers",
    "showOutgoingWhispers", "sealSound", "rankingEnabled", "buttonReady", "routerReady"}
local MAX_CODES, READ_CODES, MAX_URL = 5, 40, 6000

-- Never compare, stringify or enumerate an unavailable value. rawget additionally
-- prevents imported tables from invoking metatables during report preparation.
local function public(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret == false
end
local function readable(value)
    if not public(value) or type(value) ~= "table" or type(canaccesstable) ~= "function" then return false end
    local ok, access = pcall(canaccesstable, value)
    return ok and public(access) and access == true
end
local function version(value)
    if public(value) and type(value) == "string" and #value <= 32
        and value:match("^%d+%.%d+%.%d+$") then return value end
end
local function buildNumber(value)
    if public(value) and type(value) == "string" and #value <= 12
        and value:match("^%d+$") then return value end
end
local function interfaceNumber(value)
    if public(value) and type(value) == "number" and value == value and value >= 1
        and value <= 1000000 and value == math.floor(value) then return tostring(value) end
end
local function addField(fields, label, value)
    if value then fields[#fields + 1] = label .. value end
end

-- Only fixed public configuration fields are eligible. Example: a snapshot with
-- status={sound=true,target="Private"} contributes sound=true, never target.
local function environment(snapshot)
    local lines, versions, client, flags = {}, {}, {}, {}
    addField(versions, "Addon: ", version(rawget(snapshot, "version")))
    local status = rawget(snapshot, "status")
    if readable(status) then
        addField(versions, "WoW: ", version(rawget(status, "clientVersion")))
        addField(client, "Build: ", buildNumber(rawget(status, "clientBuild")))
        addField(client, "Interface: ", interfaceNumber(rawget(status, "clientInterface")))
        for _, key in ipairs(flagKeys) do
            local value = rawget(status, key)
            if public(value) and type(value) == "boolean" then
                flags[#flags + 1] = key .. "=" .. (value and "true" or "false")
            end
        end
    end
    local mode = rawget(snapshot, "mode")
    if public(mode) and type(mode) == "string" and modes[mode] then addField(client, "Modus: ", mode) end
    if #versions > 0 then lines[#lines + 1] = table.concat(versions, " | ") end
    if #client > 0 then lines[#lines + 1] = table.concat(client, " | ") end
    for index = 1, #flags, 3 do
        local group = {}
        for offset = 0, 2 do
            if flags[index + offset] then group[#group + 1] = flags[index + offset] end
        end
        lines[#lines + 1] = table.concat(group, ", ")
    end
    return #lines > 0 and table.concat(lines, "\n") or "Keine freigegebenen technischen Angaben verfügbar."
end

-- Reuse the diagnostic module's literal code catalogue, never an uppercase-name
-- pattern. Check at most 40 source slots and include only five recent unique codes.
-- No timestamps, event payloads, log counts or arbitrary errors leave the addon.
local function diagnostics(snapshot)
    local result, seen = {}, {}
    local codes = rawget(snapshot, "codes")
    local log = ns.DiagnosticLog
    if readable(codes) and type(log) == "table" and type(log.IsCode) == "function" then
        for index = READ_CODES, 1, -1 do
            local code = rawget(codes, index)
            if public(code) and type(code) == "string" and #code <= 80 then
                local ok, known = pcall(log.IsCode, code)
                if ok and public(known) and known == true and not seen[code] then
                    result[#result + 1], seen[code] = code, true
                    if #result == MAX_CODES then break end
                end
            end
        end
    end
    if #result == 0 then return "Keine freigegebenen Diagnosecodes vorhanden." end
    return "Diagnosecodes (neueste zuerst):\n" .. table.concat(result, ", ")
end

-- Encode every non-ASCII-unreserved byte independently, including UTF-8. This
-- preserves newlines and umlauts and prevents field text creating query options.
local function encode(value)
    return (value:gsub("([^A-Za-z0-9%-%._~])", function(character)
        return string.format("%%%02X", string.byte(character))
    end))
end
function IssueFeedback.Build(kind, snapshot, includeTechnical)
    if type(issecretvalue) ~= "function" then return nil, "ISSUE_GUARD_UNAVAILABLE" end
    if not public(kind) or type(kind) ~= "string" or not templates[kind] then
        return nil, "ISSUE_KIND_INVALID"
    end
    if not public(includeTechnical) or (includeTechnical ~= nil and type(includeTechnical) ~= "boolean") then
        return nil, "ISSUE_OPTIONS_INVALID"
    end
    local report = {kind = kind, url = BASE_URL .. "?template=" .. templates[kind],
        preview = "Keine technischen Angaben angehängt. Der Link öffnet nur die gewählte GitHub-Vorlage."}
    if includeTechnical == true then
        if not readable(snapshot) then return nil, "ISSUE_SNAPSHOT_UNAVAILABLE" end
        report.environment, report.diagnostics = environment(snapshot), diagnostics(snapshot)
        report.preview = report.environment .. "\n\n" .. report.diagnostics
        report.url = report.url .. "&environment=" .. encode(report.environment)
            .. "&diagnostics=" .. encode(report.diagnostics)
    end
    if #report.url > MAX_URL then return nil, "ISSUE_URL_TOO_LONG" end
    return report
end
