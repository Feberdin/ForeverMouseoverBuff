/* Purpose: deterministic browser-upload contracts with synthetic exports/responses.
 * Input: pure production core and fake HTTP boundary. Output: Node test assertions.
 * No browser storage, accounts or external network; node --test this file. */
const { test } = require("node:test");
const assert = require("node:assert/strict");
const core = require("../static/upload-core.js");
const NOW = 1791763200;
const origin = "http://127.0.0.1:18449";
const session = {
  participantId: "a".repeat(32),
  token: "x".repeat(43),
  trust: "self_reported",
};
const event = (id = 1, spellId = 19740, eventTime = NOW) => ({
  id: `1791763200-${id}`,
  spellId,
  eventTime,
});
const value = (events = [event()]) => ({
  schema: 1,
  enabled: true,
  casterClass: "PALADIN",
  events,
});
const fail = (action, code) =>
  assert.throws(action, (error) => error.code === code);
function transport(responses) {
  const calls = [];
  const fetch = async (path, options) => {
    calls.push({ path, options });
    const item = responses.shift();
    if (item instanceof Error) throw item;
    return {
      ok: item.status >= 200 && item.status < 300,
      status: item.status,
      headers: { get: () => "application/json" },
      text: async () => JSON.stringify(item.body),
    };
  };
  return { calls, client: core.createClient(fetch, origin, () => NOW) };
}

