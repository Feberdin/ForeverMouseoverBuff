-- Purpose: check SHA-256 and the fixed-size counter envelope independently.
-- Input: synthetic bytes, NIST examples and Python hashlib/base64 answer vectors.
-- Output: deterministic PASS/FAIL lines; no game, network or real saved data.
-- Invariants: the checksum detects mismatched data, not a knowledgeable forger.
-- Debug: lua tests/test_counter_codec.lua [exact_test_name].
local tests = {}
local function equal(actual, expected, reason)
    assert(actual == expected, reason or "unexpected codec result")
end

local function fixture()
    local f = {ns = {}}
    f.secret = setmetatable({}, {__tostring = function() error("secret printed") end})
    f.opaque = setmetatable({}, {__index = function() error("opaque table read") end})
    f.env = setmetatable({}, {__index = _G})
    f.env.issecretvalue = function(value) return rawequal(value, f.secret) end
    f.env.canaccesstable = function(value) return not rawequal(value, f.opaque) end
    f.env.UnitName = function() error("no identity read allowed") end
    f.env.UnitGUID = f.env.UnitName
    f.env.SendChatMessage = function() error("no message send allowed") end
    f.env.C_ChatInfo = {SendAddonMessage = f.env.SendChatMessage}
    -- An absent module is a missing feature, not a broken import. The focused
    -- red test below explicitly checks the intended public capability first.
    for _, name in ipairs({"Hash.lua", "CounterCodec.lua"}) do
        local path = "src/ForeverMouseoverBuff/" .. name
        local handle = io.open(path, "rb")
        if handle then
            handle:close()
            local chunk
            if setfenv then
                chunk = assert(loadfile(path)); setfenv(chunk, f.env)
            else
                chunk = assert(loadfile(path, "t", f.env))
            end
            chunk("ForeverMouseoverBuff", f.ns)
        end
    end
    f.api = f.ns.CounterCodec
    return f
end

local function requireCodec(f)
    equal(type(f.api), "table", "fixed-size encoded counter storage is not implemented")
    equal(type(f.api.Encode), "function", "counter encoding is not available")
    equal(type(f.api.Decode), "function", "counter verification is not available")
end

function tests.counter_storage_is_encoded_and_has_an_independent_sha256_answer()
    local f = fixture(); requireCodec(f)
    local data = string.rep("\0", 80)
    local stored, code = f.api.Encode(data)
    equal(code, nil); equal(type(stored), "table")
    equal(stored.schema, 2)
    equal(stored.payload, string.rep("A", 107) .. "=")
    equal(stored.digest, "8a5e4d53b429e441a75ae5860f31cbe18178a61658e0a07ead985061e59d8f63")
    equal(f.api.Decode(stored), data)
    for key in pairs(stored) do
        assert(key == "schema" or key == "payload" or key == "digest", "no counts or identity fields allowed")
    end
end

