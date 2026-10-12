-- Purpose: bounded SHA-256 checksums for the local counter storage envelope.
-- Input: a public byte string of at most 4096 bytes. Output: lowercase hex or
-- nil plus a fixed HASH_* error code. No game identity, I/O or saved data read.
-- Invariants: this is an UNKEYED checksum, not encryption or authentication.
-- Debug: tests/test_counter_codec.lua contains independently generated answers.
-- Provenance: original MIT-licensed implementation of NIST FIPS 180-4, sections
-- 4.1.2, 4.2.2, 5.1.1, 5.3.3 and 6.2; no copied third-party implementation.
-- https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.180-4.pdf
local _, ns = ...
local Hash = {}
ns.Hash = Hash

local floor, MOD32 = math.floor, 4294967296
local MAX_BYTES = 4096

local function public(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret == false
end

-- WoW Forever and the standalone Lua 5.1 test runtime do not need a bit library.
-- Sixteen small lookup rows provide XOR on four bits. Fixed eight-step word
-- operations are portable across Lua 5.1's doubles and Lua 5.5's integers.
-- Every intermediate here is exact and safely below 2^53.
local xorNibble = {}
for left = 0, 15 do
    local row = {}
    xorNibble[left] = row
    for right = 0, 15 do
        local a, b, result, weight = left, right, 0, 1
        for _ = 1, 4 do
            if a % 2 ~= b % 2 then result = result + weight end
            a, b, weight = floor(a / 2), floor(b / 2), weight * 2
        end
        row[right] = result
    end
end

local function bxor(left, right)
    local result, weight = 0, 1
    for _ = 1, 8 do
        result = result + xorNibble[left % 16][right % 16] * weight
        left, right, weight = floor(left / 16), floor(right / 16), weight * 16
    end
    return result
end

local function band(left, right)
    return (left + right - bxor(left, right)) / 2
end

local function rotateRight(word, amount)
    local shift = 2 ^ amount
    return floor(word / shift) + (word % shift) * (2 ^ (32 - amount))
end

local function xorThree(a, b, c)
    return bxor(bxor(a, b), c)
end

local function bigEndianWord(word)
    return string.char(floor(word / 16777216) % 256, floor(word / 65536) % 256,
        floor(word / 256) % 256, word % 256)
end

-- The fixed round and initial constants are the standard SHA-256 parameters.
-- Keeping them explicit makes comparison with the published algorithm simple.
local roundConstants = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

-- FIPS 180-4 section 6.2.2: expand sixteen big-endian words to sixty-four,
-- apply the compression rounds and accumulate into the eight chaining words.
local function compress(message, offset, state)
    local schedule = {}
    for index = 1, 16 do
        local start = offset + (index - 1) * 4
        local a, b, c, d = message:byte(start, start + 3)
        schedule[index] = a * 16777216 + b * 65536 + c * 256 + d
    end
    for index = 17, 64 do
        local before15, before2 = schedule[index - 15], schedule[index - 2]
        local sigma0 = xorThree(rotateRight(before15, 7), rotateRight(before15, 18), floor(before15 / 8))
        local sigma1 = xorThree(rotateRight(before2, 17), rotateRight(before2, 19), floor(before2 / 1024))
        schedule[index] = (schedule[index - 16] + sigma0 + schedule[index - 7] + sigma1) % MOD32
    end
    local a, b, c, d = state[1], state[2], state[3], state[4]
    local e, f, g, h = state[5], state[6], state[7], state[8]
    for index = 1, 64 do
        local sum1 = xorThree(rotateRight(e, 6), rotateRight(e, 11), rotateRight(e, 25))
        -- Equivalent standard Ch/Maj forms avoid a separate bitwise NOT.
        local choice = bxor(g, band(e, bxor(f, g)))
        local temp1 = (h + sum1 + choice + roundConstants[index] + schedule[index]) % MOD32
        local sum0 = xorThree(rotateRight(a, 2), rotateRight(a, 13), rotateRight(a, 22))
        local majority = bxor(band(a, b), band(c, bxor(a, b)))
        local temp2 = (sum0 + majority) % MOD32
        h, g, f, e, d, c, b, a = g, f, e, (d + temp1) % MOD32, c, b, a, (temp1 + temp2) % MOD32
    end
    local result = {a, b, c, d, e, f, g, h}
    for index = 1, 8 do state[index] = (state[index] + result[index]) % MOD32 end
end

function Hash.SHA256(message)
    if not public(message) then return nil, "HASH_DATA_RESTRICTED" end
    if type(message) ~= "string" then return nil, "HASH_INPUT_INVALID" end
    if #message > MAX_BYTES then return nil, "HASH_INPUT_TOO_LARGE" end

    -- The input cap guarantees that the upper 32 bits of the bit length are 0.
    -- Padding remains the standard 0x80, zeros, then a 64-bit big-endian length.
    local bitLength = #message * 8
    local zeroBytes = (55 - #message) % 64
    local padded = message .. string.char(128) .. string.rep("\0", zeroBytes)
        .. string.rep("\0", 4) .. bigEndianWord(bitLength)
    local state = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19}
    for offset = 1, #padded, 64 do compress(padded, offset, state) end
    local output = {}
    for index = 1, 8 do output[index] = string.format("%08x", state[index]) end
    return table.concat(output)
end
