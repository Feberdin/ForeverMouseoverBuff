/* Purpose: validate minimal ranking files and same-origin upload contracts.
 * Input: JSON text, explicit consent, in-memory access. Output: preview or bounded
 * API calls. No Lua execution, browser persistence, console logging or auto-enroll.
 * Debug: fixed error.code values; node --test service/tests/test_upload_core.cjs. */
(function (root) {
  "use strict";
  const families = {
    might: [
      19740, 19834, 19835, 19836, 19837, 19838, 25291, 27140, 48931, 48932,
    ],
    wisdom: [19742, 19850, 19852, 19853, 19854, 25290, 27142, 48935, 48936],
    kings: [20217],
  };
  const spells = new Map(
    Object.entries(families).flatMap(([name, ids]) =>
      ids.map((id) => [id, name]),
    ),
  );
  const fail = (code) => {
    const error = new Error(code);
    error.code = code;
    throw error;
  };
  const bytes = (text) => new TextEncoder().encode(text).length;
  function exact(value, keys) {
    return (
      value !== null &&
      typeof value === "object" &&
      !Array.isArray(value) &&
      Object.keys(value).length === keys.length &&
      keys.every((key) => Object.hasOwn(value, key))
    );
  }

  // A small JSON-only reader notices duplicate keys before they can disappear in
  // JSON.parse. It never evaluates input and limits nesting/token count/file size.
  function strictJSON(text, limit = 1048576) {
    if (typeof text !== "string" || bytes(text) > limit) fail("FILE_TOO_LARGE");
    let position = 0,
      tokens = 0;
    const white = () => {
      while (position < text.length && /[ \t\r\n]/.test(text[position]))
        position++;
    };
    function string() {
      const start = position++;
      while (position < text.length) {
        const character = text[position++];
        if (character === '"') {
          try {
            return JSON.parse(text.slice(start, position));
          } catch (_) {
            fail("EXPORT_INVALID");
          }
        }
        if (character === "\\") position++;
      }
      fail("EXPORT_INVALID");
    }
    function read(depth = 0) {
      if (++tokens > 20000 || depth > 32) fail("EXPORT_INVALID");
      white();
      const character = text[position];
      if (character === '"') return string();
      if (character === "{" || character === "[") {
        const object = character === "{" ? Object.create(null) : [];
        const close = character === "{" ? "}" : "]";
        position++;
        white();
        if (text[position] === close) {
          position++;
          return object;
        }
        while (position < text.length) {
          white();
          if (character === "{") {
            if (text[position] !== '"') fail("EXPORT_INVALID");
            const key = string();
            white();
            if (text[position++] !== ":" || Object.hasOwn(object, key))
              fail("EXPORT_INVALID");
            object[key] = read(depth + 1);
          } else object.push(read(depth + 1));
          white();
          if (text[position] === close) {
            position++;
            return object;
          }
          if (text[position++] !== ",") fail("EXPORT_INVALID");
        }
        fail("EXPORT_INVALID");
      }
      const match =
        /^(?:true|false|null|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)/.exec(
          text.slice(position),
        );
      if (!match) fail("EXPORT_INVALID");
      position += match[0].length;
      const value = JSON.parse(match[0]);
      if (typeof value === "number" && !Number.isFinite(value))
        fail("EXPORT_INVALID");
      return value;
    }
    const result = read();
    white();
    if (position !== text.length) fail("EXPORT_INVALID");
    return result;
  }

  function parseExport(text, now = Math.floor(Date.now() / 1000)) {
    const value = strictJSON(text);
    if (
      !Number.isSafeInteger(now) ||
      now <= 0 ||
      !exact(value, ["schema", "enabled", "casterClass", "events"]) ||
      value.schema !== 1 ||
      typeof value.enabled !== "boolean" ||
      value.casterClass !== "PALADIN" ||
      !Array.isArray(value.events) ||
      value.events.length > 1000 ||
      (!value.enabled && value.events.length)
    )
      fail("EXPORT_INVALID");
    const result = {
      enabled: value.enabled,
      total: value.events.length,
      events: [],
      expired: 0,
      families: { might: 0, wisdom: 0, kings: 0 },
      first: null,
      last: null,
    };
    const ids = new Set();
    for (const event of value.events) {
      if (
        !exact(event, ["id", "spellId", "eventTime"]) ||
        typeof event.id !== "string" ||
        !/^[A-Za-z0-9_-]{8,96}$/.test(event.id) ||
        ids.has(event.id) ||
        !Number.isSafeInteger(event.spellId) ||
        !spells.has(event.spellId) ||
        !Number.isSafeInteger(event.eventTime) ||
        event.eventTime < 1 ||
        event.eventTime > 4102444800 ||
        event.eventTime > now + 300
      )
        fail("EXPORT_INVALID");
      ids.add(event.id);
      if (event.eventTime < now - 604800) {
        result.expired++;
        continue;
      }
      result.events.push({
        id: event.id,
        spellId: event.spellId,
        eventTime: event.eventTime,
      });
      result.families[spells.get(event.spellId)]++;
      result.first =
        result.first === null
          ? event.eventTime
          : Math.min(result.first, event.eventTime);
      result.last =
        result.last === null
          ? event.eventTime
          : Math.max(result.last, event.eventTime);
    }
    return result;
  }
  function access(value) {
    if (
      !exact(value, ["participantId", "token", "trust"]) ||
      value.trust !== "self_reported" ||
      typeof value.participantId !== "string" ||
      !/^[a-f0-9]{32}$/.test(value.participantId) ||
      typeof value.token !== "string" ||
      !/^[A-Za-z0-9_-]{43}$/.test(value.token)
    )
      fail("ACCESS_INVALID");
    return {
      participantId: value.participantId,
      token: value.token,
      trust: "self_reported",
    };
  }
  function parseAccess(text, origin) {
    let value;
    try {
      value = strictJSON(text, 16384);
    } catch (_) {
      fail("ACCESS_INVALID");
    }
    const browser = exact(value, [
      "schema",
      "endpoint",
      "participantId",
      "token",
      "trust",
    ]);
    const companion = exact(value, [
      "schema",
      "endpoint",
      "participantId",
      "token",
      "savedVariables",
      "consent",
    ]);
    if (
      (!browser && !companion) ||
      value.schema !== 1 ||
      (companion &&
        (value.consent !== true || typeof value.savedVariables !== "string"))
    )
      fail("ACCESS_INVALID");
    if (value.endpoint !== origin) fail("ACCESS_ENDPOINT");
    return access({
      participantId: value.participantId,
      token: value.token,
      trust: browser ? value.trust : "self_reported",
    });
  }
  function backupAccess(value, origin) {
    return (
      JSON.stringify(
        { schema: 1, endpoint: origin, ...access(value) },
        null,
        2,
      ) + "\n"
    );
  }
  function name(value, realm = false) {
    if (typeof value !== "string") fail("IDENTITY_INVALID");
    const normalized = value.normalize("NFC");
    if (
      normalized !== normalized.trim() ||
      normalized.length < 2 ||
      normalized.length > 64 ||
      bytes(normalized) > 96 ||
      !(realm ? /^[\p{L}\p{N} '_-]+$/u : /^[\p{L} '-]+$/u).test(normalized) ||
      !/[\p{L}]/u.test(normalized)
    )
      fail("IDENTITY_INVALID");
    return normalized;
  }
  function enrollment(displayName, realm, consent) {
    if (consent !== true) fail("CONSENT_REQUIRED");
    return {
      displayName: name(displayName),
      realm: name(realm, true),
      casterClass: "PALADIN",
      consent: true,
    };
  }
  function createClient(
    fetcher,
    origin,
    clock = () => Math.floor(Date.now() / 1000),
  ) {
    async function request(method, path, body, session) {
      const headers = { Accept: "application/json" };
      if (body !== undefined) headers["Content-Type"] = "application/json";
      if (session) headers.Authorization = "Bearer " + access(session).token;
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 10000);
      try {
        const response = await fetcher(path, {
          method,
          headers,
          body: body === undefined ? undefined : JSON.stringify(body),
          signal: controller.signal,
          cache: "no-store",
          credentials: "omit",
          redirect: "error",
        });
        if (
          !response.headers.get("Content-Type")?.startsWith("application/json")
        )
          fail("RESPONSE_INVALID");
        let result;
        try {
          result = strictJSON(await response.text(), 32768);
        } catch (_) {
          fail("RESPONSE_INVALID");
        }
        if (!response.ok) {
          const known = new Set([
            "AUTH_REQUIRED",
            "CONSENT_REQUIRED",
            "IDENTITY_EXISTS",
            "ID_CONFLICT",
            "RATE_LIMIT",
            "EVENT_TIME_WINDOW",
            "SPELL_UNSUPPORTED",
            "INVALID_FIELDS",
          ]);
          fail(known.has(result.error) ? result.error : "REQUEST_FAILED");
        }
        return { status: response.status, value: result };
      } catch (error) {
        if (error.code) throw error;
        fail("NETWORK_FAILED");
      } finally {
        clearTimeout(timer);
      }
    }
    return {
      async enroll(displayName, realm, consent) {
        const result = await request(
          "POST",
          "/v1/participants",
          enrollment(displayName, realm, consent),
        );
        if (result.status !== 201) fail("RESPONSE_INVALID");
        return access(result.value);
      },
      async profile(session) {
        const result = (
          await request("GET", "/v1/participant", undefined, session)
        ).value;
        if (
          !exact(result, [
            "participantId",
            "displayName",
            "realm",
            "casterClass",
            "trust",
          ]) ||
          result.participantId !== access(session).participantId ||
          result.casterClass !== "PALADIN" ||
          result.trust !== "self_reported"
        )
          fail("RESPONSE_INVALID");
        return {
          participantId: result.participantId,
          displayName: name(result.displayName),
          realm: name(result.realm, true),
          casterClass: "PALADIN",
          trust: "self_reported",
        };
      },
      async upload(preview, session, consent, progress = () => {}) {
        if (consent !== true) fail("CONSENT_REQUIRED");
        if (
          !preview ||
          typeof preview !== "object" ||
          !Array.isArray(preview.events)
        )
          fail("EXPORT_EMPTY");
        // Revalidate the snapshot before sending; mutations by local scripts do
        // not accidentally expand the HTTP schema (they are not anti-cheat proof).
        const checked = parseExport(
          JSON.stringify({
            schema: 1,
            enabled: preview.enabled,
            casterClass: "PALADIN",
            events: preview.events,
          }),
          clock(),
        );
        if (!checked.enabled || !checked.events.length) fail("EXPORT_EMPTY");
        if (checked.expired) fail("PREVIEW_EXPIRED");
        access(session);
        const totals = {
          accepted: 0,
          duplicates: 0,
          quarantined: 0,
          trust: "self_reported",
        };
        try {
          for (let offset = 0; offset < checked.events.length; offset += 100) {
            const batch = checked.events.slice(offset, offset + 100);
            const result = (
              await request("POST", "/v1/events", { events: batch }, session)
            ).value;
            if (
              !exact(result, [
                "accepted",
                "duplicates",
                "quarantined",
                "trust",
              ]) ||
              result.trust !== "self_reported" ||
              !["accepted", "duplicates", "quarantined"].every(
                (key) => Number.isSafeInteger(result[key]) && result[key] >= 0,
              ) ||
              result.accepted + result.duplicates + result.quarantined !==
                batch.length
            )
              fail("RESPONSE_INVALID");
            for (const key of ["accepted", "duplicates", "quarantined"])
              totals[key] += result[key];
            progress({ ...totals });
          }
        } catch (error) {
          error.progress = { ...totals };
          throw error;
        }
        return totals;
      },
      async remove(session, confirmed) {
        if (confirmed !== true) fail("DELETE_CONFIRM");
        const result = (
          await request("DELETE", "/v1/participant", undefined, session)
        ).value;
        if (
          !exact(result, ["deleted", "trust"]) ||
          result.deleted !== true ||
          result.trust !== "self_reported"
        )
          fail("RESPONSE_INVALID");
        return { deleted: true, trust: "self_reported" };
      },
    };
  }
  const api = {
    parseExport,
    parseAccess,
    backupAccess,
    enrollment,
    createClient,
  };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.FMBUpload = api;
})(typeof globalThis !== "undefined" ? globalThis : this);