test("preview exposes only detached known events with families and expired count", () => {
  const original = value([
    event(1),
    event(2, 19834),
    event(3, 19742),
    event(4, 20217),
    event(5, 19740, NOW - 604801),
  ]);
  const preview = core.parseExport(JSON.stringify(original), NOW);
  assert.equal(preview.events.length, 4);
  assert.equal(preview.expired, 1);
  assert.deepEqual(preview.families, { might: 2, wisdom: 1, kings: 1 });
  assert.equal(preview.first, NOW);
  assert.equal(preview.last, NOW);
  assert.equal(preview.total, 5);
  assert.deepEqual(Object.keys(preview.events[0]).sort(), [
    "eventTime",
    "id",
    "spellId",
  ]);
  original.events[0].spellId = 999;
  assert.equal(preview.events[0].spellId, 19740);
});
test("strict file parser rejects extra fields duplicates executable Lua and malformed data", () => {
  for (const text of [
    '{"schema":1,"schema":1}',
    'ForeverMouseoverBuffRankingExport="x"',
    '{"x":NaN}',
    "{} trailing",
    "[".repeat(70) + "]".repeat(70),
  ])
    fail(() => core.parseExport(text, NOW), "EXPORT_INVALID");
  for (const bad of [
    { ...value(), count: 1000000 },
    value([{ ...event(), recipient: "private" }]),
    value([event(1, 999)]),
    value([event(), event()]),
    value([event(1, 19740, NOW + 301)]),
    { ...value(), enabled: false },
    value([event(1, 19740, true)]),
  ])
    fail(() => core.parseExport(JSON.stringify(bad), NOW), "EXPORT_INVALID");
  fail(() => core.parseExport(" ".repeat(1048577), NOW), "FILE_TOO_LARGE");
  assert.equal(
    core.parseExport(JSON.stringify({ ...value([]), enabled: false }), NOW)
      .enabled,
    false,
  );
});
test("access files are endpoint-bound and stripped of companion paths", () => {
  const saved = {
    schema: 1,
    endpoint: origin,
    participantId: session.participantId,
    token: session.token,
    consent: true,
    savedVariables: "/synthetic/private/path",
  };
  assert.deepEqual(core.parseAccess(JSON.stringify(saved), origin), session);
  const backup = core.backupAccess(session, origin);
  assert.deepEqual(core.parseAccess(backup, origin), session);
  assert.equal(backup.includes("savedVariables"), false);
  fail(
    () => core.parseAccess(backup, "http://localhost:18449"),
    "ACCESS_ENDPOINT",
  );
  fail(
    () => core.parseAccess(JSON.stringify({ ...saved, token: "bad" }), origin),
    "ACCESS_INVALID",
  );
});
test("enrollment requires consent and validates identity without unsafe text", () => {
  fail(() => core.enrollment("Synthetic", "Realm", false), "CONSENT_REQUIRED");
  for (const name of ["<script>", "bad\nname", "X\ud800", "x"])
    fail(() => core.enrollment(name, "Realm", true), "IDENTITY_INVALID");
  assert.deepEqual(core.enrollment("Synthetic", "Realm", true), {
    displayName: "Synthetic",
    realm: "Realm",
    casterClass: "PALADIN",
    consent: true,
  });
});
test("upload requires consent before network and sends selected event fields only", async () => {
  const preview = core.parseExport(JSON.stringify(value()), NOW);
  const flow = transport([
    {
      status: 200,
      body: {
        accepted: 1,
        duplicates: 0,
        quarantined: 0,
        trust: "self_reported",
      },
    },
  ]);
  await assert.rejects(
    flow.client.upload(preview, session, false),
    (e) => e.code === "CONSENT_REQUIRED",
  );
  assert.equal(flow.calls.length, 0);
  const result = await flow.client.upload(preview, session, true);
  assert.equal(result.accepted, 1);
  assert.equal(flow.calls[0].path, "/v1/events");
  assert.deepEqual(JSON.parse(flow.calls[0].options.body), {
    events: [event()],
  });
  assert.equal(
    flow.calls[0].options.headers.Authorization,
    "Bearer " + session.token,
  );
  assert.equal(flow.calls[0].options.redirect, "error");
  assert.equal(flow.calls[0].options.credentials, "omit");
});
test("batches are bounded and partial failures keep confirmed counts explicit", async () => {
  const preview = core.parseExport(
    JSON.stringify(
      value(
        Array.from({ length: 101 }, (_, i) => event(i + 1, 19740, NOW - i * 2)),
      ),
    ),
    NOW,
  );
  const flow = transport([
    {
      status: 200,
      body: {
        accepted: 60,
        duplicates: 30,
        quarantined: 10,
        trust: "self_reported",
      },
    },
    { status: 409, body: { error: "ID_CONFLICT", trust: "self_reported" } },
  ]);
  await assert.rejects(
    flow.client.upload(preview, session, true),
    (e) =>
      e.code === "ID_CONFLICT" &&
      e.progress.accepted === 60 &&
      e.progress.duplicates === 30,
  );
  assert.deepEqual(
    flow.calls.map((c) => JSON.parse(c.options.body).events.length),
    [100, 1],
  );
});
test("invalid server counts never claim successful upload and delete needs confirmation", async () => {
  const flow = transport([
    {
      status: 200,
      body: {
        accepted: 1000000,
        duplicates: 0,
        quarantined: 0,
        trust: "self_reported",
      },
    },
    { status: 200, body: { deleted: true, trust: "self_reported" } },
  ]);
  await assert.rejects(
    flow.client.upload(
      core.parseExport(JSON.stringify(value()), NOW),
      session,
      true,
    ),
    (e) => e.code === "RESPONSE_INVALID",
  );
  await assert.rejects(
    flow.client.remove(session, false),
    (e) => e.code === "DELETE_CONFIRM",
  );
  assert.equal(flow.calls.length, 1);
  assert.equal((await flow.client.remove(session, true)).deleted, true);
});
test("profile and new enrollment validate server contracts without exposing tokens in errors", async () => {
  const profile = {
    participantId: session.participantId,
    displayName: "Synthetic",
    realm: "Realm",
    casterClass: "PALADIN",
    trust: "self_reported",
  };
  const flow = transport([
    { status: 201, body: session },
    { status: 200, body: profile },
    { status: 401, body: { error: "AUTH_REQUIRED", message: session.token } },
  ]);
  assert.deepEqual(
    await flow.client.enroll("Synthetic", "Realm", true),
    session,
  );
  assert.deepEqual(await flow.client.profile(session), profile);
  await assert.rejects(
    flow.client.profile(session),
    (e) => e.code === "AUTH_REQUIRED" && !e.message.includes(session.token),
  );
});

test("missing preview uses a fixed actionable error before any network request", async () => {
  const flow = transport([]);
  await assert.rejects(
    flow.client.upload(null, session, true),
    (e) => e.code === "EXPORT_EMPTY",
  );
  assert.equal(flow.calls.length, 0);
});
