-- Purpose: format a short personal blessing without game APIs or side effects.
-- Input: public sender class/race, recipient traits, names and variant.
-- Output: one class-appropriate message or fixed code; unknown class stays neutral.
-- Invariants: no randomness, sending, name logging, mutation or persisted identities.
-- Debug: lua tests/test_greetings.lua; integration owns the public-value guards.
local _, ns = ...
local Greetings = {COUNT = 12, PREFIX = "[Forever Mouseover Buff] ",
    COLOR_PREFIX = "|cffffd36b[Forever Mouseover Buff]|r "}
ns.Greetings = Greetings

-- Vocative addresses use the game's public race token plus known male/female code.
-- Missing or unfamiliar facts use the unmodified name, without guessing a gender.
local addresses = {
    Human = {[2] = "edler Mensch", [3] = "edle Menschenfrau"},
    Dwarf = {[2] = "edler Zwerg", [3] = "edle Zwergin"},
    NightElf = {[2] = "edler Nachtelf", [3] = "edle Nachtelfe"},
    Gnome = {[2] = "edler Gnom", [3] = "edle Gnomin"},
    Draenei = {[2] = "edler Draenei", [3] = "edle Draenei"},
    Orc = {[2] = "edler Orc", [3] = "edle Orcin"},
    Scourge = {[2] = "edler Untoter", [3] = "edle Untote"},
    Tauren = {[2] = "edler Taure", [3] = "edle Taurin"},
    Troll = {[2] = "edler Troll", [3] = "edle Trollin"},
    BloodElf = {[2] = "edler Blutelf", [3] = "edle Blutelfe"},
}


-- Lua 5.1 has no utf8 library. Validate complete code points before formatting;
-- this also rejects overlong encodings, surrogate code points and raw bad bytes.
-- Keep our own conservative 255-byte budget, including optional native markup.
-- Native chat distinguishes visible/invisible budgets; we stay below both.
local function validUTF8(value)
    local index, length = 1, #value
    while index <= length do
        local first = value:byte(index)
        if first < 128 then
            index = index + 1
        else
            local continuation, low, high
            if first >= 194 and first <= 223 then continuation, low, high = 1, 128, 191
            elseif first == 224 then continuation, low, high = 2, 160, 191
            elseif first >= 225 and first <= 236 then continuation, low, high = 2, 128, 191
            elseif first == 237 then continuation, low, high = 2, 128, 159
            elseif first >= 238 and first <= 239 then continuation, low, high = 2, 128, 191
            elseif first == 240 then continuation, low, high = 3, 144, 191
            elseif first >= 241 and first <= 243 then continuation, low, high = 3, 128, 191
            elseif first == 244 then continuation, low, high = 3, 128, 143
            else return false end
            if index + continuation > length then return false end
            local second = value:byte(index + 1)
            if second < low or second > high then return false end
            for offset = 2, continuation do
                local byte = value:byte(index + offset)
                if byte < 128 or byte > 191 then return false end
            end
            index = index + continuation + 1
        end
    end
    return true
end
-- Match Whisper's existing public-name shape, then also require well-formed UTF-8.
-- Public-value/secret guards belong to the game-API boundary, before this module.
local function validName(value)
    return type(value) == "string" and #value >= 1 and #value <= 96
        and value:match("^[A-Za-z\128-\255][A-Za-z\128-\255 %-]*$") ~= nil
        and value:match("[ %-]$") == nil and validUTF8(value)
end

local function address(profile, receiver)
    local race, sex = rawget(profile, "raceToken"), rawget(profile, "sex")
    if type(race) ~= "string" or type(sex) ~= "number" or (sex ~= 2 and sex ~= 3) then
        return receiver
    end
    local forms = addresses[race]
    if not forms then return receiver end
    return forms[sex] .. " " .. receiver
end

