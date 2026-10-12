-- Purpose: obtain a native clickable link tied to the exact requested buff spell.
-- Input: public spell ID or link; output: validated unchanged link, ID, or fixed code.
-- Invariants: never fabricate links, alter native color/text, send chat, cast,
-- persist identities, inspect secret values, or expose native exception strings.
-- Debug: lua tests/test_spell_link.lua; caller may log the returned fixed code.
local _, ns = ...
local SpellLink = {}
ns.SpellLink = SpellLink

-- Native spell APIs may return restricted values. Check public access before
-- type-dependent comparisons, length checks, table reads, or link parsing.
local function public(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret == false
end
local function spellID(value)
    return public(value) and type(value) == "number" and value == value
        and value >= 1 and value <= 1000000000 and value == math.floor(value)
end
local function method()
    if not public(C_Spell) or type(C_Spell) ~= "table"
        or type(canaccesstable) ~= "function" then return nil end
    local ok, accessible = pcall(canaccesstable, C_Spell)
    if not ok or not public(accessible) or accessible ~= true then return nil end
    local reader = rawget(C_Spell, "GetSpellLink")
    if public(reader) and type(reader) == "function" then return reader end
end

-- These are defensive accepted forms, not a claim that the native serializer
-- promises a frozen grammar forever. Unknown future variants fall back to text.
-- Accept one spell ID and optionally one unsigned glyph ID, a bracketed label,
-- and at most one original eight-hex color wrapper. Never generalize to other
-- hyperlink types, extra fields, textures, nested escapes, or trailing text.
-- Example: |cff71d5ff|Hspell:19740:0|h[Segen der Macht]|h|r -> 19740.
local function identifier(link)
    if not public(link) or type(link) ~= "string" or #link < 1 or #link > 1024 then return nil end
    local content = link
    if content:sub(1, 2) == "|c" then
        content = content:match("^|c%x%x%x%x%x%x%x%x(.+)|r$")
        if not content then return nil end
    end
    local idText, options = content:match("^|Hspell:(%d+)([^|]*)|h%[([^|%c]+)%]|h$")
    if not idText or #idText > 10 then return nil end
    local id = tonumber(idText)
    if not spellID(id) or tostring(id) ~= idText then return nil end
    if options ~= "" then
        local glyph = options:match("^:(%d+)$")
        if not glyph or #glyph > 10 then return nil end
        local glyphID = tonumber(glyph)
        if not glyphID or glyphID < 0 or glyphID > 1000000000
            or tostring(glyphID) ~= glyph then return nil end
    end
    return id
end

-- Valid/ID recognize syntax only, not proof of who supplied a link. Get additionally
-- requires the native API to return the exact requested spell ID byte-for-byte.
function SpellLink.ID(link)
    return identifier(link)
end
function SpellLink.Valid(link, expectedID)
    if not public(expectedID) then return false end
    if expectedID ~= nil and not spellID(expectedID) then return false end
    local id = identifier(link)
    return id ~= nil and (expectedID == nil or id == expectedID)
end
function SpellLink.Get(id)
    if not spellID(id) then return nil, "SPELL_LINK_INVALID_ID" end
    local reader = method()
    if not reader then return nil, "SPELL_LINK_API_UNAVAILABLE" end
    local ok, link = pcall(reader, id)
    if not ok then return nil, "SPELL_LINK_API_FAILED" end
    if not public(link) then return nil, "SPELL_LINK_RESTRICTED" end
    if link == nil then return nil, "SPELL_LINK_UNAVAILABLE" end
    local actualID = identifier(link)
    if not actualID then return nil, "SPELL_LINK_INVALID" end
    if actualID ~= id then return nil, "SPELL_LINK_MISMATCH" end
    return link
end
