-- Purpose: encode fixed-size local counters without plain decimal saved fields.
-- Input: exactly 80 public bytes or a public schema-2 storage table.
-- Output: {schema=2,payload=canonical Base64,digest=SHA-256} or decoded bytes;
-- failure returns nil plus a fixed COUNTER_* code for the owning Stats logger.
-- Invariants: no identities, network, dynamic execution, unbounded iteration or
-- input mutation. This is encoding plus an UNKEYED checksum, not encryption,
-- authentication or anti-cheat. Anyone can encode new data with a new digest.
-- Debug: tests/test_counter_codec.lua; Stats maps errors to bounded diagnostics.
-- Base64 follows RFC 4648 section 4 with required zero pad bits and '=' padding.
local _, ns = ...
local CounterCodec = {}
ns.CounterCodec = CounterCodec

local BINARY_BYTES, PAYLOAD_BYTES = 80, 108
local DOMAIN = "FMBStats\0v2\0"
local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local digits = {}
for index = 1, #alphabet do digits[alphabet:sub(index, index)] = index - 1 end

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

local function validDigest(value)
    return public(value) and type(value) == "string" and #value == 64
        and value:match("^[0-9a-f]+$") ~= nil
end

-- Hashing is deliberately separate from encoding. A failed/missing helper must
-- never produce an envelope that looks checked. Raw exception text is discarded.
local function checksum(payload)
    if not readable(ns.Hash) then return nil, "COUNTER_HASH_UNAVAILABLE" end
    local sha256 = rawget(ns.Hash, "SHA256")
    if not public(sha256) or type(sha256) ~= "function" then return nil, "COUNTER_HASH_UNAVAILABLE" end
    local ok, digest = pcall(sha256, DOMAIN .. payload)
    if not ok or not validDigest(digest) then return nil, "COUNTER_HASH_UNAVAILABLE" end
    return digest
end

-- Exactly 80 bytes means 26 complete groups plus a two-byte tail. No general
-- parser or padding mode is needed. Example: 80 zero bytes -> 107 'A's + '='.
local function encodeBytes(binary)
    local output = {}
    for index = 1, BINARY_BYTES, 3 do
        local a, b, c = binary:byte(index, index + 2)
        local packed = a * 65536 + b * 256 + (c or 0)
        local first = math.floor(packed / 262144) % 64 + 1
        local second = math.floor(packed / 4096) % 64 + 1
        local third = math.floor(packed / 64) % 64 + 1
        local fourth = packed % 64 + 1
        output[#output + 1] = alphabet:sub(first, first) .. alphabet:sub(second, second)
            .. alphabet:sub(third, third) .. (c and alphabet:sub(fourth, fourth) or "=")
    end
    return table.concat(output)
end

local function decodeBytes(payload)
    if type(payload) ~= "string" or #payload ~= PAYLOAD_BYTES
        or not payload:match("^[A-Za-z0-9+/]+=$") then
        return nil
    end
    -- The two unused low bits in the last sextet must be zero. Otherwise four
    -- different text strings could decode to the same bytes (noncanonical).
    if digits[payload:sub(107, 107)] % 4 ~= 0 then return nil end
    local output = {}
    for index = 1, PAYLOAD_BYTES, 4 do
        local a, b = digits[payload:sub(index, index)], digits[payload:sub(index + 1, index + 1)]
        local c, d = digits[payload:sub(index + 2, index + 2)], digits[payload:sub(index + 3, index + 3)]
        local packed = a * 262144 + b * 4096 + c * 64 + (d or 0)
        local first, second = math.floor(packed / 65536) % 256, math.floor(packed / 256) % 256
        if d then output[#output + 1] = string.char(first, second, packed % 256)
        else output[#output + 1] = string.char(first, second) end
    end
    return table.concat(output)
end

function CounterCodec.Encode(binary)
    if not public(binary) then return nil, "COUNTER_DATA_RESTRICTED" end
    if type(binary) ~= "string" or #binary ~= BINARY_BYTES then return nil, "COUNTER_BINARY_INVALID" end
    local payload = encodeBytes(binary)
    local digest, code = checksum(payload)
    if not digest then return nil, code end
    return {schema = 2, payload = payload, digest = digest}
end

function CounterCodec.Decode(store)
    if not public(store) then return nil, "COUNTER_DATA_RESTRICTED" end
    if type(store) ~= "table" then return nil, "COUNTER_STORAGE_INVALID" end
    if not readable(store) then return nil, "COUNTER_DATA_RESTRICTED" end
    local schema, payload, digest = rawget(store, "schema"), rawget(store, "payload"), rawget(store, "digest")
    if not public(schema) or not public(payload) or not public(digest) then return nil, "COUNTER_DATA_RESTRICTED" end
    if schema ~= 2 then return nil, "COUNTER_SCHEMA_UNSUPPORTED" end
    local binary = decodeBytes(payload)
    if not binary then return nil, "COUNTER_PAYLOAD_INVALID" end
    if not validDigest(digest) then return nil, "COUNTER_DIGEST_INVALID" end
    local expected, code = checksum(payload)
    if not expected then return nil, code end
    if digest ~= expected then return nil, "COUNTER_INTEGRITY_MISMATCH" end
    return binary
end
