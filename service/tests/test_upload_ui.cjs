/* Purpose: run the real browser wizard against an instrumented DOM and HTTP boundary.
 * Inputs are synthetic File objects and responses. Outputs prove preview/consent,
 * credential lifetime, explicit backup and deletion behavior without live accounts.
 * Run: node --test service/tests/test_upload_ui.cjs. */
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const NOW = 1791763200;
const session = {
  participantId: "a".repeat(32),
  token: "x".repeat(43),
  trust: "self_reported",
};
const identity = {
  participantId: session.participantId,
  displayName: "Synthetic",
  realm: "Realm",
  casterClass: "PALADIN",
  trust: "self_reported",
};
const exportValue = {
  schema: 1,
  enabled: true,
  casterClass: "PALADIN",
  events: [{ id: "1791763200-1", spellId: 19740, eventTime: NOW }],
};
function fixture(responses = []) {
  const calls = [],
    downloads = [],
    statusReads = [];
  class Element {
    constructor() {
      this.listeners = {};
      this.value = "";
      this.checked = false;
      this.disabled = false;
      this.files = [];
      this.children = [];
      this.textContent = "";
    }
    addEventListener(event, callback) {
      this.listeners[event] = callback;
    }
    appendChild(element) {
      this.children.push(element);
    }
    click() {
      if (this.download) downloads.push(this.download);
      return this.listeners.click?.();
    }
    remove() {}
    set innerHTML(_) {
      throw new Error("HTML interpolation forbidden");
    }
  }
  const ids = [
    "ranking-file",
    "upload-preview",
    "access-file",
    "enroll-name",
    "enroll-realm",
    "enroll-consent",
    "enroll-send",
    "access-status",
    "access-backup",
    "access-forget",
    "upload-consent",
    "upload-send",
    "delete-consent",
    "access-delete",
    "upload-status",
  ];
  const elements = Object.fromEntries(ids.map((id) => [id, new Element()]));
  const blobs = [];
  const url = {
    createObjectURL(blob) {
      blobs.push(blob);
      return "blob:synthetic";
    },
    revokeObjectURL() {},
  };
  class TestDate extends Date {
    constructor(...args) {
      super(...(args.length ? args : [NOW * 1000]));
    }
    static now() {
      return NOW * 1000;
    }
  }
  const sandbox = {
    document: {
      getElementById: (id) => elements[id],
      createElement: () => new Element(),
      body: new Element(),
    },
    location: { origin: "http://127.0.0.1:18449" },
    Date: TestDate,
    TextEncoder,
    AbortController,
    Blob,
    URL: url,
    addEventListener() {},
    setTimeout,
    clearTimeout,
    loadRanking() {
      statusReads.push(true);
    },
    fetch: async (url, options) => {
      calls.push({ url, options });
      const response = responses.shift();
      if (!response) throw new Error("Unexpected request");
      return {
        ok: response.status >= 200 && response.status < 300,
        status: response.status,
        headers: { get: () => "application/json" },
        text: async () => JSON.stringify(response.body),
      };
    },
  };
  for (const property of ["localStorage", "sessionStorage", "indexedDB"])
    Object.defineProperty(sandbox, property, {
      get() {
        throw new Error("Persistent credential storage forbidden");
      },
    });
  vm.createContext(sandbox);
  for (const file of ["upload-core.js", "upload.js"])
    vm.runInContext(
      fs.readFileSync(path.join(__dirname, "../static", file), "utf8"),
      sandbox,
    );
  async function file(id, value, name = "synthetic.json") {
    const text = typeof value === "string" ? value : JSON.stringify(value);
    elements[id].files = [
      { name, size: Buffer.byteLength(text), text: async () => text },
    ];
    await elements[id].listeners.change();
  }
  async function consent(id) {
    elements[id].checked = true;
    await elements[id].listeners.change();
  }
  return { elements, calls, downloads, blobs, statusReads, file, consent };
}
test("file preview sends nothing and malformed or wrong file selections clear previous preview", async () => {
  const f = fixture();
  await f.file("ranking-file", exportValue);
  assert.match(f.elements["upload-preview"].textContent, /1 übertragbar/);
  assert.equal(f.calls.length, 0);
  await f.consent("upload-consent");
  assert.equal(f.elements["upload-send"].disabled, true);
  await f.file(
    "ranking-file",
    'os.execute("private")',
    "ForeverMouseoverBuff.lua",
  );
  assert.equal(f.calls.length, 0);
  assert.equal(f.elements["upload-send"].disabled, true);
  assert.match(f.elements["upload-status"].textContent, /json-Datei/);
  await f.file("ranking-file", '{"schema":1,"schema":2}');
  assert.match(f.elements["upload-status"].textContent, /keinen gültigen/);
});
test("existing access validates only against same service and upload is consent-gated", async () => {
  const f = fixture([
    { status: 200, body: identity },
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
  await f.file("ranking-file", exportValue);
  await f.file("access-file", {
    schema: 1,
    endpoint: "http://127.0.0.1:18449",
    ...session,
  });
  assert.equal(f.calls[0].url, "/v1/participant");
  assert.equal(f.calls[0].options.body, undefined);
  assert.match(f.elements["access-status"].textContent, /Synthetic/);
  await f.elements["upload-send"].listeners.click();
  assert.equal(f.calls.length, 1);
  await f.consent("upload-consent");
  assert.equal(f.elements["upload-send"].disabled, false);
  await f.elements["upload-send"].listeners.click();
  assert.equal(f.calls.length, 2);
  assert.deepEqual(JSON.parse(f.calls[1].options.body), {
    events: exportValue.events,
  });
  assert.match(f.elements["upload-status"].textContent, /1 neue Meldungen/);
  assert.equal(
    f.elements["upload-status"].textContent.includes(session.token),
    false,
  );
  assert.equal(f.statusReads.length, 1);
  assert.equal(f.downloads.length, 0);
});
test("new enrollment is explicit and access backup occurs only after its own click", async () => {
  const f = fixture([{ status: 201, body: session }]);
  await f.file("ranking-file", exportValue);
  f.elements["enroll-name"].value = "Synthetic";
  f.elements["enroll-realm"].value = "Realm";
  await f.elements["enroll-send"].listeners.click();
  assert.equal(f.calls.length, 0);
  await f.consent("enroll-consent");
  await f.elements["enroll-send"].listeners.click();
  assert.equal(f.calls.length, 1);
  assert.equal(f.calls[0].url, "/v1/participants");
  assert.equal(JSON.parse(f.calls[0].options.body).consent, true);
  assert.equal(f.downloads.length, 0);
  f.elements["access-forget"].listeners.click();
  assert.match(f.elements["upload-status"].textContent, /noch nicht gesichert/);
  f.elements["access-backup"].listeners.click();
  assert.deepEqual(f.downloads, ["fmb-ranking-zugang.json"]);
  const backup = JSON.parse(await f.blobs[0].text());
  assert.equal(backup.token, session.token);
  assert.equal(backup.savedVariables, undefined);
  f.elements["access-forget"].listeners.click();
  assert.equal(f.elements["access-backup"].disabled, true);
  assert.match(
    f.elements["upload-status"].textContent,
    /aus dieser Seitensitzung entfernt/,
  );
});
test("delete requires its own confirmation and failed requests keep access in memory", async () => {
  const f = fixture([
    { status: 200, body: identity },
    { status: 503, body: { message: session.token } },
    { status: 200, body: { deleted: true, trust: "self_reported" } },
  ]);
  await f.file("access-file", {
    schema: 1,
    endpoint: "http://127.0.0.1:18449",
    ...session,
  });
  await f.elements["access-delete"].listeners.click();
  assert.equal(f.calls.length, 1);
  await f.consent("delete-consent");
  await f.elements["access-delete"].listeners.click();
  assert.equal(f.elements["access-backup"].disabled, false);
  assert.equal(
    f.elements["upload-status"].textContent.includes(session.token),
    false,
  );
  await f.elements["access-delete"].listeners.click();
  assert.equal(f.calls[2].options.method, "DELETE");
  assert.equal(f.elements["access-backup"].disabled, true);
  assert.match(f.elements["upload-status"].textContent, /gelöscht/);
});
test("a credential for another origin never reaches the network", async () => {
  const f = fixture();
  await f.file("access-file", {
    schema: 1,
    endpoint: "https://other.invalid",
    ...session,
  });
  assert.equal(f.calls.length, 0);
  assert.match(
    f.elements["upload-status"].textContent,
    /anderen Dienstadresse/,
  );
});
