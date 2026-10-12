/* Purpose: voluntary upload wizard for an already minimized ranking JSON file.
 * Input: user-selected local files and explicit consent clicks. Output: preview,
 * same-origin API requests, and an access backup only on its own download click.
 * Invariants: credentials live only in closure RAM; no automatic enrollment or
 * upload, no raw Lua transfer/execution, no identity/token/error logging.
 * Debug: visible fixed-code hints; service/tests/test_upload_ui.cjs. */
(function () {
  "use strict";
  const core = globalThis.FMBUpload;
  const byId = (id) => document.getElementById(id);
  const elements = {
    file: byId("ranking-file"),
    preview: byId("upload-preview"),
    accessFile: byId("access-file"),
    name: byId("enroll-name"),
    realm: byId("enroll-realm"),
    enrollConsent: byId("enroll-consent"),
    enroll: byId("enroll-send"),
    identity: byId("access-status"),
    backup: byId("access-backup"),
    forget: byId("access-forget"),
    uploadConsent: byId("upload-consent"),
    send: byId("upload-send"),
    deleteConsent: byId("delete-consent"),
    remove: byId("access-delete"),
    status: byId("upload-status"),
  };
  const client = core.createClient(
    globalThis.fetch.bind(globalThis),
    globalThis.location.origin,
  );
  let preview = null,
    session = null,
    profile = null,
    busy = false,
    selection = 0,
    backupRequested = true;
  const hints = {
    EXPORT_INVALID:
      "Die Datei enthält keinen gültigen FMB-Ranking-Export. Erzeuge eine neue JSON-Datei mit dem Companion; keine .lua-Datei auswählen.",
    FILE_TOO_LARGE:
      "Die Datei ist zu groß. Erlaubt sind bis zu 1 MiB für den Ranking-Export und 16 KiB für den Zugang.",
    FILE_INVALID: "Bitte eine einzelne lesbare .json-Datei auswählen.",
    ACCESS_INVALID:
      "Diese Datei ist kein gültiger Ranking-Zugang. Wähle Deine Zugangssicherung oder die Companion-Konfiguration.",
    ACCESS_ENDPOINT:
      "Dieser Zugang gehört zu einer anderen Dienstadresse. Öffne die dazugehörige Seite; Zugangsdaten werden nicht an fremde Dienste gesendet.",
    IDENTITY_INVALID:
      "Name und Realm müssen gültige sichtbare Namen mit 2–64 Zeichen sein.",
    CONSENT_REQUIRED:
      "Bestätige vor dieser Aktion die zugehörige freiwillige Zustimmung.",
    DELETE_CONFIRM:
      "Bestätige zuerst, dass Du Deine Teilnahme und alle hochgeladenen Ereignisse löschen möchtest.",
    AUTH_REQUIRED:
      "Dieser Zugang ist ungültig oder bereits gelöscht. Lade den passenden Zugang; die Seite meldet Dich nicht automatisch neu an.",
    IDENTITY_EXISTS:
      "Dieser Name und Realm sind schon angemeldet. Lade den bestehenden Zugang. Es wird kein Ersatzkonto angelegt.",
    ID_CONFLICT:
      "Eine Ereignis-ID hat beim Dienst schon andere Daten. Datei nicht verändern; einen neuen unveränderten Export prüfen.",
    RATE_LIMIT: "Zu viele Anfragen. Warte vor einem erneuten Versuch.",
    EVENT_TIME_WINDOW:
      "Der Export ist veraltet oder die Uhr stimmt nicht. Erzeuge eine aktuelle Datei.",
    EXPORT_EMPTY:
      "Keine übertragbaren Ereignisse vorhanden oder der Export ist ausgeschaltet.",
    RESPONSE_INVALID:
      "Die Antwort des Dienstes passt nicht zum Vertrag. Eine unklare Übertragung wird nicht als Erfolg angezeigt.",
    REQUEST_FAILED:
      "Der Dienst hat die Anfrage abgelehnt. Prüfe den lokalen Dienst und versuche es nach Behebung erneut.",
    NETWORK_FAILED:
      "Der lokale Dienst ist nicht erreichbar oder hat nicht rechtzeitig geantwortet. Ein erneuter Upload erkennt bereits gespeicherte Ereignisse.",
    PREVIEW_EXPIRED:
      "Seit der Vorschau sind Ereignisse veraltet. Wähle die Datei erneut, um die aktualisierte Vorschau zu prüfen.",
  };
  function showError(error) {
    let message =
      hints[error.code] ||
      "Die Aktion konnte nicht abgeschlossen werden. Prüfe Datei und lokalen Dienst.";
    if (error.progress)
      message += ` Bereits bestätigt: ${error.progress.accepted} angenommen, ${error.progress.duplicates} doppelt, ${error.progress.quarantined} in Quarantäne. Das letzte Paket kann einen unklaren Ausgang haben.`;
    elements.status.textContent = message;
  }
  function controls() {
    for (const element of [
      elements.file,
      elements.accessFile,
      elements.name,
      elements.realm,
      elements.enrollConsent,
      elements.uploadConsent,
      elements.deleteConsent,
    ])
      element.disabled = busy;
    elements.enroll.disabled =
      busy ||
      !!session ||
      !preview ||
      !preview.enabled ||
      !preview.events.length ||
      !elements.enrollConsent.checked;
    elements.send.disabled =
      busy ||
      !session ||
      !preview ||
      !preview.enabled ||
      !preview.events.length ||
      !elements.uploadConsent.checked;
    elements.backup.disabled = busy || !session;
    elements.forget.disabled = busy || !session;
    elements.remove.disabled =
      busy || !session || !elements.deleteConsent.checked;
    elements.identity.textContent = profile
      ? `Aktiver Zugang: ${profile.displayName} · ${profile.realm} (selbst angegeben).`
      : "Kein Zugang geladen. Ein neuer Teilnehmer wird erst auf Deinen Klick angelegt.";
  }
  async function action(work) {
    if (busy) return;
    busy = true;
    controls();
    try {
      await work();
    } catch (error) {
      showError(error);
    } finally {
      busy = false;
      controls();
    }
  }
  async function readFile(input, limit) {
    const file = input.files && input.files[0];
    if (
      !file ||
      input.files.length !== 1 ||
      !file.name.toLowerCase().endsWith(".json")
    )
      throw { code: "FILE_INVALID" };
    if (!Number.isSafeInteger(file.size) || file.size < 1 || file.size > limit)
      throw { code: "FILE_TOO_LARGE" };
    try {
      return await file.text();
    } catch (_) {
      throw { code: "FILE_INVALID" };
    }
  }
  function describe() {
    if (!preview) {
      elements.preview.textContent =
        "Noch keine Ranking-Datei ausgewählt. Die Auswahl allein sendet nichts.";
      return;
    }
    const count = preview.events.length;
    const period = count
      ? `${new Date(preview.first * 1000).toLocaleString("de-DE")} bis ${new Date(preview.last * 1000).toLocaleString("de-DE")}`
      : "kein übertragbarer Zeitraum";
    elements.preview.textContent = `${preview.total} Ereignisse in der Datei; ${count} übertragbar, ${preview.expired} älter als sieben Tage und ausgelassen. Macht: ${preview.families.might}, Weisheit: ${preview.families.wisdom}, Könige: ${preview.families.kings}. Zeitraum: ${period}. ${preview.enabled ? "Export eingeschaltet." : "Export ausgeschaltet – es wird nichts übertragen."}`;
  }
  elements.file.addEventListener("change", async () => {
    const current = ++selection;
    preview = null;
    elements.uploadConsent.checked = false;
    controls();
    describe();
    try {
      const text = await readFile(elements.file, 1048576);
      const value = core.parseExport(text);
      if (current !== selection) return;
      preview = value;
      describe();
      elements.status.textContent =
        "Datei nur lokal geprüft. Prüfe die Vorschau und wähle einen Zugang.";
    } catch (error) {
      if (current === selection) showError(error);
    } finally {
      if (current === selection) controls();
    }
  });
  elements.accessFile.addEventListener("change", () =>
    action(async () => {
      if (session) {
        elements.status.textContent =
          "Vergiss zuerst den aktiven Zugang, bevor Du eine andere Zugangsdatei lädst.";
        return;
      }
      const candidate = core.parseAccess(
        await readFile(elements.accessFile, 16384),
        globalThis.location.origin,
      );
      const identity = await client.profile(candidate);
      session = candidate;
      profile = identity;
      backupRequested = true;
      elements.uploadConsent.checked = false;
      elements.deleteConsent.checked = false;
      elements.status.textContent =
        "Zugang nur für diese Seitensitzung geladen. Noch keine Ereignisse übertragen.";
    }),
  );
  elements.enroll.addEventListener("click", () =>
    action(async () => {
      if (session || !preview || !preview.enabled || !preview.events.length)
        throw { code: "EXPORT_EMPTY" };
      const candidate = await client.enroll(
        elements.name.value,
        elements.realm.value,
        elements.enrollConsent.checked,
      );
      // Retain the new credential immediately, even if a later request fails. Its
      // only persistent copy is a backup the user explicitly requests below.
      session = candidate;
      profile = {
        displayName: elements.name.value,
        realm: elements.realm.value,
      };
      backupRequested = false;
      elements.enrollConsent.checked = false;
      elements.uploadConsent.checked = false;
      elements.status.textContent =
        "Teilnahme angelegt; noch keine Ereignisse übertragen. Sichere jetzt den Zugang über „Zugang sichern“, damit Du später hochladen oder löschen kannst.";
    }),
  );
  elements.backup.addEventListener("click", () => {
    if (!session || busy) return;
    try {
      const blob = new Blob(
        [core.backupAccess(session, globalThis.location.origin)],
        { type: "application/json" },
      );
      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url;
      link.download = "fmb-ranking-zugang.json";
      document.body.appendChild(link);
      link.click();
      link.remove();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
      backupRequested = true;
      elements.status.textContent =
        "Download der Zugangssicherung angefordert. Bewahre diese private Datei sicher auf und teile sie nicht; der Browser kann ihren tatsächlichen Speicherort nicht prüfen.";
    } catch (_) {
      showError({ code: "FILE_INVALID" });
    }
  });
  elements.forget.addEventListener("click", () => {
    if (busy) return;
    if (!backupRequested) {
      elements.status.textContent =
        "Der neue Zugang ist noch nicht gesichert. Fordere zuerst die Zugangssicherung an oder lösche die neue Teilnahme.";
      return;
    }
    session = null;
    profile = null;
    elements.accessFile.value = "";
    elements.uploadConsent.checked = false;
    elements.deleteConsent.checked = false;
    controls();
    elements.status.textContent =
      "Zugang aus dieser Seitensitzung entfernt. Bereits hochgeladene Daten und Deine Sicherungsdatei bleiben bestehen.";
  });
  elements.send.addEventListener("click", () =>
    action(async () => {
      const result = await client.upload(
        preview,
        session,
        elements.uploadConsent.checked,
        (counts) => {
          elements.status.textContent = `Upload läuft: ${counts.accepted} angenommen, ${counts.duplicates} doppelt, ${counts.quarantined} in Quarantäne.`;
        },
      );
      elements.uploadConsent.checked = false;
      elements.status.textContent = `Übertragung abgeschlossen: ${result.accepted} neue Meldungen angenommen, ${result.duplicates} bereits vorhanden, ${result.quarantined} in Quarantäne. Weiterhin selbst gemeldet, nicht serverbestätigt.`;
      if (typeof loadRanking === "function") loadRanking();
    }),
  );
  elements.remove.addEventListener("click", () =>
    action(async () => {
      await client.remove(session, elements.deleteConsent.checked);
      session = null;
      profile = null;
      backupRequested = true;
      elements.accessFile.value = "";
      elements.deleteConsent.checked = false;
      elements.uploadConsent.checked = false;
      elements.status.textContent =
        "Teilnahme und hochgeladene Ereignisse gelöscht. Alte Zugangssicherungen sind ungültig; Du kannst sie selbst entfernen.";
      if (typeof loadRanking === "function") loadRanking();
    }),
  );
  for (const checkbox of [
    elements.enrollConsent,
    elements.uploadConsent,
    elements.deleteConsent,
  ])
    checkbox.addEventListener("change", controls);
  globalThis.addEventListener("beforeunload", (event) => {
    if (session && !backupRequested) {
      event.preventDefault();
      event.returnValue = "";
    }
  });
  controls();
  describe();
})();