function tests.sha256_matches_standard_empty_abc_and_multiblock_vectors()
    local f = fixture()
    equal(type(f.ns.Hash), "table", "bounded standard SHA-256 checksum is not implemented")
    equal(type(f.ns.Hash.SHA256), "function")
    equal(f.ns.Hash.SHA256(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    equal(f.ns.Hash.SHA256("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    equal(f.ns.Hash.SHA256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
        "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
end

function tests.sha256_matches_independent_binary_boundary_and_maximum_vectors()
    local f = fixture()
    equal(type(f.ns.Hash), "table", "bounded standard SHA-256 checksum is not implemented")
    -- Answers generated with Python's hashlib.sha256(bytes((i*73+19)%256 ...)).
    -- This covers padding at 55/56 and 119/120 bytes, blocks and the input cap.
    local answers = {
        [1] = "ab897fbdedfa502b2d839b6a56100887dccdc507555c282e59589e06300a62e2",
        [2] = "c756bd104d1406ec2c380c268dbef88fd2082819c15a21c8644bcd8e8de4bc96",
        [3] = "2b8c60738b844cd8716c5134363930fbc133c1f41cc0e568dfd0b4106a7b65e1",
        [55] = "0c43a30970ee9525a6603d5656803c325bded148fa65bbd363df54cb3ac3dee5",
        [56] = "f4dcdc09c846d1b3621701516b300055c1e7875e216ba019dd4423f5a420f2d0",
        [63] = "ba3bb62c4369fe74e7b94392d0f04ed284a7b5d7295bfa48fabdb25c01d85ab7",
        [64] = "cb6862268ca7c02e7b6af558f0e3d236ce9ec7ff41cc746b2848c04c582da94e",
        [65] = "b68af55df9ce8ee60870e45d10e36b2e8363c9896f6e62478dcb6f593a4d7133",
        [119] = "175624f0f95b0a47a1b3b52f5b149f88802d3822b184325d0c20a1a7c132a687",
        [120] = "0598a3d8b5a82710dda54f05c4aa11fdd1c0aa5fafb216840fccbae323f07520",
        [127] = "a8365b6e6ed1daf56c41bae89ab089c03b671240ae103070480a7f271bdbad57",
        [128] = "d399f065c9f21e2fd51e2aeadb7768eab7e6e45e5150f31227c9711934a4d1d3",
        [129] = "d672408e0571636ea21092304eb31ba8fc1fbffc5d5ea6531d62b072714599db",
        [255] = "6d59f1b3a886e8cb813e77d1f0ca0ea63ed8aa8f52511c4a438efb6a4a51d1ff",
        [256] = "8e5ed1e6474d39bf1594411085e7a50c15aabaa768e633ebf0960ce20e84e336",
        [1000] = "608e080fde320bdf980b21746fc8882c1b0211bd8d68b212a568a6cabf0e41bd",
        [4096] = "f965b526538d757ca2d6114af6517c57cbcb3650b71d8cfb92046a04ef2f566b",
    }
    for length, expected in pairs(answers) do
        local bytes = {}
        for index = 0, length - 1 do bytes[#bytes + 1] = string.char((index * 73 + 19) % 256) end
        equal(f.ns.Hash.SHA256(table.concat(bytes)), expected, "binary SHA-256 length " .. length)
    end
end

function tests.base64_matches_independent_binary_and_high_byte_vectors()
    local f = fixture(); requireCodec(f)
    local bytes = {}
    for byte = 0, 79 do bytes[#bytes + 1] = string.char(byte) end
    local data = table.concat(bytes)
    local encoded = assert(f.api.Encode(data))
    equal(encoded.payload, "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0BBQkNERUZHSElKS0xNTk8=")
    equal(encoded.digest, "1122bafd4a410de92148f4b1f70aa70e7a4ebd683ab2c1826b26cfcbcfde3cbe")
    equal(f.api.Decode(encoded), data)
    local high = assert(f.api.Encode(string.rep(string.char(255), 80)))
    equal(high.payload, string.rep("/", 106) .. "8=")
    equal(high.digest, "d6770a45d0cba0be64866f0faff1b3748f4964362c3127d57fc9696da6d9a897")
    equal(f.api.Decode(high), string.rep(string.char(255), 80))
end

function tests.one_byte_or_digest_modification_is_refused_without_rewriting_input()
    local f = fixture(); requireCodec(f)
    local stored = assert(f.api.Encode(string.rep("\0", 80)))
    local digest = stored.digest
    stored.payload = "B" .. stored.payload:sub(2)
    local result, code = f.api.Decode(stored)
    equal(result, nil); equal(code, "COUNTER_INTEGRITY_MISMATCH")
    equal(stored.digest, digest); equal(stored.payload:sub(1, 1), "B")
    stored.payload = string.rep("A", 107) .. "="
    stored.digest = "0" .. digest:sub(2)
    result, code = f.api.Decode(stored)
    equal(result, nil); equal(code, "COUNTER_INTEGRITY_MISMATCH")
end

function tests.noncanonical_base64_is_refused_even_when_its_checksum_matches()
    local f = fixture(); requireCodec(f)
    local payloads = {
        string.rep("A", 106) .. "B=", -- nonzero padding bits
        string.rep("A", 106) .. "==", -- two-byte tail needs one '='
        string.rep("A", 108), -- missing required padding
        string.rep("A", 106) .. "_=", -- URL alphabet is not canonical Base64
        string.rep("A", 106) .. "\n=",
        "=" .. string.rep("A", 106) .. "=",
        string.rep("A", 107), string.rep("A", 109),
        string.rep("A", 4096), "", "return os.execute('false')",
    }
    for _, payload in ipairs(payloads) do
        local digest = f.ns.Hash.SHA256("FMBStats\0v2\0" .. payload) or string.rep("0", 64)
        local result, code = f.api.Decode({schema = 2, payload = payload, digest = digest})
        equal(result, nil, "noncanonical payload must be refused")
        equal(code, "COUNTER_PAYLOAD_INVALID")
    end
end

function tests.invalid_digest_schema_and_storage_types_are_refused()
    local f = fixture(); requireCodec(f)
    local stored = assert(f.api.Encode(string.rep("\0", 80)))
    for _, digest in ipairs({"", string.rep("0", 63), string.rep("0", 65),
        string.rep("A", 64), string.rep("g", 64), 1, false, {}}) do
        stored.digest = digest
        local result, code = f.api.Decode(stored)
        equal(result, nil); equal(code, "COUNTER_DIGEST_INVALID")
    end
    stored.digest = nil
    local result, code = f.api.Decode(stored)
    equal(result, nil); equal(code, "COUNTER_DIGEST_INVALID")
    for _, schema in ipairs({1, 3, "2", false, {}, 0/0}) do
        result, code = f.api.Decode({schema = schema})
        equal(result, nil); equal(code, "COUNTER_SCHEMA_UNSUPPORTED")
    end
    result, code = f.api.Decode({})
    equal(result, nil); equal(code, "COUNTER_SCHEMA_UNSUPPORTED")
    for _, value in ipairs({1, "", false}) do
        result, code = f.api.Decode(value)
        equal(result, nil); equal(code, "COUNTER_STORAGE_INVALID")
    end
    result, code = f.api.Decode(nil)
    equal(result, nil); equal(code, "COUNTER_STORAGE_INVALID")
end

function tests.encode_accepts_only_public_binary_strings_of_exactly_eighty_bytes()
    local f = fixture(); requireCodec(f)
    for _, value in ipairs({"", string.rep("A", 79), string.rep("A", 81),
        string.rep("A", 100000), 1, false, {}}) do
        local result, code = f.api.Encode(value)
        equal(result, nil); equal(code, "COUNTER_BINARY_INVALID")
    end
    local result, code = f.api.Encode(nil)
    equal(result, nil); equal(code, "COUNTER_BINARY_INVALID")
    result, code = f.api.Encode(f.secret)
    equal(result, nil); equal(code, "COUNTER_DATA_RESTRICTED")
end

function tests.raw_field_reads_never_follow_metatables_or_enumerate_unknown_data()
    local f = fixture(); requireCodec(f)
    local bytes = string.rep("Z", 80)
    local stored = assert(f.api.Encode(bytes))
    stored.unrelated = f.secret
    setmetatable(stored, {
        __index = function() error("metatable followed") end,
        __pairs = function() error("table enumerated") end,
        __len = function() error("table length read") end,
    })
    equal(f.api.Decode(stored), bytes)
    rawset(stored, "schema", nil)
    local result, code = f.api.Decode(stored)
    equal(result, nil); equal(code, "COUNTER_SCHEMA_UNSUPPORTED")
end

function tests.secret_or_inaccessible_inputs_fail_closed_without_interrogating_values()
    local f = fixture(); requireCodec(f)
    for _, value in ipairs({f.secret, f.opaque}) do
        local result, code = f.api.Decode(value)
        equal(result, nil); equal(code, "COUNTER_DATA_RESTRICTED")
    end
    for _, key in ipairs({"schema", "payload", "digest"}) do
        local stored = assert(f.api.Encode(string.rep("\0", 80)))
        stored[key] = f.secret
        local result, code = f.api.Decode(stored)
        equal(result, nil); equal(code, "COUNTER_DATA_RESTRICTED")
    end
end

function tests.missing_or_broken_public_guards_fail_closed_without_raw_error_leaks()
    for _, mode in ipairs({"secret_missing", "secret_throws", "secret_wrong",
        "access_missing", "access_throws", "access_secret", "access_wrong"}) do
        local f = fixture(); requireCodec(f)
        local stored = assert(f.api.Encode(string.rep("\0", 80)))
        if mode == "secret_missing" then f.env.issecretvalue = false
        elseif mode == "secret_throws" then f.env.issecretvalue = function() error("private") end
        elseif mode == "secret_wrong" then f.env.issecretvalue = function() return "false" end
        elseif mode == "access_missing" then f.env.canaccesstable = false
        elseif mode == "access_throws" then f.env.canaccesstable = function() error("private") end
        elseif mode == "access_secret" then f.env.canaccesstable = function() return f.secret end
        else f.env.canaccesstable = function() return "true" end end
        local result, code = f.api.Decode(stored)
        equal(result, nil); equal(code, "COUNTER_DATA_RESTRICTED")
    end
end

function tests.hash_input_is_bounded_and_secret_values_are_never_hashed()
    local f = fixture(); requireCodec(f)
    local result, code = f.ns.Hash.SHA256(string.rep("A", 4097))
    equal(result, nil); equal(code, "HASH_INPUT_TOO_LARGE")
    result, code = f.ns.Hash.SHA256(f.secret)
    equal(result, nil); equal(code, "HASH_DATA_RESTRICTED")
    result, code = f.ns.Hash.SHA256({})
    equal(result, nil); equal(code, "HASH_INPUT_INVALID")
    result, code = f.ns.Hash.SHA256(nil)
    equal(result, nil); equal(code, "HASH_INPUT_INVALID")
    f.env.issecretvalue = false
    result, code = f.ns.Hash.SHA256("abc")
    equal(result, nil); equal(code, "HASH_DATA_RESTRICTED")
end

function tests.hash_unavailability_never_yields_an_unchecked_payload()
    local f = fixture(); requireCodec(f)
    local data = string.rep("\0", 80)
    local stored = assert(f.api.Encode(data))
    for _, replacement in ipairs({false, {}, {SHA256 = function() error("private failure") end},
        {SHA256 = function() return "invalid" end}, {SHA256 = function() return f.secret end}}) do
        f.ns.Hash = replacement
        local encoded, code = f.api.Encode(data)
        equal(encoded, nil); equal(code, "COUNTER_HASH_UNAVAILABLE")
        local decoded
        decoded, code = f.api.Decode(stored)
        equal(decoded, nil); equal(code, "COUNTER_HASH_UNAVAILABLE")
    end
end

function tests.a_new_valid_checksum_can_be_forged_and_is_never_called_authentication()
    local f = fixture(); requireCodec(f)
    local stored = assert(f.api.Encode(string.rep("\0", 80)))
    -- An owner can calculate a fresh checksum; this documents the explicit
    -- boundary instead of suggesting that an unkeyed hash proves gameplay.
    stored.payload = "B" .. stored.payload:sub(2)
    stored.digest = f.ns.Hash.SHA256("FMBStats\0v2\0" .. stored.payload)
    local decoded = assert(f.api.Decode(stored))
    equal(#decoded, 80); assert(decoded ~= string.rep("\0", 80))
end

local names = {}
for name in pairs(tests) do
    if not arg[1] or arg[1] == name then names[#names + 1] = name end
end
assert(#names > 0, "unknown test filter")
table.sort(names)
local failures = 0
for _, name in ipairs(names) do
    local ok, err = pcall(tests[name])
    if ok then print("PASS " .. name)
    else failures = failures + 1; print("FAIL " .. name .. ": " .. err) end
end
print(string.format("CounterCodec: %d passed, %d failed", #names - failures, failures))
if failures > 0 then os.exit(1) end