-- Formatting is deterministic and side-effect free. The caller selects a variant
-- only after a confirmed cast, and owns delivery and any anti-repeat policy.
-- Example: NightElf/3 + Alyndra -> "edle Nachtelfe Alyndra"; unknown -> "Alyndra".
function Greetings.Format(profile, variant)
    if type(profile) ~= "table" then return nil, "GREETING_INVALID_PROFILE" end
    local receiver, sender = rawget(profile, "receiverName"), rawget(profile, "senderName")
    if not validName(receiver) then return nil, "GREETING_INVALID_RECEIVER" end
    if not validName(sender) then return nil, "GREETING_INVALID_SENDER" end
    if type(variant) ~= "number" or variant ~= variant or variant < 1
        or variant > Greetings.COUNT or variant ~= math.floor(variant) then
        return nil, "GREETING_INVALID_VARIANT"
    end
    local count, link = rawget(profile, "buffCount"), rawget(profile, "spellLink")
    if count ~= nil and (type(count) ~= "number" or count ~= count or count < 0
        or count > 1000000000 or count ~= math.floor(count)) then
        return nil, "GREETING_INVALID_COUNT"
    end
    if link ~= nil and (not ns.SpellLink or not ns.SpellLink.Valid(link)) then
        return nil, "GREETING_INVALID_LINK"
    end
    local details = count ~= nil and string.format(" [lokal: %.0f Buffs]", count) or ""
    if link then details = details .. " " .. link end
    -- Sender culture chooses the voice; recipient traits only choose the address.
    -- Keep these roles separate: a paladin addressing a druid is still a paladin.
    local catalog = ns.GreetingCatalog
    if type(catalog) ~= "table" or type(catalog.Select) ~= "function" then
        return nil, "GREETING_CATALOG_UNAVAILABLE"
    end
    local templates, short = catalog.Select(rawget(profile, "senderClass"), rawget(profile, "senderRace"))
    local sentence = string.format(templates[variant], address(profile, receiver))
    local message = Greetings.PREFIX .. '"' .. sentence .. '" - ' .. sender
    if #message + #details > 255 then
        -- Both names fit in full (at most 192 bytes together). A shorter complete
        -- sentence is safer than splitting a name or a multi-byte UTF-8 character.
        message = Greetings.PREFIX .. '"' .. string.format(short, receiver) .. '" - ' .. sender
    end
    if #message + #details > 255 then
        -- Keep complete identities and a complete link. Omit the count first;
        -- if even the link cannot fit, omit both optional details, never truncate.
        if link and #message + #link + 1 <= 255 then
            return message .. " " .. link, "GREETING_DETAILS_OMITTED"
        end
        return message, "GREETING_DETAILS_OMITTED"
    end
    return message .. details
end

-- Only our own local display color is reversible. Never strip arbitrary markup:
-- WIM may see the colored display before checking the original outgoing echo.
function Greetings.PlainMessage(message)
    if type(message) == "string" and message:sub(1, #Greetings.COLOR_PREFIX) == Greetings.COLOR_PREFIX then
        return Greetings.PREFIX .. message:sub(#Greetings.COLOR_PREFIX + 1)
    end
    return message
end

-- One narrow grammar is shared by sender validation and recipient opt-out. Only
-- a native spell hyperlink is allowed after the optional self-reported counter.
-- This identifies our message format, not an authenticated addon/sender identity.
function Greetings.ValidMessage(message, expectedSpellID)
    if type(message) ~= "string" then return false end
    local plain = Greetings.PlainMessage(message)
    if #plain > 255 or plain:sub(1, #Greetings.PREFIX) ~= Greetings.PREFIX
        or not validUTF8(plain) or plain:find("%c") then return false end
    local body = plain:sub(#Greetings.PREFIX + 1)
    local base, link = body:match("^(.-) (|.+)$")
    if link then
        if not ns.SpellLink or not ns.SpellLink.Valid(link, expectedSpellID) then return false end
        body = base
    end
    if body:find("|", 1, true) then return false end
    local withoutCount, digits = body:match("^(.-) %[lokal: (%d+) Buffs%]$")
    if digits then
        local value = tonumber(digits)
        if #digits > 10 or not value or value > 1000000000
            or string.format("%.0f", value) ~= digits then return false end
        body = withoutCount
    end
    local sender = body:match('^"[^"\r\n]+" %- (.+)$')
    return validName(sender)
end
